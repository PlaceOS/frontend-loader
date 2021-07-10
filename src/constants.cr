require "secrets-env"

module PlaceOS::FrontendLoader
  APP_NAME     = "frontend-loader"
  VERSION      = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  BUILD_TIME   = {{ system("date -u").stringify }}
  BUILD_COMMIT = {{ env("PLACE_COMMIT") || "DEV" }}

  PROD = (ENV["SG_ENV"]? || ENV["ENV"]?) == "production"

  class_getter? production : Bool = PROD

  # defaults used in `./app.cr`
  HOST = ENV["PLACE_LOADER_HOST"]? || "127.0.0.1"
  PORT = (ENV["PLACE_LOADER_PORT"]? || 3000).to_i

  # settings for `./placeos-frontend-loader/loader.cr`
  WWW      = ENV["PLACE_LOADER_WWW"]? || "www"
  CRON     = ENV["PLACE_LOADER_CRON"]? || "0 * * * *"
  GIT_USER = ENV["PLACE_LOADER_GIT_USER"]?
  GIT_PASS = ENV["PLACE_LOADER_GIT_PASS"]?

  # NOTE:: following used in `./placeos-frontend-loader/client.cr`
  # URI.parse(ENV["PLACE_LOADER_URI"]? || "http://127.0.0.1:3000")
  # Independent of this file as used in other projects
end
