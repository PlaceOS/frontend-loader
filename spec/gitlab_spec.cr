require "./helper"

module PlaceOS::FrontendLoader
  LAB_TEST_FOLDER = "test-gitlab"
  describe GitLab do
    before_each do
      reset
    end
    repository = example_repository(LAB_TEST_FOLDER, uri: "https://gitlab.com/bdowney/ansible-demo/")
    expected_path = File.join(TEST_DIR, repository.folder_name)

    it "downloads a GitLab archive" do
      ref = PlaceOS::FrontendLoader::Remote::Reference.new(repository)
      actioner = PlaceOS::FrontendLoader::GitLab.new
      actioner.download(ref: ref, path: expected_path)
      Dir.exists?(File.join(expected_path, "decks")).should be_true
    end
  end
end
