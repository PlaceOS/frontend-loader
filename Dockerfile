ARG CRYSTAL_VERSION=1.1.1
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
    crystal build --static --release --no-debug --error-trace -o bin/frontends src/app.cr

FROM alpine:3.11
WORKDIR /app

RUN apk upgrade && apk add --update --no-cache ca-certificates git openssh

# Add trusted CAs for communicating with external services
RUN update-ca-certificates

COPY --from=builder /build/bin /app/bin

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD /app/bin/frontends -c http://localhost:3000/api/frontends/v1
CMD ["/app/bin/frontends", "-b", "0.0.0.0", "-p", "3000"]
