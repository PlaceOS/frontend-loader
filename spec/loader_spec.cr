require "./helper"

module PlaceOS::FrontendLoader
  describe Loader do
    repository = example_repository(TEST_FOLDER)
    expected_path = File.join(TEST_DIR, repository.folder_name)

    before_each do
      repository = example_repository(TEST_FOLDER)
      expected_path = File.join(TEST_DIR, repository.folder_name)
      reset
      # Clear retry tracking between tests
      Loader.retry_attempts.clear
      Loader.last_retry_time.clear
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

        changes = [] of PlaceOS::Model::Repository::ChangeFeed::Change(PlaceOS::Model::Repository)
        changefeed = Model::Repository.changes
        spawn do
          changefeed.each do |change|
            changes << change
          end
        end

        Fiber.yield

        repository = example_repository(commit: "f7c6d8fb810c2be78722249e06bbfbda3d30d355")
        repository.password = old_token
        repository.save!
        sleep 200.milliseconds

        loader = Loader.new

        loader.process_resource(:created, repository).success?.should be_true
        repository.reload!

        repository.password = new_token
        repository.password_will_change!
        repository.save!
        sleep 200.milliseconds

        repository = repository.class.find!(repository.id.not_nil!)
        loader.process_resource(:updated, repository).success?.should be_true

        changefeed.stop
        changes.size.should eq 4

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

    describe "error handling" do
      it "should not break on non-existent repo/branch" do
        loader = Loader.new

        branch = "doesnt-exist"
        repository.branch = branch

        loader.process_resource(:created, repository).success?.should be_false
        Dir.exists?(expected_path).should be_false
        repository = Model::Repository.find!(repository.id.as(String))
        repository.has_runtime_error.should be_true
        repository.error_message.should_not be_nil
      end

      it "should clear error flag when branch is correct" do
        loader = Loader.new
        updated_branch = "master"
        branch = "doesnt-exist"
        repository.branch = branch

        loader.process_resource(:created, repository).success?.should be_false
        Dir.exists?(expected_path).should be_false
        repository = Model::Repository.find!(repository.id.as(String))
        repository.has_runtime_error.should be_true
        repository.error_message.should_not be_nil

        repository.branch = updated_branch
        repository.save!
        loader.process_resource(:updated, repository).success?.should be_true
        Dir.exists?(expected_path).should be_true

        repository = Model::Repository.find!(repository.id.as(String))
        repository.has_runtime_error.should be_false
        repository.error_message.should be_nil
      end

      it "should retry with exponential backoff when only error fields are updated" do
        changes = [] of PlaceOS::Model::Repository::ChangeFeed::Change(PlaceOS::Model::Repository)
        changefeed = Model::Repository.changes
        spawn do
          changefeed.each do |change|
            changes << change
          end
        end

        Fiber.yield

        loader = Loader.new
        branch = "doesnt-exist"
        repository.branch = branch
        repository.save!
        sleep 100.milliseconds

        # First attempt should fail and set error fields
        loader.process_resource(:created, repository).success?.should be_false
        Dir.exists?(expected_path).should be_false
        sleep 100.milliseconds

        repository = Model::Repository.find!(repository.id.as(String))
        repository.has_runtime_error.should be_true
        error_msg = repository.error_message
        error_msg.should_not be_nil

        # Clear changes to track only the next error field update
        changes.clear

        # Now update only the error fields through the ORM
        # This simulates what happens when the loader updates error fields after a failed clone
        Model::Repository.update(repository.id, {
          has_runtime_error: true,
          error_message:     "Updated error message",
        })
        sleep 200.milliseconds

        # The changefeed should have received an update event
        changes.size.should be >= 1
        # Find the update event (filter out any other events)
        update_change = changes.find(&.updated?)
        update_change.should_not be_nil

        # First retry should happen immediately (attempt 1, backoff = 1^2 = 1s)
        result = loader.process_resource(:updated, update_change.not_nil!.value)
        result.error?.should be_true # Still fails because branch doesn't exist

        # Wait for any changefeed events from the load failure to be processed
        sleep 300.milliseconds

        # Clear changes and trigger another error-only update
        changes.clear
        Model::Repository.update(repository.id, {
          has_runtime_error: true,
          error_message:     "Still failing",
        })
        sleep 200.milliseconds

        # Verify retry tracking was set
        repo_id = repository.id.not_nil!
        Loader.retry_attempts[repo_id].should eq 1
        Loader.last_retry_time[repo_id].should_not be_nil

        # Verify no successful clone happened
        Dir.exists?(expected_path).should be_false

        changefeed.stop
      end

      it "should stop retrying after max attempts" do
        changes = [] of PlaceOS::Model::Repository::ChangeFeed::Change(PlaceOS::Model::Repository)
        changefeed = Model::Repository.changes
        spawn do
          changefeed.each do |change|
            changes << change
          end
        end

        Fiber.yield

        loader = Loader.new
        branch = "doesnt-exist"
        repository.branch = branch
        repository.save!

        # First attempt should fail
        loader.process_resource(:created, repository).success?.should be_false

        # Simulate max retry attempts by directly setting the counter
        repo_id = repository.id.not_nil!
        max_attempts = Loader.settings.max_retry_attempts
        Loader.retry_attempts[repo_id] = max_attempts

        # Clear changes to track only the next error field update
        changes.clear

        # Now update only the error fields through the ORM
        Model::Repository.update(repository.id, {
          has_runtime_error: true,
          error_message:     "Max retries test",
        })
        sleep 200.milliseconds

        # The changefeed should have received an update event
        update_change = changes.find(&.updated?)
        update_change.should_not be_nil

        # Now when we try to process this error-only update, it should skip due to max retries
        result = loader.process_resource(:updated, update_change.not_nil!.value)
        result.skipped?.should be_true

        # Verify it doesn't increment beyond max
        Loader.retry_attempts[repo_id].should eq max_attempts

        changefeed.stop
      end

      it "should not update database if error fields haven't changed" do
        loader = Loader.new
        branch = "doesnt-exist"
        repository.branch = branch

        # First attempt should fail
        loader.process_resource(:created, repository).success?.should be_false

        repository = Model::Repository.find!(repository.id.as(String))
        initial_updated_at = repository.updated_at
        repository.has_runtime_error.should be_true

        sleep 10.milliseconds

        # Second attempt with same error should not update the database
        # (simulating what would happen if the error fields are already set)
        repository.branch = branch
        loader.process_resource(:created, repository).success?.should be_false

        repository = Model::Repository.find!(repository.id.as(String))
        # updated_at should not have changed since we skip updating when error fields are the same
        repository.updated_at.should eq initial_updated_at
      end

      it "should process when non-error fields change even if error fields also change" do
        changes = [] of PlaceOS::Model::Repository::ChangeFeed::Change(PlaceOS::Model::Repository)
        changefeed = Model::Repository.changes
        spawn do
          changefeed.each do |change|
            changes << change
          end
        end

        Fiber.yield

        loader = Loader.new
        branch = "doesnt-exist"
        repository.branch = branch
        repository.save!
        sleep 100.milliseconds

        # First attempt should fail and set error fields
        loader.process_resource(:created, repository).success?.should be_false
        Dir.exists?(expected_path).should be_false
        sleep 200.milliseconds

        repository = Model::Repository.find!(repository.id.as(String))
        repository.has_runtime_error.should be_true

        # Clear changes to track only the next update
        changes.clear

        # Now update the branch to a valid one AND clear error fields
        # This should NOT be skipped because branch is a real field change
        Model::Repository.update(repository.id, {
          branch:            "master",
          has_runtime_error: false,
          error_message:     nil,
        })
        sleep 200.milliseconds

        # The changefeed should have received an update event
        changes.size.should be >= 1
        update_change = changes.find(&.updated?)
        update_change.should_not be_nil

        # When processing this update with both branch and error fields changed, it should NOT skip
        result = loader.process_resource(:updated, update_change.not_nil!.value)
        result.success?.should be_true

        # Verify the repository was actually loaded
        Dir.exists?(expected_path).should be_true

        changefeed.stop
      end
    end
  end
end
