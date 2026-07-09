# Postman / Insomnia collections

Snapshots of every service's OpenAPI 3.1 spec, captured from a live stack. Import each JSON into Postman or Insomnia to get a ready-to-run collection with every endpoint, parameter schema, and example body.

## Files

| File | Base URL | Endpoints |
|---|---|---|
| `gateway.openapi.json` | `http://localhost:8000` | 25 (proxy + composed workflows) |
| `data-service.openapi.json` | `http://localhost:8001` | 8 (dataset registry) |
| `metafeatures-service.openapi.json` | `http://localhost:8002` | 4 (meta-feature extraction) |
| `generation-service.openapi.json` | `http://localhost:8003` | 7 (async LLM runs + sweeps) |
| `analysis-service.openapi.json` | `http://localhost:8004` | 7 (RQ1–RQ5 analytics) |

## Which one should teammates use?

Import **`gateway.openapi.json` first**. It re-exposes every backend path under the same names on port `8000` and adds the two composed workflows (`/workflows/upload-and-extract`, `/workflows/full-run`). For 90% of frontend work that's the only collection needed.

Only import the individual service specs when directly hitting a backend for debugging (bypassing gateway CORS, or checking a service in isolation).

## Import — Postman

1. Postman → **File → Import** → drag the JSON in.
2. Postman auto-generates a collection named after the service (e.g. `automl-gateway`).
3. Each request comes with the exact request body schema and example. Fill in path/body, hit Send.

## Import — Insomnia

1. Insomnia → **Create → Import From File** → pick the JSON.
2. Choose "Request Collection" as the import type.

## Refreshing these snapshots

The stack must be running. From `automl-infra/`:

```bash
for svc in gateway:8000 data-service:8001 metafeatures-service:8002 generation-service:8003 analysis-service:8004; do
    name="${svc%:*}"
    port="${svc#*:}"
    curl -s "http://localhost:$port/openapi.json" -o "postman/${name}.openapi.json"
done
```

Re-run this whenever you add or rename endpoints so teammates get the up-to-date schema.

## Live example — end-to-end run

Once the stack is up (`docker compose -f docker-compose.yml -f docker-compose.full.yml up -d`), the shortest smoke test is:

```bash
# Upload CSV + extract meta-features (no LLM required)
curl -X POST http://localhost:8000/workflows/upload-and-extract \
     -F "file=@your.csv;type=text/csv" \
     -F "target_col=your_target_col" \
     -F "task_type=regression"

# Full run: upload + meta-features + enqueue LLM generation
curl -X POST http://localhost:8000/workflows/full-run \
     -F "file=@your.csv;type=text/csv" \
     -F "target_col=your_target_col" \
     -F "task_type=regression" \
     -F "condition=b2_metafeature" \
     -F "llm_backend=gpt-oss:120b-cloud" \
     -F "seed=42" \
     -F "max_iter=3" \
     -F "timeout_seconds=300"

# Poll for completion (returns immediately with rq_job_id; row appears once worker finishes)
curl "http://localhost:8000/runs?dataset_id=<id_from_full_run>&limit=1"
```
