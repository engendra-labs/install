#!/bin/bash
set -euo pipefail
# install.sh — Bootstrap a server before the repo exists.
# Download this script and run it. It installs GitHub CLI, authenticates,
# clones the repo(s), then launches the setup wizard(s).
#
# All credentials are entered interactively (hidden input) or via
# environment variables. Nothing is hardcoded.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/engendra-labs/install/main/install.sh | bash
#   bash install.sh
#   bash install.sh --product assistant
#   bash install.sh --branch feat/my-branch

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
BRANCH=""
COMMIT=""
PRODUCT="all"

# ── Product definitions ──────────────────────────────────────────────────────
# Format: REPO|CLONE_DIR|POST_CLONE_SCRIPT
declare -A PRODUCTS
PRODUCTS[engendra]="engendra-labs/engendra|engendra|manager/scripts/wizard.sh"
PRODUCTS[assistant]="engendra-labs/engendra-assistant|engendra-assistant|scripts/setup.sh"

# Install order when installing all products
PRODUCT_ORDER=(engendra assistant)

# ── Colors ────────────────────────────────────────────────────────────────────
BLUE='\033[38;5;75m'
GREEN='\033[38;5;114m'
DIM='\033[2m'
BOLD='\033[1m'
R='\033[0m'

step()  { echo -e "  ${BLUE}▸${R} $*"; }
ok()    { echo -e "  ${GREEN}✓${R} $*"; }
dim()   { echo -e "  ${DIM}$*${R}"; }

# ── Argument parsing ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: bash install.sh [OPTIONS]

Prepare a server and install Engendra products.

Options:
  --product PRODUCT       Product to install: engendra, assistant, or all (default: all)
  --branch BRANCH         Git branch to clone/checkout (default: repo default branch)
  --commit HASH           Git commit hash to checkout after cloning
  -h, --help              Show this help message

Products:
  engendra                Main Engendra system (manager, workers, dashboard)
  assistant               Engendra Assistant (AI assistant provisioning, admin UI)
  all                     Both products (default)

Credentials can be set via environment variables:
  GITHUB_TOKEN            GitHub Personal Access Token (read access to engendra-labs repos)

All other credentials (API keys) are entered during the setup wizard.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --product)       PRODUCT="$2";            shift 2 ;;
        --branch)        BRANCH="$2";             shift 2 ;;
        --commit)        COMMIT="$2";             shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

# Validate product
if [[ "$PRODUCT" != "all" ]] && [[ -z "${PRODUCTS[$PRODUCT]+x}" ]]; then
    echo "Unknown product: $PRODUCT" >&2
    echo "Valid products: engendra, assistant, all" >&2
    exit 1
fi

echo ""
echo -e "  ${BOLD}${BLUE}Engendra${R} ${DIM}Installer${R}"
echo -e "  ${DIM}──────────────────${R}"
echo ""

# ── Step 1: Install GitHub CLI ─────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    step "Installing GitHub CLI..."
    sudo apt-get update -qq >/dev/null 2>&1
    sudo apt-get install -y gh -qq >/dev/null 2>&1
    ok "GitHub CLI installed"
else
    ok "GitHub CLI ready"
fi

# ── Step 2: Authenticate with GitHub ──────────────────────────────────────────
if ! gh auth status &>/dev/null; then
    if [[ -z "${GITHUB_TOKEN}" ]]; then
        echo ""
        dim "A GitHub token with read access to engendra-labs repos is required."
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

# ── Step 3: Install product(s) ───────────────────────────────────────────────
install_product() {
    local name="$1"
    local IFS='|'
    read -r repo clone_dir post_script <<< "${PRODUCTS[$name]}"
    local full_clone_dir="${HOME}/${clone_dir}"

    echo ""
    step "Installing ${name}..."

    if [[ ! -d "${full_clone_dir}/.git" ]]; then
        step "Cloning ${repo}..."
        if [[ -n "${BRANCH}" ]]; then
            gh repo clone "${repo}" "${full_clone_dir}" -- --branch "${BRANCH}"
        else
            gh repo clone "${repo}" "${full_clone_dir}"
        fi
        ok "Repository cloned to ${full_clone_dir}"
    else
        step "Pulling latest changes..."
        if [[ -n "${BRANCH}" ]]; then
            git -C "${full_clone_dir}" checkout "${BRANCH}"
        fi
        git -C "${full_clone_dir}" pull
        ok "Repository updated"
    fi

    if [[ -n "${COMMIT}" ]]; then
        step "Checking out commit ${COMMIT}..."
        git -C "${full_clone_dir}" checkout "${COMMIT}"
    fi

    # Run the post-clone setup script
    echo ""
    ok "Ready. Launching ${name} setup..."
    echo ""
    bash "${full_clone_dir}/${post_script}"
}

if [[ "$PRODUCT" = "all" ]]; then
    for p in "${PRODUCT_ORDER[@]}"; do
        install_product "$p"
    done
else
    install_product "$PRODUCT"
fi

echo ""
ok "Installation complete."
