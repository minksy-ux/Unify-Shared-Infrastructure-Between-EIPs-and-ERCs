# Migration Guide

This guide captures the implementation details for the shared infrastructure migration.

## 0. Proposed shared-infra repository layout

```text
shared-infra/
├── .github/
│   ├── workflows/          # Reusable workflows (lint, build, etc.)
│   └── actions/            # Reusable composite actions
├── _includes/              # Jekyll includes
├── _layouts/               # Jekyll layouts (eip.html, etc.)
├── config/
│   └── eipw.toml           # Unified config (with optional layering)
├── templates/
│   ├── eip-template.md
│   └── erc-template.md     # or use one template + frontmatter flags
├── scripts/                # sync, validate, release scripts
├── CONTRIBUTING.md
└── README.md
```

## 0.1 Jekyll configuration for shared assets

```yaml
# _config.yml (in EIPs or ERCs repo)
include:
  - infra/shared/_includes
  - infra/shared/_layouts

# Or use Jekyll's data/config merging if needed
defaults:
  - scope:
      path: ""
    values:
      layout: "eip"
      shared_infra_version: "main"   # or pinned tag
```

## 1. Add the shared repo as a submodule

Run once per consumer repo:

```bash
git submodule add https://github.com/ethereum/eip-infra.git infra/shared
git submodule update --init --recursive
```

Example `.gitmodules` entry in consumer repos:

```ini
[submodule "infra/shared"]
	path = infra/shared
	url = https://github.com/ethereum/eip-infra.git
	branch = main
	# You can pin to a tag instead of branch for stability
```

Consumers can pin to a tag with:

```bash
git submodule set-branch --branch v1.2.3 infra/shared
```

## 1.1 Shared infra release workflow

In the `eip-infra` repo:

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

## 2. Initialize submodules in GitHub Actions

Use recursive checkout:

```yaml
- name: Checkout
  uses: actions/checkout@v4
  with:
    submodules: recursive
```

Or be explicit:

```yaml
- uses: actions/checkout@v4
- run: git submodule update --init --recursive
```

## 3. Point tooling at the shared config

```yaml
- name: Lint with shared config
  run: eipw --config infra/shared/config/eipw.toml
```

For Jekyll, read layouts and includes from `infra/shared` rather than duplicated local copies.

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

## 4. Sync / update script

This can live in the shared repo or as a reusable action:

```bash
#!/usr/bin/env bash
set -euo pipefail

git submodule update --init --recursive
git add .gitmodules infra/shared
git commit -m "chore: update shared infra submodule" || echo "No changes"
```

## 4.1 Local Makefile

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

## 5. Shared-repo validation workflow

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

## 5.1 Validation script

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

## 5.2 Pre-commit hooks

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

## 5.3 Issue template suggestion

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

## 5.4 Suggested rollout phases

- Phase 1: low-risk files
- Phase 2: layouts and includes
- Phase 3: full switch and cleanup

## 5.5 Success criteria

- no more disabled lint rules due only to the split
- local validation matches CI
- zero duplicated shared infra files

## 5.6 Who can help?

- `poojaranjan`
- `jochem-brouwer`
- `SamWilsn`
- `ryanio`

## 5.1 Advanced submodule-aware CI workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint-and-build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout with submodules
        uses: actions/checkout@v4
        with:
          submodules: recursive
          fetch-depth: 0

      - name: Verify shared infra
        run: |
          test -d infra/shared/_layouts
          test -f infra/shared/config/eipw.toml
          echo "Shared infra version: $(git -C infra/shared rev-parse --short HEAD)"

      - name: Run linter (unified)
        run: eipw --config infra/shared/config/eipw.toml

      - name: Build Jekyll site
        uses: actions/jekyll-build-pages@v1
        with:
          source: .
          destination: ./_site
          config: _config.yml,infra/shared/_config.yml   # optional overlay
```

## 5.2 Submodule update bot / sync workflow

Place this in the shared-infra repo or in EIPs:

```yaml
# .github/workflows/update-shared-infra.yml
name: Update shared infra submodule

on:
  schedule:
    - cron: "0 3 * * *"   # daily at 3 AM UTC
  workflow_dispatch:

jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Update submodule to latest
        run: |
          git submodule update --remote --merge infra/shared
          git -C infra/shared log -1 --oneline

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v7
        with:
          commit-message: "chore: update shared infra submodule"
          title: "chore: update shared infra submodule"
          body: "Automated update of the shared infrastructure submodule."
          branch: update-shared-infra
```

## 5.3 Config layering example

Shared config:

```toml
# infra/shared/config/eipw.toml
# ... common rules ...

# ERC-specific overrides can be applied on top in the consumer repo
```

Small overlay in ERCs:

```yaml
# ercs/config/erc-overlay.toml
[lints]
# ERC-specific rule tweaks
```

## 5.4 Local development helper script

```bash
#!/usr/bin/env bash
# scripts/setup.sh

set -euo pipefail

echo "Setting up EIP/ERC development environment..."

git submodule update --init --recursive

echo "✅ Shared infra ready at infra/shared"
echo "Current shared commit: $(git -C infra/shared rev-parse --short HEAD)"

# Optional: create symlinks for easier editing during migration
# ln -sf infra/shared/_layouts ./_layouts
```

Makefile sketch:

```makefile
.PHONY: setup lint build update-shared

setup:
	./scripts/setup.sh

lint:
	eipw --config infra/shared/config/eipw.toml

build:
	bundle exec jekyll build

update-shared:
	git submodule update --remote --merge infra/shared
```

## 5.5 Migration helper script

```bash
#!/usr/bin/env bash
# scripts/migrate-file.sh
# Usage: ./migrate-file.sh path/to/file.md

FILE=$1
if [ -z "$FILE" ]; then
  echo "Usage: $0 <file-path>"
  exit 1
fi

cp "$FILE" ../eip-infra/"$FILE"
echo "Moved $FILE to shared repo. Now remove from both EIPs/ERCs and update paths."
```

## 6. Runtime test draft

Add at least one runtime-style test that exercises the shared paths rather than only checking file existence.

Example consumer-repo job:

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

If there is a faster smoke test, it should verify that the site can render with the shared layouts and includes loaded from `infra/shared`.

## 7. Suggested rollout order

1. Create the shared-infra repository.
2. Move one low-risk shared file first, such as an include or layout.
3. Add the shared repo as a submodule in both consumer repos.
4. Update checkouts to be recursive.
5. Point tools like `eipw` and Jekyll at the submodule paths.
6. Remove merge hacks and re-enable disabled lint rules.
7. Iterate file-by-file until duplication is gone.
