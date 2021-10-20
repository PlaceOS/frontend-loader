require "digest/sha1"
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

    def self.get_commits(uri : String, count : Int32)
      response = HTTP::Client.get uri
      commits = Array(Git::Commit).new
      parsed = JSON.parse(response.body).as_a
      parsed.each do |value|
        commit = Git::Commit.new(
          commit: value["sha"].as_s,
          date: value["commit"]["author"]["date"].as_s,
          author: value["commit"]["author"]["name"].as_s,
          subject: value["commit"]["message"].as_s.strip(%(\n))
        )
        commits << commit
      end
      commits[0...count]
    end

    def self._commits(repo : String, branch : String, count : Int32 = 50)
      get_commits("https://api.github.com/repos/#{repo}/commits?sha=#{branch}", count)
    end

    def self.commits(folder : String, branch : String, count : Int32 = 50, loader : Loader = Loader.instance)
      begin
        repo = current_repo(loader.content_directory, folder)
        _commits(repo, branch, count)
      rescue e
        Log.error(exception: e) { "failed to fetch commmits" }
        nil
      end
    end

    def self.branches_lookup(repo)
      response = HTTP::Client.get "https://api.github.com/repos/#{repo}/branches"
      parsed2 = JSON.parse(response.body).as_a
      branches = Hash(String, String).new
      parsed2.each do |value|
        next if value =~ /HEAD/
        branch_name = value["name"].to_s.strip.lchop("origin/")
        branches[branch_name] = value["commit"]["sha"].to_s
      end
      branches
    end

    def self._branches(repo : String)
      branches_lookup(repo).keys.sort!.uniq!
    end

    # Returns an array of branches for a repository
    get "/:folder_name/branches", :branches do
      folder_name = params["folder_name"]
      Log.context.set(folder: folder_name)

      branches = Repositories.branches(folder_name)

      branches.nil? ? head :not_found : render json: branches
    end

    def self.branches(folder, loader : Loader = Loader.instance)
      begin
        repo = current_repo(loader.content_directory, folder)
        _branches(repo)
      rescue e
        Log.error(exception: e) { "failed to fetch branches" }
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
          hash[folder_name] = Api::Repositories.current_commit(content_directory, folder_name)
        }
    end

    def self.get_branch_name(repo, hash)
      branches = branches_lookup(repo)
      raise Exception.new("Incorrect hash") unless branches.has_value?(hash)
      branches.key_for(hash)
    end

    def self.current_branch(repository_path : String, repo : String)
      hash = File.read(Path.new([repository_path, "current_hash.txt"]))
      get_branch_name(repo, hash).to_s.strip
    end

    def self.current_commit(parent, folder)
      File.read(Path.new([parent, folder, "current_hash.txt"]))
    end

    def self.current_repo(parent, folder)
      File.read(Path.new([parent, folder, "current_repo.txt"]))
    end
  end
end
