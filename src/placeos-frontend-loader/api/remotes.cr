module PlaceOS::FrontendLoader::Api
  class Remotes < Base
    base "/api/frontend-loader/v1/remotes"
    Log = ::Log.for(self)

    private alias Remote = PlaceOS::FrontendLoader::Remote

    # Returns an array of releases for a repository
    get "/:repository_url/releases", :releases do
      url = params["repository_url"]
      uri = URI.parse(URI.decode_www_form(url))

      remote = Remote.remote_for(uri)
      repo_name = uri.path.strip("/")

      releases = remote.releases(repo_name)
      releases.nil? ? head :not_found : render json: releases
    end

    # Returns an array of commits for a repository
    get "/:repository_url/commits", :commits do
      url = params["repository_url"]
      uri = URI.parse(URI.decode_www_form(url))

      remote = Remote.remote_for(uri)
      repo_name = uri.path.strip("/")
      branch = query_params["branch"]?.presence || "master"

      commits = remote.commits(repo_name, branch)
      commits.nil? ? head :not_found : render json: commits
    end

    # Returns an array of branches for a repository
    get "/:repository_url/branches", :branches do
      url = params["repository_url"]
      uri = URI.parse(URI.decode_www_form(url))

      remote = Remote.remote_for(uri)
      repo_name = uri.path.strip("/")

      branches = remote.branches(repo_name)
      branches.nil? ? head :not_found : render json: branches
    end
  end
end
