module PlaceOS::FrontendLoader
  struct GitHubRef
    include JSON::Serializable
    property repo_name : String
    property branch : String
    # property tag : String
    property hash : String = "HEAD" # also a GitHub commit
    property parent : String = "./"

    def initialize(@repo_name : String, @branch : String? = "master", @tag : String? = nil)
      # if @hash == "HEAD"
    end

    def github_url
      "https://github.com/#{repo_name}"
    end

    def set_hash
      if !@tag.nil?
        hash = get_hash_by_tag(self.github_url, @branch)
      elsif branch != "master"
        hash = get_hash_by_branch(self.github_url, @branch)
      else
        hash = get_hash_head(self.github_url)
      end
      @hash = hash.not_nil!
    end

    private def get_hashes(repo_url : String)
      stdout = IO::Memory.new
      Process.new("git", ["ls-remote", repo_url], output: stdout).wait
      output = stdout.to_s.split('\n')
      ref_hash = Hash(String, String).new
      output.each do |ref|
        next if ref.empty?
        split = ref.partition('\t')
        ref_hash[split[2]] = split[0]
      end
      ref_hash
    end

    private def get_hash_head(repo_url : String)
      ref_hash = get_hashes(repo_url)
      ref_hash.has_key?("HEAD") ? ref_hash["HEAD"] : ref_hash.first_key?
    end

    private def get_hash_by_branch(repo_url : String, branch : String)
      ref_hash = get_hashes(repo_url)
      raise KeyError.new("Branch #{branch} does not exist in repo") unless ref_hash.has_key?("refs/heads/#{branch}")
      ref_hash["refs/heads/#{branch}"]
    end

    # tag = "1.9.0"
    private def get_hash_by_tag(repo_url : String, tag : String)
      ref_hash = get_hashes(repo_url)
      raise KeyError.new("Tag #{tag} does not exist in repo") unless ref_hash.has_key?("refs/tags/v#{tag}")
      ref_hash["refs/tags/v#{tag}"]
    end
  end

  abstract class PlaceOS::FrontendLoader::Remote
    class GithubActioner
      def initialize
      end

      TAR_NAME = "temp.tar.gz"

      struct Commit
        include JSON::Serializable
        property commit : String
        property date : String
        property author : String
        property subject : String

        def initialize(@commit, @date, @author, @subject)
        end
      end

      # repostiory class?
      # Returns the branches for a given repo
      def branches(repo : String) : Hash(String, String)
        uri = "https://api.github.com/repos/#{repo}/branches"
        response = HTTP::Client.get uri
        raise Exception.new("status_code for #{uri} was #{response.status_code}") unless (response.success? || response.status_code == 302)
        parsed = JSON.parse(response.body).as_a
        branches = Hash(String, String).new
        parsed.each do |value|
          next if value =~ /HEAD/
          branch_name = value["name"].to_s.strip.lchop("origin/")
          branches[branch_name] = value["commit"]["sha"].to_s
        end
        branches
      end

      # Returns the commits for a given repo on specified branch
      def commits(repo : String, branch : String) : Array(Commit)
        url = "https://api.github.com/repos/#{repo}/commits?sha=#{branch}"
        response = HTTP::Client.get url
        raise Exception.new("status_code for #{url} was #{response.status_code}") unless (response.success? || response.status_code == 302)
        commits = Array(Commit).new
        parsed = JSON.parse(response.body).as_a
        parsed.each do |value|
          commit = Commit.new(
            commit: value["sha"].as_s,
            date: value["commit"]["author"]["date"].as_s,
            author: value["commit"]["author"]["name"].as_s,
            subject: value["commit"]["message"].as_s.strip(%(\n))
          )
          commits << commit
        end
        commits
      end

      # Returns the release tags for a given repo
      def releases(repo : String) : Array(String)
        url = "https://api.github.com/repos/#{repo}/releases"
        response = HTTP::Client.get url
        raise Exception.new("status_code for #{url} was #{response.status_code}") unless (response.success? || response.status_code == 302)
        tags = Array(String).new
        parsed = JSON.parse(response.body).as_a
        parsed.each do |value|
          tags << value["tag_name"].as_s
        end
        tags
      end

      def download(
        repository_folder_name : String,
        content_directory : String,
        ref : GitHubRef, # has choosen branch, commit etc
        branch : String? = "master"
      )
        repository_uri = ref.github_url

        Git.repository_lock(repository_folder_name).write do
          Log.info { {
            message:    "downloading repository",
            repository: repository_folder_name,
            branch:     branch,
            uri:        repository_uri,
          } }

          begin
            archive_url = "https://github.com/#{ref.repo_name}/archive/#{ref.hash}.tar.gz"
            download_archive(archive_url)
            dest_path = Path.new([content_directory, repository_folder_name])
            extract_archive(dest_path)
            save_metadata(dest_path, ref.hash, repository_uri, branch)
          rescue ex : KeyError | File::Error
            Log.error(exception: ex) { "Could not download repository: #{ex.message}" }
          end
        end
      end

      def download_archive(url)
        HTTP::Client.get(url) do |redirect_response|
          raise HTTP::Server::ClientError.new("status_code for #{url} was #{redirect_response.status_code}") unless (redirect_response.success? || redirect_response.status_code == 302)
          HTTP::Client.get(redirect_response.headers["location"]) do |response|
            File.write(TAR_NAME, response.body_io)
          end
        end
        File.new(TAR_NAME)
      rescue ex : File::Error | HTTP::Server::ClientError
        Log.error(exception: ex) { "Could not download file at URL: #{ex.message}" }
      end

      def extract_archive(dest_path)
        raise File::NotFoundError.new(message: "File #{TAR_NAME} does not exist", file: TAR_NAME) unless File.exists?(Path.new(TAR_NAME))
        if !Dir.exists?(Path.new(["./", dest_path]))
          File.open(TAR_NAME) do |file|
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
        File.delete(TAR_NAME)
      end

      private def save_metadata(path : Path, hash : String, repository_uri : String, branch : String)
        hash_path = Path.new([path, "current_hash.txt"])
        puts hash_path
        File.write(hash_path, hash)
        repo_path = Path.new([path, "current_repo.txt"])
        repo = repository_uri.partition(".com/")[2]
        File.write(repo_path, repo)
        branch_path = Path.new([path, "current_branch.txt"])
        File.write(branch_path, branch)
      end
    end
  end
end
