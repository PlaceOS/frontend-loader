require "./helper"

module PlaceOS::FrontendLoader::Api
  describe Repositories do
    it "lists commits for a loaded repository" do
      repository = example_repository
      repository.save! unless repository.persisted?
      loader = Loader.new
      loader.process_resource(:created, repository).success?.should be_true
      commits = Compiler::Git.repository_commits(repository.folder_name, loader.content_directory) rescue nil
      commits.should_not be_nil
      commits.not_nil!.should_not be_empty
    end

    it "lists branches for a loaded repository" do
      repository = example_repository
      repository.save! unless repository.persisted?
      loader = Loader.new
      loader.process_resource(:created, repository).success?.should be_true

      branches = Compiler::Git.branches(repository.folder_name, loader.content_directory) rescue nil
      branches.should_not be_nil
      branches = branches.not_nil!
      branches.should_not be_empty
      branches.should contain("master")
    end

    it "lists current commit for all loaded repositories" do
      repository = example_repository
      repository.save! unless repository.persisted?
      loader = Loader.new
      loader.process_resource(:created, repository).success?.should be_true
      Api::Repositories.loader = loader
      loaded = Api::Repositories.loaded_repositories
      loaded.should be_a(Hash(String, String))
      loaded[repository.folder_name]?.should_not be_nil
      loaded[repository.folder_name].should_not eq("HEAD")
    end
  end
end
