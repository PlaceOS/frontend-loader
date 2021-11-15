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
      HashFile.config({"base_dir" => "#{loader.content_directory}/#{folder}/metadata"})
      repo = HashFile["current_repo"].to_s
      loader.actioner.commits(repo, branch)[0...count]
    rescue e
      Log.error(exception: e) { "failed to fetch commmits: #{e.message}" }
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
      HashFile.config({"base_dir" => "#{loader.content_directory}/#{folder}/metadata"})
      repo = HashFile["current_repo"].to_s
      loader.actioner.branches(repo).keys.sort!.uniq!
    rescue e
      Log.error(exception: e) { "failed to fetch branches for #{folder}" }
      nil
    end

    # Returns a hash of folder name to commits
    get "/", :loaded do
      render json: Repositories.loaded_repositories
    end

    def self.loaded?(folder : String)
      folder == loader.last_loaded.folder_name
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
      HashFile.config({"base_dir" => "#{repository_path}/metadata"})
      HashFile["current_branch"].to_s.strip
    end

    def self.current_commit(repository_path : String)
      HashFile.config({"base_dir" => "#{repository_path}/metadata"})
      HashFile["current_hash"].to_s.strip
    end

    def self.current_repo(repository_path : String)
      HashFile.config({"base_dir" => "#{repository_path}/metadata"})
      HashFile["current_repo"].to_s.strip
    end
  end
end
