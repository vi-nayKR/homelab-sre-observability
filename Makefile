.PHONY: bootstrap test validate up down status inject-errors stop-errors fail-readiness restore-readiness

bootstrap:
	cp -n .env.example .env

test:
	go test -race ./...
	go vet ./...

validate:
	./scripts/validate.sh

up:
	docker compose up --build -d

down:
	docker compose down

status:
	docker compose ps
	curl -fsS http://127.0.0.1:8080/health/ready
	curl -fsS http://127.0.0.1:9090/-/ready

inject-errors:
	./scripts/error-load.sh start

stop-errors:
	./scripts/error-load.sh stop

fail-readiness:
	curl -fsS -X POST 'http://127.0.0.1:8080/admin/readiness?ready=false'

restore-readiness:
	curl -fsS -X POST 'http://127.0.0.1:8080/admin/readiness?ready=true'

