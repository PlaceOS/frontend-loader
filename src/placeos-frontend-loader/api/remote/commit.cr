require "json"

struct PlaceOS::FrontendLoader::Commit
  include JSON::Serializable

  getter commit : String
  getter name : String
  getter subject : String

  getter author : String?
  getter date : String?

  def initialize(@commit : String, name : String, @author : String? = nil, @date : String? = nil)
    @name = @subject = name
  end
end
