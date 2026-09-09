# syntax=docker/dockerfile:1

FROM golang:1.26-alpine AS base
RUN apk add --no-cache git ca-certificates tzdata
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

FROM base AS dev
RUN go install github.com/air-verse/air@latest
COPY . .
EXPOSE 8080
CMD ["air", "-c", ".air.toml"]

FROM base AS build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /radio-px ./cmd/server

FROM scratch AS runner
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /radio-px /radio-px
EXPOSE 8080
ENTRYPOINT ["/radio-px"]