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

        loader.startup_finished?.should be_true
        Dir.exists?(File.join(TEST_DIR, "login")).should be_true

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

        changes = [] of PlaceOS::Model::Repository::ChangeFeed::Change(PlaceOS::Model::Repository)
        changefeed = Model::Repository.changes
        spawn do
          changefeed.each do |change|
            changes << change
          end
        end

        sleep 1

        loader = Loader.new

        loader.process_resource(:created, repository).success?.should be_true
        repository.reload!
        repository.password = new_token
        repository.password_will_change!
        repository.save!

        repository = repository.class.find!(repository.id.not_nil!)
        loader.process_resource(:updated, repository).success?.should be_true

        changefeed.stop
        changes.size.should eq 2

        repository.reload!
        encrypted = repository.password.not_nil!
        encrypted.should_not eq new_token
        encrypted.should start_with '\e'
      end
    end

    context "processing Repository" do
      loader = Loader.new

      successfully_created = loader.process_resource(:created, repository).success?
      repo_exists = Dir.exists?(expected_path)
      git_exists = Dir.exists?(File.join(expected_path, ".git"))

      successfully_deleted = loader.process_resource(:deleted, repository).success?
      repo_does_not_exist = !Dir.exists?(expected_path)

      it "loads frontends" do
        successfully_created.should be_true
        repo_exists.should be_true
      end

      it "removes the git folder" do
        git_exists.should be_false
      end

      it "removes frontends" do
        successfully_deleted.should be_true
        repo_does_not_exist.should be_true
      end
    end

    it "supports changing a uri" do
      expected_uri = "https://www.github.com/placeOS/private-drivers"
      repository = repository.class.find!(repository.id.not_nil!)
      repository.username = "robot@place.tech"

      loader = Loader.new
      loader.process_resource(:created, repository).success?.should be_true
      Dir.exists?(expected_path).should be_true

      repository = repository.class.find!(repository.id.not_nil!)
      repository.uri = expected_uri
      loader.process_resource(:updated, repository).success?.should be_true

      Dir.exists?(expected_path).should be_true
      File.exists?("#{TEST_DIR}/test-repo/README.md").should be_true
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
        repository.save!
        repository = repository.class.find!(repository.id.not_nil!)

        loader.process_resource(:created, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true

        repository = repository.class.find!(repository.id.not_nil!)
        repository.branch = updated_branch
        repository.save!
        loader.process_resource(:updated, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true
      end
    end
  end
end
