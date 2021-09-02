require "./helper"

module PlaceOS::FrontendLoader
  describe Loader do
    repository = example_repository
    expected_path = File.join(TEST_DIR, repository.folder_name)

    Spec.before_each do
      repository = example_repository
      reset
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

        changes = [] of RethinkORM::Changefeed::Change(PlaceOS::Model::Repository)
        repo = PlaceOS::Model::Generator.repository(type: :interface).tap do |r|
          r.uri = "https://github.com/PlaceOS/private-drivers"
          r.name = "drivers"
          r.folder_name = UUID.random.to_s
          r.username = "robot@place.tech"
          r.commit_hash = "7c47ed0e2d59471a1617c21f3629c682d5aefb18"
          r.password = old_token
        end.save!

        spawn do
          Model::Repository.changes.each do |change|
            changes << change
          end
        end

        Fiber.yield

        loader = Loader.new

        loader.process_resource(:created, repo).success?.should be_true
        repo.reload!
        repo.password = new_token
        repo.save!

        repo.password_will_change!
        loader.process_resource(:updated, repo).success?.should be_true

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
      loader = Loader.new

      expected_uri = "https://github.com/place-labs/backoffice-alpha"

      loader.process_resource(:created, repository).success?.should be_true
      Dir.exists?(expected_path).should be_true

      repository.clear_changes_information
      repository.uri = expected_uri
      loader.process_resource(:updated, repository).success?.should be_true

      Dir.exists?(expected_path).should be_true

      url = ExecFrom.exec_from(expected_path, "git", {"remote", "get-url", "origin"}).output.to_s
      url.strip.should end_with("backoffice-alpha")
    end

    describe "branches" do
      it "loads a specific branch" do
        loader = Loader.new

        branch = "build-alpha"
        repository.branch = branch

        loader.process_resource(:created, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true

        Compiler::Git.current_branch(expected_path).should eq branch
      end

      it "switches branches" do
        loader = Loader.new

        branch = "build-alpha"
        updated_branch = "master"

        repository.branch = branch

        loader.process_resource(:created, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true
        Compiler::Git.current_branch(expected_path).should eq branch

        repository.clear_changes_information
        repository.branch = updated_branch

        loader.process_resource(:updated, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true
        Compiler::Git.current_branch(expected_path).should eq updated_branch
      end
    end
  end
end
