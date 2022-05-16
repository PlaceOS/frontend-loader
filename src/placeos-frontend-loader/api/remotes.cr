module PlaceOS::FrontendLoader::Api
  class Remotes < Base
    base "/api/frontend-loader/v1/remotes"
    Log = ::Log.for(self)

    protected def get_repository_uri
      # NOTE:: expects the username and password to be encoded into the URL
      url = params["repository_url"]
      URI.parse(URI.decode_www_form(url))
    end

    # Returns an array of releases for a repository
    get "/:repository_url/releases", :releases do
      repo = GitRepository.new(get_repository_uri)
      if repo.is_a?(GitRepository::Releases)
        render json: repo.releases
      else
        render json: [] of String
      end
    end

    # Returns an array of commits for a repository
    get "/:repository_url/commits", :commits do
      repo = GitRepository.new(get_repository_uri)
      branch = query_params["branch"]?.presence || repo.default_branch
      depth = (query_params["depth"]? || 50).to_i
      file = query_params["file"]?.presence

      commits = file ? repo.commits(branch, file, depth) : repo.commits(branch, depth)
      render json: commits
    end

    # Returns an array of branches
    get "/:repository_url/branches", :branches do
      repo = GitRepository.new(get_repository_uri)
      render json: repo.branches.keys
    end

    # Returns an array of tags
    get "/:repository_url/tags", :tags do
      repo = GitRepository.new(get_repository_uri)
      render json: repo.tags.keys
    end
  end
end
