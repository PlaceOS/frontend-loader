module PlaceOS::FrontendLoader
  abstract class Remote
    private alias Git = PlaceOS::Compiler::Git

    def initialize(@ref : String, @folder_name : String)
    end

    abstract def commits

    abstract def branches : Hash(String, String)

    abstract def tags : Array(String)
  end
end

require "../remote/*"
