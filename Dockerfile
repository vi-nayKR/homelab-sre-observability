# syntax=docker/dockerfile:1.18
FROM golang:1.27.1-alpine3.23@sha256:d9e2f2f07b10cc922da3e80e035c3058810b328d5aef82d2c63680967c5e2ec9 AS build

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
