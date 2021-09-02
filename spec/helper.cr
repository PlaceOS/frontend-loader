require "placeos-log-backend"
require "file_utils"
require "placeos-models/spec/generator"
require "../src/placeos-frontend-loader"
require "../lib/action-controller/spec/curl_context"
require "action-controller/server"

require "spec"

TEST_DIR = "test-www"

Spec.before_suite do
  Log.builder.bind "*", :trace, PlaceOS::LogBackend.log_backend
  reset
end

Spec.after_suite { reset }

PlaceOS::FrontendLoader::Loader.configure &.content_directory=(TEST_DIR)

def reset
  FileUtils.rm_rf(TEST_DIR)
end

def example_repository(
  uri : String = "https://github.com/placeos/backoffice",
  branch : String = "master"
)
  existing = PlaceOS::Model::Repository.where(folder_name: "backoffice").first?
  if existing
    unless existing.uri == uri && existing.branch == branch
      existing.uri = uri
      existing.branch = branch
    end

    existing
  else
    repository = PlaceOS::Model::Generator.repository(type: :interface)
    repository.uri = uri
    repository.name = "Backoffice"
    repository.folder_name = "backoffice"
    repository.branch = branch
    repository
  end
end
