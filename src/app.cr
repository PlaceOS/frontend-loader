require "option_parser"
require "./constants"

# Server defaults
host = PlaceOS::FrontendLoader::HOST
port = PlaceOS::FrontendLoader::PORT

# Application configuration
content_directory = nil
update_crontab = nil
git_username = nil
git_password = nil

# Command line options
OptionParser.parse(ARGV.dup) do |parser|
  parser.banner = "Usage: #{PlaceOS::FrontendLoader::APP_NAME} [arguments]"

  # Application flags
  parser.on("--www=CONTENT_DIR", "Specifies the content directory") { |d| content_directory = d }
  parser.on("--update-crontab=CRON", "Specifies the update crontab") { |c| update_crontab = c }
  parser.on("--git-username=USERNAME", "Specifies the git username") { |u| git_username = u }
  parser.on("--git-password=PASSWORD", "Specifies the git password") { |p| git_password = p }

  # Server flags
  parser.on("-b HOST", "--bind=HOST", "Specifies the server host") { |h| host = h }
  parser.on("-p PORT", "--port=PORT", "Specifies the server port") { |p| port = p.to_i }
  parser.on("-r", "--routes", "List the application routes") do
    ActionController::Server.print_routes
    exit 0
  end

  parser.on("-v", "--version", "Display the application version") do
    puts "#{PlaceOS::FrontendLoader::APP_NAME} v#{PlaceOS::FrontendLoader::VERSION}"
    exit 0
  end

  parser.on("-c URL", "--curl=URL", "Perform a basic health check by requesting the URL") do |url|
    begin
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      response = client.get uri.to_s
      exit 0 if (200..499).includes? response.status_code
      puts "health check failed, received response code #{response.status_code}"
      exit 1
    rescue error
      puts error.inspect_with_backtrace(STDOUT)
      exit 2
    end
  end

  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} unrecognised"
    puts parser
    exit 1
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit 0
  end
end

require "./config"

# Configure the loader

PlaceOS::FrontendLoader::Loader.configure do |settings|
  content_directory.try { |cd| settings.content_directory = cd }
  update_crontab.try { |uc| settings.update_crontab = uc }
end

# Server Configuration
server = ActionController::Server.new(port, host)

terminate = Proc(Signal, Nil).new do |signal|
  puts " > terminating gracefully"
  spawn { server.close }
  signal.ignore
end

# Detect ctr-c to shutdown gracefully
Signal::INT.trap &terminate
# Docker containers use the term signal
Signal::TERM.trap &terminate

# Asynchronously start the loader
spawn(same_thread: true) do
  begin
    PlaceOS::FrontendLoader::Loader.instance.start
  rescue error
    puts error.inspect_with_backtrace
    PlaceOS::FrontendLoader::Loader::Log.error(exception: error) { "startup failed" }
    server.close
  end
end

# Start the server
server.run do
  puts "Listening on #{server.print_addresses}"
end

# Shutdown message
puts "#{PlaceOS::FrontendLoader::APP_NAME} leaps through the veldt\n"
