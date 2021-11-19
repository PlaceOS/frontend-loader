require "hash_file"
require "./remote"
require "gitlab"

module PlaceOS::FrontendLoader
  class GitLabRemote < PlaceOS::FrontendLoader::Remote
    def initialize
    end

    private alias Remote = PlaceOS::FrontendLoader::Remote

    TAR_NAME = "temp.tar.gz"

    @gitlab_client = Gitlab.client("https://gitlab.com/api/v4", GIT_LAB_TOKEN)

    struct Commit
      include JSON::Serializable
      property commit : String
      property date : String
      property author : String
      property subject : String

      def initialize(@commit, @date, @author, @subject)
      end
    end

    def get_repo_id(repo_name : String)
      repo = URI.encode_www_form(repo_name)
      @gitlab_client.project(repo)["id"].to_s.to_i
    end

    # Returns the branches for a given repo
    def branches(repo : String) : Hash(String, String)
      repo_id = get_repo_id(repo)
      fetched_branches = @gitlab_client.branches(repo_id).as_a
      branches = Hash(String, String).new
      fetched_branches.each do |value|
        branch_name = value["name"].to_s
        branches[branch_name] = value["commit"]["id"].to_s
      end
      branches
    end

    # Returns the commits for a given repo on specified branch
    def commits(repo : String, branch : String = "master") : Array(Remote::Commit)
      repo_id = get_repo_id(repo)
      fetched_commits = @gitlab_client.commits(repo_id).as_a
      commits = Array(Remote::Commit).new
      fetched_commits.each do |value|
        commit = Remote::Commit.new(
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
    def releases(repo : String) : Array(String)
      repo_id = get_repo_id(repo)
      fetched_releases = @gitlab_client.tags(repo_id).as_a
      tags = Array(String).new
      fetched_releases.each do |value|
        tags << value["name"].to_s
      end
      tags
    end

    def url(repo_name : String) : String
      "https://gitlab.com/#{repo_name}"
    end

    def download(
      ref : Remote::Reference,
      branch : String? = "master",
      hash : String? = "HEAD",
      tag : String? = "latest",
      path : String = "./"
    )
      repository_uri = url(ref.repo_name)
      repository_folder_name = path.split("/").last

      if tag != "latest"
        hash = get_hash_by_tag(ref.repo_name, tag)
      elsif branch != "master"
        hash = get_hash_by_branch(ref.repo_name, branch)
      else
        hash = get_hash_head(ref.repo_name)
      end
      hash = hash.not_nil!

      Git.repository_lock(repository_folder_name).write do
        Log.info { {
          message:    "downloading repository",
          repository: repository_folder_name,
          branch:     branch,
          uri:        repository_uri,
        } }

        begin
          repo_encoded = ref.repo_name.gsub("/", "%2F")
          archive_url = "https://gitlab.com/api/v4/projects/#{repo_encoded}/repository/archive.tar.gz?sha=#{hash}"
          download_archive(archive_url)
          extract_archive(path)
          save_metadata(path, hash, ref.repo_name, branch)
        rescue ex : KeyError | File::Error
          Log.error(exception: ex) { "Could not download repository: #{ex.message}" }
        end
      end
    end

    private def get_hash_head(repo_name : String)
      commits = commits(repo_name)
      raise Enumerable::EmptyError.new("No commits found for repo: #{repo_name}") if commits.empty?
      commits.first.commit
    end

    private def get_hash_by_branch(repo_name : String, branch : String)
      commits_by_branch = branches(repo_name)
      raise KeyError.new("Branch #{branch} does not exist in repo") unless commits_by_branch.has_key?(branch)
      commits_by_branch[branch]
    end

    # tag = "1.9.0"
    private def get_hash_by_tag(repo_name : String, tag : String)
      commits_by_release = releases_hash(repo_name)
      raise KeyError.new("Tag #{tag} does not exist in repo") unless commits_by_release.has_key?(tag)
      commits_by_release[tag]
    end

    def releases_hash(repo : String) : Hash(String, String)
      repo_id = get_repo_id(repo)
      fetched_releases = @gitlab_client.tags(repo_id).as_a
      tags = Hash(String, String).new
      fetched_releases.each do |value|
        tag_name = value["name"].to_s
        tags[tag_name] = value["commit"]["id"].to_s
      end
      tags
    end

    def download_archive(url)
      HTTP::Client.get(url) do |response|
        raise Exception.new("status_code for #{url} was #{response.status_code}") unless response.status_code < 400
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

    private def save_metadata(repo_path : String, hash : String, repo_name : String, branch : String)
      HashFile.config({"base_dir" => "#{repo_path}/metadata"})
      HashFile["current_hash"] = hash
      HashFile["current_repo"] = repo_name
      HashFile["current_branch"] = branch
    end
  end
end
