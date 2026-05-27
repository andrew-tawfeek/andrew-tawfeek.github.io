#!/usr/bin/env bash
# carepackage.sh — bootstrap a fresh Ubuntu/Debian box with python, devtools, gh, claude.
# Auth is not configured here; copy ~/.config/gh and ~/.claude separately.

set -euo pipefail

# Swap size for the swapfile (override at runtime, e.g. SWAP_SIZE=8G bash carepackage.sh).
# Accepts a fallocate-style size like 2G, 4G, 512M.
SWAP_SIZE="${SWAP_SIZE:-4G}"

SUDO=""
if [[ $EUID -ne 0 ]]; then
  SUDO="sudo"
fi

echo "==> Configuring ${SWAP_SIZE} swapfile"
if $SUDO swapon --show 2>/dev/null | grep -q '/swapfile' || [[ -e /swapfile ]]; then
  echo "    swap already present; skipping"
else
  # dd fallback needs a count in MiB; convert SWAP_SIZE (G/M suffix supported)
  case "$SWAP_SIZE" in
    *G|*g) swap_mb=$(( ${SWAP_SIZE%[Gg]} * 1024 )) ;;
    *M|*m) swap_mb=${SWAP_SIZE%[Mm]} ;;
    *)     swap_mb=$(( SWAP_SIZE / 1024 / 1024 )) ;;
  esac
  $SUDO fallocate -l "$SWAP_SIZE" /swapfile || $SUDO dd if=/dev/zero of=/swapfile bs=1M count="$swap_mb"
  $SUDO chmod 600 /swapfile
  $SUDO mkswap /swapfile
  $SUDO swapon /swapfile
  if ! grep -q '^/swapfile ' /etc/fstab 2>/dev/null; then
    echo '/swapfile none swap sw 0 0' | $SUDO tee -a /etc/fstab >/dev/null
  fi
fi

echo "==> apt update"
$SUDO apt-get update -qq

echo "==> Installing devtools and python"
$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git curl wget unzip ca-certificates \
  tmux vim htop jq \
  python3 python3-pip python3-venv

echo "==> Installing gh"
if command -v gh >/dev/null 2>&1; then
  echo "    gh already installed: $(gh --version | head -1)"
elif apt-cache show gh >/dev/null 2>&1; then
  $SUDO apt-get install -y gh
else
  # Fall back to GitHub's apt repo for older Ubuntu releases
  $SUDO mkdir -p -m 755 /etc/apt/keyrings
  wget -nv -O- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  $SUDO apt-get update -qq
  $SUDO apt-get install -y gh
fi

echo "==> Installing claude"
if command -v claude >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/claude" ]]; then
  echo "    claude already installed"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

echo "==> Installing codex (OpenAI Codex CLI)"
if command -v codex >/dev/null 2>&1; then
  echo "    codex already installed: $(codex --version 2>/dev/null || echo present)"
else
  # codex CLI ships via npm; ensure Node.js + npm are available first
  if ! command -v npm >/dev/null 2>&1; then
    echo "    npm not found; installing Node.js (NodeSource LTS)"
    if apt-cache show nodejs >/dev/null 2>&1 && apt-cache show npm >/dev/null 2>&1; then
      $SUDO apt-get install -y nodejs npm
    else
      curl -fsSL https://deb.nodesource.com/setup_lts.x | $SUDO -E bash -
      $SUDO apt-get install -y nodejs
    fi
  fi
  # Prefer a user-local global prefix so we don't need sudo for npm -g
  mkdir -p "$HOME/.npm-global"
  npm config set prefix "$HOME/.npm-global"
  export PATH="$HOME/.npm-global/bin:$PATH"
  npm install -g @openai/codex
  if ! grep -q '\.npm-global/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
    echo "==> Added ~/.npm-global/bin to ~/.bashrc"
  fi
fi

if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  echo "==> Added ~/.local/bin to ~/.bashrc"
fi

echo ""
echo "==> Done. Open a new shell or run: source ~/.bashrc"
echo ""
echo "Installed versions:"
python3 --version
gh --version | head -1
"$HOME/.local/bin/claude" --version 2>/dev/null || command -v claude && claude --version
codex --version 2>/dev/null || "$HOME/.npm-global/bin/codex" --version 2>/dev/null || echo "codex: not on PATH yet (run: source ~/.bashrc)"
source ~/.bashrc
