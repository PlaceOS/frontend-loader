require "hash_file"

module PlaceOS::FrontendLoader
  struct GitLabRef
    include JSON::Serializable
    property repo_name : String
    property branch : String
    property tag : String
    property hash : String # also a GitHub commit
    property repo_path : String

    def initialize(@repo_name : String, @branch : String? = "master", @tag : String? = nil, @hash : String? = "HEAD", @repo_path : String = "/")
      self.set_hash
    end

    def gitlab_url
      "https://gitlab.com/#{repo_name}"
    end

    def repo_encoded
      repo.gsub("/", "%2F")
    end

    def set_hash
      if !@tag.nil?
        hash = get_hash_by_tag
      elsif branch != "master"
        hash = get_hash_by_branch
      else
        hash = get_hash_head
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

    private def get_hash_head
      commits = GitLabActioner.commits(self.repo_name)
      raise Enumerable::EmptyError.new("No commits found for repo: #{self.repo_name}") if commits.empty?
      commits.first.commit
    end

    private def get_hash_by_branch
      commits_by_branch = GitLabActioner.branches(self.repo_name)
      raise KeyError.new("Branch #{@branch} does not exist in repo") unless commits_by_branch.has_key?(@branch)
      commits_by_branch[@branch]
    end

    # tag = "1.9.0"
    private def get_hash_by_tag
      commits_by_release = GitLabActioner.releases(self.repo_name)
      raise KeyError.new("Tag #{@tag} does not exist in repo") unless commits_by_release.has_key?(@tag)
      commits_by_release[@tag]
    end
  end

  abstract class PlaceOS::FrontendLoader::Remote
    class GitLabActioner
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

      # Returns the branches for a given repo
      def branches(repo : String) : Hash(String, String)
        uri = "https://gitlab.com/api/v4/projects/#{repo.gsub("/", "%2F")}/repository/branches"
        response = HTTP::Client.get uri
        raise Exception.new("status_code for #{uri} was #{response.status_code}") unless (response.success? || response.status_code == 302)
        parsed = JSON.parse(response.body).as_a
        branches = Hash(String, String).new
        parsed.each do |value|
          next if value =~ /HEAD/
          branch_name = value["name"].to_s
          branches[branch_name] = value["commit"]["id"].to_s
        end
        branches
      end

      # Returns the commits for a given repo on specified branch
      def commits(repo : String, branch : String = "master") : Array(Commit)
        url = "https://gitlab.com/api/v4/projects/#{repo.gsub("/", "%2F")}/repository/commits?ref_name=#{branch}"
        response = HTTP::Client.get url
        raise Exception.new("status_code for #{url} was #{response.status_code}") unless (response.success? || response.status_code == 302)
        commits = Array(Commit).new
        parsed = JSON.parse(response.body).as_a
        parsed.each do |value|
          commit = Commit.new(
            commit: value["id"].as_s,
            date: value["authored_date"].as_s,
            author: value["author_email"].as_s,
            subject: value["title"].as_s
          )
          commits << commit
        end
        commits
      end

      # Returns the release tags for a given repo
      def releases(repo : String) : Hash(String, String)
        url = "https://gitlab.com/api/v4/projects/#{repo.gsub("/", "%2F")}/releases"
        response = HTTP::Client.get url
        raise Exception.new("status_code for #{url} was #{response.status_code}") unless (response.success? || response.status_code == 302)
        tags = Hash(String, String).new
        parsed = JSON.parse(response.body).as_a
        parsed.each do |value|
          tag_name = value["tag_name"].to_s
          tags[tag_name] = value["commit"]["id"].to_s
        end
        tags
      end

      def download(
        ref : GitHubRef,
        branch : String? = "master"
      )
        repository_uri = ref.gitlab_url
        repository_folder_name = ref.repo_path.split("/").last

        Git.repository_lock(repository_folder_name).write do
          Log.info { {
            message:    "downloading repository",
            repository: repository_folder_name,
            branch:     branch,
            uri:        repository_uri,
          } }

          begin
            archive_url = "https://gitlab.com/api/v4/projects/#{ref.repo_name.gsub("/", "%2F")}/repository/archive.tar.gz?sha=#{commit}"
            download_archive(archive_url)
            extract_archive(ref.repo_path)
            save_metadata(ref.repo_path, ref.hash, repository_uri, branch)
          rescue ex : KeyError | File::Error
            Log.error(exception: ex) { "Could not download repository: #{ex.message}" }
          end
        end
      end

      def download_archive(url)
        HTTP::Client.get(url) do |response|
          raise Exception.new("status_code for #{url} was #{response.status_code}") unless redirect_response.status_code < 400
          File.write(TAR_NAME, response.body_io)
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

      private def save_metadata(repo_path : String, hash : String, repository_uri : String, branch : String)
        HashFile.config({"base_dir" => "#{repo_path}/metadata"})
        HashFile["current_hash"] = hash
        HashFile["current_repo"] = repository_uri.split(".com/").last
        HashFile["current_branch"] = branch
      end
    end
  end
end
