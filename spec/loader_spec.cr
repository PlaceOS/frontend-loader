require "./helper"

module PlaceOS::FrontendLoader
  describe Loader do
    repository = example_repository(TEST_FOLDER)
    expected_path = File.join(TEST_DIR, repository.folder_name)

    before_each do
      repository = example_repository(TEST_FOLDER)
      expected_path = File.join(TEST_DIR, repository.folder_name)
      reset
    end

    describe "#startup_finished?" do
      it "is `true` after initial interfaces have loaded" do
        loader = Loader.new
        loader.startup_finished?.should be_false
        loader.start

        Dir.exists?(File.join(TEST_DIR, "login")).should be_true

        loader.startup_finished?.should be_true
        loader.stop
        loader.startup_finished?.should be_false
      end
    end

    it "implicity loads www base" do
      loader = Loader.new.start

      Dir.exists?(File.join(TEST_DIR, "login")).should be_true

      loader.stop
    end

    describe "updating credentials" do
      it "does not create an update cycle" do
        old_token = "fake_password"
        new_token = "fake_password_electric_boogaloo"

        repository = example_repository(commit: "f7c6d8fb810c2be78722249e06bbfbda3d30d355")
        repository.password = old_token
        repository.save!

        changes = [] of RethinkORM::Changefeed::Change(PlaceOS::Model::Repository)
        spawn do
          Model::Repository.changes.each do |change|
            changes << change
          end
        end

        loader = Loader.new

        loader.process_resource(:created, repository).success?.should be_true
        repository.reload!
        repository.password = new_token
        repository.save!

        repository.password_will_change!
        loader.process_resource(:updated, repository).success?.should be_true

        sleep 10.seconds
        changes.size.should eq 1
      end
    end

    context "processing Repository" do
      loader = Loader.new

      successfully_created = loader.process_resource(:created, repository).success?
      repo_exists = Dir.exists?(expected_path)

      successfully_deleted = loader.process_resource(:deleted, repository).success?
      repo_does_not_exist = !Dir.exists?(expected_path)

      it "loads frontends" do
        successfully_created.should be_true
        repo_exists.should be_true
      end

      it "removes frontends" do
        successfully_deleted.should be_true
        repo_does_not_exist.should be_true
      end
    end

    it "supports changing a uri" do
      expected_uri = "https://github.com/placeOS/private-drivers"
      repository.username = "robot@place.tech"

      loader = Loader.new
      loader.process_resource(:created, repository).success?.should be_true
      Dir.exists?(expected_path).should be_true

      repository.clear_changes_information
      repository.uri = expected_uri
      loader.process_resource(:updated, repository).success?.should be_true

      Dir.exists?(expected_path).should be_true
      Api::Repositories.current_repo(loader.content_directory, TEST_FOLDER).should end_with("private-drivers")
    end

    describe "branches" do
      it "loads a specific branch" do
        loader = Loader.new

        branch = "test-fixture"
        repository.branch = branch

        loader.process_resource(:created, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true
      end

      it "switches branches" do
        loader = Loader.new

        branch = "test-fixture"
        updated_branch = "master"

        repository.branch = branch

        loader.process_resource(:created, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true
        repo = repository.uri.partition(".com/")[2]
        Api::Repositories.current_branch(expected_path, repo).should eq branch
        repository.clear_changes_information
        repository.branch = updated_branch
        loader.process_resource(:updated, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true
        Api::Repositories.current_branch(expected_path, repo).should eq updated_branch
      end
    end
  end
end
