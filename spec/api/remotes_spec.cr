require "../helper"

module PlaceOS::FrontendLoader::Api
  describe Remotes do
    with_server do
      remotes_base = "/api/frontend-loader/v1/remotes"
      it "lists releases for a given repository" do
        encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
        route = "#{remotes_base}/#{encoded_url}/releases"
        result = curl("GET", route)
        Array(String).from_json(result.body).includes?("v0.11.2").should be_true
      end

      it "lists commits for a given repository" do
        encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
        route = "#{remotes_base}/#{encoded_url}/commits"
        result = curl("GET", route)
        Array(PlaceOS::FrontendLoader::Commit).from_json(result.body).should_not be_empty
      end

      it "lists branches for a given repository" do
        encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
        route = "#{remotes_base}/#{encoded_url}/branches"
        result = curl("GET", route)
        Array(String).from_json(result.body).includes?("master").should be_true
      end

      it "lists tags for a given repository" do
        encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
        route = "#{remotes_base}/#{encoded_url}/tags"
        result = curl("GET", route)
        Array(String).from_json(result.body).includes?("v1.3.0").should be_true
      end
    end
  end
end
