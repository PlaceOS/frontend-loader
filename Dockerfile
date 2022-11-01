FROM placeos/crystal:latest as build
WORKDIR /app

# Setup commit via a build arg
ARG PLACE_COMMIT="DEV"
# Set the platform version via a build arg
ARG PLACE_VERSION="DEV"

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
    shards build --production --release --error-trace

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Extract binary dependencies
RUN for binary in "/usr/bin/git" /app/bin/* /usr/libexec/git-core/*; do \
        ldd "$binary" | \
        tr -s '[:blank:]' '\n' | \
        grep '^/' | \
        xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;' || true; \
      done

# Build a minimal docker image
FROM scratch
WORKDIR /
ENV PATH=$PATH:/

# These are required for communicating with external services
COPY --from=build /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# This is required for Timezone support
COPY --from=build /usr/share/zoneinfo/ /usr/share/zoneinfo/

# git for querying remote repositories
COPY --from=build /usr/bin/git /git
COPY --from=build /usr/share/git-core/ /usr/share/git-core/
COPY --from=build /usr/libexec/git-core/ /usr/libexec/git-core/

# Copy the app into place
COPY --from=build /app/deps /
COPY --from=build /app/bin /
COPY --from=build /app/www /app/www
COPY --from=build /app/tmp /tmp

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/frontends"]
HEALTHCHECK CMD ["/frontends", "-c", "http://localhost:3000/api/frontend-loader/v1"]
CMD ["/frontends", "-b", "0.0.0.0", "-p", "3000"]
