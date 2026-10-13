# syntax=docker/dockerfile:1.18
FROM golang:1.27.2-alpine3.23@sha256:9e45f0eb4a63ed37ad6e604950407558b7c738e34e015ae77a5d4ad369cde079 AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY cmd/ ./cmd/
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
    -ldflags="-s -w -buildid=" \
    -o /out/reliability-api ./cmd/reliability-api

FROM scratch
COPY --from=build /out/reliability-api /reliability-api
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/reliability-api", "healthcheck"]
ENTRYPOINT ["/reliability-api"]
