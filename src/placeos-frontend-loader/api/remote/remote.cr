require "mt_helpers/synchronized"

module PlaceOS::FrontendLoader
  abstract class PlaceOS::FrontendLoader::Remote
    private alias Git = PlaceOS::Compiler::Git

    class MetadataStore < Syncrhonized(HashFile)
    end

    protected class_getter remotes : Hash(Class, Remote) = {} of Class => Remote

    protected class_getter metadata_store : MetadataStore do
      MetadataStore.new
    end

    def self.from_url(url : String) : Remote?
      case url
      when Remote::Github.url_pattern then remotes[Remote::Github] ||= Remote::Github.new(metadata_store)
      when Remote::Gitlab.url_pattern then remotes[Remote::Gitlab] ||= Remote::Gitlab.new(metadata_store)
      end
    end

    getter store : MetadataStore

    def initialize(@store : MetadataStore)
    end

    struct Commit
      include JSON::Serializable
      getter commit : String
      getter date : String
      getter author : String
      getter subject : String

      def initialize(@commit, @date, @author, @subject)
      end
    end

    def url(repo_name : String) : String
      File.join(api_base, repo_name)
    end

    abstract def api_base : String

    struct Reference
      include JSON::Serializable

      getter repo_name : String
      getter branch : String
      getter tag : String?
      getter hash : String

      def initialize(@url : String, @branch : String? = "master", @tag : String? = nil, @hash : String? = "HEAD")
        raise ArgumentError.new("Expected tag or hash to not be nil") unless @hash || @tag
        @repo_name = @url.split(".com/").last.rstrip("/")
      end
    end

    abstract def commits(repo : String, branch : String) : Array(Commit)

    abstract def branches(repo : String) : Hash(String, String)

    abstract def releases(repo : String) : Array(String)

    abstract def download(ref : Reference, branch : String? = "master", hash : String? = "HEAD", tag : String? = "latest", path : String = "./")
  end
end

require "./github"
require "./gitlab"
