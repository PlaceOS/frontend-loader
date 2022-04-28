# Application dependencies
require "action-controller"

# Application code
require "./logging"
require "./placeos-frontend-loader"

# Require telemery after application code
require "./telemetry"

# Server required after application controllers
require "action-controller/server"

# Add handlers that should run before your application
ActionController::Server.before(
  ActionController::ErrorHandler.new(PlaceOS::FrontendLoader::PROD, ["X-Request-ID"]),
  ActionController::LogHandler.new(ms: true)
)
