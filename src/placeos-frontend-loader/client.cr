require "http"
require "json"
require "mutex"
require "uri"

require "./error"

module PlaceOS::FrontendLoader
  class Client
    BASE_PATH   = "/api/frontends"
    API_VERSION = "v1"
    DEFAULT_URI = URI.parse(ENV["PLACE_LOADER_URI"]? || "http://127.0.0.1:3000")
    getter api_version : String

    # Set the request_id on the client
    property request_id : String?

    getter uri : URI

    # A one-shot Core client
    def self.client(
      uri : URI = DEFAULT_URI,
      request_id : String? = nil,
      api_version : String = API_VERSION
    )
      client = new(uri, request_id, api_version)
      begin
        response = yield client
      ensure
        client.connection.close
      end

      response
    end

    # Queries
    ###########################################################################

    # Returns the loaded repositories on the node
    def loaded
      response = get("/repositories")

      Hash(String, String).from_json(response.body)
    end

    # Commits for a frontend folder
    def commits(folder_name : String, branch : String, count : Int32? = nil)
      params = HTTP::Params{"branch" => branch}
      params["count"] = count unless count.nil?
      path = "/repositories/#{folder_name}/commits?#{params}"
      response = get(path)
      Array(NamedTuple(commit: String, date: String, author: String, subject: String)).from_json(response.body)
    end

    # Branches for a frontend folder
    def branches(folder_name : String)
      path = "/repositories/#{folder_name}/branches"
      response = get(path)

      Array(String).from_json(response.body)
    end

    def version : PlaceOS::Model::Version
      Model::Version.from_json(get("/version").body)
    end

    ###########################################################################

    def initialize(
      @uri : URI = DEFAULT_URI,
      @request_id : String? = nil,
      @api_version : String = API_VERSION
    )
      @connection = HTTP::Client.new(@uri)
    end

    @connection : HTTP::Client?

    protected def connection
      @connection.as(HTTP::Client)
    end

    protected getter connection_lock : Mutex = Mutex.new

    def close
      connection_lock.synchronize do
        connection.close
      end
    end

    # Base struct for responses
    private abstract struct BaseResponse
      include JSON::Serializable
    end

    # API modem
    ###########################################################################

    {% for method in %w(get post) %}
      # Executes a {{method.id.upcase}} request on core connection.
      #
      # The response status will be automatically checked and a `ClientError` raised if
      # unsuccessful.
      # ```
      private def {{method.id}}(path, headers : HTTP::Headers? = nil, body : HTTP::Client::BodyType? = nil)
        path = File.join(BASE_PATH, API_VERSION, path)

        response = connection_lock.synchronize do
          connection.{{method.id}}(path, headers, body)
        end
        raise ClientError.from_response("#{uri}#{path}", response) unless response.success?

        response
      end

      # Executes a {{method.id.upcase}} request on the core client connection with a JSON body
      # formed from the passed `NamedTuple`.
      private def {{method.id}}(path, body : NamedTuple)
        headers = HTTP::Headers{
          "Content-Type" => "application/json"
        }
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json)
      end

      # :ditto:
      private def {{method.id}}(path, headers : HTTP::Headers, body : NamedTuple)
        headers["Content-Type"] = "application/json"
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json)
      end

      # Executes a {{method.id.upcase}} request and yields a `HTTP::Client::Response`.
      #
      # When working with endpoint that provide stream responses these may be accessed as available
      # by calling `#body_io` on the yielded response object.
      #
      # The response status will be automatically checked and a Core::ClientError raised if unsuccessful.
      private def {{method.id}}(path, headers : HTTP::Headers? = nil, body : HTTP::Client::BodyType = nil)
        connection.{{method.id}}(path, headers, body) do |response|
          raise ClientError.from_response("#{@uri}#{path}", response) unless response.success?
          yield response
        end
      end

      # Executes a {{method.id.upcase}} request on the core client connection with a JSON body
      # formed from the passed `NamedTuple` and yields streamed response entries to the block.
      private def {{method.id}}(path, body : NamedTuple)
        headers = HTTP::Headers{
          "Content-Type" => "application/json"
        }
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json) do |response|
          yield response
        end
      end

      # :ditto:
      private def {{method.id}}(path, headers : HTTP::Headers, body : NamedTuple)
        headers["Content-Type"] = "application/json"
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json) do |response|
          yield response
        end
      end
    {% end %}
  end
end
