# Supply-chain hardening: Living Off The Pipeline (LOTP) audit

[LOTP](https://boostsecurityio.github.io/lotp/) catalogs dev tools whose normal commands can
execute arbitrary code (config-driven plugins, lifecycle scripts, `go generate` directives, …):
an RCE-by-design surface when CI runs them on an untrusted PR. This is the audit of every
LOTP-listed tool pavois uses and how its use is hardened. Goal: **no PR can run bad or malicious
code in our pipeline, and no dependency runs code on install.**

## Tools we use that LOTP catalogs

| Tool | Where | RCE vector | Hardening |
|---|---|---|---|
| **npm / npx** | site build | dependency `postinstall`/`preinstall` scripts | `site/.npmrc` → `ignore-scripts=true`; clean installs use `npm ci --ignore-scripts`. Validated: the site builds with zero lifecycle scripts (native deps ship prebuilt binaries via `optionalDependencies`). |
| **golangci-lint** | `go.yml`, pre-commit | custom/module plugins (`.so`, `linters.custom`) | `.golangci.yml` declares **no** custom plugins; only first-party linters. PR runs have `contents: read` and no secrets reach fork PRs. |
| **pre-commit** | local dev | runs arbitrary hooks from `.pre-commit-config.yaml` | hook repos **pinned by rev**; local hooks run only our own `language: system` commands. Not run in CI. |
| **stylelint** | `site:lint-css` | JS plugins loaded from config | config uses only published, declared plugins; no inline JS executors. |
| **trivy** | `deps.yml` |: (scanner) | action **pinned by SHA**; read-only. |
| **uv / pip** | `python.yml`, mise | dependency `setup.py` on install | versions **pinned** (`ruff==0.14.9`, `bandit[toml]==1.9.2`); deps from PyPI; tooling only, never the shipped product. |
| **actions/setup-node** | `deps.yml` | post-setup hooks | **pinned by SHA**. |
| **bash / sed / awk / tar / wget** | scripts, CI | shell/arg injection | controlled args, `shell=False` equivalents, no untrusted interpolation (enforced by gosec/bandit + review). |

Tools LOTP lists that we deliberately **do not** use: goreleaser (we use nfpm, not LOTP-listed),
gradle/maven/ant/msbuild/make/rake/just/mage, poetry, pytest/pylint/flake8/mypy (we use ruff+bandit),
eslint/prettier/webpack/yarn, terraform/tflint, docker-in-docker, `go generate` (no `//go:generate`
in the tree).

## Pipeline-level controls (defense in depth)

- **Least privilege.** Every workflow declares `permissions: {}` at the top and the minimum per job
  (`contents: read` for quality gates). Only `release.yml` and `codeql.yml`/`scorecard.yml` request
  `write` scopes, and only for their publish/SARIF step.
- **No secrets to untrusted PRs.** GitHub withholds repository secrets from fork-triggered
  `pull_request` runs. `SCANKIT_TOKEN` (the only secret) is therefore never exposed to a fork PR; the
  Go build/CodeQL job simply can't check out the private dep on a fork PR (fails safe, leaks nothing).
- **Pinned everything.** All third-party Actions are pinned by **40-char commit SHA**; tool versions
  are pinned; container images (when used) by digest. Enforced by the Plumber compliance gate.
- **SAST on every PR.** CodeQL (Go, Python, JS/TS, `security-extended`) gates merges: the catch-all
  for injectable/malicious patterns lint misses. Run locally before push too.
- **Dependency gate.** `dependency-review.yml` blocks a PR that introduces a HIGH/CRITICAL-vuln
  dependency or a copyleft license; `deps.yml` (Trivy) re-audits the full lockfile weekly.

## Recommended repository settings (apply once public)

- **Require approval for all external contributors** before their workflow runs execute
  (Settings → Actions → Fork pull request workflows). Stops a first-PR `go test`/lint from running
  attacker code on a runner at all.
- **Branch protection on `main`** (needs public repo or Pro): no force-push, no deletion, require the
  CI checks above to pass. This also clears the last Plumber finding (ISSUE-501) → score 100/A.
