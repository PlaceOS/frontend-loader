require "hash_file"
require "./remote"
require "gitlab"

module PlaceOS::FrontendLoader
  class GitLab < PlaceOS::FrontendLoader::Remote
    def initialize(@metadata : Metadata = Metadata.instance)
    end

    private alias Remote = PlaceOS::FrontendLoader::Remote

    ENDPOINT = "https://gitlab.com/api/v4"

    @gitlab_client = Gitlab.client(ENDPOINT, GITLAB_TOKEN)

    def get_repo_id(repo_name : String)
      repo = URI.encode_www_form(repo_name)
      @gitlab_client.project(repo)["id"].to_s.to_i
    end

    # Returns the branches for a given repo
    def branches(repo : String) : Hash(String, String)
      repo_id = get_repo_id(repo)
      @gitlab_client.branches(repo_id).as_a.each_with_object({} of String => String) do |branch, branches|
        branch_name = branch["name"].to_s
        branches[branch_name] = branch["commit"]["id"].to_s
      end
    end

    # Returns the commits for a given repo on specified branch
    def commits(repo : String, branch : String = "master") : Array(Remote::Commit)
      repo_id = get_repo_id(repo)
      @gitlab_client.commits(repo_id).as_a.map do |comm|
        Remote::Commit.new(
          commit: comm["id"].as_s,
          date: comm["authored_date"].as_s,
          author: comm["author_email"].as_s,
          subject: comm["title"].as_s
        )
      end
    end

    def default_branch(repo : String) : String
      "master"
    end

    # Returns the release tags for a given repo
    def releases(repo : String) : Array(String)
      # repo_id = get_repo_id(repo)
      # @gitlab_client.tags(repo_id).as_a.map do |value|
      #   value["name"].to_s
      # end
      # TO:DO
      [""]
    end

    # Returns the tags for a given repo
    def tags(repo : String) : Array(String)
      repo_id = get_repo_id(repo)
      @gitlab_client.tags(repo_id).as_a.map do |value|
        value["name"].to_s
      end
    end

    def url(repo_name : String) : String
      "https://gitlab.com/#{repo_name}"
    end

    def download(
      ref : Remote::Reference,
      path : String,
      branch : String? = "master",
      hash : String? = "HEAD",
      tag : String? = nil
    )
      repository_uri = url(ref.repo_name)
      repository_folder_name = path.split("/").last

      hash = get_hash(hash, repository_uri, tag, branch)
      temp_tar_name = Random.rand(UInt32).to_s

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

          download_archive(archive_url, temp_tar_name)
          extract_archive(path, temp_tar_name)
          save_metadata(path, hash, ref.repo_name, branch, ref.remote_type)
        rescue ex : KeyError | File::Error
          Log.error(exception: ex) { "Could not download repository: #{ex.message}" }
        end
      end
    end

    def download_archive(url : String, temp_tar_name : String)
      HTTP::Client.get(url) do |response|
        raise Exception.new("status_code for #{url} was #{response.status_code}") unless response.status_code < 400
        File.write(temp_tar_name, response.body_io)
      end
      File.new(temp_tar_name)
    rescue ex : File::Error | HTTP::Server::ClientError
      Log.error(exception: ex) { "Could not download file at URL: #{ex.message}" }
    end
  end
end
