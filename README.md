# Shared Infrastructure Proposal

This workspace now carries two concise artifacts:

- [ISSUE_BODY.md](ISSUE_BODY.md) for the copy-paste-ready GitHub issue text
- [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) for the code and rollout steps

If you want the longer reference material, see [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md).

## Auto Review Bot Failure Analysis

The failure is caused by a missing artifact, not by the review bot itself.

### Root cause

In the failing job, the first step tries to download an artifact named `pr-number`, but the logs show:

- Workflow name: `auto-review-trigger.yml`
- Workflow conclusion: `success`
- `(not found) Artifact: pr-number`
- `no artifacts found`

The artifact is only uploaded by the trigger workflow if `pr-number.txt` was created:

- `.github/workflows/auto-review-trigger.yml` lines 24-46 create `pr-number.txt` only for specific event/condition combinations.
- `.github/workflows/auto-review-trigger.yml` lines 54-59 upload the `pr-number` artifact only if that file exists.
- `.github/workflows/auto-review-bot.yml` lines 14-20 always try to download `pr-number` from the triggering workflow run.

So the trigger workflow can complete successfully without producing the artifact, while the bot workflow assumes the artifact always exists and fails.

### Why this happened

The likely trigger was an event that matched the workflow but did not match any of the `Write PR Number` conditions in `auto-review-trigger.yml`, for example:

- a bot-authored `pull_request_review`
- an `issue_comment` without `@eth-bot rerun`
- a `pull_request_target` from a sender excluded by the bot filters

In those cases:

- `pr-number.txt` is never written
- `Check File Existence` returns false
- `Save PR Number` is skipped
- downstream workflow still runs and fails downloading the artifact

### Best fix

Prevent the downstream workflow from running unless the trigger workflow actually produced the artifact, or make the downstream workflow tolerate the missing artifact and exit cleanly.

### Recommended code change

#### Option 1: Make the trigger workflow decide whether to launch the bot

The cleanest fix is to avoid `workflow_run` for this handoff and run the bot directly in the same workflow after the PR number is known. That removes the fragile artifact dependency entirely.

If you want to keep the current structure, use Option 2.

#### Option 2: Guard the bot workflow against missing artifacts

Update `.github/workflows/auto-review-bot.yml` so the artifact download does not hard-fail, and only continue if the file exists.

Suggested revision:

```yaml
on:
  workflow_run:
    workflows:
      - Auto Review Bot Trigger
    types:
      - completed

name: Auto Review Bot

jobs:
  auto-review-bot:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    name: Run
    steps:
      - name: Fetch PR Number
        id: fetch-pr-number
        continue-on-error: true
        uses: dawidd6/action-download-artifact@246dbf436b23d7c49e21a7ab8204ca9ecd1fe615
        with:
          name: pr-number
          workflow: auto-review-trigger.yml
          run_id: ${{ github.event.workflow_run.id }}

      - name: Check PR file existence
        id: check_pr_number
        run: |
          if [ -f pr-number.txt ]; then
            echo "exists=true" >> "$GITHUB_OUTPUT"
          else
            echo "exists=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Save PR Number
        if: steps.check_pr_number.outputs.exists == 'true'
        id: save-pr-number
        run: echo "pr=$(cat pr-number.txt)" >> "$GITHUB_OUTPUT"

      - name: Auto Review Bot
        if: steps.check_pr_number.outputs.exists == 'true'
        id: auto-review-bot
        uses: ethereum/eip-review-bot@dist
        continue-on-error: true
        with:
          token: ${{ secrets.TOKEN }}
          config: config/eip-editors.yml
          pr_number: ${{ steps.save-pr-number.outputs.pr }}
```

### Even better: fail less noisily

If a missing artifact is expected for some trigger paths, treat it as a no-op instead of a failure. The current behavior creates false negatives in Actions.

### Optional improvement in the trigger workflow

You can also tighten `.github/workflows/auto-review-trigger.yml` so the workflow only runs for events that are actually intended to trigger review bot behavior, reducing empty successful runs.

For example, if `issue_comment` is only useful with `@eth-bot rerun`, keep that condition, but recognize that the downstream workflow must not assume artifact existence.

### Relevant files

- Trigger workflow: https://github.com/ethereum/EIPs/blob/68898156500eea7389cf65d746b64c7dd27e4bc1/.github/workflows/auto-review-trigger.yml
- Bot workflow: https://github.com/ethereum/EIPs/blob/68898156500eea7389cf65d746b64c7dd27e4bc1/.github/workflows/auto-review-bot.yml

### Summary

The solution is to make `auto-review-bot.yml` conditional on the artifact actually being present, because `auto-review-trigger.yml` can succeed without creating `pr-number`. The most targeted fix is to make artifact download non-fatal and skip the remaining steps when `pr-number.txt` is absent.

## Implementation status in this repository

The repository currently implements the no-op behavior for missing PR-number artifacts:

- `.github/workflows/auto-review-bot.yml` uses `continue-on-error: true` for artifact download, checks for `pr-number.txt`, and skips bot execution when absent.
- `.github/workflows/auto-review-trigger.yml` uploads the `pr-number` artifact only when `pr-number.txt` exists, and logs a no-op message otherwise.
- `.github/workflows/auto-review-bot.yml` uses `actions/download-artifact@v4` (Node 24-compatible) instead of the deprecated Node 20-based downloader.
- `.github/workflows/auto-review-bot.yml` grants `actions: read` permission so the `workflow_run` job can download artifacts from the triggering run.

Result: trigger runs that do not produce a PR number complete successfully without causing false-negative bot failures.