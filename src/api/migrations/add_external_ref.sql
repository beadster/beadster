-- Add external_ref field to issues table for hybrid workflows
-- Supports GitHub, Jira, Linear, etc.

ALTER TABLE issues ADD COLUMN external_ref TEXT;

-- Create index for fast lookups when matching external references
CREATE INDEX idx_issues_external_ref ON issues(external_ref);

-- Comment: external_ref format examples:
-- github:owner/repo:issue-id (e.g. github:steveyegge/beads:bd-1)
-- jira:PROJECT-123
-- linear:abc-123
