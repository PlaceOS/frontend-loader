require "file_utils"
require "habitat"
require "placeos-compiler/git_commands"
require "placeos-models/repository"
require "placeos-resource"
require "tasker"

module PlaceOS::Frontends
  class Loader < Resource(Model::Repository)
    Log = ::Log.for(self)

    private alias Git = PlaceOS::Compiler::GitCommands

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
    private property update_cron : Tasker::CRON(UInt64)? = nil

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
      Loader.clone_and_pull(
        repository_folder_name: content_directory,
        repository_uri: "https://github.com/PlaceOS/www-core",
        content_directory: content_directory_parent,
        username: Loader.settings.username,
        password: Loader.settings.password,
        branch: "master",
        depth: 1,
      )
    end

    protected def start_update_cron
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
      unless pull_result[:exit_status] == 0
        Log.error { "failed to pull www: #{pull_result}" }
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
      username = repository.username || Loader.settings.username
      password = repository.password || Loader.settings.password
      repository_commit = repository.commit_hash
      content_directory = File.expand_path(content_directory)
      repository_directory = File.expand_path(File.join(content_directory, repository.folder_name))

      if repository.uri_changed? && Dir.exists?(repository_directory)
        # Reload the repository to prevent conflicting histories
        unload(repository, content_directory)
      end

      # Clone and pull the repository
      clone_and_pull(
        repository_folder_name: repository.folder_name,
        repository_uri: repository.uri,
        content_directory: content_directory,
        username: username,
        password: password,
        branch: repository.branch,
      )

      # Checkout repository to commit on the model
      checkout_commit(repository_directory, repository_commit, repository.branch)

      # Grab commit for the cloned/pulled repository
      current_commit = current_commit(repository_directory: repository_directory)

      # Update model commit if the repository is not held at HEAD
      if current_commit != repository_commit && repository_commit != "HEAD"
        Log.info { {message:           "updating commit on Repository document",
                    current_commit:    current_commit,
                    repository_commit: repository_commit,
                    folder_name:       repository.folder_name,
        } }

        # Refresh the repository model commit hash
        repository_commit = current_commit
        repository.update_fields(commit_hash: current_commit)
      end

      Log.info { {
        message:           "loaded repository",
        commit:            current_commit,
        branch:            repository.branch,
        repository:        repository.folder_name,
        repository_commit: repository_commit,
        uri:               repository.uri,
      } }

      Resource::Result::Success
    end

    def self.current_commit(repository_directory : String, content_directory : String? = nil)
      path = content_directory.nil? ? repository_directory : File.join(content_directory, repository_directory)
      Git.repository_commits(path, count: 1).first[:commit]
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

    # Set repository to a specific commit
    #
    def self.checkout_commit(repository_directory : String, commit : String = "HEAD", branch : String = "master")
      # Cannot checkout HEAD in a detached state
      commit = branch if commit == "HEAD"

      result = Git.repo_operation(repository_directory) do
        ExecFrom.exec_from(repository_directory, "git", {"fetch", "--all"}, environment: {"GIT_TERMINAL_PROMPT" => "0"})
        ExecFrom.exec_from(repository_directory, "git", {"checkout", commit}, environment: {"GIT_TERMINAL_PROMPT" => "0"})
      end

      exit_code = result[:exit_code]
      raise "git checkout #{commit} failed with #{exit_code} in path #{repository_directory}: #{result[:output]}" if exit_code != 0
    end

    def self.clone_and_pull(
      repository_folder_name : String,
      repository_uri : String,
      content_directory : String,
      branch : String,
      username : String? = nil,
      password : String? = nil,
      depth : Int32? = nil
    )
      Git.repo_lock(repository_folder_name).write do
        Log.info { {
          message:    "cloning repository",
          repository: repository_folder_name,
          branch:     branch,
          uri:        repository_uri,
        } }

        clone_result = Git.clone(
          repository_folder_name,
          repository_uri,
          username,
          password,
          content_directory,
          depth: depth,
          branch: branch,
        )

        raise "failed to clone\n#{clone_result[:output]}" unless clone_result[:exit_status] == 0

        # Pull if already cloned and pull intended
        if clone_result[:output].includes?("already exists")
          Log.info { {
            message:    "pulling repository",
            repository: repository_folder_name,
            branch:     branch,
            uri:        repository_uri,
          } }
          path = File.join(content_directory, repository_folder_name)

          # Ensure branch is locally present
          Git.fetch(path)

          # Checkout the branch first
          Git.checkout_branch(branch, path)

          pull_result = Git.pull(repository_folder_name, content_directory, branch)
          raise "failed to pull\n#{pull_result}" unless pull_result[:exit_status] == 0
        end
      end
    end
  end
end
