-- Ensure datasets uniqueness across fresh DB inits.
-- Live DB already has this constraint (Stage 2 ad-hoc DDL); this file makes
-- the migration reproducible on a bare volume so init and migrated environments
-- agree.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'datasets_source_name_target_uniq'
  ) THEN
    ALTER TABLE datasets
      ADD CONSTRAINT datasets_source_name_target_uniq
      UNIQUE (source, name, target_col);
  END IF;
END $$;
