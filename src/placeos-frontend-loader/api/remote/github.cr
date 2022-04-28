require "hash_file"
require "octokit"

require "./remote"

module PlaceOS::FrontendLoader
  class Github < Remote
    def initialize(@metadata : Metadata = Metadata.instance)
    end

    private alias Remote = PlaceOS::FrontendLoader::Remote

    @github_client = Octokit.client(GIT_USER, GIT_PASS)

    private def extract_repo_name(repo : String)
      repo = repo.downcase
      repo.includes?("://") ? repo.split(".com/").last : repo
    end

    # Returns the release tags for a given repo
    def releases(repo : String) : Array(String)
      url = "https://api.github.com/repos/#{extract_repo_name repo}/releases"
      response = Crest.get(url, handle_errors: false)
      raise Exception.new("status_code for #{url} was #{response.status_code}") unless (response.success? || response.status_code == 302)
      Array(NamedTuple(tag_name: String)).from_json(response.body).map(&.[:tag_name])
    end

    def download_latest_asset(repo : String, path : String)
      @github_client.latest_release_asset(extract_repo_name(repo), path)
    end

    def download_asset(repo : String, tag : String, path : String)
      @github_client.release_asset(extract_repo_name(repo), tag, path)
    end

    def url(repo_name : String) : String
      repo_name.includes?("://") ? repo_name : "https://www.github.com/#{repo_name}"
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
  end
end
