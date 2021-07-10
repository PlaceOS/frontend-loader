require "./helper"

module PlaceOS::FrontendLoader::Api
  describe Repositories do
    it "lists commits for a loaded repository" do
      repository = example_repository
      loader = Loader.new.start
      Api::Repositories.loader = loader
      commits = Compiler::Git.repository_commits(repository.folder_name, loader.content_directory) rescue nil
      commits.should_not be_nil
      commits.not_nil!.should_not be_empty
      loader.stop
    end

    it "lists branches for a loaded repository" do
      repository = example_repository
      loader = Loader.new.start
      Api::Repositories.loader = loader

      branches = Compiler::Git.branches(repository.folder_name, loader.content_directory) rescue nil
      branches.should_not be_nil
      branches = branches.not_nil!
      branches.should_not be_empty
      branches.should contain("master")
      loader.stop
    end

    it "lists current commit for all loaded repositories" do
      repository = example_repository
      Api::Repositories.loader = Loader.new.start
      loaded = Api::Repositories.loaded_repositories
      loaded.should be_a(Hash(String, String))
      loaded[repository.folder_name]?.should_not be_nil
      loaded[repository.folder_name].should_not eq("HEAD")
      Api::Repositories.loader.stop
    end
  end
end
