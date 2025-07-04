# Crystal lang attempts to set permissions after copy
# remove after https://github.com/crystal-lang/crystal/pull/15510 merged
require "file"

class File < IO::FileDescriptor
  def self.copy(src : String | Path, dst : String | Path) : Nil
    open(src) do |s|
      open(dst, "wb") do |d|
        # TODO use sendfile or copy_file_range syscall. See #8926, #8919
        IO.copy(s, d)
        d.flush # need to flush in case permissions are read-only

        # Set the permissions after the content is written in case src permissions is read-only
        d.chmod(s.info.permissions) rescue nil
      end
    end
  end
end
