require "./helper"

module PlaceOS::FrontendLoader::Api
  describe Root do
    with_server do
      it "health checks" do
        result = curl("GET", "/api/frontend-loader/v1/")
        result.success?.should be_true
      end

      it "should check version" do
        result = curl("GET", "/api/frontend-loader/v1/version")
        result.status_code.should eq 200
        PlaceOS::Model::Version.from_json(result.body).service.should eq "frontend-loader"
      end
    end
  end
end
