#!/usr/bin/env bash
#
# install_deps.sh — get a fresh checkout of this repo to a working `make`.
#
# What it does, depending on platform:
#   macOS   -> installs missing packages via Homebrew (gsl, libomp), checks
#              for Xcode Command Line Tools (a C++ compiler).
#   Linux   -> only *checks* for a compiler/make/GSL and reports what's
#              missing; on HPC clusters these are normally provided system-
#              wide or via `module load`, and a login node usually has no
#              sudo, so this never attempts a package-manager install
#              without you explicitly confirming it first.
#   Both    -> clones twopunctures-standalone (this repo's solver
#              dependency) next to this repo if it isn't already checked
#              out somewhere, then builds ./twopunctures via `make`.
#
# Safe to re-run any time; every step is a no-op if already satisfied.
#
# Usage: ./install_deps.sh [--tp-dir PATH] [--no-clone] [--no-build]

set -euo pipefail

TP_REPO_URL="https://bitbucket.org/relastro/twopunctures-standalone.git"
TP_DIR="${TP_STANDALONE_DIR:-$(cd "$(dirname "$0")" && pwd)/../twopunctures-standalone}"
DO_CLONE=1
DO_BUILD=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tp-dir) TP_DIR=$2; shift 2 ;;
        --no-clone) DO_CLONE=0; shift ;;
        --no-build) DO_BUILD=0; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }
info() { echo "-- $*"; }
warn() { echo "WARNING: $*" >&2; }

UNAME_S=$(uname -s)

# ---------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------
if [[ "$UNAME_S" == Darwin ]]; then
    if ! have brew; then
        echo "ERROR: Homebrew is required on macOS to install dependencies automatically." >&2
        echo "       Install it from https://brew.sh, then re-run this script." >&2
        exit 1
    fi

    if ! xcode-select -p >/dev/null 2>&1; then
        info "Xcode Command Line Tools not found; requesting install (a GUI prompt will appear)..."
        xcode-select --install || true
        echo "ERROR: install the Command Line Tools from the prompt, then re-run this script." >&2
        exit 1
    fi

    for pkg in gsl libomp; do
        if brew list --versions "$pkg" >/dev/null 2>&1; then
            info "$pkg already installed (brew)"
        else
            info "Installing $pkg via brew..."
            brew install "$pkg"
        fi
    done
    have make || { echo "ERROR: 'make' not found even with Xcode CLT installed; something is unusual about this machine." >&2; exit 1; }

elif [[ "$UNAME_S" == Linux ]]; then
    missing=()
    have g++ || missing+=("g++ (a C++ compiler)")
    have make || missing+=("make")
    have gsl-config || missing+=("GSL (libgsl-dev / gsl-devel)")

    if [[ ${#missing[@]} -eq 0 ]]; then
        info "All required system packages already present."
    else
        warn "Missing: ${missing[*]}"
        echo "On HPC clusters these are usually provided system-wide or via" >&2
        echo "'module load <name>' — check with your cluster's documentation/admins" >&2
        echo "before trying to install anything yourself." >&2
        if have apt-get && have sudo; then
            echo >&2
            read -r -p "Detected apt-get + sudo — attempt 'sudo apt-get install g++ make libgsl-dev' now? [y/N] " reply
            if [[ "$reply" =~ ^[Yy]$ ]]; then
                sudo apt-get update && sudo apt-get install -y g++ make libgsl-dev
            else
                echo "Skipped. Install the missing packages yourself, then re-run this script." >&2
                exit 1
            fi
        else
            exit 1
        fi
    fi
else
    warn "Unrecognized platform '$UNAME_S'; skipping package checks. You need a C++ compiler, make, and GSL (gsl-config on PATH)."
fi

# ---------------------------------------------------------------------------
# twopunctures-standalone (the solver library this repo's Main.cc links against)
# ---------------------------------------------------------------------------
if [[ -f "$TP_DIR/libtwopunctures/TP_Parameters.h" ]]; then
    info "twopunctures-standalone already present at $TP_DIR"
elif [[ "$DO_CLONE" == 1 ]]; then
    info "Cloning twopunctures-standalone into $TP_DIR ..."
    git clone "$TP_REPO_URL" "$TP_DIR"
else
    warn "twopunctures-standalone not found at $TP_DIR and --no-clone given; the build below will fail."
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if [[ "$DO_BUILD" == 1 ]]; then
    info "Building ./twopunctures (TP_STANDALONE_DIR=$TP_DIR)..."
    make -C "$(dirname "$0")" TP_STANDALONE_DIR="$TP_DIR"
    info "Done. Try: ./submit.sh --dry-run params.par 1.0"
else
    info "Skipping build (--no-build). Run: make TP_STANDALONE_DIR=$TP_DIR"
fi
