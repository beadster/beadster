/**
 * Tests for shared utility functions
 */

import { describe, it, expect } from '@jest/globals';
import {
  formatDate,
  formatDateTime,
  formatRelativeTime,
  getPriorityClass,
  getRepoName,
  parseExternalRef,
} from './utils';

describe('formatDate', () => {
  it('should format Unix timestamp to localized date', () => {
    // Jan 1, 2024 00:00:00 UTC
    const timestamp = 1704067200;
    const result = formatDate(timestamp);
    expect(result).toMatch(/1\/1\/2024|2024/); // Different locales format differently
  });
});

describe('formatDateTime', () => {
  it('should format Unix timestamp to localized date and time', () => {
    const timestamp = 1704067200;
    const result = formatDateTime(timestamp);
    expect(result).toBeTruthy();
    expect(typeof result).toBe('string');
  });
});

describe('formatRelativeTime', () => {
  it('should return "just now" for recent timestamps', () => {
    const now = Date.now();
    expect(formatRelativeTime(now)).toBe('just now');
  });

  it('should return minutes ago', () => {
    const fiveMinutesAgo = Date.now() - 5 * 60 * 1000;
    expect(formatRelativeTime(fiveMinutesAgo)).toBe('5m ago');
  });

  it('should return hours ago', () => {
    const twoHoursAgo = Date.now() - 2 * 60 * 60 * 1000;
    expect(formatRelativeTime(twoHoursAgo)).toBe('2h ago');
  });

  it('should return days ago', () => {
    const threeDaysAgo = Date.now() - 3 * 24 * 60 * 60 * 1000;
    expect(formatRelativeTime(threeDaysAgo)).toBe('3d ago');
  });
});

describe('getPriorityClass', () => {
  it('should return empty string for null priority', () => {
    expect(getPriorityClass(null)).toBe('');
  });

  it('should return "priority" for P0', () => {
    expect(getPriorityClass(0)).toBe('priority');
  });

  it('should return "priority p1" for P1', () => {
    expect(getPriorityClass(1)).toBe('priority p1');
  });

  it('should return "priority p2" for P2 and higher', () => {
    expect(getPriorityClass(2)).toBe('priority p2');
    expect(getPriorityClass(3)).toBe('priority p2');
    expect(getPriorityClass(4)).toBe('priority p2');
  });
});

describe('getRepoName', () => {
  it('should extract repo name from HTTPS URL', () => {
    expect(getRepoName('https://github.com/user/repo.git')).toBe('user/repo');
  });

  it('should extract repo name from HTTPS URL without .git', () => {
    expect(getRepoName('https://github.com/user/repo')).toBe('user/repo');
  });

  it('should extract repo name from SSH URL', () => {
    expect(getRepoName('git@github.com:user/repo.git')).toBe('user/repo');
  });

  it('should return original string if no match', () => {
    expect(getRepoName('invalid-url')).toBe('invalid-url');
  });
});

describe('parseExternalRef', () => {
  it('should return null for null input', () => {
    expect(parseExternalRef(null)).toBeNull();
  });

  it('should parse GitHub reference', () => {
    const result = parseExternalRef('github:owner/repo:123');
    expect(result).toEqual({
      platform: 'GitHub',
      repoPath: 'owner/repo',
      id: '123',
      url: 'https://github.com/owner/repo',
    });
  });

  it('should parse Jira reference', () => {
    const result = parseExternalRef('jira:PROJECT-123');
    expect(result).toEqual({
      platform: 'Jira',
      id: 'PROJECT-123',
    });
  });

  it('should parse Linear reference', () => {
    const result = parseExternalRef('linear:abc-123');
    expect(result).toEqual({
      platform: 'Linear',
      id: 'abc-123',
    });
  });

  it('should parse unknown reference as External', () => {
    const result = parseExternalRef('custom:xyz-789');
    expect(result).toEqual({
      platform: 'External',
      id: 'custom:xyz-789',
    });
  });
});
