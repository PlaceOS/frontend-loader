require "placeos-compiler/git"

module PlaceOS::FrontendLoader
  abstract class PlaceOS::FrontendLoader::Remote
    class Github < Remote
      # repo name e.g. PlaceOS/Core
      def initialize(@ref : String, @folder_name : String)
        stdout = IO::Memory.new
        Process.new("git", ["ls-remote", "https://github.com/#{@ref}"], output: stdout).wait
        output = stdout.to_s
        raise Exception.new("Repo #{@ref} is incorrect or does not exsist") if output.includes?("not found")
      end

      TAR_NAME = "temp.tar.gz"

      property current_branch : String = "master"
      property current_commit : String?

      def folder_name
        @folder_name
      end

      struct Commit
        include JSON::Serializable
        property commit : String
        property date : String
        property author : String
        property subject : String

        def initialize(@commit, @date, @author, @subject)
        end
      end

      def github_url
        "https://github.com/#{@ref}"
      end

      def branches : Hash(String, String)
        uri = "https://api.github.com/repos/#{@ref}/branches"
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

      def tags : Array(String)
        ["df", "fd"]
      end

      def download(
        repository_folder_name : String,
        content_directory : String,
        branch : String,
        repository_commit : String? = nil,
        username : String? = nil,
        password : String? = nil
      )
        Git.repository_lock(repository_folder_name).write do
          Log.info { {
            message:    "downloading repository",
            repository: repository_folder_name,
            branch:     branch,
            uri:        @ref,
          } }

          repository_uri = github_url

          begin
            if branch != "master"
              hash = get_hash_by_branch(repository_uri, branch)
            else
              if repository_commit.nil? || repository_commit == "HEAD"
                hash = get_hash_head(repository_uri)
              else
                hash = repository_commit
              end
            end
            hash = hash.not_nil!
            tar_url = "#{repository_uri}/archive/#{hash}.tar.gz"
            download_file(tar_url, TAR_NAME)
            dest_path = Path.new([content_directory, repository_folder_name])
            extract_file(TAR_NAME, dest_path)
            save_metadata(dest_path, hash, repository_uri, branch)
          rescue ex : Exception
            Log.error(exception: ex) { ex.message }
          end
        end
      end

      def commits(branch : String = @current_branch) : Array(Commit)
        url = "https://api.github.com/repos/#{@ref}/commits?sha=#{branch}"
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

      def download_file(url, dest)
        HTTP::Client.get(url) do |redirect_response|
          raise HTTP::Server::ClientError.new("status_code for #{url} was #{redirect_response.status_code}") unless (redirect_response.success? || redirect_response.status_code == 302)
          HTTP::Client.get(redirect_response.headers["location"]) do |response|
            File.write(dest, response.body_io)
          end
        end
        File.new(dest)
      rescue ex : File::Error | HTTP::Server::ClientError
        Log.error(exception: ex) { "Could not download file at URL: #{ex.message}" }
      end

      def extract_file(tar_name, dest_path)
        raise File::NotFoundError.new(message: "File #{tar_name} does not exist", file: tar_name) unless File.exists?(Path.new(tar_name))
        if !Dir.exists?(Path.new(["./", dest_path]))
          File.open(tar_name) do |file|
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
        File.delete(tar_name)
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
        raise Exception.new("Branch #{branch} does not exist in repo") unless ref_hash.has_key?("refs/heads/#{branch}")
        ref_hash["refs/heads/#{branch}"]
      end

      private def save_metadata(path : Path, hash : String, repository_uri : String, branch : String)
        hash_path = Path.new([path, "current_hash.txt"])
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
