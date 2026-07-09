# AutoML Stack — team onboarding & API testing guide

This repo (`automl-infra`) orchestrates six sibling microservices that together make up the AutoML research stack. If you're a teammate who just wants to bring the stack up on your laptop and hit the APIs from Postman, **you're in the right place — read this doc top to bottom**.

---

## 1. What you're bringing up

Seven repos under [Major-Proj-AutoML](https://github.com/Major-Proj-AutoML) work together:

| Repo | Role | Container | Host port | Ships with docs |
|---|---|---|---|---|
| `automl-infra` | Compose files, DB schema, this README | — | — | — |
| `automl-reusables` | Shared library (`src.*`) — meta-features, prompt conditions, runner | — | — | — |
| `automl-data-service` | Dataset registry (upload CSV, fetch OpenML) | `automl-data-service` | `:8001` | `/docs` |
| `automl-metafeatures-service` | Compute + cache meta-features | `automl-metafeatures-service` | `:8002` | `/docs` |
| `automl-generation-service` | Async LLM code generation (RQ + Ollama) | `automl-generation-service` + `-worker` | `:8003` | `/docs` |
| `automl-analysis-service` | RQ1–RQ5 analytics over completed runs | `automl-analysis-service` | `:8004` | `/docs` |
| `automl-gateway` | Single entry point + composed workflows | `automl-gateway` | `:8000` | `/docs` |

Plus infra:

| Service | Container | Host port | Internal port |
|---|---|---|---|
| Postgres 16 | `Auto-ML-Postgres` | `:5433` | `:5432` |
| Redis 7 | `Auto-ML-Redis` | `:6380` | `:6379` |

> The stack uses non-standard host ports (`5433`, `6380`) so it can coexist with any other Postgres/Redis containers you may already run. Inside the docker network the services still talk to `postgres:5432` and `redis:6379`.

---

## 2. Prerequisites

Install once on your machine:

1. **Docker Desktop** — Windows/Mac. Confirm with `docker --version`.
2. **Ollama** — https://ollama.com/download. After install, in a terminal:
   ```bash
   ollama serve            # runs on localhost:11434
   ollama pull gpt-oss:120b-cloud
   ```
   Any Ollama-supported model works; `gpt-oss:120b-cloud` is the current default in examples. Confirm with `curl http://localhost:11434/api/tags`.
3. **Git** — `git --version`.
4. **Postman** (or Insomnia) — https://www.postman.com/downloads/.

That's it. You don't need Python locally — everything runs in containers.

---

## 3. First-time setup: clone the repos

Pick a parent directory (any location). Then:

```bash
mkdir automl-stack && cd automl-stack

git clone https://github.com/Major-Proj-AutoML/automl-infra.git
git clone https://github.com/Major-Proj-AutoML/automl-reusables.git
git clone https://github.com/Major-Proj-AutoML/automl-data-service.git
git clone https://github.com/Major-Proj-AutoML/automl-metafeatures-service.git
git clone https://github.com/Major-Proj-AutoML/automl-generation-service.git
git clone https://github.com/Major-Proj-AutoML/automl-analysis-service.git
git clone https://github.com/Major-Proj-AutoML/automl-gateway.git
```

You should end up with all seven folders as siblings. The compose file uses relative paths (`../automl-data-service`, etc.), so this layout matters.

---

## 4. Start the whole stack

From `automl-infra/`:

```bash
docker compose -f docker-compose.yml -f docker-compose.full.yml up -d --build
```

First run downloads base images and builds six service images — takes **5–10 min**. Subsequent starts take ~30 s.

The command exits when everything is up. To watch progress in real time, drop `-d`.

---

## 5. Verify it's alive

Three checks — all should pass.

**A. Every container up and healthy:**
```bash
docker compose -f docker-compose.yml -f docker-compose.full.yml ps
```
You want to see 8 containers, all `Up`, with `Auto-ML-Postgres` and `Auto-ML-Redis` marked `(healthy)`.

**B. Gateway health endpoint (browser or curl):**
```
http://localhost:8000/health
```
Expected response:
```json
{"status":"ok","upstream":{"data":true,"metafeatures":true,"generation":true,"analysis":true}}
```
If any upstream is `false`, run `docker logs <container>` for that service.

**C. Ollama reachable from inside the worker:**
```bash
docker exec automl-generation-worker curl -s http://host.docker.internal:11434/api/tags
```
You should see a JSON listing your local models.

If any check fails, jump to **Troubleshooting** at the bottom.

---

## 6. Import the Postman collection

Every service exposes an OpenAPI 3.1 spec at `/openapi.json`. Fresh snapshots live in `automl-infra/postman/`:

| File | Base URL | Endpoints |
|---|---|---|
| `gateway.openapi.json` | `http://localhost:8000` | 25 |
| `data-service.openapi.json` | `http://localhost:8001` | 8 |
| `metafeatures-service.openapi.json` | `http://localhost:8002` | 4 |
| `generation-service.openapi.json` | `http://localhost:8003` | 7 |
| `analysis-service.openapi.json` | `http://localhost:8004` | 7 |

**Import the gateway collection** (that's all you need for 90% of testing — it proxies to every backend):

1. Open Postman → **File → Import**.
2. Drag `automl-infra/postman/gateway.openapi.json` in.
3. Postman creates a collection named "automl-gateway" with every endpoint pre-filled.

If you want to test a backend service directly (bypassing the gateway), also import that service's JSON.

**Prefer a browser?** Every service has a live interactive docs page — go to `http://localhost:8000/docs` (or any port from the table above). Fill the form fields, hit **Execute**. Same effect as Postman.

---

## 7. Walkthrough — testing the APIs in Postman

Grab any CSV you have that's suitable for supervised ML. The examples below assume a regression dataset, but everything works for `binary_classification` and `multiclass_classification` too.

### Test 1 — Health

Postman → `automl-gateway` collection → **GET /health** → **Send**.

Expected: 200 OK, JSON with all four upstreams `true`.

---

### Test 2 — Upload a CSV and get its meta-features (no LLM)

This is the safest first test: no Ollama involvement, deterministic result in ~1 s.

**Endpoint:** `POST /workflows/upload-and-extract`

In Postman, click the request → **Body** tab → select **form-data**. Fill in:

| Key | Type | Value |
|---|---|---|
| `file` | File | your CSV, e.g. `housing.csv` |
| `target_col` | Text | the column your model should predict, e.g. `median_house_value` |
| `task_type` | Text | one of `regression`, `binary_classification`, `multiclass_classification` |

Hit **Send**. Expected response:

```json
{
  "dataset": {
    "id": 1,
    "name": "housing",
    "source": "custom",
    "target_col": "median_house_value",
    "task_type": "regression",
    "n_rows": 20640,
    "n_cols": 10,
    "created_at": "2026-07-09T..."
  },
  "meta_features": {
    "dataset_id": 1,
    "features": { "...": "..." },
    "cached": false
  }
}
```

**Note the `dataset.id`** — you'll need it in Tests 3 and 4.

---

### Test 3 — Full end-to-end run (LLM generates code, executes, scores)

**Endpoint:** `POST /workflows/full-run`

Same body as Test 2, plus these extra fields:

| Key | Type | Value | Meaning |
|---|---|---|---|
| `condition` | Text | `b2_metafeature` | Prompt style. Options: `b0_naive`, `b1_schema`, `b2_metafeature` |
| `llm_backend` | Text | `gpt-oss:120b-cloud` | Whatever Ollama model you have pulled |
| `seed` | Text | `42` | Random seed for reproducibility |
| `max_iter` | Text | `3` | LLM retry attempts if code fails |
| `timeout_seconds` | Text | `300` | Per-attempt timeout for generated code |

Send. You get an **immediate** response (HTTP 200 in ~1 s):

```json
{
  "dataset": { "id": 3, "...": "..." },
  "meta_features": { "...": "..." },
  "run": {
    "rq_job_id": "4d8aea39-c3ad-4edf-9025-87c26dd9c2c3",
    "status_url": "/runs/by-rq-job/..."
  }
}
```

The run is queued — the worker takes 20–60 s depending on the model + dataset size. Note the `dataset.id`.

---

### Test 4 — Poll for the run's result

**Endpoint:** `GET /runs?dataset_id=<id>&limit=1`

In Postman, set `dataset_id` (Params tab) to whatever ID Test 3 returned. Send.

- **Empty array `[]`** → worker hasn't picked it up yet; wait 10 s, resend.
- Row with `"success": null` → still executing.
- Row with `"success": true` → done, `test_score` is your result.
- Row with `"success": false` → failed; look at `error_category` and `error_message`.

Score interpretation:
- **Regression** — negative RMSE. Closer to 0 = better. `-48728` means RMSE ≈ 48,728 in your target's units.
- **Classification** — balanced accuracy in `[0, 1]`. Higher = better.

---

### Test 5 — Analytics endpoints

Once you have at least one completed run:

| Postman request | What it tells you |
|---|---|
| `GET /analysis/summary` | Mean test-score per (condition, model), plus failure counts |
| `GET /analysis/errors` | Distribution of error categories (`missing_name`, `import_error`, etc.) |
| `GET /analysis/iterations` | Average iterations used per condition — does B2 reduce retries? |
| `GET /analysis/models` | Per-backend comparison |
| `GET /analysis/size-stratified` | Small vs medium vs large dataset breakdown |
| `GET /analysis/wilcoxon?a=B0&b=B2` | Statistical significance test: is B2 better than B0? |

Compare `b0_naive` vs `b2_metafeature` for the same dataset+model+seed to see the meta-feature effect.

---

## 8. Peek at what got saved

Sometimes you want to sanity-check that data really landed in Postgres/Redis.

```bash
# What datasets are registered?
docker exec -it Auto-ML-Postgres psql -U automl -d automl -c "SELECT id, name, target_col, task_type, n_rows FROM datasets;"

# All finished runs
docker exec -it Auto-ML-Postgres psql -U automl -d automl -c "SELECT id, dataset_id, condition, llm_backend, test_score, success, error_category FROM run_results ORDER BY id DESC LIMIT 10;"

# Cached meta-features
docker exec -it Auto-ML-Postgres psql -U automl -d automl -c "SELECT dataset_id, computed_at FROM meta_features;"

# Is the RQ queue empty?
docker exec -it Auto-ML-Redis redis-cli LLEN rq:queue:automl-generation

# Live worker log while a run is in progress
docker logs -f automl-generation-worker
```

---

## 9. Stop / restart / wipe

| Goal | Command |
|---|---|
| Stop everything (keeps data) | `docker compose -f docker-compose.yml -f docker-compose.full.yml down` |
| Restart one service after code change | `docker compose -f docker-compose.yml -f docker-compose.full.yml restart <service-name>` |
| Full wipe (destroys DB + Redis + uploaded CSVs) | `docker compose -f docker-compose.yml -f docker-compose.full.yml down -v` |
| Rebuild after Dockerfile change | `docker compose -f docker-compose.yml -f docker-compose.full.yml up -d --build` |

Service names (for `restart`): `postgres`, `redis`, `data-service`, `metafeatures-service`, `generation-service`, `generation-worker`, `analysis-service`, `gateway`.

---

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `/health` shows an upstream `false` | `docker logs <that-container>` — 90% of the time it's a Python crash on import |
| Run stays "still running" for minutes | `docker logs automl-generation-worker` — usually Ollama unreachable |
| `error_category: "infrastructure"` on a run row | Ollama not reachable from the container. Confirm `ollama serve` is running on the host and `docker exec automl-generation-worker curl http://host.docker.internal:11434/api/tags` succeeds |
| `error_category: "missing_name"` | LLM emitted code with unresolved names — this is expected on some attempts, the pipeline retries automatically up to `max_iter` |
| Port conflict on `5433` or `6380` on `up` | Something else is using those host ports. Either free them or edit `.env`: `POSTGRES_PORT=xxxx`, `REDIS_PORT=xxxx` |
| "No module named 'src'" in a service log | The `../automl-reusables` bind mount is missing or the sibling folder isn't there. Confirm you have all 7 repos as siblings |
| Ollama on a different host | Set `OLLAMA_URL=http://your-host:11434` in `.env` before starting |
| Everything stuck / weird | `docker compose down && docker compose -f docker-compose.yml -f docker-compose.full.yml up -d --build` |

---

## 11. What lives where in this repo

- `docker-compose.yml` — Postgres + Redis (base). Always included.
- `docker-compose.full.yml` — overlay adding the 5 app services + worker.
- `db/init/01_schema.sql` — auto-runs on Postgres first start; creates `datasets`, `meta_features`, `run_results`, `sweep_jobs`.
- `.env.example` — copy to `.env` and override ports/creds.
- `postman/` — OpenAPI snapshots + import instructions ([postman/README.md](postman/README.md)).

The 5 app services bind-mount `../automl-reusables` into `/opt/automl-reusables` and set `PYTHONPATH=/opt/automl-reusables`. This means you can edit reusables' source files on your host and restart a single service (`docker compose restart generation-worker`) to pick up the change — no rebuild.

The `gateway` service does not import `src` and does not receive that mount.
