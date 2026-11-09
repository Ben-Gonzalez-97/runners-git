# runners-git

Self-hosted GitHub Actions workflows for heavy Playwright E2E runs against the private
[`pNiquitao`](https://github.com/Ben-Gonzalez-97/pNiquitao) repository and its lab
environment.

The repository is public on purpose: it hosts the workflow and its runbook without
exposing the private application code. The runner only executes trusted `pNiquitao`
code selected by a repository writer (the schedule always runs `main`); it never
executes code from forks.

## Architecture

```text
GitHub (public repo)                  Self-hosted runner (Linux, label `lab`)
+-------------------------+           +--------------------------------------------+
| runners-git             |           | 1. checkout pNiquitao (read-only PAT)      |
|  .github/workflows/     |   job     | 2. pnpm install + Playwright Chromium      |
|    e2e-heavy.yml  ------+---------->| 3. bash e2e/scripts/nightly.sh run         |
|    runner-smoke.yml     |           | 4. publish summary + upload artifacts      |
+-------------------------+           +----------------------+---------------------+
                                                             | HTTPS
                                                             v
                                                    Niquitao lab environment
```

## Workflows

| Workflow | Trigger | What it runs |
|----------|---------|--------------|
| `E2E heavy (pNiquitao lab)` | `schedule` (01:06 UTC = 21:06 VET) and `workflow_dispatch` | `e2e/scripts/nightly.sh run`: wake, deploy check, functional web -> mobile -> pwa, stress web -> mobile -> pwa, observability, summary and artifacts |
| `Runner smoke` | `workflow_dispatch` | Runner sanity check (`uname`, tools) and lab `/api/health` |

`E2E heavy` inputs:

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
| `LAB_WAKE_URL`, `LAB_WAKE_TOKEN` | no* | Lambda that wakes the lab |

\* Required by `nightly.sh run` when the lab is asleep.

## Runner setup

Full runbook: [`docs/RUNNER.md`](docs/RUNNER.md). Short version on a fresh Linux host:

```bash
# Create a dedicated non-root user; the installer refuses to run as root.
sudo adduser --disabled-password --gecos "" runner
echo "runner ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-actions-runner
sudo chmod 440 /etc/sudoers.d/90-actions-runner
sudo -iu runner

# As `runner` (generate the token first, see docs/RUNNER.md section 2):
git clone https://github.com/Ben-Gonzalez-97/runners-git.git
cd runners-git
RUNNER_TOKEN="<registration-token>" INSTALL_DEPS=1 ./scripts/install-runner.sh
```

The runner must carry the custom label `lab`. Both workflows select
`[self-hosted, linux, lab]`.

## Trigger a run

```bash
gh workflow run e2e-heavy.yml -f suite=nightly
gh workflow run e2e-heavy.yml -f suite=smoke
gh run watch
```

## Artifacts and public visibility

Workflow logs and step summaries in a public repository are public. The workflow
therefore:

- uploads only a sanitized nightly summary (lab and observability origins redacted);
- never uploads `test-results/`, Playwright traces, videos, or `nightly.log`, because a
  failed login trace can contain the typed lab password.

Raw artifacts stay on the runner under `actions-runner/_work/.../e2e/artifacts` for
on-host debugging. If you need them remotely, copy them to private storage; do not
publish them as public artifacts.

## Security

- There is no `pull_request` or `pull_request_target` trigger: fork code never runs on
  the runner.
- `PNIQUITAO_TOKEN` should be a fine-grained PAT limited to `pNiquitao` with
  **Contents: read** only.
- In **Settings -> Actions -> General -> Fork pull request workflows**, require approval
  for all outside collaborators.
- Keep the runner dedicated to this repository; do not register it at organization level.
- Never print secret values in workflow steps.
- Never upload Playwright traces or `test-results/` from this public repository: traces
  can contain values typed into login forms.

## Notes

- Scheduled workflows are disabled after 60 days without repository activity.
- The runner is a long-lived host: monitor disk usage, because Playwright traces, videos
  and E2E artifacts accumulate under `actions-runner/_work`.
- `nightly.sh` keeps its own run lock; the workflow also uses a `concurrency` group so a
  manual run cannot overlap or cancel an in-flight nightly.
