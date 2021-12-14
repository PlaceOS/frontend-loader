require "file_utils"
require "habitat"
require "placeos-compiler/git"
require "placeos-models/repository"
require "placeos-resource"
require "tasker"

require "http/client"
require "crystar"

require "../constants.cr"
require "./api/remote/*"

module PlaceOS::FrontendLoader
  class Loader < Resource(Model::Repository)
    Log = ::Log.for(self)

    private alias Git = PlaceOS::Compiler::Git
    private alias Remote = PlaceOS::FrontendLoader::Remote
    private alias Type = PlaceOS::FrontendLoader::Remote::Reference::Type

    private getter remotes : Hash(Type, Remote) = Hash(Type, Remote).new

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

    def remote_for(type : Type) : Remote
      case type
      in Type::Github
        PlaceOS::FrontendLoader::Github.new
      in Type::GitLab
        PlaceOS::FrontendLoader::GitLab.new
      end
    end

    def initialize(
      @content_directory : String = Loader.settings.content_directory,
      @update_crontab : String = Loader.settings.update_crontab
    )
      Type.values.each do |key|
        @remotes[key] = remote_for(key)
      end
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
      base_repo = Model::Repository.new(
        name: "PlaceOS/www-core",
        repo_type: Model::Repository::Type::Interface,
        folder_name: content_directory.split("/").last,
        uri: BASE_REF,
      )

      base_ref = Remote::Reference.new(repository: base_repo)
      remotes[base_ref.remote_type].download(ref: base_ref, path: File.expand_path(content_directory))
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
      create_base_www

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
          remotes: @remotes
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
      content_directory : String,
      remotes : Hash(Type, Remote)
    )
      content_directory = File.expand_path(content_directory)
      repository_directory = File.expand_path(File.join(content_directory, repository.folder_name))

      repository_commit = repository.commit_hash

      unload(repository, content_directory) if repository.uri_changed? && Dir.exists?(repository_directory)

      # Download and extract the repository at given branch or commit
      ref = Remote::Reference.new(repository: repository, branch: repository.branch)

      current_remote = remotes[ref.remote_type]

      current_remote.download(ref: ref, hash: ref.hash, branch: ref.branch, path: repository_directory)

      # Grab commit for the downloaded/extracted repository
      checked_out_commit = Api::Repositories.current_commit(repository_directory)

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
        branch:            repository.branch,
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
  end
end
