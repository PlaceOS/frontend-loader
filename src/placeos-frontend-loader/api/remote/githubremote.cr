require "hash_file"
require "octokit"

require "./remote"

abstract class PlaceOS::FrontendLoader::Remote
  class Generic < Remote
  end

  class GitHub < Remote
    TAR_NAME = "temp.tar.gz"

    @github_client = Octokit.client(GIT_USER, GIT_PASS)

    # Returns the branches for a given repo
    def branches(repo : String) : Hash(String, String)
      get_branches = @github_client.branches(repo)
      branches = Hash(String, String).new
      get_branches.fetch_all.each do |branch|
        next if branch =~ /HEAD/
        branches[branch.name] = branch.commit.sha
      end
      branches
    end

    # Returns the commits for a given repo on specified branch
    def commits(repo : String, branch : String) : Array(Remote::Commit)
      get_commits = @github_client.commits(repo, branch)
      commits = Array(Remote::Commit).new
      get_commits.fetch_all.each do |comm|
        commit = Commit.new(
          commit: comm.sha,
          date: comm.commit.author.date,
          author: comm.commit.author.name,
          subject: comm.commit.message,
        )
        commits << commit
      end
      commits
    end

    # Returns the release tags for a given repo
    def releases(repo : String) : Array(String)
      get_tags = @github_client.tags(repo)
      tags = Array(String).new
      get_tags.fetch_all.each { |tag| tags << tag.name }
      tags
    end

    getter api_base = "https://github.com"

    def download(
      ref : Remote::Reference,
      branch : String? = "master",
      hash : String? = "HEAD",
      tag : String? = "latest",
      path : String = "./"
    )
      repository_uri = url(ref.repo_name)
      repository_folder_name = path.split("/").last

      if hash == "HEAD" || hash.nil?
        if tag != "latest"
          hash = get_hash_by_tag(repository_uri, tag)
        elsif branch != "master"
          hash = get_hash_by_branch(repository_uri, branch)
        else
          hash = get_hash_head(repository_uri)
        end
        hash = hash.not_nil!
      end

      Git.repository_lock(repository_folder_name).write do
        Log.info { {
          message:    "downloading repository",
          repository: repository_folder_name,
          branch:     branch,
          uri:        repository_uri,
        } }

        begin
          archive_url = "https://github.com/#{ref.repo_name}/archive/#{hash}.tar.gz"
          download_archive(archive_url)
          extract_archive(path)
          save_metadata(path, hash, repository_uri, branch)
        rescue ex : KeyError | File::Error
          Log.error(exception: ex) { "Could not download repository: #{ex.message}" }
        end
      end
    end

    private def get_commit_hashes(repo_url : String)
      stdout = IO::Memory.new
      Process.new("git", ["ls-remote", repo_url], output: stdout).wait
      output = stdout.to_s.split('\n')
      output.compact_map do |ref|
        next if ref.empty?
        ref.split('\t', limit: 2).reverse
      end.to_h
    end

    private def get_hash_head(repo_url : String)
      ref_hash = get_commit_hashes(repo_url)
      ref_hash.has_key?("HEAD") ? ref_hash["HEAD"] : ref_hash.first_key?
    end

    private def get_hash_by_branch(repo_url : String, branch : String)
      ref_hash = get_commit_hashes(repo_url)
      raise KeyError.new("Branch #{branch} does not exist in repo") unless ref_hash.has_key?("refs/heads/#{branch}")
      ref_hash["refs/heads/#{branch}"]
    end

    # tag = "1.9.0"
    private def get_hash_by_tag(repo_url : String, tag : String)
      ref_hash = get_commit_hashes(repo_url)
      raise KeyError.new("Tag #{tag} does not exist in repo") unless ref_hash.has_key?("refs/tags/v#{tag}")
      ref_hash["refs/tags/v#{tag}"]
    end

    def download_archive(url)
      HTTP::Client.get(url) do |redirect_response|
        raise HTTP::Server::ClientError.new("status_code for #{url} was #{redirect_response.status_code}") unless (redirect_response.success? || redirect_response.status_code == 302)
        HTTP::Client.get(redirect_response.headers["location"]) do |response|
          File.write(TAR_NAME, response.body_io)
        end
      end
      File.new(TAR_NAME)
    rescue ex : File::Error | HTTP::Server::ClientError
      Log.error(exception: ex) { "Could not download file at URL: #{ex.message}" }
    end

    def extract_archive(dest_path)
      raise File::NotFoundError.new(message: "File #{TAR_NAME} does not exist", file: TAR_NAME) unless File.exists?(Path.new(TAR_NAME))
      if !Dir.exists?(Path.new(["./", dest_path]))
        File.open(TAR_NAME) do |file|
          begin
            Compress::Gzip::Reader.open(file) do |gzip|
              Crystar::Reader.open(gzip) do |tar|
                tar.each_entry do |entry|
                  next if entry.file_info.directory?
                  parts = Path.new(entry.name).parts
                  parts = parts.last(parts.size > 1 ? parts.size - 1 : 0)
                  next if parts.size == 0
                  file_path = Path.new([dest_path] + parts)
                  Dir.mkdir_p(file_path.dirname) unless Dir.exists?(file_path.dirname)
                  File.write(file_path, entry.io, perm: entry.file_info.permissions)
                end
              end
            end
          rescue ex : File::Error | Compress::Gzip::Error
            Log.error(exception: ex) { "Could not unzip tar" }
          end
        end
      end
      File.delete(TAR_NAME)
    end

    private def save_metadata(repo_path : String, hash : String, repository_uri : String, branch : String)
      HashFile.config({"base_dir" => "#{repo_path}/metadata"})
      HashFile["current_hash"] = hash
      HashFile["current_repo"] = repository_uri.split(".com/").last
      HashFile["current_branch"] = branch
    end
  end
end
