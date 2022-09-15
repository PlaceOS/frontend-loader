module PlaceOS::FrontendLoader::Api
  class Remotes < Base
    base "/api/frontend-loader/v1/remotes"

    # =====================
    # Filters
    # =====================

    @[AC::Route::Filter(:before_action)]
    protected def get_repository_url(
      @[AC::Param::Info(description: "the git url that represents the repository", example: "https://github.com/PlaceOS/PlaceOS.git")]
      repository_url : String,
      @[AC::Param::Info(description: "a username for access if required", example: "steve")]
      username : String? = nil,
      @[AC::Param::Info(description: "the password or access token as required", example: "ab34cfe4567")]
      password : String? = nil,
    )
      @repository_url = repository_url
    end

    getter! repository_url : String
    getter username : String? = nil
    getter password : String? = nil

    # =====================
    # Routes
    # =====================

    # Returns an array of releases for a repository
    @[AC::Route::GET("/:repository_url/releases")]
    def releases : Array(String)
      repo = GitRepository.new(repository_url, username, password)
      if repo.is_a?(GitRepository::Releases)
        repo.releases
      else
        [] of String
      end
    end

    # Returns an array of commits for a repository
    @[AC::Route::GET("/:repository_url/commits")]
    def commits(
      @[AC::Param::Info(description: "the branch to grab commits from", example: "main")]
      branch : String? = nil,
      @[AC::Param::Info(description: "the number of commits to return", example: "50")]
      depth : Int32 = 50,
      @[AC::Param::Info(description: "the file we want to grab commits from", example: "src/place/meet.cr")]
      file : String? = nil
    ) : Array(GitRepository::Commit)
      repo = GitRepository.new(repository_url, username, password)
      branch = branch || repo.default_branch
      file ? repo.commits(branch, file, depth) : repo.commits(branch, depth)
    end

    # Returns an array of branches
    @[AC::Route::GET("/:repository_url/branches")]
    def branches : Array(String)
      repo = GitRepository.new(repository_url, username, password)
      repo.branches.keys
    end

    # Returns an array of tags
    @[AC::Route::GET("/:repository_url/tags")]
    def tags : Array(String)
      repo = GitRepository.new(repository_url, username, password)
      repo.tags.keys
    end
  end
end
