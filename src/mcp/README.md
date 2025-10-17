# Beadster MCP Server

model context protocol server for claude to interact with beads

## features

- wraps bd cli
- auto-finds .beads/ directory
- adds session tracking labels automatically
- supports ready work queries
- falls back to ~/.beadster/inbox if no .beads/ found

## setup

```bash
npm install
npm run build
```

## configure in claude code

add to `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "beadster": {
      "command": "node",
      "args": ["/path/to/beadster/src/mcp/dist/index.js"]
    }
  }
}
```

## tools provided

- `todo_create` - create todo with session tracking
- `todo_list` - list todos (filter by status/labels)
- `todo_complete` - mark todo complete
- `todo_ready` - list ready work (no blockers)

## session tracking

automatically adds labels to every issue:

- `session:xxx` - unique session id (persists 24h)
- `client:xxx` - which claude client (code/desktop)
- `project:xxx` - project name from directory

these labels are extracted by sync daemon and sent to cloud for session grouping

## example usage

in claude code:

```
User: "Create todo: implement auth"

Claude: ✓ Created todo: beadster-2
        Title: implement auth
        Session: session_1234567890...
        Client: claude-code
```

```
User: "Show ready work"

Claude: Ready to work on (3):
        beadster-1: build POC [P0]
        beadster-2: implement auth [P2]
        beadster-3: add tests [P2]
```
