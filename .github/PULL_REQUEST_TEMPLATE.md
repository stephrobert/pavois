<!-- Thanks for contributing! Keep the PR focused. See CONTRIBUTING.md. -->

## What & why

<!-- What does this change and why? Link issues with "Closes #123". -->

## Type

<!-- Conventional Commits scope of the change. -->

- [ ] feat: new capability
- [ ] fix: bug fix
- [ ] rule: new / improved control
- [ ] docs · refactor · test · ci · chore · build

## Checklist

- [ ] Commits follow **Conventional Commits**; the change is focused.
- [ ] **Tested on a real target** (state which): `pavois scan …` output validated.
- [ ] Go gates pass locally: `gofmt -l .` clean, `go vet`, `go build`, `go test -race`, `golangci-lint run`, `govulncheck`.
- [ ] Python gates pass (if `tools/` changed): `ruff check`, `ruff format --check`, `bandit -c pyproject.toml`.
- [ ] Tests and docs updated with the code; no dead code.
- [ ] **No derived artifacts committed** (the `.rb` corpus, OSCAL, `dist/` are generated: `mise run regen`).
- [ ] No secrets, real hostnames/IPs or keys in the diff.

## For a rule change

- [ ] Audits the **effective** configuration (not a service file).
- [ ] Neutral slug id + `impact`/`title`/`desc` + `tag domain:` + ≥1 **sourced** standard mapping + level tags.
- [ ] Edited in `docs/reference/rules.yml` (not the generated `.rb`); `mise run gen:verify` passes.
