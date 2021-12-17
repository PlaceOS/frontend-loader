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
        PlaceOS::FrontendLoader::Remote::Reference::Type.parse?(hash_file["#{repo_name}/metadata/remote_type"].to_s.strip)
      end
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
      {% for remote in Reference::Type.constants %}
        when .includes?(Reference::Type::{{ remote }}.to_s.downcase)
          PlaceOS::FrontendLoader::{{ remote.id }}.new
      {% end %}
      else
        raise Exception.new("Host not supported: #{repository_url}")
      end
    {% end %}
    end

    struct Commit
      include JSON::Serializable
      getter commit : String
      getter date : String
      getter author : String
      getter subject : String

      def initialize(@commit, @date, @author, @subject)
      end
    end

    struct Reference
      include JSON::Serializable

      enum Type
        GitLab
        Github
      end

      getter repo_name : String
      getter remote_type : Reference::Type
      getter branch : String
      getter hash : String
      getter tag : String | Nil

      def initialize(url : String | URI, @branch : String? = "master", @tag : String? = nil, @hash : String? = "HEAD")
        uri = url.is_a?(URI) ? url : URI.parse(url)
        @repo_name = uri.path.strip("/")
        @remote_type = {% begin %}
          case uri.host.to_s
            {% for remote in Reference::Type.constants %}
          when .includes?(Reference::Type::{{ remote }}.to_s.downcase)
            Reference::Type::{{ remote.id }}
          {% end %}
          else
            raise Exception.new("Host not supported: #{url}")
          end
          {% end %}
      end

      def self.from_repository(repository : Model::Repository)
        hash = repository.should_pull? ? "HEAD" : repository.commit_hash
        self.new(url: repository.uri, branch: repository.branch, hash: hash)
      end
    end

    abstract def commits(repo : String, branch : String) : Array(Commit)

    abstract def branches(repo : String) : Hash(String, String)

    abstract def releases(repo : String) : Array(String)

    abstract def tags(repo : String) : Array(String)

    abstract def download(ref : Reference, path : String, branch : String? = "master", hash : String? = "HEAD", tag : String? = nil)

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
                  File.write(file_path, entry.io, perm: entry.file_info.permissions)
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

    # grabs the commit sha needed for repo download based on provided tag/branch or defaults to latest commit
    def get_hash(hash : String, repository_uri : String, tag : String?, branch : String)
      begin
        if hash == "HEAD"
          if (!tag.nil?)
            hash = get_hash_by_tag(repository_uri, tag)
          else
            hash = get_hash_by_branch(repository_uri, branch)
          end
        end
      rescue ex : KeyError
        hash = get_hash_head(repository_uri) if hash.nil?
      end
      hash.not_nil!
    end

    def save_metadata(repo_path : String, hash : String, repository_uri : String, branch : String, type : Remote::Reference::Type)
      metadata.set_metadata(repo_path, "current_hash", hash)
      metadata.set_metadata(repo_path, "current_repo", repository_uri.split(".com/").last)
      metadata.set_metadata(repo_path, "current_branch", branch)
      metadata.set_metadata(repo_path, "remote_type", type)
    end

    private def get_commit_hashes(repo_url : String)
      stdout = IO::Memory.new
      Process.new("git", ["ls-remote", repo_url], output: stdout).wait
      output = stdout.to_s.split('\n')
      output.compact_map do |ref|
        next if ref.empty?
        ref.split('\t', limit: 2).reverse
      end.to_h
    end

    private def get_hash_head(repo_url : String)
      ref_hash = get_commit_hashes(repo_url)
      ref_hash.has_key?("HEAD") ? ref_hash["HEAD"] : ref_hash.first_key?
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
  end
end
