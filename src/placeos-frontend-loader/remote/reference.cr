require "json"

module PlaceOS::FrontendLoader
  struct Remote::Reference
    include JSON::Serializable

    enum Type
      GitLab
      Github
      Generic
    end

    getter uri : URI
    getter repo_name : String
    getter remote_type : Reference::Type
    getter branch : String
    getter hash : String
    getter tag : String | Nil

    def initialize(
      url : String | URI,
      @branch : String? = "master",
      @tag : String? = nil,
      @hash : String? = "HEAD",
      user : String? = nil,
      pass : String? = nil
    )
      @uri = uri = url.is_a?(URI) ? url : URI.parse(url)
      if user.presence && pass.presence
        uri.user = user
        uri.password = pass
      end

      @repo_name = uri.path.strip("/")
      @remote_type = {% begin %}
          case uri.host.to_s
            {% for remote in Reference::Type.constants %}
          when .includes?(Reference::Type::{{ remote }}.to_s.downcase)
            Reference::Type::{{ remote.id }}
          {% end %}
          else
            Reference::Type::Generic
          end
          {% end %}
    end

    def self.from_repository(repository : Model::Repository)
      hash = repository.should_pull? ? "HEAD" : repository.commit_hash
      self.new(url: repository.uri, branch: repository.branch, hash: hash, user: repository.username, pass: repository.decrypt_password)
    end

    def remote
      case remote_type
      in Type::Github
        Github.new
      in Type::GitLab
        GitLab.new
      in Type::Generic
        Generic.new(uri)
      end
    end
  end
end
