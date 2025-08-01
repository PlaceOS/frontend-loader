# Application dependencies
require "action-controller"
require "git-repository"

# Application code
require "./logging"
require "./placeos-frontend-loader"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  ActionController::ErrorHandler.new(PlaceOS::FrontendLoader::PROD, ["X-Request-ID"]),
  ActionController::LogHandler.new(ms: true)
)

require "./placeos-frontend-loader/core_ext/file.cr"
