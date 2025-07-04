## Unreleased

### Feat

- **shard.lock**: add crystal 1.13 support
- PPT-1413 Add error handling + reporting. Clean-up and linting c… ([#84](https://github.com/PlaceOS/frontend-loader/pull/84))
- **shard.lock**: bump opentelemetry-instrumentation.cr

### Fix

- use debian as musl libc doesn't work with NFS
- **Dockerfile**: make git certificate store is explicit
- file copy issue with some volumes ([#87](https://github.com/PlaceOS/frontend-loader/pull/87))
- **Dockerfile**: use busybox to set permissions
- **Dockerfile**: owner needs to be available in the image
- **Dockerfile**: allow random user ids in production ([#86](https://github.com/PlaceOS/frontend-loader/pull/86))
- **remotes**: ensure file listing on a branch works
- **resource**: replaced change feed iterator with async closure
- **resource**: replaced change feed iterator with async closure
- **loader**: specify load timeout
- **resource**: missing change events
- **eventbus**: handle read replica race conditions
- **eventbus**: handle read replica race conditions
- **eventbus**: handle read replica race conditions
- **loader**: ensure sub directories are updated for www-core ([#83](https://github.com/PlaceOS/frontend-loader/pull/83))

### Refactor

- PPT-1456 Remove Raven dependency ([#85](https://github.com/PlaceOS/frontend-loader/pull/85))

## v3.0.0 (2023-03-15)

### Refactor

- migrate to postgres ([#82](https://github.com/PlaceOS/frontend-loader/pull/82))

## v2.7.0 (2022-11-01)

### Feat

- **Dockerfile**: build a minimal image ([#79](https://github.com/PlaceOS/frontend-loader/pull/79))

## v2.6.0 (2022-10-18)

### Feat

- **loader**: remove git folder once downloaded ([#77](https://github.com/PlaceOS/frontend-loader/pull/77))

## v2.5.3 (2022-09-22)

## v2.5.2 (2022-09-21)

### Fix

- querying generic git repos with auth ([#75](https://github.com/PlaceOS/frontend-loader/pull/75))

## v2.5.1 (2022-09-15)

### Feat

- **api/remotes**: allow querying protected remotes ([#74](https://github.com/PlaceOS/frontend-loader/pull/74))
- add support for ARM64 images ([#72](https://github.com/PlaceOS/frontend-loader/pull/72))

### Fix

- **Dockerfile**: app dependencies and fs permissions
- **Dockerfile**: revert static build ([#73](https://github.com/PlaceOS/frontend-loader/pull/73))
- **app**: removal of connect-proxy ext broke compilation

## v2.5.0 (2022-05-17)

### Feat

- add support for dev.azure repositories

## v2.4.1 (2022-05-16)

### Fix

- **loader**: provide feedback of the deployed commit hash ([#67](https://github.com/PlaceOS/frontend-loader/pull/67))

## v2.4.0 (2022-05-14)

### Feat

- refactor using git-repository ([#66](https://github.com/PlaceOS/frontend-loader/pull/66))

## v2.3.6 (2022-05-04)

### Fix

- **api/remote**: cleanup temp files

## v2.3.5 (2022-05-04)

### Fix

- **client**: should use standard commit struct

## v2.3.4 (2022-05-04)

### Fix

- **remote**: only listing a single commit ([#65](https://github.com/PlaceOS/frontend-loader/pull/65))

## v2.3.3 (2022-05-03)

### Fix

- **telemetry**: ensure `Instrument` in scope

## v2.3.2 (2022-05-03)

### Fix

- update `placeos-log-backend`

## v2.3.1 (2022-04-30)

### Fix

- update `placeos-compiler`

## v2.3.0 (2022-04-28)

### Feat

- add support for generic repositories ([#60](https://github.com/PlaceOS/frontend-loader/pull/60))

## v2.2.1 (2022-04-28)

### Fix

- **logging**: bring inline with other services ([#59](https://github.com/PlaceOS/frontend-loader/pull/59))
- **telemetry**: seperate telemetry file

## v2.2.0 (2022-04-27)

### Feat

- **logging**: configure OpenTelemetry

## v2.1.0 (2022-04-26)

### Feat

- **logging**: optional log level from ENV var ([#57](https://github.com/PlaceOS/frontend-loader/pull/57))

## v2.0.3 (2022-04-13)

### Fix

- **loader**: remove the creation of the base www model ([#55](https://github.com/PlaceOS/frontend-loader/pull/55))

## v2.0.2 (2022-04-08)

## v2.0.1 (2022-03-09)

### Fix

- bump `placeos-models` ([#53](https://github.com/PlaceOS/frontend-loader/pull/53))

## v2.0.0 (2022-03-07)

## v1.3.3 (2022-03-01)

### Fix

- **Dockerfile**: resolve swath of `expat` CVEs

## v1.3.2 (2022-02-24)

### Fix

- resolve CVE-2022-23990

### Refactor

- central build ci ([#50](https://github.com/PlaceOS/frontend-loader/pull/50))

## v1.3.1 (2022-01-28)

### Feat

- **loader**: expose a service startup status
- **api:repositories**: clean copies for querying metadata

### Fix

- **Dockerfile**: compile args typo
- **api:repositories**: strip url-unsafe chars from the remote digest
- use correct repo uri
- healthcheck URI

### Refactor

- use `startup_finished?` from placeos-resource
- mount under frontend-loader

## v1.1.1 (2021-09-03)

### Fix

- **client**: to_s on param
- factor branch when fetching commits
- **repositories_spec**: ensure repo persisted
- **loader**: avoid update cycle
- bump placeos-compiler
- **loader**: decrypt creds

### Refactor

- **loader**: update for full commit sha
- frontends -> frontend-loader

## v0.11.3 (2021-07-19)

## v0.11.2 (2021-06-25)

### Feat

- conform to PlaceOS::Model::Version
- **logging**: configure progname
- **logging**: use placeos-log-backend
- support git user/pass

### Fix

- add version method to client
- **loader**: update commit if more than a minute elapsed
- **loader**: update the timestamp when updating model's commit
- **loader**: force pull repositories
- dev builds

### Refactor

- **controller:repositories**: reduce iterations

## v0.10.8 (2020-12-03)

## v0.10.6 (2020-08-31)

### Fix

- correct flow for pulling a new branch

## v0.10.5 (2020-08-20)

### Refactor

- lazy getter

## v0.10.4 (2020-08-19)

## v0.10.3 (2020-08-10)

### Refactor

- models refresh

## v0.10.2 (2020-07-15)

## v0.10.1 (2020-07-09)

### Feat

- **controller:repositories**: support branch listing via API
- **loader**: support branches

### Fix

- **client**: typo

## v0.9.0 (2020-07-07)

## v0.8.0 (2020-07-02)

## v0.7.3 (2020-06-29)

### Feat

- add secrets and cleanup env

## v0.7.2 (2020-06-24)

## v0.7.1 (2020-06-19)

### Feat

- **config**: standardise on `SG_ENV`

### Fix

- **Log**: use `Log#setup`

## v0.7.0 (2020-06-16)

### Fix

- **loader**: prevent second path expansion

## v0.6.3 (2020-06-05)

### Fix

- **loader**: catch load errors

## v0.6.2 (2020-06-05)

### Fix

- let resource catch loading errors

## v0.6.1 (2020-06-05)

## v0.6.0 (2020-06-02)

### Fix

- rename directories to match top-level require

## v0.5.0 (2020-05-29)

### Refactor

- rename to `placeos-frontends`

## v0.4.2 (2020-05-13)

## v0.4.1 (2020-05-11)

## v0.4.0 (2020-05-09)

### Feat

- **loader**: implicitly clone backoffice

### Fix

- **controller:repositories**: reject non-git dirs in repository listing

## v0.3.0 (2020-05-04)

### Feat

- add limit to commits endpoint

## v0.2.2 (2020-05-04)

## v0.2.1 (2020-05-04)

## v0.2.0 (2020-05-04)

### Feat

- **client**: simple client for frontends service
- **api:repositories**: list commits, list loaded repositories
- initial commit
