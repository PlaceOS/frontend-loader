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
      folder_name = params["folder_name"]
      branch = params["branch"]?.presence || nil
      count = (params["count"]? || 50).to_i
      Log.context.set(branch: branch, count: count, folder: folder_name)
      commits = Repositories.commits(folder_name, branch, count)

      commits.nil? ? head :not_found : render json: commits
    end

    def self.commits(folder : String, branch : String?, count : Int32 = 50, loader : Loader = Loader.instance)
      metadata = Metadata.instance
      repo = metadata.get_metadata(folder, "current_repo")
      remote_type = metadata.remote_type(folder)
      return unless remote_type
      repository_uri = loader.remote_for(remote_type).url(repo)
      repository_uri = "#{repository_uri}/tree/#{branch}" if branch != loader.remote_for(remote_type).default_branch(repo)

      commits = Array(Remote::Commit).new
      Repositories.get_commit_hashes(repository_uri).each do |name, hash|
        commit = Remote::Commit.new(
          commit: hash,
          name: name.split("refs/heads/", limit: 2).last
        )
        commits << commit
      end
      commits[0...count]
    end

    def self.get_commit_hashes(repo_url : String)
      stdout = IO::Memory.new
      Process.new("git", ["ls-remote", repo_url], output: stdout).wait
      output = stdout.to_s.split('\n')
      output.compact_map do |ref|
        next if ref.empty?
        ref.split('\t', limit: 2).reverse
      end.to_h
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
      remote_type = metadata.remote_type(folder)
      return unless remote_type
      repository_uri = loader.remote_for(remote_type).url(repo)

      branches = Array(String).new
      Repositories.get_commit_hashes(repository_uri).each_key do |name|
        next if !name.includes?("refs/heads")
        branches << name.split("refs/heads/", limit: 2).last
      end
      branches.sort!.uniq!
    end

    get "/:folder_name/releases", :branches do
      folder_name = params["folder_name"]
      count = (params["count"]? || 50).to_i
      Log.context.set(folder: folder_name)

      releases = Repositories.releases(folder_name, count)

      releases.nil? ? head :not_found : render json: releases
    end

    def self.releases(folder, count : Int32 = 50, loader : Loader = Loader.instance)
      metadata = Metadata.instance
      repo = metadata.get_metadata(folder, "current_repo")
      remote_type = metadata.remote_type(folder)
      return unless remote_type
      repository_uri = loader.remote_for(remote_type).url(repo)

      releases = Array(String).new
      Repositories.get_commit_hashes(repository_uri).each_key do |name|
        next if !name.includes?("refs/tags/")
        releases << name.split("refs/tags/", limit: 2).last
      end
      releases[0...count]
    end

    def self.default_branch(folder, loader : Loader = Loader.instance) : String
      metadata = Metadata.instance
      repo = metadata.get_metadata(folder, "current_repo")
      remote_type = metadata.remote_type(folder)
      return "master" unless remote_type
      loader.remote_for(remote_type).default_branch(repo)
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
