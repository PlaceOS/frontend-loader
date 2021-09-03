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
      commits = Git.repository_commits(folder_name, loader.content_directory, count, branch) rescue nil
      head :not_found if commits.nil?

      render json: commits
    end

    # Returns an array of branches for a repository
    get "/:folder_name/branches", :branches do
      folder_name = params["folder_name"]
      branches = Git.branches(folder_name, loader.content_directory) rescue nil
      head :not_found if branches.nil?

      render json: branches
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
