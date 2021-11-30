module PlaceOS::FrontendLoader
  abstract class PlaceOS::FrontendLoader::Remote
    private alias Git = PlaceOS::Compiler::Git

    def initialize
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
      getter repo_name : String
      getter branch : String
      getter tag : String | Nil

      def initialize(@url : String, @branch : String? = "master", @tag : String? = nil, @hash : String? = "HEAD")
        @repo_name = @url.split(".com/").last.rstrip("/")
      end
    end

    abstract def commits(repo : String, branch : String) : Array(Commit)

    abstract def branches(repo : String) : Hash(String, String)

    abstract def releases(repo : String) : Array(String)

    abstract def download(ref : Reference, path : String, branch : String? = "master", hash : String? = "HEAD", tag : String? = "latest")

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

    def get_hash(hash : String, repository_uri : String, tag : String, branch : String)
      if hash == "HEAD" || hash.nil?
        if tag != "latest"
          hash = get_hash_by_tag(repository_uri, tag)
        elsif branch != "master"
          hash = get_hash_by_branch(repository_uri, branch)
        else
          hash = get_hash_head(repository_uri)
        end
      end
      hash.not_nil!
    end

    def save_metadata(repo_path : String, hash : String, repository_uri : String, branch : String)
      HashFile.config({"base_dir" => "#{repo_path}/metadata"})
      HashFile["current_hash"] = hash
      HashFile["current_repo"] = repository_uri.split(".com/").last
      HashFile["current_branch"] = branch
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
