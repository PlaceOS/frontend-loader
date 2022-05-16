require "../helper"

module PlaceOS::FrontendLoader::Api
  describe Repositories do
    it "fetches a specific commit of a generic repository" do
      repository = example_repository(TEST_FOLDER, uri: "https://bitbucket.org/cotag/angular_core_test.git", commit: "5bb5855038cc1ff63636223f389b5b927592e1f8")
      loader = Loader.new
      loader.process_resource(:created, repository).success?.should be_true
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

        Dir.exists?(expected_path).should be_true
      end
    end
  end
end
