ARG CRYSTAL_VERSION=latest

FROM placeos/crystal:$CRYSTAL_VERSION AS build
# FROM 84codes/crystal:latest-debian-12 AS build
WORKDIR /app

# Setup commit via a build arg
ARG PLACE_COMMIT="DEV"
# Set the platform version via a build arg
ARG PLACE_VERSION="DEV"

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

# Install package updates since image release
RUN apk update && apk --no-cache --quiet upgrade

# Update CA certificates
RUN update-ca-certificates

# Set environment variables for TLS CA validation
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
RUN git config --system http.sslCAInfo /etc/ssl/certs/ca-certificates.crt

# Install shards for caching
COPY shard.yml .
COPY shard.override.yml .
COPY shard.lock .

RUN shards install --production --ignore-crystal-version --skip-postinstall --skip-executables

# Add src
COPY ./src /app/src
RUN mkdir -p /app/www
RUN mkdir -p /app/tmp

# Build application
RUN PLACE_COMMIT=$PLACE_COMMIT \
    PLACE_VERSION=$PLACE_VERSION \
    shards build \
      --debug \
      --error-trace \
      --no-color \
      --static \
      -O1 \
      --frame-pointers=always \
      --link-flags "-no-pie -Wl,-no-pie -Wl,--eh-frame-hdr -Wl,--build-id -rdynamic -Wl,--export-dynamic -lunwind -llzma"

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# Extract binary dependencies
RUN mkdir -p /app/deps && \
    for binary in "/usr/bin/git" /app/bin/* /usr/libexec/git-core/*; do \
        file "$binary" | grep -q ELF || continue; \
        ldd "$binary" 2>/dev/null | \
        tr -s '[:blank:]' '\n' | \
        grep '^/' | \
        xargs -I % sh -c 'mkdir -p "/app/deps$(dirname %)"; cp "%" "/app/deps%"' || true; \
      done

RUN git config --system http.sslCAInfo /etc/ssl/certs/ca-certificates.crt

# obtain busy box for file ops in scratch image
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) ARCH=x86_64 ;; \
      arm64) ARCH=armv8l ;; \
      *) echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget -q -O /busybox "https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-${ARCH}" && \
    chmod +x /busybox

# Build a minimal docker image
FROM scratch
WORKDIR /app
ENV PATH=$PATH:/

# Copy the user information over
COPY --from=build etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group

# These are required for communicating with external services
# COPY --from=build /etc/hosts /etc/hosts

COPY --from=build /busybox /bin/busybox
SHELL ["/bin/busybox", "sh", "-euo", "pipefail", "-c"]

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=build /etc/gitconfig /etc/gitconfig
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt

# This is required for Timezone support
COPY --from=build /usr/share/zoneinfo/ /usr/share/zoneinfo/

# git for querying remote repositories
COPY --from=build /usr/bin/git /git
COPY --from=build /usr/share/git-core/ /usr/share/git-core/
COPY --from=build /usr/libexec/git-core/ /usr/libexec/git-core/

# Copy the app and its dependencies into place
COPY --from=build /app/deps /

# Copy the musl dynamic linker (required for dynamically linked binaries like git)
COPY --from=build /lib/ld-musl-* /lib/

COPY --from=build /app/bin /

COPY --from=build --chown=0:0 /app/www /app/www
COPY --from=build --chown=0:0 /app/tmp /tmp

# This seems to be the only way to set permissions properly
# this only works as we're copying over the dependencies for git
# which includes /lib/ld-musl-* files
# COPY --from=build /bin /bin
RUN /bin/busybox chmod -R a+rwX /tmp
RUN /bin/busybox chmod -R a+rwX /app/www

# so we can run commands on remote network volumes
RUN /bin/busybox mkdir /nonexistent/ && /bin/busybox chown appuser:appuser /nonexistent/
USER appuser:appuser
RUN /bin/busybox touch /nonexistent/.gitconfig
RUN /git config --global --add safe.directory '*'

# remove the shell and make the home folder read only to the user
USER root:root
RUN /bin/busybox chown -R root:root /nonexistent/
RUN /bin/busybox rm -rf /bin/busybox

# Use an unprivileged user.
USER appuser:appuser

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/frontends"]
HEALTHCHECK CMD ["/frontends", "-c", "http://localhost:3000/api/frontend-loader/v1"]
CMD ["/frontends", "-b", "0.0.0.0", "-p", "3000"]
