/**
 * Unit tests for hash-based ID generation
 * Run with: node --test hashIdGenerator.test.ts (Node.js 20+)
 * Or with any test framework (Jest, Vitest, etc.)
 */

import { describe, test } from 'node:test';
import assert from 'node:assert';
import {
  generateHashID,
  collisionProbability,
  computeAdaptiveLength,
  countTopLevelIssues,
  getAdaptiveIDLength,
  generateUniqueID,
  defaultAdaptiveIDConfig,
} from './hashIdGenerator';

describe('HashIDGenerator', () => {
  describe('generateHashID', () => {
    test('generates 4-character hash', () => {
      const id = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        new Date(1234567890000),
        4,
        0
      );

      assert.ok(id.startsWith('test-'), 'ID should start with prefix');
      const hash = id.substring(5); // 'test-' is 5 chars
      assert.strictEqual(hash.length, 4, 'Hash should be 4 characters');
      assert.match(hash, /^[0-9a-f]+$/, 'Hash should be hexadecimal');
    });

    test('generates 5-character hash', () => {
      const id = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        new Date(1234567890000),
        5,
        0
      );

      const hash = id.substring(5);
      assert.strictEqual(hash.length, 5, 'Hash should be 5 characters');
      assert.match(hash, /^[0-9a-f]+$/, 'Hash should be hexadecimal');
    });

    test('generates 6-character hash', () => {
      const id = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        new Date(1234567890000),
        6,
        0
      );

      const hash = id.substring(5);
      assert.strictEqual(hash.length, 6, 'Hash should be 6 characters');
      assert.match(hash, /^[0-9a-f]+$/, 'Hash should be hexadecimal');
    });

    test('generates 7-character hash', () => {
      const id = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        new Date(1234567890000),
        7,
        0
      );

      const hash = id.substring(5);
      assert.strictEqual(hash.length, 7, 'Hash should be 7 characters');
      assert.match(hash, /^[0-9a-f]+$/, 'Hash should be hexadecimal');
    });

    test('generates 8-character hash', () => {
      const id = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        new Date(1234567890000),
        8,
        0
      );

      const hash = id.substring(5);
      assert.strictEqual(hash.length, 8, 'Hash should be 8 characters');
      assert.match(hash, /^[0-9a-f]+$/, 'Hash should be hexadecimal');
    });

    test('is deterministic with same inputs', () => {
      const timestamp = new Date(1234567890000);

      const id1 = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        timestamp,
        6,
        0
      );

      const id2 = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        timestamp,
        6,
        0
      );

      assert.strictEqual(id1, id2, 'Same inputs should produce same hash');
    });

    test('different nonce produces different hash', () => {
      const timestamp = new Date(1234567890000);

      const id1 = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        timestamp,
        6,
        0
      );

      const id2 = generateHashID(
        'test',
        'Sample Issue',
        'Description',
        'user1',
        timestamp,
        6,
        1
      );

      assert.notStrictEqual(id1, id2, 'Different nonces should produce different hashes');
    });

    test('different title produces different hash', () => {
      const timestamp = new Date(1234567890000);

      const id1 = generateHashID(
        'test',
        'Issue A',
        'Description',
        'user1',
        timestamp,
        6,
        0
      );

      const id2 = generateHashID(
        'test',
        'Issue B',
        'Description',
        'user1',
        timestamp,
        6,
        0
      );

      assert.notStrictEqual(id1, id2, 'Different titles should produce different hashes');
    });
  });

  describe('collisionProbability', () => {
    test('small database has low collision probability', () => {
      // With 100 issues and 4-char hash (16^4 = 65,536 possibilities)
      const prob = collisionProbability(100, 4);
      assert.ok(prob < 0.1, 'Collision probability should be < 10% for 100 issues with 4-char hash');
    });

    test('large database has higher collision probability', () => {
      // With 1000 issues and 4-char hash (16^4 = 65,536 possibilities)
      const prob = collisionProbability(1000, 4);
      assert.ok(prob > 0.05, 'Collision probability should increase with more issues');
    });

    test('increases with more issues', () => {
      const prob100 = collisionProbability(100, 4);
      const prob500 = collisionProbability(500, 4);

      assert.ok(prob500 > prob100, 'More issues should increase collision probability');
    });

    test('decreases with longer hash', () => {
      const prob4 = collisionProbability(500, 4);
      const prob6 = collisionProbability(500, 6);

      assert.ok(prob6 < prob4, 'Longer hashes should decrease collision probability');
    });
  });

  describe('computeAdaptiveLength', () => {
    test('uses minimum length for small database', () => {
      const config = defaultAdaptiveIDConfig();
      const length = computeAdaptiveLength(100, config);
      assert.strictEqual(length, 4, 'Should use minimum length for small database');
    });

    test('uses longer length for medium database', () => {
      const config = defaultAdaptiveIDConfig();
      const length = computeAdaptiveLength(500, config);
      assert.ok(length >= 5, 'Should use longer length for medium database');
    });

    test('uses longer length for large database', () => {
      const config = defaultAdaptiveIDConfig();
      const length = computeAdaptiveLength(2000, config);
      assert.ok(length >= 6, 'Should use longer length for large database');
    });

    test('respects max length', () => {
      const config = defaultAdaptiveIDConfig();
      const length = computeAdaptiveLength(1_000_000, config);
      assert.ok(length <= config.maxLength, 'Should not exceed max length');
    });
  });

  describe('countTopLevelIssues', () => {
    test('excludes children with dots', () => {
      const issues = [
        { id: 'test-a1b2' },
        { id: 'test-c3d4' },
        { id: 'test-a1b2.1' },  // child
        { id: 'test-a1b2.2' },  // child
        { id: 'test-c3d4.1' },  // child
      ];

      const count = countTopLevelIssues('test', issues);
      assert.strictEqual(count, 2, 'Should count only top-level issues');
    });

    test('excludes other prefixes', () => {
      const issues = [
        { id: 'test-a1b2' },
        { id: 'test-c3d4' },
        { id: 'other-e5f6' },
        { id: 'another-g7h8' },
      ];

      const count = countTopLevelIssues('test', issues);
      assert.strictEqual(count, 2, 'Should count only issues with matching prefix');
    });

    test('returns 0 for empty list', () => {
      const issues: { id: string }[] = [];
      const count = countTopLevelIssues('test', issues);
      assert.strictEqual(count, 0, 'Should return 0 for empty list');
    });
  });

  describe('getAdaptiveIDLength', () => {
    test('returns minimum length for small database', () => {
      const issues = Array.from({ length: 100 }, (_, i) => ({
        id: `test-${i.toString(16).padStart(4, '0')}`
      }));

      const length = getAdaptiveIDLength('test', issues);
      assert.strictEqual(length, 4, 'Should use minimum length for 100 issues');
    });

    test('returns longer length for medium database', () => {
      const issues = Array.from({ length: 500 }, (_, i) => ({
        id: `test-${i.toString(16).padStart(4, '0')}`
      }));

      const length = getAdaptiveIDLength('test', issues);
      assert.ok(length >= 5, 'Should use longer length for 500 issues');
    });
  });

  describe('generateUniqueID', () => {
    test('generates unique ID without collisions', () => {
      const existingIssues = [
        { id: 'test-a1b2' },
        { id: 'test-c3d4' },
      ];

      const id = generateUniqueID(
        'test',
        'New Issue',
        'Description',
        'user1',
        new Date(),
        existingIssues
      );

      assert.ok(id.startsWith('test-'), 'Should have correct prefix');
      assert.ok(!existingIssues.some(issue => issue.id === id), 'Should not collide with existing IDs');
    });

    test('handles many existing issues', () => {
      const existingIssues = Array.from({ length: 100 }, (_, i) => ({
        id: `test-${i.toString(16).padStart(4, '0')}`
      }));

      const id = generateUniqueID(
        'test',
        'New Issue',
        'Description',
        'user1',
        new Date(),
        existingIssues
      );

      assert.ok(id.startsWith('test-'), 'Should have correct prefix');
      assert.ok(!existingIssues.some(issue => issue.id === id), 'Should generate unique ID even with many existing');
    });

    test('different timestamps produce different IDs', () => {
      const existingIssues: { id: string }[] = [];

      const id1 = generateUniqueID(
        'test',
        'Issue',
        'Description',
        'user1',
        new Date(1234567890000),
        existingIssues
      );

      const id2 = generateUniqueID(
        'test',
        'Issue',
        'Description',
        'user1',
        new Date(1234567891000),
        existingIssues
      );

      assert.notStrictEqual(id1, id2, 'Different timestamps should produce different IDs');
    });
  });
});
