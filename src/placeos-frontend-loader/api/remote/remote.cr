module PlaceOS::FrontendLoader
  abstract class PlaceOS::FrontendLoader::Remote
    private alias Git = PlaceOS::Compiler::Git

    def initialize
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

    struct Reference
      include JSON::Serializable
      getter repo_name : String
      getter branch : String
      getter tag : String | Nil

      def initialize(@url : String, @branch : String? = "master", @tag : String? = nil, @hash : String? = "HEAD")
        @repo_name = @url.split(".com/").last.rstrip("/")
      end
    end

    abstract def commits(repo : String, branch : String) : Array(Commit)

    abstract def branches(repo : String) : Hash(String, String)

    abstract def releases(repo : String) : Array(String)

    abstract def download(ref : Reference, branch : String? = "master", hash : String? = "HEAD", tag : String? = "latest", path : String = "./")
  end
end
