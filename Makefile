.PHONY: bootstrap test validate up down status inject-errors stop-errors fail-readiness restore-readiness deploy backup

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

# These helpers operate only on the isolated hardened project.
deploy:
	./scripts/deploy-local.sh

backup:
	@test -n "$(BACKUP_DIR)" || { echo 'Set BACKUP_DIR to an application-private path' >&2; exit 1; }
	./scripts/backup-stack.sh --offline "$(BACKUP_DIR)"
