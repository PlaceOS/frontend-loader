require "./base"

require "placeos-models/version"

module PlaceOS::FrontendLoader::Api
  class Root < Base
    base "/api/frontend-loader/v1"

    # health check, is the service responsive
    @[AC::Route::GET("/")]
    def root : Nil
    end

    # has the service finished initializing
    @[AC::Route::GET("/startup")]
    def startup : Nil
      unless PlaceOS::FrontendLoader::Loader.instance.startup_finished?
        raise Error::ServiceUnavailable.new("frontends has not finished loading repositories")
      end
    end

    # return the service build details
    @[AC::Route::GET("/version")]
    def version : PlaceOS::Model::Version
      PlaceOS::Model::Version.new(
        version: VERSION,
        build_time: BUILD_TIME,
        commit: BUILD_COMMIT,
        service: APP_NAME
      )
    end
  end
end
