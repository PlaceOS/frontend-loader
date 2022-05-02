## Unreleased

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

### Refactor

- use `startup_finished?` from placeos-resource
- mount under frontend-loader

### Feat

- **loader**: expose a service startup status
- **api:repositories**: clean copies for querying metadata

### Fix

- **Dockerfile**: compile args typo
- **api:repositories**: strip url-unsafe chars from the remote digest
- use correct repo uri
- healthcheck URI

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

### Fix

- correct flow for pulling a new branch

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

### Fix

- **client**: typo

### Feat

- **controller:repositories**: support branch listing via API
- **loader**: support branches

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

### Fix

- **loader**: allow repository model to control backoffice

## v0.6.0 (2020-06-02)

### Fix

- rename directories to match top-level require

## v0.5.0 (2020-05-29)

### Refactor

- rename to `placeos-frontends`

## v0.4.2 (2020-05-13)

## v0.4.1 (2020-05-11)

## v0.4.0 (2020-05-09)

### Fix

- **controller:repositories**: reject non-git dirs in repository listing

### Feat

- **loader**: implicitly clone backoffice

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
