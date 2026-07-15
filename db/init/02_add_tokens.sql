-- Migration: add per-run LLM token accounting to run_results.
--
-- Applied live 2026-07-15 (Stage 2, Task 5a). Also included here so a fresh
-- Postgres init (via docker compose up on a clean volume) picks it up without
-- a separate migration step.
--
-- prompt_tokens     : Ollama /api/generate `prompt_eval_count`, summed across iterations
-- completion_tokens : Ollama /api/generate `eval_count`, summed across iterations
-- total_tokens      : GENERATED (STORED) sum — computed by Postgres, never written to
--                     directly by application code.
--
-- Idempotent (uses IF NOT EXISTS).

ALTER TABLE run_results
  ADD COLUMN IF NOT EXISTS prompt_tokens INT,
  ADD COLUMN IF NOT EXISTS completion_tokens INT,
  ADD COLUMN IF NOT EXISTS total_tokens INT GENERATED ALWAYS AS
    (COALESCE(prompt_tokens,0) + COALESCE(completion_tokens,0)) STORED;
