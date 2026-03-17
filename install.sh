#!/bin/bash
set -euo pipefail
# install.sh — Bootstrap a server before the repo exists.
# Download this script and run it. It installs GitHub CLI, authenticates,
# clones the repo, then launches the setup wizard.
#
# All credentials are entered interactively (hidden input) or via
# environment variables. Nothing is hardcoded.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/engendra-labs/install/main/install.sh | bash
#   bash install.sh
#   bash install.sh --branch feat/my-branch

REPO_DIR="${HOME}/engendra"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BRANCH=""
COMMIT=""

# ── Argument parsing ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: bash install.sh [OPTIONS]

Prepare a server and install Engendra.

Options:
  --repo-dir PATH         Where to clone the repo (default: ~/engendra)
  --branch BRANCH         Git branch to clone/checkout (default: repo default branch)
  --commit HASH           Git commit hash to checkout after cloning
  -h, --help              Show this help message

Credentials can be set via environment variables:
  GITHUB_TOKEN            GitHub Personal Access Token (read access to engendra-labs/engendra)

All other credentials (API keys) are entered during the setup wizard.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-dir)      REPO_DIR="$2";           shift 2 ;;
        --branch)        BRANCH="$2";             shift 2 ;;
        --commit)        COMMIT="$2";            shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

echo ""
echo "  Engendra Installer"
echo "  ──────────────────"
echo ""

# ── Step 1: Install GitHub CLI ─────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    echo "[install] Installing GitHub CLI..."
    sudo apt-get update -qq >/dev/null 2>&1
    sudo apt-get install -y gh -qq >/dev/null 2>&1
else
    echo "[install] GitHub CLI already installed."
fi

# ── Step 2: Authenticate with GitHub ──────────────────────────────────────────
if ! gh auth status &>/dev/null; then
    if [[ -z "${GITHUB_TOKEN}" ]]; then
        echo ""
        echo "  A GitHub token with read access to engendra-labs/engendra is required."
        echo ""
        read -rsp "  GitHub Token: " GITHUB_TOKEN </dev/tty
        echo ""
        if [[ -z "${GITHUB_TOKEN}" ]]; then
            echo "  ERROR: GitHub token is required." >&2
            exit 1
        fi
    fi
    echo "[install] Authenticating with GitHub..."
    gh auth login --with-token <<< "${GITHUB_TOKEN}"
else
    echo "[install] GitHub already authenticated."
fi

# ── Step 3: Clone or update the engendra repo ────────────────────────────────
if [[ ! -d "${REPO_DIR}/.git" ]]; then
    echo "[install] Cloning engendra repo to ${REPO_DIR}..."
    if [[ -n "${BRANCH}" ]]; then
        gh repo clone engendra-labs/engendra "${REPO_DIR}" -- --branch "${BRANCH}"
    else
        gh repo clone engendra-labs/engendra "${REPO_DIR}"
    fi
else
    echo "[install] Repo already cloned — pulling latest changes..."
    if [[ -n "${BRANCH}" ]]; then
        git -C "${REPO_DIR}" checkout "${BRANCH}"
    fi
    git -C "${REPO_DIR}" pull
fi

if [[ -n "${COMMIT}" ]]; then
    echo "[install] Checking out commit ${COMMIT}..."
    git -C "${REPO_DIR}" checkout "${COMMIT}"
fi

# ── Step 4: Launch setup wizard ───────────────────────────────────────────────
echo ""
echo "[install] Repo ready. Launching setup wizard..."
echo ""
exec bash "${REPO_DIR}/manager/scripts/wizard.sh"
