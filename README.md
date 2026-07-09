# automl-infra

Local infrastructure for the AutoML microservices.

Contains:

- `docker-compose.yml` — Postgres 16 + Redis 7 with persistent volumes and healthchecks. This is the **base** compose file — always include it. Containers are named `Auto-ML-Postgres` and `Auto-ML-Redis` and mapped to non-default host ports (`5433`, `6380`) so they don't collide with other local Postgres/Redis containers.
- `docker-compose.full.yml` — overlay that also builds and runs all five services (`data`, `metafeatures`, `generation` + worker, `analysis`, `gateway`). Combine with the base for a full stack. The five app services also bind-mount `../automl-reusables` into `/opt/automl-reusables` and set `PYTHONPATH=/opt/automl-reusables` so `import src.*` resolves inside the containers — the Dockerfiles are `--no-deps` builds that expect the reusables source at runtime.
- `db/init/01_schema.sql` — tables (`datasets`, `meta_features`, `run_results`, `sweep_jobs`) auto-created on first postgres start.
- `.env.example` — copy to `.env` to override defaults (ports, credentials).

## Prerequisites

- Docker Desktop (Windows/Mac) or Docker + docker-compose (Linux).

## Start (infra only — Postgres + Redis)

```bash
cp .env.example .env       # optional; edit if you need custom ports/creds
docker compose up -d
```

Postgres is reachable at `localhost:5433`, Redis at `localhost:6380`. (Internal ports inside the `automl-net` bridge network stay `5432` / `6379` — only the host-side mapping is remapped.)

## Start (full stack — infra + all services)

```bash
docker compose -f docker-compose.yml -f docker-compose.full.yml up -d
```

Then:

- Gateway (frontend entry point): http://localhost:8000/docs
- data-service: http://localhost:8001/docs
- metafeatures-service: http://localhost:8002/docs
- generation-service: http://localhost:8003/docs
- analysis-service: http://localhost:8004/docs

Note: the generation-worker container needs Ollama reachable. On Docker Desktop this defaults to `http://host.docker.internal:11434` so it can reach an Ollama instance running on the host. Override with the `OLLAMA_URL` env var if you run Ollama elsewhere.

## Stop

```bash
docker compose down
```

To also wipe all data (destroys DB contents):

```bash
docker compose down -v
```

## Verify

```bash
docker compose ps
docker exec -it Auto-ML-Postgres psql -U automl -d automl -c "\dt"
docker exec -it Auto-ML-Redis redis-cli ping
curl http://localhost:8000/health   # gateway; reports each upstream service
```

Expected output from `\dt`: four tables — `datasets`, `meta_features`, `run_results`, `sweep_jobs`.

Expected gateway health response:

```json
{"status":"ok","upstream":{"data":true,"metafeatures":true,"generation":true,"analysis":true}}
```

## Shared network

The compose file creates a `automl-net` bridge network. Each service (`automl-data-service`, etc.) will attach to this network so they can reach `postgres:5432` and `redis:6379` by service name.

## Connection strings

Default (matches `.env.example`):

```
POSTGRES_DSN=postgresql://automl:automl_dev_pw@localhost:5433/automl
REDIS_URL=redis://localhost:6380/0
```

From inside another container on `automl-net`, use hostnames `postgres` / `redis` and the **internal** ports `5432` / `6379` instead — the host-side remapping to `5433` / `6380` only affects clients connecting from your machine.

## Why the ports and names look non-default

Both `Auto-ML-Postgres` and `Auto-ML-Redis` deliberately avoid the standard host ports (`5432`, `6379`) so this stack can run alongside other developer stacks on the same machine without a port fight. If you have your own Postgres or Redis container that expects those ports (e.g. a separate `chaiDB` compose stack), it continues to work unchanged. Service-to-service traffic inside `automl-net` is unaffected — those calls use the docker network DNS names (`postgres:5432`, `redis:6379`).

## Reusables bind mount

The five app services (`data`, `metafeatures`, `generation`, `generation-worker`, `analysis`) all `import src.*` from the shared `automl-reusables` library. Their Dockerfiles install the service with `pip install --no-deps -e .`, deliberately skipping the git-URL dep, and instead pick up the reusables source at container startup via:

```yaml
volumes:
  - ../automl-reusables:/opt/automl-reusables
environment:
  PYTHONPATH: /opt/automl-reusables
```

This lets you edit `automl-reusables/src/**/*.py` and restart just the affected service (no rebuild) to pick up the change. The `gateway` service does **not** import `src` and does not receive this mount.
