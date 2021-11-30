require "hash_file"
require "./remote"
require "octokit"

module PlaceOS::FrontendLoader
  class GitHubRemote < Remote
    def initialize
    end

    private alias Remote = PlaceOS::FrontendLoader::Remote

    @github_client = Octokit.client(GIT_USER, GIT_PASS)

    # Returns the branches for a given repo
    def branches(repo : String) : Hash(String, String)
      branches = Hash(String, String).new
      @github_client.branches(repo).fetch_all.map do |branch|
        next if branch =~ /HEAD/
        branches[branch.name] = branch.commit.sha
      end
      branches
    end

    # Returns the commits for a given repo on specified branch
    def commits(repo : String, branch : String) : Array(Remote::Commit)
      @github_client.commits(repo, branch).fetch_all.map do |comm|
        Remote::Commit.new(
          commit: comm.sha,
          date: comm.commit.author.date,
          author: comm.commit.author.name,
          subject: comm.commit.message,
        )
      end
    end

    # Returns the release tags for a given repo
    def releases(repo : String) : Array(String)
      @github_client.tags(repo).fetch_all.map { |tag| tags << tag.name }
    end

    def url(repo_name : String) : String
      "https://github.com/#{repo_name}"
    end

    def download(
      ref : Remote::Reference,
      path : String,
      branch : String? = "master",
      hash : String? = "HEAD",
      tag : String? = "latest"
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
          archive_url = "https://github.com/#{ref.repo_name}/archive/#{hash}.tar.gz"
          download_archive(archive_url, temp_tar_name)
          extract_archive(path, temp_tar_name)
          save_metadata(path, hash, repository_uri, branch)
        rescue ex : KeyError | File::Error
          Log.error(exception: ex) { "Could not download repository: #{ex.message}" }
        end
      end
    end

    def download_archive(url : String, temp_tar_name : String)
      HTTP::Client.get(url) do |redirect_response|
        raise HTTP::Server::ClientError.new("status_code for #{url} was #{redirect_response.status_code}") unless (redirect_response.success? || redirect_response.status_code == 302)
        HTTP::Client.get(redirect_response.headers["location"]) do |response|
          File.write(temp_tar_name, response.body_io)
        end
      end
      File.new(temp_tar_name)
    rescue ex : File::Error | HTTP::Server::ClientError
      Log.error(exception: ex) { "Could not download file at URL: #{ex.message}" }
    end
  end
end
