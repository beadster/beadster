-- Add mirror support columns to sources table

ALTER TABLE sources ADD COLUMN is_mirror INTEGER DEFAULT 0;
ALTER TABLE sources ADD COLUMN auto_sync INTEGER DEFAULT 0;
ALTER TABLE sources ADD COLUMN sync_interval_minutes INTEGER DEFAULT 5;

-- Update existing github-import sources to be non-mirrors
UPDATE sources SET is_mirror = 0, auto_sync = 0 WHERE type IN ('github-import', 'github-import-private');
