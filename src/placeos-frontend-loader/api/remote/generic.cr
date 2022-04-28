require "./remote"

module PlaceOS::FrontendLoader
  class Generic < PlaceOS::FrontendLoader::Remote
    def initialize(@uri : URI, @metadata : Metadata = Metadata.instance)
    end

    private alias Remote = PlaceOS::FrontendLoader::Remote

    class GitRepo
      def initialize(@path : String)
      end

      getter path

      def init
        stdout = IO::Memory.new
        success = Process.new("git", {"-C", path, "init"}, output: stdout, error: stdout).wait.success?
        raise "failed to init git repository\n#{stdout}" unless success
      end

      def remove_origin
        # This only fails when there is no origin specified
        Process.new("git", {"-C", path, "remote", "remove", "origin"}).wait.success?
      end

      def add_origin(repository_uri : String)
        stdout = IO::Memory.new
        success = Process.new("git", {"-C", path, "remote", "add", "origin", repository_uri}, output: stdout, error: stdout).wait.success?
        raise "failed to add git origin #{repository_uri.inspect}\n#{stdout}" unless success
      end

      def fetch(branch : String)
        stdout = IO::Memory.new
        success = Process.new("git", {"-C", path, "fetch", "--depth", "1", "origin", branch}, output: stdout, error: stdout).wait.success?
        raise "failed to git fetch #{branch.inspect}\n#{stdout}" unless success
      end

      def checkout(branch : String)
        stdout = IO::Memory.new
        success = Process.new("git", {"-C", path, "checkout", branch}, output: stdout, error: stdout).wait.success?
        raise "failed to git checkout #{branch.inspect}\n#{stdout}" unless success
      end

      def reset
        stdout = IO::Memory.new
        success = Process.new("git", {"-C", path, "reset", "--hard"}, output: stdout, error: stdout).wait.success?
        raise "failed to git reset\n#{stdout}" unless success
      end
    end

    # none available for generic repos
    def releases(repo : String) : Array(String)
      [""]
    end

    def url(repo_name : String) : String
      @uri.to_s
    end

    def download(
      ref : Remote::Reference,
      path : String,
      branch : String? = "master",
      hash : String? = "HEAD",
      tag : String? = nil
    )
      repository_uri = ref.uri.to_s
      repository_folder_name = path.split("/").last

      Git.repository_lock(repository_folder_name).write do
        Log.info { {
          message:    "downloading repository",
          repository: repository_folder_name,
          branch:     branch,
          uri:        repository_uri,
        } }

        Dir.mkdir_p(path) if !Dir.exists?(path)

        git = GitRepo.new(path)
        git.init if !Dir.exists?(Path.new(path, ".git"))

        # origin might have changed
        git.remove_origin
        git.add_origin repository_uri

        if !hash.presence || hash == "HEAD"
          git.fetch branch    # git fetch --depth 1 origin branch
          git.reset           # git reset --hard
          git.checkout branch # git checkout branch
        else
          git.reset
          git.fetch hash            # git fetch --depth 1 origin <sha1>
          git.checkout "FETCH_HEAD" # git checkout FETCH_HEAD
        end

        save_metadata(path, hash, repository_uri, branch, ref.remote_type)
      end
    end
  end
end
