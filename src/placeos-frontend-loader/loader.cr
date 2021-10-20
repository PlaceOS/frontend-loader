require "file_utils"
require "habitat"
require "placeos-compiler/git"
require "placeos-models/repository"
require "placeos-resource"
require "tasker"

require "http/client"
require "crystar"

require "../constants.cr"

module PlaceOS::FrontendLoader
  class Loader < Resource(Model::Repository)
    Log = ::Log.for(self)

    private alias Git = PlaceOS::Compiler::Git
    TAR_NAME = "temp.tar.gz"

    Habitat.create do
      setting content_directory : String = WWW
      setting update_crontab : String = CRON
      setting username : String? = GIT_USER
      setting password : String? = GIT_PASS
    end

    class_getter instance : Loader do
      Loader.new(
        content_directory: settings.content_directory,
      )
    end

    getter content_directory : String
    getter username : String?
    private getter password : String?
    getter update_crontab : String
    private property update_cron : Tasker::CRON(Int64)? = nil

    def initialize(
      @content_directory : String = Loader.settings.content_directory,
      @update_crontab : String = Loader.settings.update_crontab
    )
      super()
    end

    def start
      create_base_www
      start_update_cron
      super
    end

    def stop
      update_cron.try &.cancel
      super
    end

    # Frontend loader implicitly and idempotently creates a base www
    protected def create_base_www
      content_directory_parent = Path[content_directory].parent.to_s
      Loader.download_and_extract(
        repository_folder_name: content_directory,
        repository_uri: "https://github.com/PlaceOS/www-core",
        content_directory: content_directory_parent,
        username: Loader.settings.username,
        password: Loader.settings.password,
        branch: "master",
        depth: 1,
      )
    end

    protected def start_update_cron : Nil
      unless self.update_cron
        # Update the repositories periodically
        self.update_cron = Tasker.instance.cron(update_crontab) do
          repeating_update
        end
      end
    end

    protected def repeating_update
      # Pull all frontends
      loaded = load_resources

      # Pull www (content directory)
      pull_result = Git.pull(".", content_directory)
      unless pull_result.success?
        Log.error { "failed to pull www: #{pull_result.output}" }
      end

      loaded
    end

    def process_resource(action : Resource::Action, resource : Model::Repository) : Resource::Result
      repository = resource

      # Only consider Interface Repositories
      return Resource::Result::Skipped unless repository.repo_type.interface?

      case action
      in Action::Created, Action::Updated
        # Load the repository
        Loader.load(
          repository: repository,
          content_directory: @content_directory,
        )
      in Action::Deleted
        # Unload the repository
        Loader.unload(
          repository: repository,
          content_directory: @content_directory,
        )
      end
    rescue e
      # Add cloning errors
      raise Resource::ProcessingError.new(resource.name, "#{resource.attributes} #{e.inspect_with_backtrace}")
    end

    def self.load(
      repository : Model::Repository,
      content_directory : String
    )
      branch = repository.branch
      username = repository.username || Loader.settings.username
      password = repository.decrypt_password || Loader.settings.password
      repository_commit = repository.commit_hash
      content_directory = File.expand_path(content_directory)
      repository_directory = File.expand_path(File.join(content_directory, repository.folder_name))

      if repository.uri_changed? && Dir.exists?(repository_directory)
        # Reload the repository to prevent conflicting histories
        unload(repository, content_directory)
      end

      hash = repository.should_pull? ? "HEAD" : repository.commit_hash
      # Download and extract the repository at given branch or commit
      download_and_extract(
        repository_folder_name: repository.folder_name,
        repository_uri: repository.uri,
        content_directory: content_directory,
        repository_commit: hash,
        username: username,
        password: password,
        branch: branch,
      )

      # Grab commit for the downloaded/extracted repository
      checked_out_commit = Api::Repositories.current_commit(content_directory, repository.folder_name)

      # Update model commit iff...
      # - the repository is not held at HEAD
      # - the commit has changed
      unless checked_out_commit.starts_with?(repository_commit) || repository_commit == "HEAD"
        Log.info { {
          message:           "updating commit on Repository document",
          current_commit:    checked_out_commit,
          repository_commit: repository_commit,
          folder_name:       repository.folder_name,
        } }

        # Refresh the repository's `commit_hash`
        repository_commit = checked_out_commit
        repository.commit_hash = checked_out_commit
        repository.update
      end

      Log.info { {
        message:           "loaded repository",
        commit:            checked_out_commit,
        branch:            branch,
        repository:        repository.folder_name,
        repository_commit: repository_commit,
        uri:               repository.uri,
      } }

      Resource::Result::Success
    end

    def self.unload(
      repository : Model::Repository,
      content_directory : String
    )
      content_directory = File.expand_path(content_directory)
      repository_dir = File.expand_path(File.join(content_directory, repository.folder_name))

      # Ensure we `rmdir` a sane folder
      # - don't delete root
      # - don't delete working directory
      safe_directory = repository_dir.starts_with?(content_directory) &&
                       repository_dir != "/" &&
                       !repository.folder_name.empty? &&
                       !repository.folder_name.includes?("/") &&
                       !repository.folder_name.includes?(".")

      if !safe_directory
        Log.error { {
          message:           "attempted to delete unsafe directory",
          repository_folder: repository.folder_name,
        } }
        Resource::Result::Error
      else
        if Dir.exists?(repository_dir)
          begin
            FileUtils.rm_rf(repository_dir)
            Resource::Result::Success
          rescue
            Log.error { "failed to remove #{repository_dir}" }
            Resource::Result::Error
          end
        else
          Resource::Result::Skipped
        end
      end
    end

    def self.download_file(url, dest)
      begin
        HTTP::Client.get(url) do |redirect_response|
          raise Exception.new("status_code for #{url} was #{redirect_response.status_code}") unless redirect_response.status_code < 400
          HTTP::Client.get(redirect_response.headers["location"]) do |response|
            File.write(dest, response.body_io)
          end
        end
        File.new(dest)
      rescue ex : Exception
        Log.error(exception: ex) { "Could not download file at URL: #{url}" }
      end
    end

    def self.extract_file(tar_name, dest_path)
      raise Exception.new("File #{tar_name} does not exist") unless File.exists?(Path.new(tar_name))
      if !Dir.exists?(Path.new(["./", dest_path]))
        File.open(tar_name) do |file|
          begin
            Compress::Gzip::Reader.open(file) do |gzip|
              Crystar::Reader.open(gzip) do |tar|
                tar.each_entry do |entry|
                  next if entry.file_info.directory?
                  parts = Path.new(entry.name).parts
                  parts = parts.last(parts.size > 1 ? parts.size - 1 : 0)
                  next if parts.size == 0
                  filePath = Path.new([dest_path] + parts)
                  Dir.mkdir_p(filePath.dirname) unless Dir.exists?(filePath.dirname)
                  File.write(filePath, entry.io, perm = entry.file_info.permissions)
                end
              end
            end
          rescue ex : Exception
            Log.error(exception: ex) { "Could not unzip tar" }
          end
        end
      end
      File.delete(tar_name)
    end

    def self.get_hashes(repo_url : String)
      stdout = IO::Memory.new
      Process.new("git", ["ls-remote", repo_url], output: stdout).wait
      output = stdout.to_s.split('\n')
      ref_hash = Hash(String, String).new
      output.each do |ref|
        next if ref.empty?
        split = ref.partition('\t')
        ref_hash[split[2]] = split[0]
      end
      ref_hash
    end

    def self.get_hash_head(repo_url : String)
      ref_hash = get_hashes(repo_url)
      ref_hash.has_key?("HEAD") ? ref_hash["HEAD"] : ref_hash.first_key?
    end

    def self.get_hash_by_branch(repo_url : String, branch : String)
      ref_hash = get_hashes(repo_url)
      raise Exception.new("Branch #{branch} does not exist in repo") unless ref_hash.has_key?("refs/heads/#{branch}")
      ref_hash["refs/heads/#{branch}"]
    end

    def self.save_metadata(parent_folder : String, folder_name : String, hash : String, repository_uri : String)
      hash_path = Path.new([parent_folder, folder_name, "current_hash.txt"])
      File.write(hash_path, hash)
      repo_path = Path.new([parent_folder, folder_name, "current_repo.txt"])
      repo = repository_uri.partition(".com/")[2]
      File.write(repo_path, repo)
    end

    def self.download_and_extract(
      repository_folder_name : String,
      repository_uri : String,
      content_directory : String,
      branch : String,
      repository_commit : String? = nil,
      username : String? = nil,
      password : String? = nil,
      depth : Int32? = nil
    )
      Git.repository_lock(repository_folder_name).write do
        Log.info { {
          message:    "downloading repository",
          repository: repository_folder_name,
          branch:     branch,
          uri:        repository_uri,
        } }

        begin
          if branch != "master"
            hash = get_hash_by_branch(repository_uri, branch)
          else
            unless repository_commit.nil? || repository_commit == "HEAD"
              hash = repository_commit
            else
              hash = get_hash_head(repository_uri)
            end
          end
          hash = hash.not_nil!
          tar_url = "#{repository_uri}/archive/#{hash}.tar.gz"
          download_file(tar_url, TAR_NAME)
          extract_file(TAR_NAME, content_directory + "/" + repository_folder_name)
          save_metadata(content_directory, repository_folder_name, hash, repository_uri)
        rescue ex : Exception
          Log.error(exception: ex) { ex.message }
        end
      end
    end
  end
end
