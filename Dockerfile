ARG CRYSTAL_VERSION=1.5.0
FROM alpine:3.16 as build
WORKDIR /app

# Setup commit via a build arg
ARG PLACE_COMMIT="DEV"
# Set the platform version via a build arg
ARG PLACE_VERSION="DEV"

# Add trusted CAs for communicating with external services
RUN apk add --update --no-cache \
      ca-certificates \
    && \
    update-ca-certificates

# Add crystal lang
# can look up packages here: https://pkgs.alpinelinux.org/packages?name=crystal
RUN apk add \
  --update \
  --no-cache \
  --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
  --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
    crystal \
    shards \
    yaml-dev \
    yaml-static \
    libxml2-dev \
    openssl-dev \
    openssl-libs-static \
    zlib-dev \
    zlib-static \
    tzdata

# Install shards for caching
COPY shard.yml .
COPY shard.override.yml .
COPY shard.lock .

RUN shards install --production --ignore-crystal-version --skip-postinstall --skip-executables

# Add src
COPY ./src /app/src

# Build application
RUN PLACE_COMMIT=$PLACE_COMMIT \
    PLACE_VERSION=$PLACE_VERSION \
    crystal build \
        --release \
        --error-trace \
        --static \
        -o /app/frontends \
        /app/src/app.cr

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Build a minimal docker image
FROM alpine:3.16
WORKDIR /app

RUN apk add --update --no-cache \
    'apk-tools>=2.10.8-r0' \
    ca-certificates \
    'expat>=2.4.5-r0' \
    git \
    'libcurl>=7.79.1-r0' \
    openssh

# Add trusted CAs for communicating with external services
RUN update-ca-certificates

COPY --from=build /app/frontends /app/bin/frontends

# Create a non-privileged user, defaults are appuser:10001
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser

# See https://stackoverflow.com/a/55757473/12429735
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

USER appuser:appuser

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD /app/bin/frontends -c http://localhost:3000/api/frontend-loader/v1
CMD ["/app/bin/frontends", "-b", "0.0.0.0", "-p", "3000"]
