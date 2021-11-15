require "./helper"

module PlaceOS::FrontendLoader
  LAB_TEST_FOLDER = "test-gitlab"
  describe Remote do
    before_each do
      reset
    end
    repository = example_repository(LAB_TEST_FOLDER, uri: "https://gitlab.com/bdowney/ansible-demo/")
    expected_path = File.join(TEST_DIR, repository.folder_name)
    repo_name = repository.uri.split(".com/").last.rstrip("/")

    it "downloads a GitLab archive" do
      ref = PlaceOS::FrontendLoader::Remote::Reference.new(repo_name, branch: "master", repo_path: expected_path)
      actioner = PlaceOS::FrontendLoader::GitLabRemote.new
      actioner.download(ref: ref)
      Dir.exists?(File.join(expected_path, "decks")).should be_true
    end
  end
end
