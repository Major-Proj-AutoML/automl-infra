-- AutoML schema. Runs once on first postgres container start.

CREATE TABLE IF NOT EXISTS datasets (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    source          TEXT NOT NULL CHECK (source IN ('openml', 'custom')),
    openml_id       INTEGER,
    target_col      TEXT NOT NULL,
    task_type       TEXT NOT NULL CHECK (task_type IN (
        'binary_classification',
        'multiclass_classification',
        'regression'
    )),
    train_path      TEXT NOT NULL,
    test_path       TEXT NOT NULL,
    n_rows          INTEGER,
    n_cols          INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_datasets_source ON datasets(source);
CREATE INDEX IF NOT EXISTS idx_datasets_openml_id ON datasets(openml_id);


CREATE TABLE IF NOT EXISTS meta_features (
    id              SERIAL PRIMARY KEY,
    dataset_id      INTEGER NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    features        JSONB NOT NULL,
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (dataset_id)
);

CREATE INDEX IF NOT EXISTS idx_meta_features_dataset_id ON meta_features(dataset_id);


CREATE TABLE IF NOT EXISTS run_results (
    id                      SERIAL PRIMARY KEY,
    dataset_id              INTEGER NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    condition               TEXT NOT NULL CHECK (condition IN ('B0', 'B1', 'B2')),
    llm_backend             TEXT NOT NULL,
    seed                    INTEGER NOT NULL,
    iteration               INTEGER NOT NULL DEFAULT 0,
    success                 BOOLEAN NOT NULL,
    test_score              DOUBLE PRECISION,
    error_category          TEXT,
    error_message           TEXT,
    iterations_used         INTEGER,
    max_iterations          INTEGER,
    runtime_seconds         DOUBLE PRECISION,
    generated_code_path     TEXT,
    -- B2 structured reasoning: the LLM's decision list (as parsed) and the
    -- mechanical audit against meta-features + code AST. NULL for B0/B1
    -- runs and for B2 runs where extraction/verification failed.
    reasoning_trace         JSONB,
    verification_report     JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_run_results_dataset_id ON run_results(dataset_id);
CREATE INDEX IF NOT EXISTS idx_run_results_condition ON run_results(condition);
CREATE INDEX IF NOT EXISTS idx_run_results_llm_backend ON run_results(llm_backend);
CREATE INDEX IF NOT EXISTS idx_run_results_success ON run_results(success);


CREATE TABLE IF NOT EXISTS sweep_jobs (
    id              SERIAL PRIMARY KEY,
    rq_job_id       TEXT UNIQUE,
    status          TEXT NOT NULL CHECK (status IN (
        'queued', 'running', 'completed', 'failed', 'cancelled'
    )),
    params          JSONB NOT NULL,
    total_cells     INTEGER,
    completed_cells INTEGER NOT NULL DEFAULT 0,
    failed_cells    INTEGER NOT NULL DEFAULT 0,
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sweep_jobs_status ON sweep_jobs(status);
CREATE INDEX IF NOT EXISTS idx_sweep_jobs_rq_job_id ON sweep_jobs(rq_job_id);
