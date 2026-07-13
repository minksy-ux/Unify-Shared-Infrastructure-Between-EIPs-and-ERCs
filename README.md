# Unify Shared Infrastructure Between EIPs and ERCs

This proposal asks Ethereum editors to consolidate shared infrastructure for `ethereum/EIPs` and `ethereum/ERCs` into a single canonical source, while keeping proposal content in separate repos if that remains desirable.

## Why This Matters

The split repos now maintain roughly 50 shared infrastructure files twice. That has produced drift in CI, linting, templates, layouts, and contributor docs. The existing setup already behaves like one logical system, but it does so through hidden merge steps and scheduled repo stitching, which is harder to reason about and harder to reproduce locally.

## Decision Requested

Please give feedback on two points:

1. Whether shared infrastructure should be consolidated at all.
2. If yes, whether a shared repository consumed via submodule is acceptable.

## Recommendation

Use a dedicated shared-infra repository as the source of truth, consumed as a submodule by both repositories.

This keeps `EIPs` and `ERCs` separate at the GitHub level, but removes duplicated maintenance for the common layer. It also makes local validation match CI, because contributors can initialize the same submodule path that CI uses.

## What Moves To Shared Infra

- `.github/workflows/`
- `.github/actions/`
- `_includes/`
- `_layouts/`
- `config/`
- `templates/`
- shared lint rules and template logic

## What Stays In The Consumer Repos

- proposal markdown files
- repo-specific publishing or deployment differences
- intentional overrides that are truly repo-specific

## Concrete Implementation

The first useful code change is small and mechanical.

```bash
git submodule add <shared-infra-url> infra/shared
git submodule update --init --recursive
```

In GitHub Actions, use recursive checkout:

```yaml
- name: Checkout repository
	uses: actions/checkout@v4
	with:
		submodules: recursive
```

Then point tooling at the shared paths instead of duplicated local copies:

```yaml
- name: Run lint
	run: eipw --config infra/shared/config/eipw.toml
```

If Jekyll or other site logic depends on layouts and includes, read them from `infra/shared` rather than copying them into each repo.

## Migration Plan

1. Create the shared-infra repository.
2. Move one low-risk shared file first, such as an include or layout.
3. Add the shared repo as a submodule in both consumer repos.
4. Replace CI merge hacks with direct submodule usage.
5. Re-enable lint rules that were only disabled because of the split.
6. Move the remaining shared files gradually until only repo-specific differences remain.

## Operating Model

To make this sustainable, maintain the shared layer like a product:

- assign clear ownership for shared infra
- version shared changes and record them in changelogs
- require repo-specific divergence to be intentional and documented
- validate the shared repo itself before consumers update their pinned revision

## Smallest High-Value First PR

The best first PR should do four things:

1. Move a single shared file into the shared repo.
2. Update both repos to consume it through the submodule.
3. Remove one CI merge step.
4. Re-enable one lint rule that was disabled only because of the split.

That proves the model works before the full migration.

## Code Execution Draft

If you want a more implementation-ready version, this is the shape of the change set:

### Consumer repo setup

```bash
git submodule add <shared-infra-url> infra/shared
git submodule update --init --recursive
```

```yaml
- name: Checkout repository
	uses: actions/checkout@v4
	with:
		submodules: recursive
```

```yaml
- name: Validate shared infra
	run: test -f infra/shared/config/eipw.toml
```

### Lint and build wiring

```yaml
- name: Run lint
	run: eipw --config infra/shared/config/eipw.toml
```

```yaml
- name: Build site
	run: bundle exec jekyll build
```

The build should read layouts and includes from `infra/shared` so the consumer repo no longer needs duplicated copies.

### Sync script draft

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_dir="${1:-.}"
shared_path="infra/shared"

cd "$repo_dir"
git submodule update --init --recursive
git status --short "$shared_path"
```

### Shared repo validation draft

```yaml
name: Validate shared infra

on:
	push:
	pull_request:
	workflow_dispatch:

jobs:
	validate:
		runs-on: ubuntu-latest
		steps:
			- uses: actions/checkout@v4
			- run: test -f config/eipw.toml
			- run: test -d _includes
			- run: test -d _layouts
```

### Runtime test draft

Add at least one runtime-style test that exercises the shared paths instead of only checking file existence.

Example consumer repo job:

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

If the repository has a faster smoke test, it should verify that the site can render with the shared layouts and includes loaded from `infra/shared`.

### Suggested repo split

- shared repo: workflows, actions, layouts, includes, config, templates
- consumer repo: proposal markdown, repo-specific overrides, publishing differences

### Practical rollout order

1. Add the submodule.
2. Switch CI to recursive checkout.
3. Move one shared file.
4. Remove one merge hack.
5. Re-enable one lint rule.
6. Expand until the remaining files are intentionally repo-specific.
