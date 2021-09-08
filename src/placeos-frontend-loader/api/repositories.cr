require "placeos-compiler/git"

require "./base"
require "../loader"

module PlaceOS::FrontendLoader::Api
  class Repositories < Base
    base "/api/frontend-loader/v1/repositories"
    Log = ::Log.for(self)

    # :nodoc:
    alias Git = PlaceOS::Compiler::Git

    class_property loader : Loader = Loader.instance

    getter loader : Loader { self.class.loader }

    # Returns an array of commits for a repository
    get "/:folder_name/commits", :commits do
      branch = params["branch"]?.presence || "master"
      count = (params["count"]? || 50).to_i
      folder_name = params["folder_name"]
      Log.context.set(branch: branch, count: count, folder: folder_name)
      commits = Repositories.commits(folder_name, branch, count)

      commits.nil? ? head :not_found : render json: commits
    end

    def self.commits(folder : String, branch : String, count : Int32 = 50, loader : Loader = Loader.instance)
      Git.repository_commits(
        repository: folder,
        working_directory: loader.content_directory,
        count: count, branch: branch
      )
    rescue e
      Log.error(exception: e) { "failed to fetch commmits" }
      nil
    end

    # Returns an array of branches for a repository
    get "/:folder_name/branches", :branches do
      folder_name = params["folder_name"]
      Log.context.set(folder: folder_name)

      branches = Repositories.branches(folder_name)

      branches.nil? ? head :not_found : render json: branches
    end

    def self.branches(folder, loader : Loader = Loader.instance)
      Git.branches(folder, loader.content_directory)
    rescue e
      Log.error(exception: e) { "failed to fetch branches" }
      nil
    end

    # Returns a hash of folder name to commits
    get "/", :loaded do
      render json: Repositories.loaded_repositories
    end

    # Generates a hash of currently loaded repositories and their current commit
    def self.loaded_repositories : Hash(String, String)
      content_directory = loader.content_directory
      Dir
        .entries(content_directory)
        .reject(/^\./)
        .select { |e|
          path = File.join(content_directory, e)
          File.directory?(path) && File.exists?(File.join(path, ".git"))
        }
        .each_with_object({} of String => String) { |folder_name, hash|
          hash[folder_name] = Compiler::Git.current_repository_commit(folder_name, content_directory)
        }
    end
  end
end
