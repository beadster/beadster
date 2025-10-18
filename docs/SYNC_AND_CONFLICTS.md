# sync and conflicts in beadster

how beadster handles multi-source sync and conflict resolution

## overview

beadster needs to work like beads auto-sync, but across:
- multiple sources (different .beads/ directories)
- multiple devices (macbook, iphone, web)
- cloud as sync layer (instead of just git)

like beads:
- auto-export: local changes → cloud (after 5s debounce)
- auto-import: cloud changes → local (when cloud is newer)
- conflict resolution: smart merge with desktop as authority

## architecture

```
Desktop A                     Cloud (D1)                    Desktop B
~/projects/                                                 ~/projects/
├── app-a/.beads/            sources table:                ├── app-a/.beads/
│   └── issues.jsonl         - app-a (anton, device-mac1)  │   └── issues.jsonl
└── app-b/.beads/            - app-b (anton, device-mac1)  └── app-c/.beads/
    └── issues.jsonl         - app-c (anton, device-mac2)      └── issues.jsonl

                             issues table:
                             - source_id + beads_id (unique)
                             - global id (ulid)

iPhone                       Web Browser
beadster app                 beadster.com
- reads from cloud           - reads from cloud
- no local .beads/           - no local .beads/
- writes to cloud            - writes to cloud
```

## sync flow (like beads auto-sync)

### 1. local → cloud (auto-export)

when bd creates/updates issue in local .beads/:

```typescript
// beads does this automatically:
// 1. bd create writes to SQLite
// 2. after 5s debounce, exports to issues.jsonl
// 3. git commit captures the change

// beadster sync daemon does:
class SyncDaemon {
  private pendingChanges = new Map<SourceId, Change[]>();
  private debounceTimers = new Map<SourceId, NodeJS.Timeout>();

  // watch .beads/issues.jsonl for changes
  watchSource(source: Source) {
    const watcher = fs.watch(`${source.path}/.beads/issues.jsonl`);

    watcher.on('change', () => {
      this.scheduleSync(source);
    });
  }

  // debounce like beads (5 seconds)
  scheduleSync(source: Source) {
    const existingTimer = this.debounceTimers.get(source.id);
    if (existingTimer) clearTimeout(existingTimer);

    this.debounceTimers.set(source.id, setTimeout(() => {
      this.syncToCloud(source);
    }, 5000));
  }

  async syncToCloud(source: Source) {
    // read local issues.jsonl
    const localIssues = await this.readLocalJSONL(source);

    // fetch cloud issues for this source
    const cloudIssues = await this.cloudAPI.getIssues(source.id);

    // detect changes (new, updated, deleted)
    const changes = this.detectChanges(localIssues, cloudIssues);

    // resolve conflicts (desktop wins)
    const resolved = await this.resolveConflicts(changes, source);

    // push to cloud
    await this.cloudAPI.syncIssues(source.id, resolved);

    // update last_sync timestamp
    source.last_sync = Date.now();
    await this.saveSources();
  }
}
```

### 2. cloud → local (auto-import)

when cloud has newer changes (from other device or web):

```typescript
class SyncDaemon {
  // poll cloud every 30s (or use websocket)
  async pollCloud() {
    for (const source of this.sources) {
      const cloudIssues = await this.cloudAPI.getIssues(source.id, {
        since: source.last_sync
      });

      if (cloudIssues.length > 0) {
        await this.syncFromCloud(source, cloudIssues);
      }
    }
  }

  async syncFromCloud(source: Source, cloudIssues: Issue[]) {
    // read local issues.jsonl
    const localIssues = await this.readLocalJSONL(source);

    // merge cloud changes into local
    const merged = this.mergeIssues(localIssues, cloudIssues);

    // write back to issues.jsonl
    await this.writeLocalJSONL(source, merged);

    // bd auto-imports from jsonl on next command
    // (beads checks if jsonl is newer than sqlite)

    source.last_sync = Date.now();
    await this.saveSources();
  }
}
```

## conflict resolution

### case 1: no conflict (easy)

```typescript
// local has bd-1 v1, cloud has bd-1 v2 (same issue, cloud newer)
// → use cloud version (cloud wins for timestamps)

// local has bd-2, cloud doesn't have it
// → push to cloud (new from local)

// cloud has bd-3, local doesn't have it
// → pull to local (new from cloud)
```

### case 2: ID collision (rare but critical)

happens when:
- web creates bd-5 for source "myapp"
- desktop creates different bd-5 for same source
- both try to sync

**beads solution:** `bd import --resolve-collisions`
- detects collision (same id, different content)
- renumbers incoming issue to new id
- updates all text references and dependencies

**beadster uses same approach:**

```typescript
async resolveConflicts(changes: Change[], source: Source): Promise<Change[]> {
  const resolved: Change[] = [];

  for (const change of changes) {
    if (change.type === 'collision') {
      // collision: local and cloud have different bd-5

      // strategy: desktop wins
      const localIssue = change.local;
      const cloudIssue = change.cloud;

      // check if cloud issue has been seen by any real client
      const views = await this.cloudAPI.getIssueViews(cloudIssue.id);
      const seenByRealClient = views.some(v =>
        ['macos', 'ios', 'cli'].includes(v.client)
      );

      if (!seenByRealClient) {
        // cloud issue only from web, never synced to real client
        // safe to renumber cloud issue
        const newBeadsId = await this.getNextAvailableId(source);

        await this.cloudAPI.remapIssue(cloudIssue.id, {
          old_beads_id: cloudIssue.beads_id,
          new_beads_id: newBeadsId
        });

        // now push local issue (wins the original id)
        resolved.push({
          type: 'create',
          issue: localIssue
        });
      } else {
        // cloud issue already synced to clients
        // must keep both - renumber local instead
        const newBeadsId = await this.getNextAvailableId(source);

        // update local issue with new id
        localIssue.beads_id = newBeadsId;

        // update references in local jsonl
        await this.updateLocalReferences(source,
          change.local.beads_id,
          newBeadsId
        );

        resolved.push({
          type: 'create',
          issue: localIssue
        });
      }
    } else {
      resolved.push(change);
    }
  }

  return resolved;
}
```

## issue_views table (visibility tracking)

**purpose:** know if cloud issue has been synced to real clients yet

```sql
CREATE TABLE issue_views (
  issue_id TEXT NOT NULL,           -- global issue id
  device_id TEXT NOT NULL,
  client TEXT NOT NULL,             -- 'macos', 'ios', 'web', 'cli'
  first_seen INTEGER,
  last_seen INTEGER,
  PRIMARY KEY (issue_id, device_id),
  FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
  FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_issue_views_issue ON issue_views(issue_id);
CREATE INDEX idx_issue_views_device ON issue_views(device_id);
```

**usage:**

```typescript
// when sync daemon pulls issue from cloud
async syncFromCloud(source: Source, cloudIssues: Issue[]) {
  for (const issue of cloudIssues) {
    // record that this device saw this issue
    await this.cloudAPI.recordView(issue.id, {
      device_id: this.deviceId,
      client: 'macos',
      timestamp: Date.now()
    });
  }

  // ... continue with merge
}

// when checking if safe to renumber
async isSafeToRenumber(issueId: string): Promise<boolean> {
  const views = await this.cloudAPI.getIssueViews(issueId);

  // safe if only seen by web/mobile (ephemeral clients)
  return views.every(v => ['web', 'mobile'].includes(v.client));
}
```

## web/mobile issue creation

web and mobile don't have local .beads/, so they use cloud as their database

**prevent collisions upfront:**

```sql
-- track next id per source
CREATE TABLE source_sequences (
  source_id TEXT PRIMARY KEY,
  next_beads_id INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (source_id) REFERENCES sources(id)
);
```

```typescript
// web creates issue
app.post('/api/issues', async (c) => {
  const { source_id, title, body } = await c.req.json();

  // get next id for this source
  const result = await c.env.DB.prepare(`
    UPDATE source_sequences
    SET next_beads_id = next_beads_id + 1
    WHERE source_id = ?
    RETURNING next_beads_id - 1 as seq
  `).bind(source_id).first();

  const beadsId = `bd-${result.seq}`;
  const globalId = ulid();

  await c.env.DB.prepare(`
    INSERT INTO issues (
      id, source_id, beads_id, title, body,
      created_by_device_id, created_by_client,
      created_at, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    globalId, source_id, beadsId, title, body,
    deviceId, 'web',
    Date.now(), Date.now()
  ).run();

  return c.json({ id: globalId, beads_id: beadsId });
});

// when desktop syncs, it updates the sequence if higher
async syncToCloud(source: Source) {
  const localIssues = await this.readLocalJSONL(source);

  // get highest local beads_id
  const maxId = Math.max(...localIssues.map(i =>
    parseInt(i.beads_id.replace('bd-', ''))
  ));

  // ensure cloud sequence is at least this high
  await this.cloudAPI.updateSequence(source.id, maxId + 1);

  // ... continue with sync
}
```

## sync algorithm (complete)

```typescript
class SyncDaemon {
  async syncSource(source: Source) {
    // 1. read local state
    const localIssues = await this.readLocalJSONL(source);
    const localHashes = this.hashIssues(localIssues);

    // 2. fetch cloud state
    const cloudIssues = await this.cloudAPI.getIssues(source.id);
    const cloudHashes = this.hashIssues(cloudIssues);

    // 3. detect changes
    const changes = {
      newLocal: [],      // in local, not in cloud
      newCloud: [],      // in cloud, not in local
      updatedLocal: [],  // in both, local newer
      updatedCloud: [],  // in both, cloud newer
      collisions: [],    // in both, different, same timestamp
      deleted: []        // was in cloud, now gone from local
    };

    for (const local of localIssues) {
      const cloud = cloudIssues.find(c => c.beads_id === local.beads_id);

      if (!cloud) {
        changes.newLocal.push(local);
      } else if (localHashes[local.beads_id] !== cloudHashes[cloud.beads_id]) {
        if (local.updated_at > cloud.updated_at) {
          changes.updatedLocal.push(local);
        } else if (cloud.updated_at > local.updated_at) {
          changes.updatedCloud.push(cloud);
        } else {
          changes.collisions.push({ local, cloud });
        }
      }
    }

    for (const cloud of cloudIssues) {
      if (!localIssues.find(l => l.beads_id === cloud.beads_id)) {
        changes.newCloud.push(cloud);
      }
    }

    // 4. resolve collisions
    for (const collision of changes.collisions) {
      const resolved = await this.resolveCollision(collision, source);
      if (resolved.useLocal) {
        changes.updatedLocal.push(collision.local);
      } else if (resolved.useCloud) {
        changes.updatedCloud.push(collision.cloud);
      } else {
        // renumber one of them
        changes.updatedLocal.push(resolved.remappedIssue);
      }
    }

    // 5. apply changes

    // push new/updated local → cloud
    await this.cloudAPI.batchUpsert(source.id, [
      ...changes.newLocal,
      ...changes.updatedLocal
    ]);

    // pull new/updated cloud → local
    const mergedIssues = [...localIssues];
    for (const cloudIssue of changes.newCloud) {
      mergedIssues.push(cloudIssue);
    }
    for (const cloudIssue of changes.updatedCloud) {
      const idx = mergedIssues.findIndex(i => i.beads_id === cloudIssue.beads_id);
      mergedIssues[idx] = cloudIssue;
    }

    // write back to local
    await this.writeLocalJSONL(source, mergedIssues);

    // 6. record views
    for (const issue of mergedIssues) {
      await this.cloudAPI.recordView(issue.id, {
        device_id: this.deviceId,
        client: 'macos',
        timestamp: Date.now()
      });
    }

    // 7. update last sync
    source.last_sync = Date.now();
    await this.saveSources();
  }

  hashIssues(issues: Issue[]): Record<string, string> {
    return Object.fromEntries(
      issues.map(i => [
        i.beads_id,
        crypto.createHash('sha256')
          .update(JSON.stringify(i))
          .digest('hex')
      ])
    );
  }
}
```

## recommendations

### implement in this order:

1. **source_sequences table** - prevent web/mobile collisions upfront
2. **basic sync** - push/pull without conflict resolution
3. **issue_views table** - track visibility for safe renumbering
4. **collision resolution** - use beads algorithm (renumber + update refs)
5. **auto-sync debounce** - 5s debounce like beads
6. **polling/websocket** - real-time cloud → local updates

### sync strategies by device:

**desktop (has .beads/):**
- authority for its sources
- wins conflicts
- uses local sqlite + jsonl
- sync daemon watches file changes

**mobile/web (no .beads/):**
- uses cloud as database
- cloud generates ids from sequence
- reads from cloud api
- writes to cloud api

**cloud:**
- aggregation layer
- tracks sequences per source
- resolves conflicts (desktop wins)
- provides views table for consensus

### when to use issue_views:

- determining if cloud issue has synced to real clients
- safe window for id renumbering (web → desktop collision)
- consensus tracking (future: wait for all devices to see before deleting)
- analytics (which devices are active, sync health)

### NOT for:

- normal sync (use timestamps)
- change detection (use hashes)
- deciding who wins (desktop always wins)
