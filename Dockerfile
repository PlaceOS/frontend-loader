ARG CRYSTAL_VERSION=1.5
FROM alpine:3.16 as build
WORKDIR /app

# Setup commit via a build arg
ARG PLACE_COMMIT="DEV"
# Set the platform version via a build arg
ARG PLACE_VERSION="DEV"

# Add trusted CAs for communicating with external services
RUN apk add \
  --update \
  --no-cache \
    ca-certificates \
    yaml-dev \
    yaml-static \
    libxml2-dev \
    openssl-dev \
    openssl-libs-static \
    zlib-dev \
    zlib-static \
    tzdata

RUN update-ca-certificates

# Add crystal lang
# can look up packages here: https://pkgs.alpinelinux.org/packages?name=crystal
RUN apk add \
  --update \
  --no-cache \
  --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main \
  --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
    crystal \
    shards

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
    shards build --production --release --error-trace

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Extract binary dependencies
RUN for binary in /app/bin/*; do \
        ldd "$binary" | \
        tr -s '[:blank:]' '\n' | \
        grep '^/' | \
        xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'; \
    done

# Build a minimal docker image
FROM alpine:3.16
WORKDIR /app
ENV PATH=$PATH:/

RUN apk add --update --no-cache \
    'apk-tools>=2.10.8-r0' \
    ca-certificates \
    'expat>=2.4.5-r0' \
    git \
    'libcurl>=7.79.1-r0' \
    openssh

# Add trusted CAs for communicating with external services
RUN update-ca-certificates

# Copy the app into place
COPY --from=build /app/deps /
COPY --from=build /app/bin /
RUN mkdir -p /app/www

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/frontends"]
HEALTHCHECK CMD ["/frontends", "-c", "http://localhost:3000/api/frontend-loader/v1"]
CMD ["/frontends", "-b", "0.0.0.0", "-p", "3000"]
