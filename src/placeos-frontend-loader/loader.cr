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
    TAR_NAME = "temp.tar.gz"

    property last_loaded : Remote = Remote::Github.new("PlaceOS/www-core", WWW)

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
      last_loaded = Remote::Github.new("PlaceOS/www-core", content_directory)
      last_loaded.download(repository_folder_name: content_directory, content_directory: content_directory_parent, branch: "master")
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
      # pull_result = Git.pull(".", content_directory)
      # unless pull_result.success?
      #   Log.error { "failed to pull www: #{pull_result.output}" }
      # end

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
      # username = repository.username || Loader.settings.username
      # password = repository.decrypt_password || Loader.settings.password
      repository_commit = repository.commit_hash
      content_directory = File.expand_path(content_directory)
      repository_directory = File.expand_path(File.join(content_directory, repository.folder_name))

      if repository.uri_changed? && Dir.exists?(repository_directory)
        # Reload the repository to prevent conflicting histories
        unload(repository, content_directory)
      end

      hash = repository.should_pull? ? "HEAD" : repository.commit_hash
      # Download and extract the repository at given branch or commit
      last_loaded = Remote::Github.new(repository.uri.partition(".com/")[2], repository.folder_name)
      last_loaded.download(repository_folder_name: repository.folder_name, repository_commit: hash, content_directory: content_directory, branch: branch)

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
  end
end
