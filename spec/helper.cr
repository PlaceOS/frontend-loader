require "placeos-log-backend"
require "file_utils"
require "placeos-models/spec/generator"
require "../src/placeos-frontend-loader"

# Helper methods for testing controllers (curl, with_server, context)
require "action-controller/spec_helper"

require "spec"

TEST_DIR = "/app/test-www"

PgORM::Database.configure { |_| }
PgORM::Database.connection do |db|
  db.exec <<-SQL
    DROP TABLE IF EXISTS "repo"
  SQL

  db.exec <<-SQL
  CREATE TABLE IF NOT EXISTS "repo"(
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    folder_name TEXT NOT NULL,
    uri TEXT NOT NULL,
    commit_hash TEXT NOT NULL,
    branch TEXT NOT NULL,
    deployed_commit_hash TEXT,
    release BOOLEAN NOT NULL,
    username TEXT,
    password TEXT,
    repo_type INTEGER NOT NULL,
    id TEXT NOT NULL PRIMARY KEY
  );
  SQL
end

Spec.before_suite do
  Log.builder.bind "*", :info, PlaceOS::LogBackend.log_backend
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
