require "hash_file"

class Metadata
  private getter hash_file : HashFile = HashFile
  private getter lock : Mutex = Mutex.new(protection: Mutex::Protection::Reentrant)

  def initialize
    hash_file.config({"base_dir" => Dir.current})
  end

  class_getter instance : Metadata do
    new
  end

  def get_metadata(repo_name, field)
    lock.synchronize do
      hash_file["#{repo_name}/metadata/#{field}"].to_s.strip
    end
  end

  def remote_type(repo_name)
    lock.synchronize do
      begin
        PlaceOS::FrontendLoader::Remote::Reference::Type.parse?(hash_file["#{repo_name}/metadata/remote_type"].to_s.strip)
      rescue
        PlaceOS::FrontendLoader::Remote::Reference::Type::Generic
      end
    end
  end

  def set_metadata(repo_name, field, value)
    lock.synchronize do
      hash_file["#{repo_name}/metadata/#{field}"] = value.to_s
    end
  end
end
