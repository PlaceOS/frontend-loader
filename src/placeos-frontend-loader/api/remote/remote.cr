module PlaceOS::FrontendLoader
  abstract class Remote
    private alias Git = PlaceOS::Compiler::Git

    def initialize(@content_directory : Path)
    end

    abstract def commits

    abstract def branches : Hash(String, String)

    abstract def releases : Array(String)

    abstract def download
  end
end

require "../remote/*"
