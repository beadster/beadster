# URL structure

beadster uses GitHub as the default namespace for repository viewing

## design principle

GitHub is the default tool for everyone, so GitHub repos should be first-class citizens in the URL structure

## URL patterns

### GitHub repos (primary)

```
beadster.ai/steveyegge/beads
beadster.ai/facebook/react
beadster.ai/owner/repo
```

direct mapping from GitHub URLs:
- `github.com/steveyegge/beads` → `beadster.ai/steveyegge/beads`
- `github.com/facebook/react` → `beadster.ai/facebook/react`

### closed issues view

```
beadster.ai/owner/repo/closed
```

### backwards compatibility

old URLs redirect to new structure:
```
beadster.ai/github/owner/repo → beadster.ai/owner/repo (301 redirect)
```

## rationale

**simpler URLs**
- shorter and cleaner
- mirrors GitHub structure exactly
- intuitive for developers

**GitHub as default**
- GitHub is the de facto standard for code hosting
- most users expect GitHub repos
- no need to specify platform in URL

**future extensibility**
- can add other platforms with explicit prefixes if needed:
  - `/gitlab/owner/repo`
  - `/bitbucket/owner/repo`
- GitHub remains unprefixed as the default

## implementation

### file structure

```
src/web/src/pages/
├── [owner]/
│   └── [repo]/
│       ├── index.astro          # /{owner}/{repo}
│       └── closed.astro         # /{owner}/{repo}/closed
└── github/
    └── [owner]/
        └── [repo].astro         # redirect to /{owner}/{repo}
```

### dynamic routes

- `[owner]` - GitHub username or organization
- `[repo]` - repository name
- automatically fetches from github.com/{owner}/{repo}

### route precedence

Astro resolves routes in this order:
1. static routes (e.g., `/settings`, `/login`)
2. dynamic routes (e.g., `/[owner]/[repo]`)

this means:
- `/settings` → settings page (static)
- `/steveyegge/beads` → GitHub repo viewer (dynamic)
- `/login` → login page (static)

no conflicts because we don't have users at top-level routes

## user experience

### discovery

users can:
- paste GitHub URLs and replace domain
- browse from homepage link
- share clean URLs without /github/ prefix

### migration

- old URLs automatically redirect
- no broken links
- transparent to users

## examples

### viewing a repo

```
https://beadster.ai/steveyegge/beads
```

shows:
- repository info
- open issues
- stats
- import button

### viewing closed issues

```
https://beadster.ai/steveyegge/beads/closed
```

shows:
- repository info
- closed issues
- stats

### importing a repo

from `beadster.ai/owner/repo`:
- click "import to my account"
- creates source record
- imports all issues

## documentation updates

all docs updated to reflect new URL structure:
- examples use `beadster.ai/owner/repo`
- no mention of `/github/` prefix
- backwards compatibility noted

## future considerations

### other platforms

if we add GitLab, Bitbucket, or other platforms:
```
beadster.ai/owner/repo          # GitHub (default)
beadster.ai/gitlab/owner/repo   # GitLab (explicit)
beadster.ai/bb/owner/repo       # Bitbucket (explicit)
```

### user profiles

if we add user profiles, use different path:
```
beadster.ai/@username           # user profile
beadster.ai/u/username          # user profile (alternative)
beadster.ai/owner/repo          # GitHub repo (no conflict)
```

### ambiguity resolution

if `beadster.ai/foo/bar` could be either:
- user 'foo' with project 'bar'
- GitHub repo 'foo/bar'

strategy:
1. check if it's a valid GitHub repo (API call)
2. if yes, show repo
3. if no, show 404 or user profile

currently: always assume GitHub repo (no user profiles yet)

## performance

### caching

GitHub API responses cached for fast loading:
- repo info: 15 minutes
- issues: 5 minutes
- public repos use unauthenticated API

### rate limits

public GitHub API:
- 60 requests/hour per IP (unauthenticated)
- 5000 requests/hour per user (authenticated)

this is sufficient for typical usage

## SEO benefits

clean URLs improve SEO:
- shorter URLs rank better
- keyword-rich (owner/repo names)
- matches user search intent
- mirrors canonical GitHub URLs

## conclusion

treating GitHub as the default namespace provides:
- cleaner, shorter URLs
- better user experience
- simpler mental model
- room for future expansion

the new structure feels natural to developers and aligns with how they already think about GitHub repos
