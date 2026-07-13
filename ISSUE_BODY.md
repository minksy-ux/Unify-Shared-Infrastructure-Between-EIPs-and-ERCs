# Reduce duplication and drift between ethereum/EIPs and ethereum/ERCs

## Problem

Since the EIPs/ERCs split, both repos have maintained roughly 50 shared infrastructure files separately. CI, Jekyll layouts/includes, templates, and configs have drifted, creating maintenance overhead and fragile workarounds.

Evidence:

- CI already papers over the split with repo-merging steps.
- Linting is partly disabled to tolerate cross-repo limitations.
- Templates and docs have drifted unintentionally.
- Shared files such as `_config.yml` and workflows stopped receiving coordinated updates.

## Goal

Keep proposal content logically separated if desired, while making shared infrastructure a single source of truth.

## Recommendation

Create a shared infrastructure repository and consume it via Git submodule from `EIPs` and `ERCs`.

Why this fits best:

- keeps the current separate-repo UX
- gives one source of truth for shared files
- makes local validation match CI
- removes hidden merge hacks
- aligns with feedback already leaning toward the shared-repo + submodule model

## Canonical One-Way Model

- Shared repo is canonical owner of infra (`shared -> consumers` only).
- Consumers never copy shared files back into local duplicates.
- CI merge-in steps are removed so local and CI execution paths are identical.

## Pinned Version Enforcement

- Consumers pin to labeled shared tags.
- Consumer CI validates only against the pinned shared version before publish.
- Upgrades happen through explicit PRs that move the pinned tag.

## Top Technical Actions

- Add submodule and recursive checkout in both consumers.
- Remove merge-in-CI hacks.
- Re-enable full linting in shared infra and keep consumer differences in tiny override files.
- Move common workflow logic into reusable workflows/actions in shared infra.

Reusable workflow pattern:

```yaml
jobs:
	lint:
		uses: ethereum/eip-infra/.github/workflows/lint.yml@v1
```

Concrete templates for the pilot are included in:

- [examples/workflows/shared-reusable-lint.yml](examples/workflows/shared-reusable-lint.yml)
- [examples/workflows/consumer-ci-using-shared.yml](examples/workflows/consumer-ci-using-shared.yml)
- [examples/workflows/consumer-update-shared-tag-bot.yml](examples/workflows/consumer-update-shared-tag-bot.yml)

## High-Level Migration Plan

1. Create the shared infra repo and move the common files into it.
2. Add it as a submodule in both consumer repos.
3. Switch checkouts to recursive submodule checkout.
4. Point `eipw`, Jekyll, and related tooling at the shared paths.
5. Remove merge hacks and re-enable disabled lint rules.
6. Move file-by-file until only repo-specific differences remain.

## What Moves / What Stays

- Moves: `.github/workflows/`, `.github/actions/`, `_includes/`, `_layouts/`, `config/`, templates, and shared contributor guidance.
- Stays: proposal markdown files, minimal repo-specific wiring, and intentional overrides.

## Open Questions

- Is this direction desired?
- Should the shared layer be a submodule, generated mirror, or monorepo?
- Should RIPs also consume the shared layer?
- Which files should intentionally diverge?
- Who owns the shared infra repo?

## Governance

- Shared infra should have named maintainers and a clear approval path for changes.
- Consumer repos should only pin to released or approved shared revisions.
- Major shared changes should require review from both EIP and ERC maintainers.

## Ownership and Approval

- Define one canonical owner group for the shared infra repo.
- Require approval from at least one EIP maintainer and one ERC maintainer for shared changes.
- Let consumer-repo maintainers approve version bumps, but not silently change shared content.
- Document who can cut shared releases and who can revert them.

## Rollback / Recovery

- If a shared release breaks consumers, pin both repos back to the previous known-good tag.
- If a submodule update fails CI, revert the submodule bump PR rather than patching consumer copies.
- Keep the last known-good shared release documented in the changelog.

## Rollback Playbook

1. Identify the last known-good shared tag.
2. Pin both consumer repos back to that tag.
3. Revert the bad shared release or submodule bump PR.
4. Cut a fixed shared release once CI passes.
5. Announce the rollback and the replacement release in the discussion thread.

## Decision Matrix

| Option | Contributor UX | CI Simplicity | Migration Risk | Notes |
| --- | --- | --- | --- | --- |
| Submodule | Medium | High | Medium | Best fit for preserving separate repos |
| Generated mirror | Medium | Medium | Medium-High | Good fallback if submodules prove awkward |
| Monorepo | Low-Medium | High | High | Cleanest structurally, most disruptive culturally |

## Validation Matrix

- `make setup` succeeds locally.
- `make lint` matches CI.
- `bundle exec jekyll build` succeeds with shared assets.
- Shared repo validation passes on every tag and pull request.
- Consumer CI fails fast if `infra/shared` is missing.

## Consumer Impact

- Maintainers need to update `.gitmodules`, `Makefile`, and setup docs.
- Contributors should edit shared files only in the shared repo.
- Repo-specific overrides should be explicit and small.

## Communication Plan

- Announce shared release bumps in the issue or PR thread.
- Document the pinned shared revision in consumer release notes.
- Call out breaking changes before the shared release is tagged.

## Monitoring

- Track duplicated infra file count over time.
- Track count of lint rules disabled due to split.
- Track frequency of cross-repo hotfixes caused by infra drift.
- Track shared release adoption lag in consumers.

## Why This Matters Long-Term

- Contributors can validate locally exactly as CI does.
- Tooling and template changes land once instead of twice.
- No more “disabled because of the split” rules.
- Future proposal repos become much easier to onboard.

Feedback from the recent EIPIP meeting and comments from `poojaranjan`, `jochem-brouwer`, `SamWilsn`, and `ryanio` has leaned toward the shared-repo + submodule model.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Submodule confusion for new contributors | Medium | Medium | Clear `CONTRIBUTING.md` + `Makefile` + setup script + CI that fails fast if the submodule is missing |
| Submodule version skew between repos | Low | High | Daily auto-update PR bot + approval required for major changes |
| Broken CI during migration | Medium | High | Incremental file-by-file migration + feature flags or symlinks during transition |
| Resistance to submodules | Low-Medium | Medium | Strong docs + fallback generated-mirror path if needed |
| GitHub rate limits on submodule fetches | Low | Low | Shallow submodules + CI cache |

## Phased Migration Plan

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

## Definition of Done

- Zero near-identical duplicated files remain.
- All lint rules disabled solely because of the split are re-enabled.
- `make lint` locally matches CI behavior.
- No more scheduled `merge-repos` steps.
- A new contributor can run `make setup && make lint` successfully.
- Shared infra has its own release tags and changelog.
- At least one auto-update PR has landed successfully.

## Suggested Repository Name Options

- `ethereum/eip-infra` (most clear)
- `ethereum/proposal-infra`
- `ethereum/eips-infra`
- `ethereum/shared-proposal-tooling`

## Contributor Onboarding Snippet

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

## Bonus: One-Command Bootstrap Script

See [bootstrap.sh](bootstrap.sh) for a ready-to-run bootstrap helper.

## Editor-Approved Pilot (3-4 PRs)

1. Create shared-infra repo and add `COPYING` and `MAINTAINERS`.
2. Move one safe file (for example `_includes/header.html`), add submodule in both repos, and wire Jekyll path.
3. Replace one CI merge step with submodule checkout and re-enable one previously disabled lint rule.
4. Add shared release/tag workflow and a bot PR that updates consumer pinned tag.
