require "file_utils"
require "habitat"
require "placeos-models/repository"
require "placeos-resource"
require "tasker"

require "http/client"
require "crystar"

require "../constants.cr"

module PlaceOS::FrontendLoader
  class Loader < Resource(Model::Repository)
    Log = ::Log.for(self)

    Habitat.create do
      setting content_directory : String = WWW
      setting update_crontab : String = CRON
    end

    class_getter instance : Loader do
      Loader.new(
        content_directory: settings.content_directory,
      )
    end

    getter content_directory : String
    getter update_crontab : String
    private property update_cron : Tasker::CRON(Int64)? = nil
    @www_commit : String = ""

    record RepoCache, repo : Model::Repository, cache : GitRepository::Interface, commit : String
    class_getter id_lookup : Hash(String, RepoCache) = {} of String => RepoCache
    class_getter uri_lookup : Hash(String, RepoCache) = {} of String => RepoCache
    class_getter folder_lookup : Hash(String, RepoCache) = {} of String => RepoCache

    def initialize(
      @content_directory : String = Loader.settings.content_directory,
      @update_crontab : String = Loader.settings.update_crontab
    )
      # we want to cache this repo and then copy any changes into www folder
      @www_repo = GitRepository.new(BASE_REF, branch: WWW_BRANCH)

      # ensure the www directory exists on the volume
      www_folder = File.expand_path(content_directory)
      Dir.mkdir_p www_folder

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
      # use our history cache to check if there is a new version available
      www_folder = File.expand_path(content_directory)
      branch = WWW_BRANCH
      latest_commit = @www_repo.commits(branch, 1).first.hash
      if @www_commit != latest_commit
        temp_path = File.join(www_folder, "#{Time.utc.to_unix_ms}_#{rand(9999)}")
        begin
          # 1. clone the repo locally (handled by the library)
          # 2. copy the files to the volume in a temp directory
          @www_repo.fetch_commit(latest_commit, temp_path)

          # 3. move the files into place (ignore hidden files)
          FileUtils.mv(Dir.entries(temp_path).compact_map { |file|
            next if file.starts_with?('.')
            File.join(temp_path, file)
          }, www_folder)

          # 4. update the commit
          @www_commit = latest_commit
        rescue error
          Log.error(exception: error) { "failed to update or create the www folder" }
          raise error
        ensure
          # clean up the temp directory
          FileUtils.rm_rf(temp_path)
        end
      end
    end

    protected def start_update_cron : Nil
      unless self.update_cron
        # Update the repositories periodically
        self.update_cron = Tasker.instance.cron(update_crontab) do
          repeating_update
        end
      end
    end

    # Pull all frontends
    protected def repeating_update
      load_resources.tap do
        # Pull base PlaceOS WWW folder
        create_base_www
      end
    end

    def process_resource(action : Resource::Action, resource : Model::Repository) : Resource::Result
      repository = resource

      # Only consider Interface Repositories
      return Resource::Result::Skipped unless repository.repo_type.interface?

      case action
      in Action::Created, Action::Updated
        # Skip load if the only change was `deployed_commit_hash`
        if (changes = repository.changed_attributes).size == 1 && changes[:deployed_commit_hash]? && !repository.deployed_commit_hash.nil?
          return Resource::Result::Skipped
        end

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

    protected def self.check_for_changes(repository) : Tuple(Bool, String)
      if loaded = id_lookup[repository.id]?
        Log.trace { "#{repository.folder_name}: already loaded, checking for relevant changes" }
        old_repo = loaded.repo
        old_folder_name = old_repo.folder_name

        if (
             old_folder_name == repository.folder_name &&
             old_repo.branch == repository.branch &&
             old_repo.username == repository.username &&
             old_repo.password == repository.password &&
             old_repo.uri == repository.uri
           )
          Log.trace { "#{repository.folder_name}: no changes found" }
          {false, old_folder_name}
        else
          id_lookup.delete(old_repo.id)
          uri_lookup.delete(old_repo.uri)
          folder_lookup.delete(old_repo.folder_name)
          Log.trace { "#{repository.folder_name}: cleaned up old settings" }
          {true, old_folder_name}
        end
      else
        {true, repository.folder_name}
      end
    end

    def self.load(
      repository : Model::Repository,
      content_directory : String
    )
      Log.trace { "loading repository #{repository.folder_name}: #{repository.uri} (branch: #{repository.branch})" }

      # check for any relevant changes
      rebuild_cache, old_folder_name = check_for_changes(repository)

      # rebuild caches
      cache = if rebuild_cache
                GitRepository.new(repository.uri, repository.username, repository.decrypt_password, repository.branch)
              else
                repo_cache = id_lookup[repository.id]
                old_commit_hash = repo_cache.commit
                repo_cache.cache
              end

      # grab the required commit
      content_directory = File.expand_path(content_directory)
      repository_directory = File.join(content_directory, repository.folder_name)
      new_commit_hash = repository.commit_hash == "HEAD" ? cache.commits(repository.branch, depth: 1).first.hash : repository.commit_hash
      download_required = rebuild_cache || new_commit_hash != old_commit_hash || !Dir.exists?(repository_directory)

      repo_cache = RepoCache.new(repository, cache, new_commit_hash)
      id_lookup[repository.id.not_nil!] = repo_cache
      uri_lookup[repository.uri.not_nil!] = repo_cache
      folder_lookup[repository.folder_name.not_nil!] = repo_cache

      # update files
      if download_required
        Log.trace { "#{repository.folder_name}: downloading new content" }
        commit_ref = repository.commit_hash == "HEAD" ? repository.branch : repository.commit_hash
        commit = cache.fetch_commit(commit_ref, repository_directory)

        # remove old files if folder name changed
        if old_folder_name != repository.folder_name
          Log.trace { "#{repository.folder_name}: removing old folder: #{old_folder_name}" }
          FileUtils.rm_rf(old_folder_name)
        end

        Log.info { {
          message:           "updated frontend repository",
          commit:            commit.hash,
          branch:            repository.branch,
          repository:        repository.folder_name,
          repository_commit: repository.commit_hash,
          uri:               repository.uri,
        } }
      end

      if repository.deployed_commit_hash != new_commit_hash
        Log.info { {
          message:           "updating commit on Repository document",
          current_commit:    new_commit_hash,
          repository_commit: repository.commit_hash,
          folder_name:       repository.folder_name,
        } }
        repository.deployed_commit_hash = new_commit_hash
        repository.update
      end

      Resource::Result::Success
    end

    def self.unload(
      repository : Model::Repository,
      content_directory : String
    )
      content_directory = File.expand_path(content_directory)
      repository_dir = File.expand_path(File.join(content_directory, repository.folder_name))

      id_lookup.delete(repository.id)
      uri_lookup.delete(repository.uri)
      folder_lookup.delete(repository.folder_name)

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

            Log.info { {
              message:           "removed frontend repository",
              branch:            repository.branch,
              repository:        repository.folder_name,
              repository_commit: repository.commit_hash,
              uri:               repository.uri,
            } }

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
