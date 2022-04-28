require "crest"
require "json"

module PlaceOS::FrontendLoader
  class Metadata
    private getter hash_file : HashFile = HashFile
    private getter lock : Mutex = Mutex.new(protection: Mutex::Protection::Reentrant)

    def initialize
      hash_file.config({"base_dir" => Dir.current})
    end

    class_getter instance : Metadata do
      new
    end

    def get_metadata(repo_name, field)
      lock.synchronize do
        hash_file["#{repo_name}/metadata/#{field}"].to_s.strip
      end
    end

    def remote_type(repo_name)
      lock.synchronize do
        begin
          PlaceOS::FrontendLoader::Remote::Reference::Type.parse?(hash_file["#{repo_name}/metadata/remote_type"].to_s.strip)
        rescue
          PlaceOS::FrontendLoader::Remote::Reference::Type::Generic
        end
      end
    end

    def remote
    end

    def set_metadata(repo_name, field, value)
      lock.synchronize do
        hash_file["#{repo_name}/metadata/#{field}"] = value.to_s
      end
    end
  end

  abstract class PlaceOS::FrontendLoader::Remote
    private alias Git = PlaceOS::Compiler::Git
    private alias Remote = PlaceOS::FrontendLoader::Remote

    getter metadata : Metadata

    def initialize(@metadata : Metadata = Metadata.instance)
    end

    def self.remote_for(repository_url : URI | String) : Remote
      uri = repository_url.is_a?(URI) ? repository_url : URI.parse(repository_url)
      {% begin %}
      case uri.host.to_s
      {% for remote in Reference::Type.constants.reject { |rem| rem.stringify == "Generic" } %}
        when .includes?(Reference::Type::{{ remote }}.to_s.downcase)
          PlaceOS::FrontendLoader::{{ remote.id }}.new
      {% end %}
      else
        PlaceOS::FrontendLoader::Generic.new(uri)
      end
    {% end %}
    end

    struct Commit
      include JSON::Serializable
      getter commit : String
      getter name : String

      def initialize(@commit, @name)
      end
    end

    struct Reference
      include JSON::Serializable

      enum Type
        GitLab
        Github
        Generic
      end

      getter uri : URI
      getter repo_name : String
      getter remote_type : Reference::Type
      getter branch : String
      getter hash : String
      getter tag : String | Nil

      def initialize(url : String | URI, @branch : String? = "master", @tag : String? = nil, @hash : String? = "HEAD")
        @uri = uri = url.is_a?(URI) ? url : URI.parse(url)
        @repo_name = uri.path.strip("/")
        @remote_type = {% begin %}
          case uri.host.to_s
            {% for remote in Reference::Type.constants %}
          when .includes?(Reference::Type::{{ remote }}.to_s.downcase)
            Reference::Type::{{ remote.id }}
          {% end %}
          else
            Reference::Type::Generic
          end
          {% end %}
      end

      def self.from_repository(repository : Model::Repository)
        hash = repository.should_pull? ? "HEAD" : repository.commit_hash
        self.new(url: repository.uri, branch: repository.branch, hash: hash)
      end

      def remote
        case remote_type
        in Type::Github
          PlaceOS::FrontendLoader::Github.new
        in Type::GitLab
          PlaceOS::FrontendLoader::GitLab.new
        in Type::Generic
          PlaceOS::FrontendLoader::Generic.new(uri)
        end
      end
    end

    # Returns the commits for a given repo on specified branch
    def commits(repo : String, branch : String) : Array(Remote::Commit)
      repository_uri = url(repo)

      if branch.nil?
        get_commit_hashes(repository_uri).map do |name, commit|
          Remote::Commit.new(
            commit: commit,
            name: name.split("refs/heads/", limit: 2).last
          )
        end
      else
        commit = Remote::Commit.new(
          commit: get_commit_hashes(repository_uri, branch),
          name: branch
        )
        [commit]
      end
    end

    # Returns the branches for a given repo
    def branches(repo : String) : Array(String)
      get_commit_hashes(url(repo)).keys.compact_map do |name|
        name.split("refs/heads/", limit: 2).last if name.includes?("refs/heads")
      end.sort!.uniq!
    end

    abstract def releases(repo : String) : Array(String)

    # Returns the tags for a given repo
    def tags(repo : String) : Array(String)
      get_commit_hashes(url(repo)).keys.compact_map do |name|
        name.split("refs/tags/", limit: 2).last if name.includes?("refs/tags/")
      end
    end

    def default_branch(repo : String) : String
      stdout = IO::Memory.new
      Process.new("git", {"ls-remote", "--symref", repo, "HEAD"}, output: stdout).wait
      stdout.to_s
        .split('\n')
        .first
        .split('\t')
        .first
        .lchop("ref: refs/heads/")
    end

    abstract def download(ref : Reference, path : String, branch : String? = "master", hash : String? = "HEAD", tag : String? = nil)

    def save_metadata(repo_path : String, hash : String, repository_uri : String, branch : String, type : Remote::Reference::Type)
      metadata.set_metadata(repo_path, "current_hash", hash)
      metadata.set_metadata(repo_path, "current_repo", repository_uri)
      metadata.set_metadata(repo_path, "current_branch", branch)
      metadata.set_metadata(repo_path, "remote_type", type)
    end

    # Querying
    ###############################################################################################

    # grabs the commit sha needed for repo download based on provided tag/branch or defaults to latest commit
    def get_hash(hash : String, repository_uri : String, tag : String?, branch : String) : String
      if hash == "HEAD"
        if !tag.nil?
          get_hash_by_tag(repository_uri, tag)
        else
          get_hash_by_branch(repository_uri, branch)
        end
      else
        hash
      end
    rescue ex : KeyError
      get_hash_head(repository_uri)
    end

    def get_commit_hashes(repo_url : String)
      uri = url(repo_url).gsub("www.", "")
      stdout = IO::Memory.new
      Process.new("git", {"ls-remote", uri}, output: stdout).wait
      output = stdout.to_s.split('\n')
      output.compact_map do |ref|
        next if ref.empty?
        ref.split('\t', limit: 2).reverse
      end.to_h
    end

    def get_commit_hashes(repo_url : String, branch : String)
      ref_hash = get_commit_hashes(repo_url)
      raise KeyError.new("Branch #{branch} does not exist in repo") unless ref_hash.has_key?("refs/heads/#{branch}")
      ref_hash["refs/heads/#{branch}"]
    end

    private def get_hash_head(repo_url : String)
      ref_hash = get_commit_hashes(repo_url)
      ref_hash["HEAD"]? || ref_hash.first_key
    end

    private def get_hash_by_branch(repo_url : String, branch : String)
      ref_hash = get_commit_hashes(repo_url)
      raise KeyError.new("Branch #{branch} does not exist in repo") unless ref_hash.has_key?("refs/heads/#{branch}")
      ref_hash["refs/heads/#{branch}"]
    end

    # tag = "1.9.0"
    private def get_hash_by_tag(repo_url : String, tag : String)
      ref_hash = get_commit_hashes(repo_url)
      raise KeyError.new("Tag #{tag} does not exist in repo") unless ref_hash.has_key?("refs/tags/v#{tag}")
      ref_hash["refs/tags/v#{tag}"]
    end

    # Downloading
    ###############################################################################################

    def download_archive(url : String, temp_tar_name : String)
      Crest.get(url) do |response|
        File.write(temp_tar_name, response.body_io)
      end
      File.new(temp_tar_name)
    rescue ex : File::Error | Crest::RequestFailed
      Log.error(exception: ex) { "Could not download file at #{url}" }
    end

    def extract_archive(dest_path : String, temp_tar_name : String)
      raise File::NotFoundError.new(message: "File #{temp_tar_name} does not exist", file: temp_tar_name) unless File.exists?(Path.new(temp_tar_name))
      if !Dir.exists?(Path.new(["./", dest_path]))
        File.open(temp_tar_name) do |file|
          begin
            Compress::Gzip::Reader.open(file) do |gzip|
              Crystar::Reader.open(gzip) do |tar|
                tar.each_entry do |entry|
                  next if entry.file_info.directory?
                  parts = Path.new(entry.name).parts
                  parts = parts.last(parts.size > 1 ? parts.size - 1 : 0)
                  next if parts.size == 0
                  file_path = Path.new([dest_path] + parts)
                  Dir.mkdir_p(file_path.dirname) unless Dir.exists?(file_path.dirname)
                  File.write(file_path, entry.io, perm: entry.file_info.permissions) unless Dir.exists?(file_path)
                end
              end
            end
          rescue ex : File::Error | Compress::Gzip::Error
            Log.error(exception: ex) { "Could not unzip tar" }
          end
        end
      end
      File.delete(temp_tar_name)
    end
  end
end
