require "placeos-log-backend"

require "./constants"

module PlaceOS::FrontendLoader::Logging
  ::Log.progname = APP_NAME
  log_level = PlaceOS::FrontendLoader.production? ? Log::Severity::Info : Log::Severity::Debug
  ::Log.setup_from_env default_sources: "*", default_level: log_level, backend: PlaceOS::LogBackend.log_backend, log_level_env: "LOG_LEVEL"
end
