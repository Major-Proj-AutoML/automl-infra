# automl-infra

Local infrastructure for the AutoML microservices.

Contains:

- `docker-compose.yml` — Postgres 16 + Redis 7 with persistent volumes and healthchecks. This is the **base** compose file — always include it.
- `docker-compose.full.yml` — overlay that also builds and runs all five services (`data`, `metafeatures`, `generation` + worker, `analysis`, `gateway`). Combine with the base for a full stack.
- `db/init/01_schema.sql` — tables (`datasets`, `meta_features`, `run_results`, `sweep_jobs`) auto-created on first postgres start.
- `.env.example` — copy to `.env` to override defaults (ports, credentials).

## Prerequisites

- Docker Desktop (Windows/Mac) or Docker + docker-compose (Linux).

## Start (infra only — Postgres + Redis)

```bash
cp .env.example .env       # optional; edit if you need custom ports/creds
docker compose up -d
```

Postgres is reachable at `localhost:5432`, Redis at `localhost:6379`.

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
docker exec -it automl-postgres psql -U automl -d automl -c "\dt"
docker exec -it automl-redis redis-cli ping
```

Expected output from `\dt`: four tables — `datasets`, `meta_features`, `run_results`, `sweep_jobs`.

## Shared network

The compose file creates a `automl-net` bridge network. Each service (`automl-data-service`, etc.) will attach to this network so they can reach `postgres:5432` and `redis:6379` by service name.

## Connection strings

Default (matches `.env.example`):

```
POSTGRES_DSN=postgresql://automl:automl_dev_pw@localhost:5432/automl
REDIS_URL=redis://localhost:6379/0
```

From inside another container on `automl-net`, use hostnames `postgres` / `redis` instead of `localhost`.
