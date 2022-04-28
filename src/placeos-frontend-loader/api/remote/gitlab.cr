require "hash_file"
require "gitlab"

require "./remote"

module PlaceOS::FrontendLoader
  class GitLab < PlaceOS::FrontendLoader::Remote
    def initialize(@metadata : Metadata = Metadata.instance)
    end

    private alias Remote = PlaceOS::FrontendLoader::Remote

    ENDPOINT = "https://gitlab.com/api/v4"

    @gitlab_client = Gitlab.client(ENDPOINT, GITLAB_TOKEN)

    private def extract_repo_name(repo : String)
      repo = repo.downcase
      repo.includes?("://") ? repo.split(".com/").last : repo
    end

    def get_repo_id(repo_name : String)
      repo = URI.encode_www_form(repo_name)
      @gitlab_client.project(repo)["id"].to_s.to_i
    end

    # TODO: Implement
    # Returns the release tags for a given repo
    def releases(repo : String) : Array(String)
      # repo_id = get_repo_id(repo)
      # @gitlab_client.tags(repo_id).as_a.map do |value|
      #   value["name"].to_s
      # end
      [""]
    end

    # Returns the tags for a given repo
    def tags(repo : String) : Array(String)
      repo_id = get_repo_id(extract_repo_name repo)
      @gitlab_client.tags(repo_id).as_a.map do |value|
        value["name"].to_s
      end
    end

    def url(repo_name : String) : String
      repo_name.includes?("://") ? repo_name : "https://gitlab.com/#{repo_name}"
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
          save_metadata(repository_folder_name, hash, ref.repo_name, branch, ref.remote_type)
        rescue ex : KeyError | File::Error
          Log.error(exception: ex) { "Could not download repository: #{ex.message}" }
        end
      end
    end
  end
end
