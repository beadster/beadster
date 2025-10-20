-- Fix priority column type from TEXT to INTEGER
-- Priority values: 0 (P0 - critical), 1 (P1 - high), 2 (P2 - normal)

-- SQLite doesn't support ALTER COLUMN TYPE directly, so we need to:
-- 1. Add new column
-- 2. Copy data (converting text to integer)
-- 3. Drop old column
-- 4. Rename new column

-- Add new INTEGER column
ALTER TABLE issues ADD COLUMN priority_new INTEGER;

-- Copy data, converting TEXT to INTEGER
-- Handle "P0" -> 0, "P1" -> 1, "P2" -> 2
-- Also handle raw numbers "0", "1", "2"
UPDATE issues
SET priority_new = CASE
  WHEN priority = 'P0' OR priority = '0' THEN 0
  WHEN priority = 'P1' OR priority = '1' THEN 1
  WHEN priority = 'P2' OR priority = '2' THEN 2
  WHEN priority = '1.0' THEN 1
  WHEN priority = '2.0' THEN 2
  WHEN priority = '0.0' THEN 0
  ELSE NULL
END
WHERE priority IS NOT NULL;

-- Drop old column
ALTER TABLE issues DROP COLUMN priority;

-- Rename new column
ALTER TABLE issues RENAME COLUMN priority_new TO priority;
