ARG CRYSTAL_VERSION=1.4.1
FROM crystallang/crystal:${CRYSTAL_VERSION}-alpine as builder

ARG PLACE_COMMIT="DEV"
ARG PLACE_VERSION="DEV"

WORKDIR /build

COPY shard.yml .
COPY shard.override.yml .
COPY shard.lock .

RUN CRFLAGS="--static" \
    shards install --production --ignore-crystal-version

COPY src /build/src

RUN PLACE_COMMIT=$PLACE_COMMIT \
    PLACE_VERSION=$PLACE_VERSION \
    crystal build --static --release -o bin/frontends src/app.cr

FROM alpine:3.15
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

COPY --from=builder /build/bin /app/bin

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD /app/bin/frontends -c http://localhost:3000/api/frontend-loader/v1
CMD ["/app/bin/frontends", "-b", "0.0.0.0", "-p", "3000"]
