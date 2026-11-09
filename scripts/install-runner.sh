#!/usr/bin/env bash
# Install a GitHub Actions self-hosted runner for Ben-Gonzalez-97/runners-git on Linux.
#
# Usage (as a dedicated non-root user):
#   RUNNER_TOKEN=... ./scripts/install-runner.sh
#
# Environment:
#   RUNNER_TOKEN    required  Registration token (expires in 1 hour)
#   RUNNER_URL      optional  Default: https://github.com/Ben-Gonzalez-97/runners-git
#   RUNNER_NAME     optional  Default: <hostname>-lab
#   RUNNER_LABELS   optional  Default: lab
#   RUNNER_DIR      optional  Default: $HOME/actions-runner
#   RUNNER_VERSION  optional  Default: latest runner release
#   INSTALL_DEPS    optional  Set to 1 to apt-get the base packages (Debian/Ubuntu)
#
# Generate a registration token with:
#   gh api -X POST repos/Ben-Gonzalez-97/runners-git/actions/runners/registration-token --jq .token
set -euo pipefail
umask 077

if [[ "$(id -u)" -eq 0 ]]; then
  cat >&2 <<'EOF'
Do not run this installer as root: the runner would execute job code and secrets as root.
Create a dedicated user and run it there:

  sudo adduser --disabled-password --gecos "" runner
  echo "runner ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-actions-runner
  sudo chmod 440 /etc/sudoers.d/90-actions-runner
  sudo -iu runner
  # then clone this repo and re-run the installer as `runner`
EOF
  exit 1
fi

RUNNER_URL="${RUNNER_URL:-https://github.com/Ben-Gonzalez-97/runners-git}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-lab}"
RUNNER_LABELS="${RUNNER_LABELS:-lab}"
RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner}"

if [[ -z "${RUNNER_TOKEN:-}" ]]; then
  cat >&2 <<'EOF'
RUNNER_TOKEN is required. Generate one with:
  gh api -X POST repos/Ben-Gonzalez-97/runners-git/actions/runners/registration-token --jq .token
Registration tokens expire after about one hour.
EOF
  exit 1
fi

case "$(uname -s)" in
  Linux) ;;
  *) echo "This installer only supports Linux. Use actions/runner binaries for other hosts." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64 | amd64) ARCH="x64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [[ "${INSTALL_DEPS:-0}" == "1" ]]; then
  sudo apt-get update
  sudo apt-get install -y curl tar git rsync python3 jq
fi

for cmd in curl tar git rsync python3 jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing required command: $cmd (re-run with INSTALL_DEPS=1 on Debian/Ubuntu)" >&2
    exit 1
  }
done

if [[ -z "${RUNNER_VERSION:-}" ]]; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    RUNNER_VERSION="$(gh api repos/actions/runner/releases/latest --jq '.tag_name' 2>/dev/null | sed 's/^v//')"
  fi
  if [[ -z "${RUNNER_VERSION:-}" ]]; then
    RUNNER_VERSION="$(curl -fsSL --retry 3 --retry-delay 2 https://api.github.com/repos/actions/runner/releases/latest \
      | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
  fi
fi

if [[ -z "$RUNNER_VERSION" ]]; then
  echo "Could not resolve the latest runner version; set RUNNER_VERSION explicitly." >&2
  exit 1
fi

echo "Installing actions runner v${RUNNER_VERSION} (${ARCH}) in ${RUNNER_DIR}"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

tarball="actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"
if [[ ! -f "$tarball" ]]; then
  curl -fL --retry 3 --retry-delay 2 -o "$tarball" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${tarball}"
fi
tar xzf "$tarball"

./config.sh \
  --url "$RUNNER_URL" \
  --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --unattended \
  --replace

# Re-running the installer must not fail on an existing systemd unit.
if compgen -G "/etc/systemd/system/actions.runner.*.service" >/dev/null; then
  echo "Existing Actions runner service detected; reinstalling the unit"
  sudo ./svc.sh uninstall || true
fi
sudo ./svc.sh install "$(id -un)"
sudo ./svc.sh start

echo
echo "Runner '${RUNNER_NAME}' installed with labels: ${RUNNER_LABELS}"
echo "It is registered in: ${RUNNER_URL}/settings/actions/runners"
echo "Check status with: sudo ${RUNNER_DIR}/svc.sh status"
echo "Logs: ${RUNNER_DIR}/_diag/"
