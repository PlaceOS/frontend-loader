require "digest/sha1"
require "git-repository"

require "./base"
require "../loader"

module PlaceOS::FrontendLoader::Api
  class Repositories < Base
    base "/api/frontend-loader/v1/repositories"
    Log = ::Log.for(self)

    class_property loader : Loader = Loader.instance
    getter loader : Loader { self.class.loader }

    before_action :load_repo_cache, except: :loaded
    getter! repo_cache : GitRepository::Interface
    getter folder_name : String { params["folder_name"] }

    protected def load_repo_cache
      @repo_cache = Loader.folder_lookup[folder_name]?.try &.cache
      return if @repo_cache

      # attempt to find the record in the database
      repo_details = ::PlaceOS::Model::Repository.collection_query do |table|
        table.get_all(folder_name, index: :authority_id)
      end.to_a.select!(&.repo_type.interface?).first?

      head :not_found unless repo_details
      @repo_cache = GitRepository.new(repo_details.uri, repo_details.username, repo_details.decrypt_password)
    end

    # Returns an array of commits for a repository
    get "/:folder_name/commits", :commits do
      repo = repo_cache
      branch = params["branch"]?.presence || repo.default_branch
      depth = (params["depth"]? || 50).to_i

      Log.context.set(branch: branch, depth: depth, folder: folder_name)
      render json: repo.commits(branch, depth: depth)
    end

    # Returns an array of branches for a repository
    get "/:folder_name/branches", :branches do
      Log.context.set(folder: folder_name)
      render json: repo_cache.branches.keys
    end

    get "/:folder_name/releases", :releases do
      depth = (params["depth"]? || 50).to_i
      Log.context.set(folder: folder_name)

      repo = repo_cache
      render(json: [] of String) unless repo.is_a?(GitRepository::Releases)
      render json: repo.as(GitRepository::Releases).releases
    end

    # Returns a hash of folder name to commits
    get "/", :loaded do
      render json: self.class.loaded_repositories
    end

    def self.loaded_repositories
      Loader.folder_lookup.transform_values(&.commit)
    end
  end
end
