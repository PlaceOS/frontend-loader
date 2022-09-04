require "digest/sha1"
require "git-repository"

require "./base"
require "../loader"

module PlaceOS::FrontendLoader::Api
  class Repositories < Base
    base "/api/frontend-loader/v1/repositories"

    # =====================
    # Helpers
    # =====================

    class_property loader : Loader = Loader.instance
    getter loader : Loader { self.class.loader }

    def self.loaded_repositories
      Loader.folder_lookup.transform_values(&.commit)
    end

    # =====================
    # Filters
    # =====================

    @[AC::Route::Filter(:before_action, except: [:loaded])]
    protected def get_folder_name(folder_name : String)
      @folder_name = folder_name
    end

    getter! folder_name : String

    @[AC::Route::Filter(:before_action, except: [:loaded])]
    protected def load_repo_cache
      @repo_cache = Loader.folder_lookup[folder_name]?.try &.cache
      return if @repo_cache

      # attempt to find the record in the database
      repo_details = ::PlaceOS::Model::Repository.collection_query do |table|
        table.get_all(folder_name, index: :folder_name)
      end.to_a.select!(&.repo_type.interface?).first?

      raise Error::NotFound.new("unable to find repository at #{folder_name}") unless repo_details
      @repo_cache = GitRepository.new(repo_details.uri, repo_details.username, repo_details.decrypt_password)
    end

    getter! repo_cache : GitRepository::Interface

    # =====================
    # Routes
    # =====================

    # Returns an array of commits for a repository
    @[AC::Route::GET("/:folder_name/commits")]
    def commits(
      @[AC::Param::Info(description: "the branch to grab commits from", example: "main")]
      branch : String? = nil,
      @[AC::Param::Info(description: "the number of commits to return", example: "50")]
      depth : Int32 = 50,
    ) : Array(GitRepository::Commit)
      repo = repo_cache
      branch = branch || repo.default_branch
      depth = (params["depth"]? || 50).to_i

      Log.context.set(branch: branch, depth: depth, folder: folder_name)
      repo.commits(branch, depth: depth)
    end

    # Returns an array of branches for a repository
    @[AC::Route::GET("/:folder_name/branches")]
    def branches : Array(String)
      Log.context.set(folder: folder_name)
      repo_cache.branches.keys
    end

    # Returns an array of releases for a repository
    @[AC::Route::GET("/:folder_name/releases")]
    def releases(count : Int32 = 50) : Array(String)
      Log.context.set(folder: folder_name)

      repo = repo_cache
      return [] of String unless repo.is_a?(GitRepository::Releases)
      repo.as(GitRepository::Releases).releases(count)
    end

    # Returns a hash of folder name to commits
    @[AC::Route::GET("/")]
    def loaded : Hash(String, String)
      self.class.loaded_repositories
    end
  end
end
