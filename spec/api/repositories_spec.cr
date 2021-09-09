require "../helper"

module PlaceOS::FrontendLoader::Api
  describe Repositories do
    describe "query" do
      it "does not mutate the managed repositories" do
        branch = "test-fixture"
        checked_out_commit = "d37c34a49c96a2559408468b2b9458867cbf1329"
        folder = UUID.random.to_s
        repo = PlaceOS::Model::Generator.repository(type: :interface).tap do |r|
          r.name = "compiler"
          r.uri = "https://github.com/placeos/compiler"
          r.username = "robot@place.tech"
          r.branch = branch
          r.commit_hash = checked_out_commit
          r.folder_name = folder
        end
        loader = Loader.new

        loader.process_resource(:created, repo).success?.should be_true

        expected_path = File.join(loader.content_directory, folder)

        Dir.exists?(expected_path).should be_true
        Compiler::Git.current_repository_commit(folder, loader.content_directory).should eq checked_out_commit
        Api::Repositories.with_query_directory(folder, loader) do |key, directory|
          Compiler::Git.current_repository_commit(key, directory).should eq checked_out_commit
          Api::Repositories.branches(folder, loader).not_nil!.should_not be_empty
          Api::Repositories.commits(folder, branch, loader: loader).not_nil!.should_not be_empty
          Api::Repositories.commits(folder, "master", loader: loader).not_nil!.should_not be_empty
        end
        Compiler::Git.current_repository_commit(folder, loader.content_directory).should eq checked_out_commit
      end
    end
  end
end
