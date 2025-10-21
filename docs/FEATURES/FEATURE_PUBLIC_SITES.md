# public sites for public issues

public issue tracking sites with SEO, free hosting, and read-only access for open source projects

## problem

- people want to follow development of projects they care about
- project managers need to track external dependencies
- open source projects need public issue tracking with good SEO
- no easy way to view GitHub issues in a clean, fast interface

## solution

connect public GitHub repos and display issues at beadster.ai/username/repo with nice SEO and fast UI

## core features

- connect GitHub repo URL: https://github.com/steveyegge/beads
- display at: beadster.ai/steveyegge/beads
- read-only public view (no auth required)
- good SEO for issue discovery
- free for public repos
- import via GitHub URL in macOS app (no file backend needed)
- live sync with GitHub issues

## use cases

- following development of projects you care about (eg beads itself)
- project managers tracking external dependencies
- teams wanting better GitHub issues UI with beadster features
- open source projects wanting public issue tracking with SEO
- developers researching how projects handle certain issues

## implementation notes

- no file backend required for GitHub-sourced projects
- issues stored in cloud database, synced from GitHub
- read-only for non-members
- sign in required for: commenting, creating issues, watching
- free tier: public repos only
- paid tier: private repos

## macOS app integration

- add project via GitHub URL (no .beads folder needed)
- auto-sync from GitHub
- read-only mode for non-members
- edit mode if user has GitHub access
- use case: follow projects you don't own

## web interface

- clean, fast issue list
- good SEO (server-side rendering)
- public URLs: beadster.ai/{owner}/{repo}
- individual issue URLs: beadster.ai/{owner}/{repo}/issues/{number}
- no sign-in required for viewing
- sign-in for interactions (watch, comment, create)

## monetization

- public repos: free
- private repos: paid plans
- GitHub issues import: free
- beadster-native features: paid tiers
