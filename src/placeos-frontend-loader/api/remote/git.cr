require "./commit"
require "./remote"

module PlaceOS::FrontendLoader
  class GitRepo
    def initialize(@path : String)
    end

    # NOTE:: assumes this path exists!
    getter path
    LOG_FORMAT = "format:%H%n%cI%n%an%n%s%n<--%n%n-->"

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

      stdout = IO::Memory.new
      success = Process.new("git", {"-C", path, "clean", "-fd", "-fx"}, output: stdout, error: stdout).wait.success?
      raise "failed to git clean\n#{stdout}" unless success
    end

    def commits(repository_uri : String, branch : String, count : Int? = 50)
      args = ["-C", path, "clone", repository_uri, "-b", branch]
      args.concat({"--depth", count.to_s}) if count
      # bare repo, no file data, quiet clone, . = clone into current directory
      args.concat({"--bare", "--filter=blob:none", "-q", "."})

      stdout = IO::Memory.new
      success = Process.new("git", args, output: stdout, error: stdout).wait.success?
      raise "failed to clone git history from remote\n#{stdout}" unless success

      errout = IO::Memory.new
      stdout = IO::Memory.new
      success = Process.new("git", {
        "--no-pager",
        "-C", path,
        "log",
        "--format=#{LOG_FORMAT}",
        "--no-color",
        "-n", count.to_s,
      }, output: stdout, error: errout).wait.success?
      raise "failed to obtain git history\n#{errout}" unless success

      stdout.tap(&.rewind)
        .each_line("<--\n\n-->")
        .reject(&.empty?)
        .map { |line|
          commit = line.strip.split("\n").map(&.strip)
          Commit.new(
            commit: commit[0],
            name: commit[3],
            author: commit[2],
            date: commit[1]
          )
        }.to_a
    end
  end
end
