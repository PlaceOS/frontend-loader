require "../helper"

module PlaceOS::FrontendLoader::Api
  describe Repositories do
    it "lists commits for a loaded repository" do
      repository = example_repository(TEST_FOLDER)
      loader = Loader.new
      loader.process_resource(:created, repository).success?.should be_true
      commits = Api::Repositories.commits(repository.folder_name, repository.branch, loader: loader).not_nil!
      commits.should_not be_empty
    end

    it "lists branches for a loaded repository" do
      repository = example_repository(TEST_FOLDER)
      loader = Loader.new
      loader.process_resource(:created, repository).success?.should be_true
      branches = Api::Repositories.branches(repository.folder_name, loader).not_nil!
      branches.should_not be_empty
      branches.should contain("master")
    end

    it "lists current commit for all loaded repositories" do
      repository = example_repository(TEST_FOLDER)
      Api::Repositories.loader = Loader.new
      Api::Repositories.loader.process_resource(:created, repository).success?.should be_true

      loaded = Api::Repositories.loaded_repositories
      loaded.should be_a(Hash(String, String))
      loaded[repository.folder_name]?.should_not be_nil
      loaded[repository.folder_name].should_not eq("HEAD")
    end

    describe "query" do
      it "does not mutate the managed repositories" do
        branch = "test-fixture"
        checked_out_commit = "d37c34a49c96a2559408468b2b9458867cbf1329"
        repository = example_repository(branch: branch, commit: checked_out_commit)

        loader = Loader.new
        loader.process_resource(:created, repository).success?.should be_true

        folder = repository.folder_name
        expected_path = File.join(loader.content_directory, folder)

        repo = repository.uri.partition(".com/")[2]
        Dir.exists?(expected_path).should be_true
        Api::Repositories.current_commit(loader.content_directory, folder).should eq checked_out_commit
        Api::Repositories.branches(folder, loader).not_nil!.should_not be_empty
        Api::Repositories.commits(folder, branch, loader: loader).not_nil!.should_not be_empty
        Api::Repositories.commits(folder, "master", loader: loader).not_nil!.should_not be_empty
        Api::Repositories.current_commit(loader.content_directory, folder).should eq checked_out_commit
      end
    end
  end
end
