ARG CRYSTAL_VERSION=latest

FROM placeos/crystal:$CRYSTAL_VERSION AS build
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
    shards build --production --error-trace

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Extract binary dependencies
RUN for binary in "/usr/bin/git" /app/bin/* /usr/libexec/git-core/*; do \
        ldd "$binary" | \
        tr -s '[:blank:]' '\n' | \
        grep '^/' | \
        xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;' || true; \
      done

RUN git config --system http.sslCAInfo /etc/ssl/certs/ca-certificates.crt

# Build a minimal docker image
FROM scratch
WORKDIR /app
ENV PATH=$PATH:/

# Copy the user information over
COPY --from=build etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group

# These are required for communicating with external services
COPY --from=build /etc/hosts /etc/hosts

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

# Copy the app into place
COPY --from=build /app/deps /
COPY --from=build /app/bin /

COPY --from=build --chown=0:0 /app/www /app/www
COPY --from=build --chown=0:0 /app/tmp /tmp

# This seems to be the only way to set permissions properly
# this only works as we're copying over the dependencies for git
# which includes /lib/ld-musl-* files
COPY --from=build /bin /bin
RUN chmod -R a+rwX /tmp
RUN chmod -R a+rwX /app/www

# so we can run commands on remote network volumes
RUN mkdir /nonexistent/ && chown appuser:appuser /nonexistent/
USER appuser:appuser
RUN touch /nonexistent/.gitconfig
RUN /git config --global --add safe.directory '*'

# remove the shell and make the home folder read only to the user
USER root:root
RUN chown -R root:root /nonexistent/
RUN rm -rf /bin

# Use an unprivileged user.
USER appuser:appuser

# Run the app binding on port 3000
EXPOSE 3000
ENTRYPOINT ["/frontends"]
HEALTHCHECK CMD ["/frontends", "-c", "http://localhost:3000/api/frontend-loader/v1"]
CMD ["/frontends", "-b", "0.0.0.0", "-p", "3000"]
