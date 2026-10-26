# syntax=docker/dockerfile:1.18
FROM golang:1.27.3-alpine3.23@sha256:754d5200fc3edae76d3b6598a9a3fac7e74981ee6a5413ab955025f185753ef2 AS build

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
