require "../helper"

module PlaceOS::FrontendLoader::Api
  describe Remotes do
    client = AC::SpecHelper.client
    remotes_base = "/api/frontend-loader/v1/remotes"

    it "lists releases for a given repository" do
      pending!("we need to implement a github specific repository client")

      encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
      route = "#{remotes_base}/#{encoded_url}/releases"
      result = client.get(route)
      Array(String).from_json(result.body).includes?("v0.11.2").should be_true
    end

    it "lists commits for a given repository" do
      encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
      route = "#{remotes_base}/#{encoded_url}/commits"
      result = client.get(route)
      Array(GitRepository::Commit).from_json(result.body).should_not be_empty
    end

    it "lists branches for a given repository" do
      encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
      route = "#{remotes_base}/#{encoded_url}/branches"
      result = client.get(route)
      Array(String).from_json(result.body).includes?("master").should be_true
    end

    it "lists tags for a given repository" do
      encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
      route = "#{remotes_base}/#{encoded_url}/tags"
      result = client.get(route)
      Array(String).from_json(result.body).includes?("v1.3.0").should be_true
    end

    it "lists folders in a given repository" do
      encoded_url = URI.encode_www_form("https://www.github.com/PlaceOS/frontend-loader")
      route = "#{remotes_base}/#{encoded_url}/folders"
      result = client.get(route)
      Array(String).from_json(result.body).includes?("src").should be_true
    end
  end
end
