require "./helper"

module PlaceOS::FrontendLoader::Api
  describe Root do
    it "health checks" do
      result = client.get("/api/frontend-loader/v1/")
      result.success?.should be_true
    end

    it "should check version" do
      result = client.get("/api/frontend-loader/v1/version")
      result.status_code.should eq 200
      PlaceOS::Model::Version.from_json(result.body).service.should eq "frontend-loader"
    end
  end
end
