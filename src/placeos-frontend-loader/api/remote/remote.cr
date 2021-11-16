module PlaceOS::FrontendLoader
  abstract class PlaceOS::FrontendLoader::Remote
    private alias Git = PlaceOS::Compiler::Git

    def initialize
    end

    struct Commit
      include JSON::Serializable
      property commit : String
      property date : String
      property author : String
      property subject : String

      def initialize(@commit, @date, @author, @subject)
      end
    end

    struct Reference
      include JSON::Serializable
      getter repo_name : String
      getter branch : String
      getter tag : String | Nil
      getter repo_path : String

      def initialize(@url : String, @branch : String? = "master", @tag : String? = nil, @hash : String? = "HEAD", @repo_path : String = "/")
        @repo_name = @url.split(".com/").last.rstrip("/")
      end
    end

    abstract def commits(repo : String, branch : String) : Array(Commit)

    abstract def branches(repo : String) : Hash(String, String)

    abstract def releases(repo : String) : Array(String)

    abstract def download(ref : Reference, branch : String? = "master", hash : String? = "HEAD", tag : String? = "latest", path : String? = ref.repo_path)
  end
end
