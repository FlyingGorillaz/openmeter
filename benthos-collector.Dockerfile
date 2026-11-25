FROM --platform=$BUILDPLATFORM golang:1.27.4-alpine3.23@sha256:f70850ef6ce341e8b6427f677049145d63c0b7ce002d4d7e3d464828b1b96dcd AS builder

RUN apk add --update --no-cache ca-certificates make git curl

ARG TARGETPLATFORM

WORKDIR /src

ARG GOPROXY

ENV CGO_ENABLED=0

ENV GOCACHE=/go/cache
ENV GOMODCACHE=/go/pkg/mod

COPY --link go.mod go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/go/cache \
    go mod download -x

COPY --link collector/go.mod collector/go.sum ./collector/

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/go/cache \
    go mod download -C ./collector -x

ARG VERSION

COPY --link . .

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/go/cache \
    go build -C ./collector -ldflags "-X main.version=${VERSION}" -o /usr/local/bin/benthos ./cmd

FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

RUN apk add --update --no-cache ca-certificates tzdata bash \
    && addgroup -S -g 10001 openmeter \
    && adduser -S -D -H -u 10001 -G openmeter openmeter \
    && mkdir -p /var/run/openmeter-ca /var/lib/collector \
    && chown openmeter:openmeter /var/run/openmeter-ca /var/lib/collector

SHELL ["/bin/bash", "-c"]

# This is so we can reuse presets in development
WORKDIR /etc/benthos

COPY cloudevents.spec.json /etc/benthos/

COPY collector/benthos/presets /etc/benthos/presets

COPY --link --from=builder /usr/local/bin/benthos /usr/local/bin/
COPY --link --chmod=755 prepare-ca-bundle.sh /usr/local/bin/prepare-ca-bundle

USER 10001:10001

ENTRYPOINT ["/usr/local/bin/benthos"]
