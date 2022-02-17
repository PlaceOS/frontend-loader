require "hash_file"
require "./remote"
require "octokit"

module PlaceOS::FrontendLoader
  class Github < Remote
    def initialize(@metadata : Metadata = Metadata.instance)
    end

    private alias Remote = PlaceOS::FrontendLoader::Remote

    @github_client = Octokit.client(GIT_USER, GIT_PASS)

    # Returns the branches for a given repo
    def branches(repo : String) : Array(String)
      repository_uri = url(repo)
      branches = Array(String).new
      get_commit_hashes(repository_uri).each_key do |name|
        next if !name.includes?("refs/heads")
        branches << name.split("refs/heads/", limit: 2).last
      end
      branches.sort!.uniq!
    end

    # Returns the commits for a given repo on specified branch
    def commits(repo : String, branch : String) : Array(Remote::Commit)
      commits = Array(Remote::Commit).new
      repository_uri = url(repo)
      if !branch.nil?
        hash = get_commit_hashes(repository_uri, branch)
        commit = Remote::Commit.new(
          commit: hash,
          name: branch
        )
        commits << commit
      else
        get_commit_hashes(repository_uri).each do |name, hash|
          commit = Remote::Commit.new(
            commit: hash,
            name: name.split("refs/heads/", limit: 2).last
          )
          commits << commit
        end
      end
      commits
    end

    def default_branch(repo : String) : String
      url = "https://api.github.com/repos/#{repo}"
      response = HTTP::Client.get url
      raise Exception.new("status_code for #{url} was #{response.status_code}") unless (response.success? || response.status_code == 302)
      parsed = JSON::Any.from_json(response.body)
      parsed["default_branch"]?.try(&.to_s) || "master"
    end

    # Returns the release tags for a given repo
    def releases(repo : String) : Array(String)
      repository_uri = url(repo)
      releases = Array(String).new
      get_commit_hashes(repository_uri).each_key do |name|
        next if !name.includes?("refs/tags/")
        releases << name.split("refs/tags/", limit: 2).last
      end
      releases
    end

    # Returns the tags for a given repo
    def tags(repo : String) : Array(String)
      url = "https://api.github.com/repos/#{repo}/tags"
      response = HTTP::Client.get url
      raise Exception.new("status_code for #{url} was #{response.status_code}") unless (response.success? || response.status_code == 302)
      tags = Array(String).new
      Array(JSON::Any).from_json(response.body).map do |value|
        tags << value["name"].as_s
      end
      tags
    end

    def download_latest_asset(repo : String, path : String)
      @github_client.latest_release_asset(repo, path)
    end

    def download_asset(repo : String, tag : String, path : String)
      @github_client.release_asset(repo, tag, path)
    end

    def url(repo_name : String) : String
      "https://www.github.com/#{repo_name}"
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

      Git.repository_lock(repository_folder_name).write do
        Log.info { {
          message:    "downloading repository",
          repository: repository_folder_name,
          branch:     branch,
          uri:        repository_uri,
        } }

        model = PlaceOS::Model::Repository.where(uri: repository_uri).first?

        if model.nil? || !model.release
          hash = get_hash(hash, repository_uri, tag, branch)
          temp_tar_name = Random.rand(UInt32).to_s
          begin
            archive_url = "https://github.com/#{ref.repo_name}/archive/#{hash}.tar.gz"
            download_archive(archive_url, temp_tar_name)
            extract_archive(path, temp_tar_name)
            save_metadata(repository_folder_name, hash, repository_uri, branch, ref.remote_type)
          rescue ex : KeyError | File::Error
            Log.error(exception: ex) { "Could not download repository: #{ex.message}" }
          end
        else
          Dir.mkdir_p(path) unless Dir.exists?(path)
          self.download_latest_asset(ref.repo_name, path)
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
