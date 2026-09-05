#!/usr/bin/env bash
# Bootstraps every vendored tool repo under repos/ on a fresh machine.
#
# Usage (from a fresh clone of this repository):
#   git submodule update --init --recursive
#   ./repos/setup.sh
#
# Requires: node/npm, pnpm, bun, python3, uv, cargo (only needed for the
# repos that use them — the script skips a step if the tool isn't found).

set -uo pipefail
cd "$(dirname "$0")"

have() { command -v "$1" >/dev/null 2>&1; }

npm_install() {
  local dir="$1"
  echo "=== npm install: $dir ==="
  (cd "$dir" && npm install) || echo "!! npm install failed in $dir"
}

pnpm_install() {
  local dir="$1"
  echo "=== pnpm install: $dir ==="
  have pnpm || { echo "!! pnpm not found, skipping $dir"; return; }
  pnpm install --dir "$dir" || echo "!! pnpm install failed in $dir"
}

bun_install() {
  local dir="$1"
  echo "=== bun install: $dir ==="
  have bun || { echo "!! bun not found, skipping $dir"; return; }
  (cd "$dir" && bun install) || echo "!! bun install failed in $dir"
}

uv_sync() {
  local dir="$1"
  echo "=== uv sync: $dir ==="
  have uv || { echo "!! uv not found, skipping $dir"; return; }
  (cd "$dir" && uv sync) || echo "!! uv sync failed in $dir"
}

pip_venv() {
  local dir="$1" req="$2"
  echo "=== venv + pip install: $dir ==="
  python3 -m venv "$dir/.venv" || { echo "!! venv creation failed in $dir"; return; }
  "$dir/.venv/bin/pip" install -q -r "$dir/$req" || echo "!! pip install failed in $dir"
}

cargo_check() {
  local dir="$1"
  echo "=== cargo check: $dir ==="
  have cargo || { echo "!! cargo not found, skipping $dir"; return; }
  (cd "$dir" && cargo check) || echo "!! cargo check failed in $dir"
}

# --- npm (root package.json + package-lock.json) ---
for d in ECC agent-skills chrome-devtools-mcp perplexity-modelcontextprotocol playwright-mcp; do
  npm_install "$d"
done

# --- pnpm workspaces ---
for d in OmniRoute agent-browser context7 firecrawl-mcp-server; do
  pnpm_install "$d"
done

# --- bun ---
bun_install claude-mem

# --- uv (Python, pyproject.toml + uv.lock) ---
uv_sync strix

# --- plain venv + requirements.txt ---
pip_venv storyscope requirements.txt
pip_venv watermarks-remover requirements-dev.txt

# --- ECC also ships a Python package (llm-abstraction) ---
python3 -m venv ECC/ecc2/.venv 2>/dev/null
ECC/ecc2/.venv/bin/pip install -q -e "ECC[dev]" || echo "!! ECC python install failed"

# --- Rust workspace ---
cargo_check headroom

echo
echo "Done. Repos with no build step (pure markdown skills/plugins, or a"
echo "hosted remote MCP server) need no install: awesome-design-md,"
echo "taste-skill, one-skill-to-rule-them-all, claude-plugins-official,"
echo "knowledge-work-plugins, marketingskills, social-media-skills,"
echo "glif-mcp-server. See repos/README.md for how to use each repo."
