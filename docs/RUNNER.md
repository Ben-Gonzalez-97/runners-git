# Self-hosted runner runbook

This runner exists because the heavy `pNiquitao` E2E suite runs for hours, needs a stable
host with Chromium dependencies, and talks to the lab. GitHub-hosted minutes are also
exhausted on the private repository.

## 1. Host requirements

Recommended host: Hetzner CAX21 (ARM64, 4 vCPU, 8 GB RAM, 80 GB disk) with Ubuntu 24.04,
matching the migration plan tracked in `pNiquitao` issue #525.

Requirements:

- Linux `x64` or `arm64`.
- Outbound HTTPS to `github.com` and to the lab origin.
- Base packages: `curl`, `tar`, `git`, `rsync`, `python3`, `jq`.
- Passwordless `sudo` for `playwright install --with-deps`, or the Playwright system
  dependencies preinstalled once as root.
- Disk headroom: Playwright traces, videos and nightly artifacts accumulate in
  `actions-runner/_work`.

```bash
sudo apt-get update
sudo apt-get install -y curl tar git rsync python3 jq
```

Node and pnpm are installed per run by the workflow (`actions/setup-node` and
`pnpm/action-setup`); a system Node is optional.

## 2. Registration token

UI: **Settings -> Actions -> Runners -> New self-hosted runner**, then copy the token.

CLI:

```bash
gh api -X POST repos/Ben-Gonzalez-97/runners-git/actions/runners/registration-token --jq .token
```

The token expires after about one hour. Do not commit it or paste it into issues.

## 3. Install

```bash
git clone https://github.com/Ben-Gonzalez-97/runners-git.git
cd runners-git

RUNNER_TOKEN="<token>" \
RUNNER_NAME="lab-01" \
RUNNER_LABELS="lab" \
INSTALL_DEPS=1 \
./scripts/install-runner.sh
```

The script downloads the latest runner release for the host architecture, configures it
with the `lab` label, and installs/starts the systemd service as the invoking user.

Manual fallback:

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
# Pick the latest release from https://github.com/actions/runner/releases
curl -fLO https://github.com/actions/runner/releases/download/vX.Y.Z/actions-runner-linux-arm64-X.Y.Z.tar.gz
tar xzf actions-runner-linux-arm64-X.Y.Z.tar.gz
./config.sh --url https://github.com/Ben-Gonzalez-97/runners-git \
  --token "<token>" --name lab-01 --labels lab --unattended --replace
sudo ./svc.sh install "$(id -un)"
sudo ./svc.sh start
```

## 4. Verify

1. **Settings -> Actions -> Runners** should list `lab-01` as `Idle` with labels
   `self-hosted`, `linux`, `ARM64`, `lab`.
2. Run **Actions -> Runner smoke -> Run workflow**.
   Expected: host details plus the lab health JSON (`{"status":"ok"}`).
3. Optionally run **E2E heavy** with `suite: smoke`, then `suite: nightly`.

## 5. Secrets

Configure these in the repository (never on the runner host, except an optional
`E2E_CREDENTIALS_FILE`):

| Secret | Required | Notes |
|--------|----------|-------|
| `PNIQUITAO_TOKEN` | yes | Fine-grained PAT, `Contents: read` on `pNiquitao` |
| `E2E_BASE_URL` | yes | Lab origin |
| `E2E_USER_GERENTE`, `E2E_PASSWORD_GERENTE` | yes | Manager credentials |
| `E2E_USER_OPERADOR`, `E2E_PASSWORD_OPERADOR` | no | Operator role |
| `E2E_OBS_LOGS_URL`, `E2E_OBS_USER`, `E2E_OBS_PASSWORD` | no | VictoriaLogs |
| `E2E_GLITCHTIP_URL`, `E2E_GLITCHTIP_EMAIL`, `E2E_GLITCHTIP_PASSWORD` | no | GlitchTip |
| `LAB_WAKE_URL`, `LAB_WAKE_TOKEN` | no* | Wake Lambda |

\* Required by `nightly.sh run` when the lab is asleep.

## 6. Operations

```bash
sudo ~/actions-runner/svc.sh status
sudo ~/actions-runner/svc.sh stop
sudo ~/actions-runner/svc.sh start
tail -f ~/actions-runner/_diag/Runner_*.log
```

- The runner auto-updates itself.
- Clean old work only while no job is running:
  `rm -rf ~/actions-runner/_work/_temp/*`.
- If a job fails with `sudo: a password is required`, grant passwordless sudo to the
  runner user for `playwright install --with-deps`, or preinstall the dependencies with
  `sudo pnpm exec playwright install-deps chromium` once.
- If the lab is asleep, `nightly.sh` calls `LAB_WAKE_URL`; without those secrets it exits
  `FAILED-INFRA`.

## 7. Security

- The repository is public. Keep the runner dedicated to it.
- Do not add `pull_request` or `pull_request_target` triggers to workflows that use this
  runner: fork code would execute on the host.
- Require approval for outside collaborators in **Settings -> Actions -> General**.
- `PNIQUITAO_TOKEN` must be read-only and scoped to `pNiquitao`.
- The checkout persists the token in the job workspace so `nightly.sh` can run
  `git fetch`; the checkout post-step removes it. Do not run untrusted code on this host.
