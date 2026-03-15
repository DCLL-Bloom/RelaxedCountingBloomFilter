---
description: "Initialize all MCP servers and verify they are responsive"
agent: "orchestrator"
---

Initialize and verify all configured MCP servers. For each server, make one simple call to confirm it responds:

1. **fetch** — Fetch `https://example.com` to verify web fetching works
2. **sequential-thinking** — Start a single thought: "Test connectivity"
3. **papersflow** — Search for "bloom filter" with limit 1
4. **arxiv** — Search arXiv for "bloom filter" with limit 1
5. **dblp** — Search DBLP for "bloom filter" with limit 1
6. **oncite** — Look up citation for "10.1145/362686.362692" (Bloom's original paper)
7. **arxiv-latex** — Attempt to fetch LaTeX for any recent arXiv paper
8. **latex** — List available tools/capabilities
9. **github** — Get the current repository info (if GITHUB_TOKEN is set)

For each server, report:
- ✅ Server name — working
- ❌ Server name — error message

Summarize which servers are ready and which need attention.
