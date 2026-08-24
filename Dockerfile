# syntax=docker/dockerfile:1.18
FROM golang:1.27.0-alpine3.23@sha256:3747dcba41c8b0db3211fda4db61638b980e17ac5bb3c94460a975a9cfe19395 AS build

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
