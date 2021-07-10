# PlaceOS Frontend Loader

[![Build Dev Image](https://github.com/PlaceOS/frontends/actions/workflows/build-dev-image.yml/badge.svg)](https://github.com/PlaceOS/frontends/actions/workflows/build-dev-image.yml)
[![CI](https://github.com/PlaceOS/frontends/actions/workflows/ci.yml/badge.svg)](https://github.com/PlaceOS/frontends/actions/workflows/ci.yml)

![suprisingly, a frontend loader!](./logo.svg)

An application Intended to be a sidecar to a webserver that listens for published front-end repositories and clones them to the webserver's static folder.
The loader can also be configured to update via a CRON.

Included in this repo is an alpine based Dockerfile.

## Usage

- Specify the your static content path via the `PLACE_LOADER_WWW` environment variable, or the `--www` flag.
- Ensure that the content directory is on a shared volume with the webserver.

- A repository pinned to `HEAD` will be kept up to date automatically.
- If a repository commit is specified it will held at that commit.
- Configuring the update frequency is done via a CRON in `PLACE_LOADER_CRON` environment variable, or the `--update-cron` flag. Use [crontab guru](https://crontab.guru/) to validate your CRONs!!!

### Client

Included is a simple client that can be configured via the `PLACE_LOADER_URI` environment variable.

```crystal
require "placeos-frontend-loader/client"

# One-shot
commits = PlaceOS::Frontends::Client.client do |client|
    client.commits("backoffice")
end

commits # => ["fac3caf3", ...]

# Instance
client = PlaceOS::Frontends::Client.new
client.commits("backoffice") # => ["fac3caf3", ...]
client.loaded # => {"backoffice" => "fac3caf3"...}
client.close
```

### Routes

- `GET ../frontends/v1/repositories/:id/commits`: returns a list of commits
- `GET ../frontends/v1/repositories/`: return the loaded frontends and their current commit

## Contributing

1. [Fork it](https://github.com/placeos/frontends/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
