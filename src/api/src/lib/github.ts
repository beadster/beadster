// GitHub API utilities for importing beads repositories

export interface GitHubRepo {
  owner: string;
  repo: string;
  branch: string;
}

export interface Issue {
  id: string;
  title: string;
  body?: string;
  status: string;
  priority?: number;
  issue_type?: string;
  labels?: string[];
  created_at: string;
  updated_at: string;
  closed_at?: string;
  external_ref?: string;
  [key: string]: any;
}

export function parseGitHubUrl(url: string): GitHubRepo | null {
  // https://github.com/owner/repo
  // git@github.com:owner/repo.git
  const httpsMatch = url.match(/github\.com[\/:]([^\/]+)\/([^\/\.]+)/);
  if (httpsMatch) {
    return {
      owner: httpsMatch[1],
      repo: httpsMatch[2],
      branch: 'main'
    };
  }
  return null;
}

export function createExternalRef(owner: string, repo: string, issueId: string): string {
  return `github:${owner}/${repo}:${issueId}`;
}

export function parseExternalRef(ref: string): { platform: string; repoPath: string; issueId: string } | null {
  const match = ref.match(/^github:([^:]+):(.+)$/);
  if (!match) return null;

  return {
    platform: 'github',
    repoPath: match[1],
    issueId: match[2]
  };
}

/**
 * Fetch issues.jsonl from a public GitHub repository
 */
export async function fetchPublicBeads(
  owner: string,
  repo: string,
  branch: string = 'main'
): Promise<Issue[]> {
  const url = `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/.beads/issues.jsonl`;

  const response = await fetch(url);
  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('repository not found or no .beads/issues.jsonl');
    }
    throw new Error(`GitHub API error: ${response.statusText}`);
  }

  const jsonl = await response.text();
  return parseJSONL(jsonl, owner, repo);
}

/**
 * Fetch issues.jsonl from a private GitHub repository (requires token)
 */
export async function fetchPrivateBeads(
  owner: string,
  repo: string,
  token: string,
  branch: string = 'main'
): Promise<Issue[]> {
  const url = `https://api.github.com/repos/${owner}/${repo}/contents/.beads/issues.jsonl?ref=${branch}`;

  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github.v3.raw',
      'User-Agent': 'Beadster-Import'
    }
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('repository not found or no .beads/issues.jsonl');
    }
    if (response.status === 401 || response.status === 403) {
      throw new Error('authentication failed - check GitHub token');
    }
    throw new Error(`GitHub API error: ${response.statusText}`);
  }

  const jsonl = await response.text();
  return parseJSONL(jsonl, owner, repo);
}

/**
 * Parse JSONL content and add external_ref to each issue
 */
function parseJSONL(jsonl: string, owner: string, repo: string): Issue[] {
  const lines = jsonl.split('\n').filter(line => line.trim());
  const issues: Issue[] = [];

  for (const line of lines) {
    try {
      const issue = JSON.parse(line);
      // Add external_ref if not already present
      if (!issue.external_ref) {
        issue.external_ref = createExternalRef(owner, repo, issue.id);
      }
      issues.push(issue);
    } catch (err) {
      console.error('failed to parse JSONL line:', err);
    }
  }

  return issues;
}

/**
 * Check if a GitHub repository has beads by checking for .beads/issues.jsonl
 */
export async function checkRepoHasBeads(owner: string, repo: string, branch: string = 'main'): Promise<boolean> {
  const url = `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/.beads/issues.jsonl`;

  try {
    const response = await fetch(url, { method: 'HEAD' });
    return response.ok;
  } catch {
    return false;
  }
}

/**
 * Fetch repository info from GitHub API
 */
export async function fetchRepoInfo(owner: string, repo: string, token?: string) {
  const url = `https://api.github.com/repos/${owner}/${repo}`;

  const headers: HeadersInit = {
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'Beadster'
  };

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch(url, { headers });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('repository not found');
    }
    throw new Error(`GitHub API error: ${response.statusText}`);
  }

  return response.json();
}
