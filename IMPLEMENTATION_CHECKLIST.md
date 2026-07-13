# Implementation Checklist

## Structure

- Create a shared infra repo, such as `ethereum/eip-infra` or `ethereum/proposal-infra`.
- Move the shared layer into it:
  - `.github/workflows/`
  - `.github/actions/`
  - `_includes/`
  - `_layouts/`
  - `config/`
  - templates
  - shared contributor guidance
- Keep proposal markdown files and repo-specific overrides in `EIPs` and `ERCs`.

## Canonical One-Way Consumption

- Shared repo is the canonical owner of infra.
- Flow is one-way: `shared -> consumers`.
- Remove CI merge workarounds so local and CI execution are identical.

## Consumer Repo .gitmodules

```ini
[submodule "infra/shared"]
	path = infra/shared
	url = https://github.com/ethereum/eip-infra.git
	branch = main
	# You can pin to a tag instead of branch for stability
```

## Shared Infra Release Workflow

In `eip-infra`:

```yaml
# .github/workflows/release.yml
name: Release shared infra

on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Create release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ github.ref }}
          name: "Shared Infra Release ${{ github.ref_name }}"
          draft: false
          prerelease: false
```

Consumers can pin to a tag with:

```bash
git submodule set-branch --branch v1.2.3 infra/shared
```

## Consumer Repo Setup

```bash
git submodule add https://github.com/ethereum/eip-infra.git infra/shared
git submodule update --init --recursive
```

## GitHub Actions

```yaml
- name: Checkout
  uses: actions/checkout@v4
  with:
    submodules: recursive
```

```yaml
- name: Lint with shared config
  run: eipw --config infra/shared/config/eipw.toml
```

Reusable workflow pattern:

```yaml
jobs:
  lint:
    uses: ethereum/eip-infra/.github/workflows/lint.yml@v1
```

Reusable action pattern:

```yaml
- uses: ethereum/eip-infra/.github/actions/lint@v1
```

## Pilot Workflow Templates

- Shared reusable lint workflow: [examples/workflows/shared-reusable-lint.yml](examples/workflows/shared-reusable-lint.yml)
- Consumer CI calling shared workflow: [examples/workflows/consumer-ci-using-shared.yml](examples/workflows/consumer-ci-using-shared.yml)
- Consumer bot PR for pinned tag updates: [examples/workflows/consumer-update-shared-tag-bot.yml](examples/workflows/consumer-update-shared-tag-bot.yml)

## Jekyll

Point Jekyll at shared layouts and includes from `infra/shared` instead of copying them into each repo.

Temporary compatibility layer during migration:

```yaml
# _config.yml in EIPs/ERCs (temporary)
collections:
  shared:
    permalink: /shared/:path
```

Or use symlinks and add them to `.gitignore` in the consumer repos:

```bash
ln -sfn infra/shared/_includes _includes
ln -sfn infra/shared/_layouts _layouts
```

## Sync / Update Script

```bash
#!/usr/bin/env bash
set -euo pipefail

git submodule update --init --recursive
git add .gitmodules infra/shared
git commit -m "chore: update shared infra submodule" || echo "No changes"
```

## Makefile

```makefile
# Makefile (add to both EIPs and ERCs)

SHARED_PATH = infra/shared

setup:
  git submodule update --init --recursive
  @echo "✅ Environment ready"

lint:
  eipw --config $(SHARED_PATH)/config/eipw.toml

lint-fix:
  eipw --config $(SHARED_PATH)/config/eipw.toml --fix

build:
  bundle exec jekyll build --config _config.yml,$(SHARED_PATH)/_config.yml

serve:
  bundle exec jekyll serve --config _config.yml,$(SHARED_PATH)/_config.yml

update-shared:
  git submodule update --remote --merge $(SHARED_PATH)
  git add $(SHARED_PATH) .gitmodules
  git commit -m "chore: update shared infra to latest"

status:
  @echo "Shared infra commit:"
  @git -C $(SHARED_PATH) log -1 --oneline
```

## Shared-Repo Validation

```yaml
name: Validate shared infra

on:
  push:
    branches: [main]
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Basic checks
        run: |
          test -f config/eipw.toml
          test -d _includes
          test -d _layouts
```

Also run a representative consumer validation subset from shared-infra CI to catch cross-repo breakage before release.

## Runtime Test

```yaml
name: Runtime Test

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  runtime-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install dependencies
        run: bundle install

      - name: Build site
        run: bundle exec jekyll build

      - name: Run lint against shared config
        run: eipw --config infra/shared/config/eipw.toml
```

## Helper Scripts

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Setting up EIP/ERC development environment..."

git submodule update --init --recursive

echo "✅ Shared infra ready at infra/shared"
echo "Current shared commit: $(git -C infra/shared rev-parse --short HEAD)"
```

## Validation Script

```bash
#!/usr/bin/env bash
# scripts/validate-infra.sh

set -euo pipefail

echo "Validating shared infrastructure..."

REQUIRED=(
  "config/eipw.toml"
  "_layouts/eip.html"
  "_includes/header.html"
  "templates/eip-template.md"
)

for file in "${REQUIRED[@]}"; do
  if [[ ! -f "infra/shared/$file" ]]; then
    echo "❌ Missing required file: $file"
    exit 1
  fi
done

echo "✅ All required shared files present"
echo "Shared commit: $(git -C infra/shared rev-parse --short HEAD)"
```

## Pre-commit Hooks

```yaml
# .pre-commit-config.yaml (in shared repo + consumers)
repos:
  - repo: local
    hooks:
      - id: check-shared-infra
        name: Verify shared infra submodule
        entry: bash -c 'test -f infra/shared/config/eipw.toml || (echo "Shared infra not initialized!" && exit 1)'
        language: system
        always_run: true
        pass_filenames: false
```

## Issue Template

Add this in consumers at `.github/ISSUE_TEMPLATE/infra-change.md`:

```markdown
---
name: Shared Infrastructure Change
about: Changes that affect both EIPs and ERCs
labels: infra, shared
---

**Impact**
- [ ] Affects EIPs only
- [ ] Affects ERCs only
- [ ] Affects both (shared)

**Files changed in shared repo:**
- 
```

## Suggested rollout phases

- Phase 1: low-risk files
- Phase 2: layouts and includes
- Phase 3: full switch and cleanup

## Success criteria

- no more disabled lint rules due only to the split
- local validation matches CI
- zero duplicated shared infra files

## Governance

- Name maintainers for the shared infra repo.
- Require review from both EIP and ERC maintainers for shared changes.
- Prefer pinned shared releases over ad hoc branch tracking in consumers.

## Ownership and Approval

- Define one canonical owner group for the shared infra repo.
- Require approval from at least one EIP maintainer and one ERC maintainer for shared changes.
- Let consumer-repo maintainers approve version bumps, but not silently change shared content.
- Document who can cut shared releases and who can revert them.

## Rollback / Recovery

- If a shared release breaks consumers, pin back to the previous known-good tag.
- If a submodule bump fails CI, revert the submodule update PR.
- Keep the last known-good shared release in the changelog.

## Rollback Playbook

1. Identify the last known-good shared tag.
2. Pin both consumer repos back to that tag.
3. Revert the bad shared release or submodule bump PR.
4. Cut a fixed shared release once CI passes.
5. Announce the rollback and the replacement release in the discussion thread.

## Decision matrix

| Option | Contributor UX | CI Simplicity | Migration Risk | Notes |
| --- | --- | --- | --- | --- |
| Submodule | Medium | High | Medium | Best fit for preserving separate repos |
| Generated mirror | Medium | Medium | Medium-High | Good fallback if submodules prove awkward |
| Monorepo | Low-Medium | High | High | Cleanest structurally, most disruptive culturally |

## Validation matrix

- `make setup` succeeds locally.
- `make lint` matches CI.
- `bundle exec jekyll build` succeeds with shared assets.
- Shared repo validation passes on every tag and pull request.
- Consumer CI fails fast if `infra/shared` is missing.
- Consumer CI runs against pinned shared tag before publish.

## Consumer impact

- Update `.gitmodules`, `Makefile`, and setup docs.
- Contributors edit shared files only in the shared repo.
- Repo-specific overrides should be explicit and small.

## Communication plan

- Announce shared release bumps in the issue or PR thread.
- Document the pinned shared revision in consumer release notes.
- Call out breaking changes before the shared release is tagged.

## Monitoring metrics

- duplicated infra file count
- lint rules disabled due to split
- cross-repo hotfix frequency
- shared release adoption lag in consumers

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Submodule confusion for new contributors | Medium | Medium | Clear `CONTRIBUTING.md` + `Makefile` + setup script + CI that fails fast if the submodule is missing |
| Submodule version skew between repos | Low | High | Daily auto-update PR bot + approval required for major changes |
| Broken CI during migration | Medium | High | Incremental file-by-file migration + feature flags or symlinks during transition |
| Resistance to submodules | Low-Medium | Medium | Strong docs + fallback generated-mirror path if needed |
| GitHub rate limits on submodule fetches | Low | Low | Shallow submodules + CI cache |

## Phased migration plan

### Phase 0: Preparation

- Create `ethereum/eip-infra`.
- Move 3–5 low-risk files first, such as one `_includes/` file or shared scripts.
- Add the submodule to both `EIPs` and `ERCs`.

### Phase 1: Low Risk (1–2 weeks)

- Common GitHub Actions and reusable workflows.
- Documentation files like `CONTRIBUTING.md` and templates.
- Basic config files.

### Phase 2: Medium Risk

- Jekyll layouts and includes.
- `eipw.toml` unification and re-enable disabled rules.
- Remove merge-repos hacks.

### Phase 3: Cleanup

- Delete duplicated files.
- Update all documentation and paths.
- Add update bot and release process.
- Apply the same pattern to RIPs if applicable.

## Suggested repository name options

- `ethereum/eip-infra` (most clear)
- `ethereum/proposal-infra`
- `ethereum/eips-infra`
- `ethereum/shared-proposal-tooling`

## Contributor onboarding snippet

Add this to the main README:

### Quick Start

```bash
# Clone + setup
git clone https://github.com/ethereum/EIPs.git
cd EIPs
git submodule update --init --recursive

# Development
make setup     # first time only
make lint
make serve
```

All shared tooling lives in `infra/shared/`. Never edit copies — always edit in the shared repo.

## One-command bootstrap script

See [bootstrap.sh](bootstrap.sh) for a ready-to-run bootstrap helper.

## Who can help?

- `poojaranjan`
- `jochem-brouwer`
- `SamWilsn`
- `ryanio`


## Suggested Rollout Order

1. Create the shared infra repository.
2. Move one low-risk shared file first, such as an include or layout.
3. Add the shared repo as a submodule in both consumer repos.
4. Update checkouts to be recursive.
5. Point tools like `eipw` and Jekyll at the submodule paths.
6. Remove merge hacks and re-enable disabled lint rules.
7. Iterate file-by-file until duplication is gone.

## Editor-Approved Pilot (3-4 PRs)

1. Create shared-infra repo and add `COPYING` and `MAINTAINERS`.
2. Move one safe file (for example `_includes/header.html`), add submodule in both repos, and wire Jekyll path.
3. Replace one CI merge step with submodule checkout and re-enable one previously disabled lint rule.
4. Add shared release/tag workflow and a bot PR that updates consumer pinned tag.
