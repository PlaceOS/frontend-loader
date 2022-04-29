require "json"

record(
  PlaceOS::FrontendLoader::Remote::Commit,
  commit : String,
  name : String,
) do
  include JSON::Serializable
end
