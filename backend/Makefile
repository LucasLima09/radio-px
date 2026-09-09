SHELL := /bin/bash
COMPOSE := docker compose

.PHONY: help dev up down logs restart psql db-only migrate-up reset-db test build fmt vet clean

## Dev: builds, starts db + api with Air hot reload in foreground
dev:
	$(COMPOSE) up --build

## Starts db + api detached
up:
	$(COMPOSE) up -d --build

## Stops and removes containers (keeps postgres volume)
down:
	$(COMPOSE) down

## Follow the logs of all services
logs:
	$(COMPOSE) logs -f --tail=100

## Restart api container
restart:
	$(COMPOSE) restart api

## Open a psql shell inside the db container
psql:
	$(COMPOSE) exec db psql -U radio -d radio_px

## Starts only the database
db-only:
	$(COMPOSE) up -d db

## Apply migrations (runs automatically on API startup; this restarts the api)
migrate-up:
	$(COMPOSE) restart api

## Drops the database volume and recreates everything from scratch
reset-db:
	$(COMPOSE) down -v
	$(COMPOSE) up -d --build

## Run tests locally (requires go toolchain)
test:
	go test ./...

## Build the binary locally
build:
	go build -o bin/radio-px ./cmd/server

## Run gofmt and report files that need formatting
fmt:
	gofmt -l .

## Run go vet
vet:
	go vet ./...

## Clean build artifacts
clean:
	rm -rf bin tmp
	$(COMPOSE) down -v --remove-orphans

## Print available commands
help:
	@grep -E '^[a-zA-Z_-]+:' Makefile | sed 's/://' | sort