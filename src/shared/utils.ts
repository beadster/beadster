/**
 * Shared utility functions for beadster
 * Date formatting, string helpers, etc.
 */

/**
 * Format Unix timestamp to localized date string
 */
export function formatDate(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleDateString();
}

/**
 * Format Unix timestamp to localized date and time string
 */
export function formatDateTime(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleString();
}

/**
 * Format timestamp as relative time (e.g., "2h ago", "3d ago")
 */
export function formatRelativeTime(timestamp: number): string {
  const now = Date.now();
  const diff = now - timestamp;
  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) return `${days}d ago`;
  if (hours > 0) return `${hours}h ago`;
  if (minutes > 0) return `${minutes}m ago`;
  return 'just now';
}

/**
 * Get CSS class for priority badge
 */
export function getPriorityClass(priority: number | null): string {
  if (priority === null) return '';
  if (priority === 0) return 'priority';
  if (priority === 1) return 'priority p1';
  return 'priority p2';
}

/**
 * Extract repository name from Git URL
 * Examples:
 *   https://github.com/user/repo.git -> user/repo
 *   git@github.com:user/repo.git -> user/repo
 */
export function getRepoName(url: string): string {
  try {
    const match = url.match(/([^/:]+\/[^/:]+?)(\.git)?$/);
    return match ? match[1] : url;
  } catch {
    return url;
  }
}

/**
 * Parse external reference string into structured data
 * Supports: GitHub, Jira, Linear
 */
export function parseExternalRef(ref: string | null): {
  platform: string;
  repoPath?: string;
  id: string;
  url?: string;
} | null {
  if (!ref) return null;

  // github:owner/repo:issue-id
  const githubMatch = ref.match(/^github:([^:]+):(.+)$/);
  if (githubMatch) {
    return {
      platform: 'GitHub',
      repoPath: githubMatch[1],
      id: githubMatch[2],
      url: `https://github.com/${githubMatch[1]}`
    };
  }

  // jira:PROJECT-123
  const jiraMatch = ref.match(/^jira:(.+)$/);
  if (jiraMatch) {
    return { platform: 'Jira', id: jiraMatch[1] };
  }

  // linear:abc-123
  const linearMatch = ref.match(/^linear:(.+)$/);
  if (linearMatch) {
    return { platform: 'Linear', id: linearMatch[1] };
  }

  return { platform: 'External', id: ref };
}
