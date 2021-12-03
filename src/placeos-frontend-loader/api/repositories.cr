require "digest/sha1"
require "placeos-compiler/git"
require "hash_file"

require "./base"
require "../loader"

module PlaceOS::FrontendLoader::Api
  class Repositories < Base
    base "/api/frontend-loader/v1/repositories"
    Log = ::Log.for(self)

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
      metadata = Metadata.instance
      repo = metadata.get_metadata(folder, "current_repo")
      remote_type = metadata.get_metadata(folder, "remote_type")
      if remote_type
        loader.set_actioner(remote_type)
        loader.actioner.commits(repo, branch)[0...count]
      else
        e = Exception.new("remote_type could not be read from metadata")
        Log.error(exception: e) { "failed to fetch commmits: #{e.message}" }
        nil
      end
    end

    # Returns an array of branches for a repository
    get "/:folder_name/branches", :branches do
      folder_name = params["folder_name"]
      Log.context.set(folder: folder_name)

      branches = Repositories.branches(folder_name)

      branches.nil? ? head :not_found : render json: branches
    end

    def self.branches(folder, loader : Loader = Loader.instance)
      metadata = Metadata.instance
      repo = metadata.get_metadata(folder, "current_repo")
      remote_type = metadata.get_metadata(folder, "remote_type")

      if remote_type
        loader.set_actioner(remote_type)
        loader.actioner.branches(repo).keys.sort!.uniq!
      else
        e = Exception.new("remote_type could not be read from metadata")
        Log.error(exception: e) { "failed to fetch branches for #{folder}" }
        nil
      end
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
          File.directory?(path)
        }
        .each_with_object({} of String => String) { |folder_name, hash|
          hash[folder_name] = Api::Repositories.current_commit(Path.new([content_directory, folder_name]).to_s)
        }
    end

    def self.current_branch(repository_path : String)
      Metadata.instance.get_metadata(repository_path.split("/").last, "current_branch")
    end

    def self.current_commit(repository_path : String)
      Metadata.instance.get_metadata(repository_path.split("/").last, "current_hash")
    end

    def self.current_repo(repository_path : String)
      Metadata.instance.get_metadata(repository_path.split("/").last, "current_repo")
    end
  end
end
