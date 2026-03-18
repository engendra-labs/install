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
#   curl -fsSL https://raw.githubusercontent.com/engendra-labs/install/main/install.sh | bash -s -- --verbose
#   bash install.sh --branch feat/my-branch

REPO_DIR="${HOME}/engendra"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BRANCH=""
COMMIT=""
VERBOSE="${ENGENDRA_VERBOSE:-0}"

# ── Colors ────────────────────────────────────────────────────────────────────
BLUE='\033[38;5;75m'
GREEN='\033[38;5;114m'
DIM='\033[2m'
BOLD='\033[1m'
R='\033[0m'

step()  { echo -e "  ${BLUE}▸${R} $*"; }
ok()    { echo -e "  ${GREEN}✓${R} $*"; }
dim()   { echo -e "  ${DIM}$*${R}"; }
verbose_enabled() { [[ "${VERBOSE}" == "1" ]]; }

prepare_cli_install_helper() {
    local helper_path="${REPO_DIR}/manager/scripts/install_cli.sh"
    local wizard_path="${REPO_DIR}/manager/scripts/wizard.sh"
    local server_path="${REPO_DIR}/setup/server.py"

    if [[ ! -d "${REPO_DIR}/cli" || ! -f "${wizard_path}" || ! -f "${server_path}" ]]; then
        return 0
    fi

    step "Preparing CLI installer..."

    mkdir -p "$(dirname "${helper_path}")"
    cat > "${helper_path}" <<'EOF'
#!/bin/bash
set -euo pipefail

CLI_DIR="${1:-}"
if [[ -z "${CLI_DIR}" || ! -d "${CLI_DIR}" ]]; then
    echo "Engendra CLI source directory not found: ${CLI_DIR:-<missing>}" >&2
    exit 1
fi

PYTHON_BIN=""
for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "${candidate}" >/dev/null 2>&1 && "${candidate}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v "${candidate}")"
        break
    fi
done

if [[ -z "${PYTHON_BIN}" ]]; then
    echo "Python 3.10 or newer is required to install the Engendra CLI." >&2
    exit 1
fi

INSTALL_ROOT="${HOME}/.local/share/engendra-cli"
VENV_DIR="${INSTALL_ROOT}/venv"
BIN_DIR="${HOME}/.local/bin"

mkdir -p "${INSTALL_ROOT}" "${BIN_DIR}"

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    rm -rf "${VENV_DIR}"
    if ! "${PYTHON_BIN}" -m venv "${VENV_DIR}" >/dev/null 2>&1; then
        PY_VER="$("${PYTHON_BIN}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
        if command -v sudo >/dev/null 2>&1; then
            sudo apt-get update -qq >/dev/null 2>&1 || true
            sudo apt-get install -y "python${PY_VER}-venv" -qq >/dev/null 2>&1 || sudo apt-get install -y python3-venv -qq >/dev/null 2>&1
        fi
        "${PYTHON_BIN}" -m venv "${VENV_DIR}"
    fi
fi

"${VENV_DIR}/bin/python" -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
"${VENV_DIR}/bin/python" -m pip install --quiet --editable "${CLI_DIR}"
ln -sf "${VENV_DIR}/bin/engendra" "${BIN_DIR}/engendra"

if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
    echo "Engendra CLI installed to ${BIN_DIR}/engendra. Add ${BIN_DIR} to PATH if the command is not found." >&2
fi
EOF
    chmod +x "${helper_path}"

    python3 - "${wizard_path}" "${server_path}" <<'PY'
from pathlib import Path
import sys

wizard_path = Path(sys.argv[1])
server_path = Path(sys.argv[2])

wizard_old = '        pip install -e "${REPO_DIR}/cli" --quiet 2>/dev/null || pip3 install -e "${REPO_DIR}/cli" --quiet 2>/dev/null'
wizard_new = '        bash "${REPO_DIR}/manager/scripts/install_cli.sh" "${REPO_DIR}/cli"'
server_old = '        parts.append(f"pip install -e {cli_dir} --quiet 2>/dev/null || pip3 install -e {cli_dir} --quiet 2>/dev/null")'
server_new = '        parts.append(f"bash \\"{REPO_DIR / \'manager\' / \'scripts\' / \'install_cli.sh\'}\\" \\"{cli_dir}\\"")'

wizard_text = wizard_path.read_text()
if wizard_new not in wizard_text and wizard_old in wizard_text:
    wizard_path.write_text(wizard_text.replace(wizard_old, wizard_new))

server_text = server_path.read_text()
if server_new not in server_text and server_old in server_text:
    server_path.write_text(server_text.replace(server_old, server_new))
PY

    ok "CLI installer ready"
}

# ── Argument parsing ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: bash install.sh [OPTIONS]

Prepare a server and install Engendra.

Options:
  --repo-dir PATH         Where to clone the repo (default: ~/engendra)
  --branch BRANCH         Git branch to clone/checkout (default: repo default branch)
  --commit HASH           Git commit hash to checkout after cloning
  -v, --verbose           Print installer and setup command output
  -h, --help              Show this help message

Credentials can be set via environment variables:
  GITHUB_TOKEN            GitHub Personal Access Token (read access to engendra-labs/engendra)
  ENGENDRA_VERBOSE=1      Same as --verbose

All other credentials (API keys) are entered during the setup wizard.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-dir)      REPO_DIR="$2";           shift 2 ;;
        --branch)        BRANCH="$2";             shift 2 ;;
        --commit)        COMMIT="$2";            shift 2 ;;
        -v|--verbose)    VERBOSE=1;               shift ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

export ENGENDRA_VERBOSE="${VERBOSE}"

echo ""
echo -e "  ${BOLD}${BLUE}Engendra${R} ${DIM}Installer${R}"
echo -e "  ${DIM}──────────────────${R}"
echo ""

# ── Step 1: Install GitHub CLI ─────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    step "Installing GitHub CLI..."
    if verbose_enabled; then
        sudo apt-get update
        sudo apt-get install -y gh
    else
        sudo apt-get update -qq >/dev/null 2>&1
        sudo apt-get install -y gh -qq >/dev/null 2>&1
    fi
    ok "GitHub CLI installed"
else
    ok "GitHub CLI ready"
fi

# ── Step 2: Authenticate with GitHub ──────────────────────────────────────────
if ! gh auth status &>/dev/null; then
    if [[ -z "${GITHUB_TOKEN}" ]]; then
        echo ""
        dim "A GitHub token with read access to engendra-labs/engendra is required."
        echo ""
        read -rsp "  GitHub Token: " GITHUB_TOKEN </dev/tty
        echo ""
        if [[ -z "${GITHUB_TOKEN}" ]]; then
            echo -e "  ${BOLD}\033[31mError:${R} GitHub token is required." >&2
            exit 1
        fi
    fi
    step "Authenticating with GitHub..."
    gh auth login --with-token <<< "${GITHUB_TOKEN}"
    ok "Authenticated"
else
    ok "GitHub authenticated"
fi

# ── Step 3: Clone or update the engendra repo ────────────────────────────────
if [[ ! -d "${REPO_DIR}/.git" ]]; then
    step "Cloning repository..."
    if [[ -n "${BRANCH}" ]]; then
        gh repo clone engendra-labs/engendra "${REPO_DIR}" -- --branch "${BRANCH}"
    else
        gh repo clone engendra-labs/engendra "${REPO_DIR}"
    fi
    ok "Repository cloned to ${REPO_DIR}"
else
    step "Pulling latest changes..."
    if [[ -n "${BRANCH}" ]]; then
        git -C "${REPO_DIR}" checkout "${BRANCH}"
    fi
    git -C "${REPO_DIR}" pull
    ok "Repository updated"
fi

if [[ -n "${COMMIT}" ]]; then
    step "Checking out commit ${COMMIT}..."
    git -C "${REPO_DIR}" checkout "${COMMIT}"
fi

prepare_cli_install_helper

# ── Step 4: Launch setup wizard ───────────────────────────────────────────────
echo ""
ok "Ready. Launching setup..."
echo ""
wizard_args=()
if verbose_enabled; then
    wizard_args+=(--verbose)
fi
exec env ENGENDRA_VERBOSE="${VERBOSE}" bash "${REPO_DIR}/manager/scripts/wizard.sh" "${wizard_args[@]}"
