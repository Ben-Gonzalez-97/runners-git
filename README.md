# runners-git

Runs the heavy Playwright E2E suite of the private
[`pNiquitao`](https://github.com/Ben-Gonzalez-97/pNiquitao) repository on **GitHub-hosted
runners** and reports the result against its lab environment.

This repository is public on purpose:

- public repositories get free standard GitHub-hosted runner minutes, which works around
  the exhausted Actions minutes on the private repository;
- the workflow and its documentation stay public without exposing the private code;
- the runner is ephemeral and never executes code from forks.

## Architecture

```text
GitHub (public repo)                 GitHub-hosted runner (ubuntu-latest, ephemeral)
+-------------------------+          +---------------------------------------------+
| runners-git             |          | 1. sparse checkout of pNiquitao/e2e (PAT)  |
|  .github/workflows/     |   job    | 2. pnpm install + Playwright Chromium       |
|    e2e-heavy.yml  ------+--------->| 3. bash e2e/scripts/nightly.sh run          |
+-------------------------+          | 4. sanitized summary + artifact             |
                                     +----------------------+----------------------+
                                                            | HTTPS
                                                            v
                                                   Niquitao lab environment
```

The checkout uses `sparse-checkout: e2e`: only the `e2e/` working tree is materialized.
Full git history is still fetched because `nightly.sh` needs `origin/main`, product-path
diffs and `git archive origin/main e2e`.

## Workflow

| Workflow | Trigger | What it runs |
|----------|---------|--------------|
| `E2E heavy (pNiquitao lab)` | `schedule` (01:06 UTC = 21:06 VET) and `workflow_dispatch` | `e2e/scripts/nightly.sh run`: deploy check, functional web -> mobile -> pwa, stress web -> mobile -> pwa, observability, summary and artifacts |

Inputs:

| Input | Default | Meaning |
|-------|---------|---------|
| `suite` | `nightly` | `nightly`, `functional`, `stress`, `all-surfaces` or `smoke` |
| `ref` | `main` | `pNiquitao` ref to test; `nightly` always tests `main` and rejects other refs |
| `force` | `false` | `nightly` only: skip the product-merge gate |

> `nightly.sh run` also waits for the lab deployment to match `main` (30 min by default)
> and exits `2` (`FAILED-INFRA`) otherwise. Deploy the lab first, or run
> `suite: functional|stress|smoke` to skip that precondition.

## Required secrets

Create these in **Settings -> Secrets and variables -> Actions**:

| Secret | Required | Purpose |
|--------|----------|---------|
| `PNIQUITAO_TOKEN` | yes | Fine-grained PAT with **Contents: read** on `Ben-Gonzalez-97/pNiquitao` |
| `E2E_BASE_URL` | yes | Lab origin (for example `https://lab.example`) |
| `E2E_USER_GERENTE` / `E2E_PASSWORD_GERENTE` | yes | Lab manager credentials |
| `E2E_USER_OPERADOR` / `E2E_PASSWORD_OPERADOR` | no | Operator role |
| `E2E_OBS_LOGS_URL`, `E2E_OBS_USER`, `E2E_OBS_PASSWORD` | no | VictoriaLogs observability |
| `E2E_GLITCHTIP_URL`, `E2E_GLITCHTIP_EMAIL`, `E2E_GLITCHTIP_PASSWORD` | no | GlitchTip observability |
| `E2E_CREDENTIALS_FILE` | no | Role-matrix credentials file path on the runner |

The lab is expected to be always up; no wake Lambda is configured. If it is down,
`nightly.sh` fails with `FAILED-INFRA` instead of waking it.

## Trigger a run

```bash
gh workflow run e2e-heavy.yml -f suite=nightly
gh workflow run e2e-heavy.yml -f suite=smoke
gh run watch
```

## Known limits

- **6-hour job cap.** GitHub-hosted jobs are hard-capped at 6 hours. `nightly.sh` runs
  functional (up to 3 surfaces) plus stress (up to 3 surfaces), so the worst case can
  exceed the cap. If the nightly is cancelled at 6 hours, run `suite: functional` and
  `suite: stress` as two separate manual runs (or split the schedule).
- **Lab reachability.** GitHub-hosted runners use dynamic public IPs. If the lab has an
  IP allowlist, the run will fail; `suite: smoke` is the fastest way to check.
- **Lab deploy precondition.** `nightly` requires the lab deployment to match `main`;
  otherwise it waits 30 minutes and exits `FAILED-INFRA`.
- **Scheduled workflows** are disabled after 60 days without repository activity.
- **Concurrency.** The `e2e-lab` group prevents overlapping runs from this repository.

## Artifacts and public visibility

Workflow logs and step summaries in a public repository are public. The workflow
therefore:

- uploads only a sanitized nightly summary (lab and observability origins redacted);
- never uploads `test-results/`, Playwright traces, videos, or `nightly.log`, because a
  failed login trace can contain the typed lab password.

## Security

- There is no `pull_request` or `pull_request_target` trigger: fork code never runs with
  secrets.
- `PNIQUITAO_TOKEN` should be a fine-grained PAT limited to `pNiquitao` with
  **Contents: read** only.
- In **Settings -> Actions -> General -> Fork pull request workflows**, require approval
  for all outside collaborators.
- Never print secret values in workflow steps.
- Never upload Playwright traces or `test-results/` from this public repository: traces
  can contain values typed into login forms.
