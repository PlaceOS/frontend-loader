# PlaceOS Frontend Loader

[![Build](https://github.com/PlaceOS/frontend-loader/actions/workflows/build.yml/badge.svg)](https://github.com/PlaceOS/frontend-loader/actions/workflows/build.yml)
[![CI](https://github.com/PlaceOS/frontend-loader/actions/workflows/ci.yml/badge.svg)](https://github.com/PlaceOS/frontend-loader/actions/workflows/ci.yml)
[![Changelog](https://img.shields.io/badge/Changelog-available-github.svg)](/CHANGELOG.md)

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

### Retry Configuration

When repository loading fails (e.g., network issues, GitHub downtime), the loader automatically retries with exponential backoff:

- `PLACE_LOADER_MAX_RETRY_ATTEMPTS`: Maximum number of retry attempts before giving up (default: `10`)
- `PLACE_LOADER_MAX_BACKOFF_SECONDS`: Maximum backoff time between retries in seconds (default: `300` / 5 minutes)

Backoff timing follows the pattern: attempt² seconds (1s, 4s, 9s, 16s...) capped at the max backoff value.

### Client

Included is a simple client that can be configured via the `PLACE_LOADER_URI` environment variable.

```crystal
require "placeos-frontend-loader/client"

# One-shot
commits = PlaceOS::FrontendLoader::Client.client do |client|
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

See [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## Contributors

- [Caspian Baska](https://github.com/caspiano) - creator and maintainer
- [Tassja Kriek](https://github.com/tassja) - contributor and maintainer
