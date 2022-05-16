require "placeos-log-backend"
require "file_utils"
require "placeos-models/spec/generator"
require "../src/placeos-frontend-loader"
require "../lib/action-controller/spec/curl_context"
require "action-controller/server"

require "spec"

TEST_DIR = "/app/test-www"

module ExecFrom
  def self.exec_from(
    directory : String,
    command : String,
    arguments : Enumerable(String) = [] of String,
    environment : Process::Env = nil,
    clear_environment : Bool = false,
    capture_stderr : Bool = true,
    input : IO | Process::Redirect = Process::Redirect::Close,
    output : IO = IO::Memory.new
  ) : Result
    puts "\n\n====\n"
    pp! directory
    pp! Dir.current
    pp! Dir.entries("bin")
    pp! File.exists?("./bin/exec_from")
    pp! File.executable?("./bin/exec_from")
    pp! File.info("./bin/exec_from").permissions
    puts "\n===="

    status = Process.run(
      command: Path["./bin/exec_from"].expand.to_s,
      args: [directory, command].concat(arguments),
      input: Process::Redirect::Close,
      env: environment,
      clear_env: clear_environment,
      output: output,
      error: capture_stderr ? output : Process::Redirect::Close,
    )

    Result.new(status, output)
  end
end

Spec.before_suite do
  Log.builder.bind "*", :trace, PlaceOS::LogBackend.log_backend
  reset
end

Spec.after_suite { reset }

PlaceOS::FrontendLoader::Loader.configure &.content_directory=(TEST_DIR)

def reset
  FileUtils.rm_rf(TEST_DIR)
end

TEST_FOLDER = "test-repo"

def example_repository(
  folder_name : String = UUID.random.to_s[0..8],
  uri : String = "https://www.github.com/placeos/compiler",
  commit : String = "HEAD",
  branch : String = "master"
)
  existing = PlaceOS::Model::Repository.where(folder_name: folder_name).first?
  if existing
    existing.uri = uri unless existing.uri == uri
    existing.branch = branch unless existing.branch == branch
    existing.commit_hash = commit unless existing.commit_hash == commit
    existing.save!
    existing
  else
    PlaceOS::Model::Generator.repository(type: :interface).tap do |repository|
      repository.uri = uri
      repository.username = "robot@place.tech"
      repository.folder_name = folder_name
      repository.commit_hash = commit
      repository.branch = branch
    end.save!
  end
end
