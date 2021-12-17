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
    def branches(repo : String) : Hash(String, String)
      @github_client.branches(repo).fetch_all.each_with_object({} of String => String) do |branch, branches|
        next if branch.name =~ /HEAD/
        branches[branch.name] = branch.commit.sha
      end
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
      releases = Array(String).new
      @github_client.releases(repo).fetch_all.map do |rel|
        releases << rel.name.to_s
      end
      releases
    end

    # Returns the tags for a given repo
    def tags(repo : String) : Array(String)
      tags = Array(String).new
      @github_client.tags(repo).fetch_all.map do |tag|
        tags << tag.name.to_s
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

        raise Exception.new("#{repository_uri} was not found in database") if model.nil?

        if model.release
          Dir.mkdir_p(path) unless Dir.exists?(path)
          self.download_latest_asset(ref.repo_name, path)
        else
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
