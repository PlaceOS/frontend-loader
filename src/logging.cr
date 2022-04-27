require "placeos-log-backend"
require "placeos-log-backend/telemetry"

require "./constants"

module PlaceOS::FrontendLoader::Logging
  ::Log.progname = APP_NAME
  log_level = PlaceOS::FrontendLoader.production? ? Log::Severity::Info : Log::Severity::Debug
  ::Log.setup_from_env default_sources: "*", default_level: log_level, backend: PlaceOS::LogBackend.log_backend, log_level_env: "LOG_LEVEL"

  PlaceOS::LogBackend.configure_opentelemetry(
    service_name: APP_NAME,
    service_version: VERSION,
  )
end
