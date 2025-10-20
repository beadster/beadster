-- Add issue_type column to issues table
ALTER TABLE issues ADD COLUMN issue_type TEXT;

-- Set default issue_type for existing issues
UPDATE issues SET issue_type = 'task' WHERE issue_type IS NULL;
