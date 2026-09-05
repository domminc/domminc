# repos/ — vendored tool repos

22 external tool/skill/MCP-server repositories, tracked here as **git
submodules** (source only — no `node_modules`/`.venv`/`target` is ever
committed, since each submodule is a separate repo and the parent only
records a commit pointer).

## Get everything on a new machine

```bash
git clone <this repo>
cd domminc
git submodule update --init --recursive
./repos/setup.sh   # installs npm/pnpm/bun/uv/pip/cargo deps for every repo that needs one
```

## Update a submodule to its latest upstream commit

```bash
git submodule update --remote repos/<name>
git add repos/<name>
git commit -m "chore: bump repos/<name>"
```

## What's here and how to use it

| Repo | What it is | How to use |
|---|---|---|
| [ECC](https://github.com/affaan-m/ECC) | Agent harness OS (skills/hooks/rules for Claude Code, Cursor, Codex, etc.) | `npx ecc-universal setup` inside a project, or see `AGENTS.md` |
| [context7](https://github.com/upstash/context7) | Up-to-date library docs MCP server | `npx ctx7 setup` to wire it into your MCP clients |
| [strix](https://github.com/usestrix/strix) | Autonomous security-testing agent (Python/uv) | `uv run strix` (see README for scan targets/auth); also installable as a skill via `npx skills add usestrix/strix` |
| [awesome-design-md](https://github.com/VoltAgent/awesome-design-md) | Curated collection of `DESIGN.md` files from real projects | Reference material, browse `design-md/` |
| [taste-skill](https://github.com/Leonxlnx/taste-skill) | "Anti-slop" frontend design skill | `npx skills add https://github.com/Leonxlnx/taste-skill` |
| [agent-skills](https://github.com/vercel-labs/agent-skills) | Vercel Labs' skill collection + the `skills` CLI itself | `npm install` done; `npx skills add <owner/repo>` installs any skill repo into your project |
| [agent-browser](https://github.com/vercel-labs/agent-browser) | Browser-automation agent CLI | `npm install -g agent-browser`, or `npx skills add vercel-labs/agent-browser` |
| [watermarks-remover](https://github.com/guillaumemeyer/watermarks-remover) | Removes watermarks from images/video (Python skill + service) | `./install-skill.sh` or use the `.venv` created by `setup.sh` |
| [storyscope](https://github.com/jenna-russell/storyscope) | Story/content analysis tool (Python) | Use the `.venv` created by `setup.sh`; see `storyscope/` package entrypoints |
| [OmniRoute](https://github.com/diegosouzapw/OmniRoute) | LLM routing platform (web + CLI + Electron, pnpm monorepo) | `npm install -g omniroute`, or run from source after `pnpm install` — see `README.md` |
| [headroom](https://github.com/headroomlabs-ai/headroom) | LLM context-optimization proxy (Rust, Python bindings via maturin) | `cargo build --release` for the Rust proxy/CLI; `uv run maturin develop` for the Python package |
| [claude-mem](https://github.com/thedotmack/claude-mem) | Persistent memory plugin for Claude Code | `npx claude-mem install` |
| [claude-plugins-official](https://github.com/anthropics/claude-plugins-official) | Anthropic's official Claude Code plugin marketplace/directory | Browse `plugins/` and `external_plugins/`; install via Claude Code's `/plugin` marketplace |
| [one-skill-to-rule-them-all](https://github.com/rebelytics/one-skill-to-rule-them-all) | Meta-skill ("task-observer") that watches usage and improves your other skills | See `SKILL.md` / `USER-GUIDE.md` for install |
| [playwright-mcp](https://github.com/microsoft/playwright-mcp) | Browser automation MCP server | `claude mcp add playwright npx @playwright/mcp@latest` |
| [firecrawl-mcp-server](https://github.com/firecrawl/firecrawl-mcp-server) | Web scraping/crawling MCP server | `claude mcp add firecrawl --env FIRECRAWL_API_KEY=<key> -- npx -y firecrawl-mcp` |
| [chrome-devtools-mcp](https://github.com/ChromeDevTools/chrome-devtools-mcp) | Chrome DevTools Protocol MCP server | See README for `claude mcp add` invocation; Chromium is already available in this env |
| [perplexity-modelcontextprotocol](https://github.com/perplexityai/modelcontextprotocol) | Perplexity search MCP server | `claude mcp add perplexity --env PERPLEXITY_API_KEY=<key> -- npx -y @perplexity-ai/mcp-server` |
| [glif-mcp-server](https://github.com/glifxyz/glif-mcp-server) | Media-generation MCP server (hosted, not self-run) | `claude mcp add --transport http glif https://glif.app/api/mcp` (OAuth sign-in, no API key) |
| [knowledge-work-plugins](https://github.com/anthropics/knowledge-work-plugins) | Anthropic's role-based Claude/Cowork plugins (sales, legal, finance, etc.) | Browse the role folders; install a plugin via Claude Code's `/plugin` marketplace |
| [marketingskills](https://github.com/coreyhaines31/marketingskills) | Marketing-focused agent skills (CRO, copywriting, SEO, growth) | `npx skills add coreyhaines31/marketingskills`, or copy a skill from `skills/` |
| [social-media-skills](https://github.com/charlie947/social-media-skills) | Social-media content skills (LinkedIn, X, Substack, YouTube) | `npx skills add charlie947/social-media-skills`, or copy a skill from `skills/` |

## Notes

- Everything was cloned and dependency-installed once already in this
  session (`npm`/`pnpm`/`bun install`, `uv sync`, a `pip` venv, or
  `cargo check`, depending on the repo) — `setup.sh` reproduces exactly
  that on any other machine.
- MCP servers that need an API key (`firecrawl-mcp-server`,
  `perplexity-modelcontextprotocol`) won't do anything useful until you
  supply one via `claude mcp add --env ...` or your MCP client's config.
- `npm audit` flags some vulnerabilities in a few of these (mostly dev
  dependencies upstream) — not fixed here since these are vendored
  third-party repos, not this project's own code.
