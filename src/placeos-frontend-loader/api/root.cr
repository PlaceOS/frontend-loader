require "./base"

require "placeos-models/version"

module PlaceOS::FrontendLoader::Api
  class Root < Base
    base "/api/frontend-loader/v1"

    get "/", :root do
      head :ok
    end

    get "/startup", :startup do
      if PlaceOS::FrontendLoader::Loader.instance.startup_finished?
        head :ok
      else
        head :service_unavailable
      end
    end

    get "/version", :version do
      render :ok, json: PlaceOS::Model::Version.new(
        version: VERSION,
        build_time: BUILD_TIME,
        commit: BUILD_COMMIT,
        service: APP_NAME
      )
    end
  end
end
