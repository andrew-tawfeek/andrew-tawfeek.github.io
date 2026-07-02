#!/usr/bin/env bash
# carepackage.sh — quick-start a fresh dev/server box: swap (servers), devtools, python, gh,
# claude, codex, mosh, and mobile-friendly SSH (auto-land interactive logins on your
# primary user).
#
# CROSS-PLATFORM: one `curl | bash` one-liner runs on
#   * macOS (Homebrew)             — personal machine: dev tooling only
#   * Ubuntu/Debian server         — full: swap + hardening + mobile-SSH + dev tooling
#   * Ubuntu/Debian desktop        — full dev tooling (server bits still apply if not WSL)
#   * Raspberry Pi (Debian/Pi OS)  — dev tooling; swap auto-SKIPPED (SD-card wear)
#   * WSL (Windows Subsystem)      — dev tooling; server-only sections auto-skipped
#
# Auto-skip summary:
#   * macOS     — swap, mobile-SSH land-on-primary, and the hardening trio are skipped
#                 (personal machine; no apt/systemctl/profile.d). Dev tooling via brew.
#   * WSL       — swap, mobile-SSH land-on-primary, hardening trio skipped.
#   * Raspberry Pi — swapfile skipped (Pi OS manages swap via dphys-swapfile; avoid SD wear);
#                 other server sections still run if it's a real Linux server (non-WSL).
# Everything is idempotent: re-running is a fast no-op (every tool is checked before install).
#
# No secrets live in this script. Auth is configured separately: copy ~/.config/gh and
# ~/.claude over, and run `codex login` (e.g. `codex login --device-auth` on a headless box).
#
# Usage:   curl -fsSL https://atawfeek.com/carepackage.sh | bash
#   Vars:  SWAP_SIZE=8G              swapfile size (default 4G; Linux servers only)
#          PRIMARY_USER=<name>       user to land mobile/console SSH on (default: current user)

set -euo pipefail

# Swap size for the swapfile (override at runtime, e.g. SWAP_SIZE=8G bash carepackage.sh).
# Accepts a fallocate-style size like 2G, 4G, 512M.
SWAP_SIZE="${SWAP_SIZE:-4G}"

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
OS="$(uname -s)"
IS_MAC=0
IS_WSL=0
IS_PI=0

if [[ "$OS" == "Darwin" ]]; then
  IS_MAC=1
fi

if [[ "$IS_MAC" == 0 ]]; then
  # Detect WSL (Windows Subsystem for Linux). On WSL we skip the server-only sections
  # (swapfile, mobile-SSH land-on-primary, and unattended-upgrades/fail2ban/ufw) — they are
  # unnecessary there and can error under `set -e`. All dev + CLI + Python tooling still installs.
  if grep -qiE "microsoft|WSL" /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    IS_WSL=1
  fi
  # Detect Raspberry Pi so we can skip the swapfile (SD-card write-wear; Pi OS manages
  # swap via dphys-swapfile). Other Linux-server sections still apply on a real Pi server.
  if grep -qi "raspberry pi" /proc/cpuinfo 2>/dev/null \
     || grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
    IS_PI=1
  fi
fi

# sudo is only meaningful on Linux; Homebrew must NOT run under sudo.
SUDO=""
if [[ "$IS_MAC" == 0 && $EUID -ne 0 ]]; then
  SUDO="sudo"
fi

# One-line detection summary.
if [[ "$IS_MAC" == 1 ]]; then
  echo "==> Detected: macOS ($(uname -m)) — Homebrew path; server-only sections auto-skip"
else
  _plat="Linux ($(uname -m))"
  [[ "$IS_WSL" == 1 ]] && _plat="$_plat / WSL"
  [[ "$IS_PI" == 1 ]] && _plat="$_plat / Raspberry Pi"
  echo "==> Detected: $_plat — apt path"
  [[ "$IS_WSL" == 1 ]] && echo "    WSL — server-only sections (swap, SSH land-on-primary, hardening) will auto-skip"
  [[ "$IS_PI" == 1 ]] && echo "    Raspberry Pi — swapfile will be skipped (Pi OS manages swap; SD-card wear)"
fi

# ---------------------------------------------------------------------------
# Package-manager abstraction + helpers
# ---------------------------------------------------------------------------
# have <cmd> — is a command already on PATH?
have() { command -v "$1" >/dev/null 2>&1; }

# On macOS ensure Homebrew is present and on PATH for this session.
if [[ "$IS_MAC" == 1 ]]; then
  echo "==> Ensuring Homebrew is installed"
  if ! have brew; then
    echo "    brew not found; installing Homebrew (no sudo used by brew itself)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "    brew already installed"
  fi
  # Load brew into this session's PATH. Apple Silicon: /opt/homebrew; Intel: /usr/local.
  if have brew; then
    eval "$(brew shellenv)"
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# On Linux, refresh apt once up front (mac has no apt).
if [[ "$IS_MAC" == 0 ]]; then
  echo "==> apt update"
  $SUDO apt-get update -qq
fi

# pkg_install <cmd_to_check> <brew_pkg> <apt_pkg>
#   Idempotent: if <cmd_to_check> is already present, skip. Otherwise install via the
#   platform package manager. brew never uses sudo; apt uses $SUDO + noninteractive.
pkg_install() {
  local check="$1" brewpkg="$2" aptpkg="$3"
  if have "$check"; then
    echo "    $check already installed; skipping"
    return 0
  fi
  if [[ "$IS_MAC" == 1 ]]; then
    echo "    installing $brewpkg (brew)"
    brew install "$brewpkg" || echo "    WARN: brew install $brewpkg failed; skipping"
  else
    echo "    installing $aptpkg (apt)"
    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y $aptpkg \
      || echo "    WARN: apt install $aptpkg failed; skipping"
  fi
}

# ---------------------------------------------------------------------------
# Choose the right shell rc file for PATH/alias/init appends.
#   * macOS default shell is zsh -> write ~/.zshrc (+ ~/.bash_profile for bash users).
#   * Linux default is bash     -> write ~/.bashrc.
# All rc-appends route through SHELL_RC and are grep-guarded (idempotent).
# ---------------------------------------------------------------------------
if [[ "$IS_MAC" == 1 ]]; then
  SHELL_RC="$HOME/.zshrc"
  SHELL_RC_ALT="$HOME/.bash_profile"
  ZOXIDE_SHELL="zsh"
else
  SHELL_RC="$HOME/.bashrc"
  SHELL_RC_ALT=""
  ZOXIDE_SHELL="bash"
fi
touch "$SHELL_RC"
[[ -n "$SHELL_RC_ALT" ]] && touch "$SHELL_RC_ALT"

# rc_append <grep-pattern> <line-to-add> [note]
#   Append <line> to SHELL_RC (and SHELL_RC_ALT on macOS) only if <grep-pattern> is absent.
rc_append() {
  local pat="$1" line="$2" note="${3:-}"
  local added=0
  if ! grep -qF "$pat" "$SHELL_RC" 2>/dev/null; then
    printf '%s\n' "$line" >> "$SHELL_RC"
    added=1
  fi
  if [[ -n "$SHELL_RC_ALT" ]] && ! grep -qF "$pat" "$SHELL_RC_ALT" 2>/dev/null; then
    printf '%s\n' "$line" >> "$SHELL_RC_ALT"
    added=1
  fi
  if [[ "$added" == 1 && -n "$note" ]]; then
    echo "    $note"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Swapfile — Linux servers only (skip on macOS, WSL, and Raspberry Pi)
# ---------------------------------------------------------------------------
echo "==> Configuring ${SWAP_SIZE} swapfile"
if [[ "$IS_MAC" == 1 ]]; then
  echo "    macOS — skipping (the OS manages virtual memory automatically)"
elif [[ "$IS_WSL" == 1 ]]; then
  echo "    WSL — skipping (swap is managed by Windows via .wslconfig)"
elif [[ "$IS_PI" == 1 ]]; then
  echo "    Raspberry Pi — skipping (Pi OS manages swap via dphys-swapfile; avoids SD-card wear)"
elif $SUDO swapon --show 2>/dev/null | grep -q '/swapfile' || [[ -e /swapfile ]]; then
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

# ---------------------------------------------------------------------------
# Core dev + CLI tools — cross-platform, each guarded by have()/pkg_install
# ---------------------------------------------------------------------------
echo "==> Installing core dev + CLI tools"
# On Linux, a couple of build/base packages have no single command to probe cleanly,
# so install them directly (apt is idempotent — already-installed is a no-op). macOS
# gets its compilers from the Xcode CLT that Homebrew pulls in.
if [[ "$IS_MAC" == 0 ]]; then
  echo "    installing base packages (build-essential, ca-certificates, unzip, rsync)"
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential unzip ca-certificates rsync python3-pip python3-venv \
    || echo "    WARN: some base packages failed; continuing"
else
  # rsync ships with macOS; install a couple of base helpers idempotently.
  pkg_install rsync rsync rsync
fi

# name-quirk note: on Linux, ripgrep's binary is `rg`; check that command.
pkg_install git      git      git
pkg_install curl     curl     curl
pkg_install wget     wget     wget
pkg_install tmux     tmux     tmux
pkg_install vim      vim      vim
pkg_install htop     htop     htop
pkg_install btop     btop     btop
pkg_install jq       jq       jq
pkg_install tree     tree     tree
pkg_install ncdu     ncdu     ncdu
pkg_install rg       ripgrep  ripgrep
pkg_install fzf      fzf      fzf
pkg_install mosh     mosh     mosh
pkg_install python3  python   python3

# mosh = SSH that survives roaming/disconnects (great from a phone); ripgrep=rg, ncdu=disk usage.
# btop = prettier top; fzf = fuzzy finder (Ctrl-R history, Ctrl-T files).

# --- fd + bat: binary names differ by platform -----------------------------
# Debian/Ubuntu ship these under quirky binary names: fd-find -> fdfind, bat -> batcat,
# so we alias them back to fd/bat. On macOS/brew the packages ARE `fd` and `bat` with the
# real binary names, so NO alias is needed (and adding one would be wrong).
echo "==> Installing fd + bat"
if [[ "$IS_MAC" == 1 ]]; then
  pkg_install fd  fd  fd
  pkg_install bat bat bat
else
  # Linux: check for the real fd/bat OR the Debian-renamed fdfind/batcat before installing.
  if have fd || have fdfind; then
    echo "    fd already installed; skipping"
  else
    echo "    installing fd-find (apt)"
    $SUDO apt-get install -y fd-find || echo "    WARN: fd-find install failed; skipping"
  fi
  if have bat || have batcat; then
    echo "    bat already installed; skipping"
  else
    echo "    installing bat (apt)"
    $SUDO apt-get install -y bat || echo "    WARN: bat install failed; skipping"
  fi
  rc_append 'alias fd=fdfind'  'alias fd=fdfind'  "added 'alias fd=fdfind' to $SHELL_RC"
  rc_append 'alias bat=batcat' 'alias bat=batcat' "added 'alias bat=batcat' to $SHELL_RC"
fi

# --- eza (modern ls) -------------------------------------------------------
echo "==> Installing eza (modern ls)"
if have eza; then
  echo "    eza already installed"
elif [[ "$IS_MAC" == 1 ]]; then
  echo "    installing eza (brew)"
  brew install eza || echo "    WARN: brew install eza failed; skipping"
elif apt-cache show eza >/dev/null 2>&1; then
  $SUDO apt-get install -y eza
else
  # Older Ubuntu has no eza package; grab the latest release binary for this arch.
  echo "    no eza apt package; downloading release binary"
  case "$(dpkg --print-architecture)" in
    amd64) eza_arch="x86_64-unknown-linux-gnu" ;;
    arm64) eza_arch="aarch64-unknown-linux-gnu" ;;
    *)     eza_arch="" ;;   # e.g. 32-bit armhf (older Pi) — no prebuilt binary; skip gracefully
  esac
  if [[ -n "$eza_arch" ]]; then
    mkdir -p "$HOME/.local/bin"
    eza_tmp="$(mktemp -d)"
    eza_url="https://github.com/eza-community/eza/releases/latest/download/eza_${eza_arch}.tar.gz"
    if curl -fsSL "$eza_url" -o "$eza_tmp/eza.tar.gz"; then
      tar -xzf "$eza_tmp/eza.tar.gz" -C "$eza_tmp"
      # binary may be at ./eza or ./bin/eza depending on release layout
      eza_bin="$(find "$eza_tmp" -type f -name eza | head -1)"
      if [[ -n "$eza_bin" ]]; then
        install -m 0755 "$eza_bin" "$HOME/.local/bin/eza"
        echo "    installed eza to ~/.local/bin/eza"
      else
        echo "    WARN: eza binary not found in release tarball; skipping"
      fi
    else
      echo "    WARN: eza download failed; skipping"
    fi
    rm -rf "$eza_tmp"
  else
    echo "    WARN: unsupported arch for eza binary (e.g. 32-bit armhf); skipping"
  fi
fi

# --- zoxide (smarter cd) ---------------------------------------------------
echo "==> Installing zoxide (smarter cd)"
if have zoxide || [[ -x "$HOME/.local/bin/zoxide" ]]; then
  echo "    zoxide already installed"
elif [[ "$IS_MAC" == 1 ]]; then
  echo "    installing zoxide (brew)"
  brew install zoxide || echo "    WARN: brew install zoxide failed; skipping"
else
  if ! curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
    echo "    installer failed; falling back to apt"
    $SUDO apt-get install -y zoxide || echo "    WARN: zoxide install failed; skipping"
  fi
fi
# zoxide init takes the shell name — zsh on macOS, bash on Linux.
rc_append "zoxide init $ZOXIDE_SHELL" "eval \"\$(zoxide init $ZOXIDE_SHELL)\"" \
  "added zoxide init ($ZOXIDE_SHELL) to $SHELL_RC (use: z <dir>)"

# --- uv (fast Python package/venv manager) ---------------------------------
echo "==> Installing uv (fast Python package/venv manager)"
if have uv || [[ -x "$HOME/.local/bin/uv" ]]; then
  echo "    uv already installed"
elif [[ "$IS_MAC" == 1 ]]; then
  echo "    installing uv (brew)"
  brew install uv || curl -LsSf https://astral.sh/uv/install.sh | sh
else
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# --- pipx (isolated Python app installer) ----------------------------------
echo "==> Installing pipx (isolated Python app installer)"
if have pipx; then
  echo "    pipx already installed"
elif [[ "$IS_MAC" == 1 ]]; then
  echo "    installing pipx (brew)"
  brew install pipx || echo "    WARN: brew install pipx failed; skipping"
elif ! $SUDO apt-get install -y pipx; then
  echo "    apt pipx unavailable; falling back to pip --user"
  python3 -m pip install --user --break-system-packages pipx || echo "    WARN: pipx install failed"
fi
pipx ensurepath >/dev/null 2>&1 || true

# --- gh (GitHub CLI) -------------------------------------------------------
echo "==> Installing gh"
if have gh; then
  echo "    gh already installed: $(gh --version | head -1)"
elif [[ "$IS_MAC" == 1 ]]; then
  echo "    installing gh (brew)"
  brew install gh || echo "    WARN: brew install gh failed; skipping"
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

# --- claude (Anthropic Claude Code CLI) ------------------------------------
# The official installer supports both macOS and Linux, so it's the same on both.
echo "==> Installing claude"
if have claude || [[ -x "$HOME/.local/bin/claude" ]]; then
  echo "    claude already installed"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- codex (OpenAI Codex CLI, ships via npm) -------------------------------
echo "==> Installing codex (OpenAI Codex CLI)"
if have codex; then
  echo "    codex already installed: $(codex --version 2>/dev/null || echo present)"
else
  # codex CLI ships via npm; ensure Node.js + npm are available first.
  if ! have npm; then
    echo "    npm not found; installing Node.js"
    if [[ "$IS_MAC" == 1 ]]; then
      brew install node || echo "    WARN: brew install node failed"
    elif apt-cache show nodejs >/dev/null 2>&1 && apt-cache show npm >/dev/null 2>&1; then
      $SUDO apt-get install -y nodejs npm
    else
      curl -fsSL https://deb.nodesource.com/setup_lts.x | $SUDO -E bash -
      $SUDO apt-get install -y nodejs
    fi
  fi
  if [[ "$IS_MAC" == 1 ]]; then
    # Homebrew's node has a writable global prefix — no sudo, no custom prefix needed.
    npm install -g @openai/codex || echo "    WARN: npm install -g @openai/codex failed"
  else
    # Prefer a user-local global prefix so we don't need sudo for npm -g
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    npm install -g @openai/codex
    rc_append '.npm-global/bin' 'export PATH="$HOME/.npm-global/bin:$PATH"' \
      "Added ~/.npm-global/bin to $SHELL_RC"
  fi
fi

# Ensure ~/.local/bin is on PATH (uv, claude, zoxide, eza land here on Linux).
rc_append '.local/bin' 'export PATH="$HOME/.local/bin:$PATH"' \
  "Added ~/.local/bin to $SHELL_RC"

# ---------------------------------------------------------------------------
# Server-only sections — Linux, non-WSL only (skipped on macOS + WSL)
# ---------------------------------------------------------------------------
if [[ "$IS_MAC" == 0 && "$IS_WSL" == 0 ]]; then
echo "==> Server hardening: unattended-upgrades"
$SUDO apt-get install -y unattended-upgrades || true
# Enable automatic security updates (idempotent: tee overwrites with the same content).
$SUDO tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'AUTOUPG'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
AUTOUPG
echo "    automatic security updates enabled"

echo "==> Server hardening: fail2ban"
$SUDO apt-get install -y fail2ban || true
# Debian/Ubuntu ships a default sshd jail — safe, only bans SSH brute-forcers.
$SUDO systemctl enable --now fail2ban 2>/dev/null || true

echo "==> Server hardening: ufw (installed, rules staged, LEFT DISABLED)"
$SUDO apt-get install -y ufw || true
# CRITICAL: do NOT enable ufw here. Force-enabling on a remote box with the wrong
# rules can lock you out of SSH. These GCP boxes are already firewalled at the cloud
# layer, so enabling the host firewall is the user's explicit call. We only stage rules.
$SUDO ufw allow OpenSSH 2>/dev/null || $SUDO ufw allow 22/tcp 2>/dev/null || true
$SUDO ufw allow 60000:61000/udp 2>/dev/null || true   # mosh
echo "    ufw installed + SSH/mosh allowed but left disabled; enable when ready with: sudo ufw enable"
elif [[ "$IS_MAC" == 1 ]]; then
  echo "==> macOS — skipping server hardening (unattended-upgrades / fail2ban / ufw)"
else
  echo "==> WSL — skipping server hardening (unattended-upgrades / fail2ban / ufw)"
fi

# ---------------------------------------------------------------------------
# Dotfiles — cross-platform ($HOME files; written only if missing)
# ---------------------------------------------------------------------------
echo "==> Installing dotfiles (.vimrc)"
mkdir -p "$HOME/.vim/undo"
if [[ -f "$HOME/.vimrc" ]]; then
  echo "    ~/.vimrc already exists; left as-is"
else
  cat > "$HOME/.vimrc" <<'VIMRC'
" ~/.vimrc — tuned for iTerm "Galaxy" theme (background #1d2837)

set nocompatible          " use Vim features, not vi-compatible mode
syntax on                 " enable syntax highlighting
filetype plugin indent on " detect filetype, load plugins + indent rules

set background=dark
set termguicolors         " 24-bit color so the exact Galaxy hexes render

" Sensible defaults
set number                " show line numbers (current line = absolute)...
set relativenumber        " ...other lines relative -> hybrid gutter
set scrolloff=5           " keep 5 lines of context above/below the cursor
set splitbelow            " :split opens the new window below
set splitright            " :vsplit opens the new window to the right
set tabstop=4             " a tab is 4 spaces wide
set shiftwidth=4          " autoindent uses 4 spaces
set expandtab             " convert tabs to spaces
set autoindent            " keep indentation on new lines
set incsearch             " incremental search
set hlsearch              " highlight search matches
set ruler                 " show cursor position
set cursorline            " highlight the current line
set linebreak             " soft-wrap at word boundaries, not mid-word
set wildmenu              " visual tab-completion in the : command line
set clipboard=unnamed     " yank/paste through the macOS system clipboard

" Persistent undo — undo history survives closing the file
set undofile
set undodir=~/.vim/undo//

" --- Galaxy-tuned syntax colors -------------------------------------------
" Every group is pinned to a high-contrast Galaxy palette color so nothing
" falls back to the theme's dark blues/grays, which are unreadable on #1d2837.
" Wrapped in an autocmd so it survives any later :colorscheme change.
function! s:GalaxyHighlights() abort
  " Base
  highlight Normal       guifg=#ffffff guibg=#1d2837
  highlight Comment      guifg=#8492ac gui=italic cterm=italic
  highlight LineNr       guifg=#5c6c88
  highlight NonText      guifg=#3a4a64               " ~ markers, listchars
  highlight EndOfBuffer  guifg=#3a4a64               " ~ below the last line
  highlight CursorLine   guibg=#26344a gui=NONE cterm=NONE
  highlight CursorLineNr guifg=#ffff55 gui=bold
  highlight Visual       guibg=#b5d5ff guifg=#000000

  " Syntax groups (distinct, all high-contrast on the Galaxy background)
  highlight Constant     guifg=#fa8c8f               " numbers, booleans
  highlight String       guifg=#21b089               " green
  highlight Identifier   guifg=#589df6 gui=NONE      " variables, blue
  highlight Function     guifg=#1f9ee7               " functions / builtins, cyan
  highlight Statement    guifg=#e75699               " keywords (if/def/return), pink
  highlight PreProc      guifg=#e75699               " imports, decorators
  highlight Type         guifg=#fef02a               " types / classes, yellow
  highlight Special      guifg=#ffff55

  " UI / search
  highlight Search       guibg=#fef02a guifg=#000000
  highlight IncSearch    guibg=#e75699 guifg=#000000
  highlight MatchParen   guibg=#944d95 guifg=#ffffff " dark purple works as a bg
  highlight Todo         guibg=#fef02a guifg=#000000
  highlight Error        guibg=#f9555f guifg=#ffffff
  highlight StatusLine   guibg=#589df6 guifg=#000000
  highlight StatusLineNC guibg=#26344a guifg=#bbbbbb
  highlight Pmenu        guibg=#26344a guifg=#ffffff
  highlight PmenuSel     guibg=#589df6 guifg=#000000
endfunction

augroup GalaxyColors
  autocmd!
  autocmd ColorScheme * call s:GalaxyHighlights()
augroup END
call s:GalaxyHighlights()
VIMRC
  echo "    wrote ~/.vimrc"
fi

echo "==> Installing dotfiles (.tmux.conf)"
if [[ -f "$HOME/.tmux.conf" ]]; then
  echo "    ~/.tmux.conf already exists; left as-is"
else
  cat > "$HOME/.tmux.conf" <<'TMUXCONF'
# ~/.tmux.conf — mobile-friendly defaults (written by carepackage.sh)

set -g mouse on                 # scroll/select/resize with the mouse or touchscreen
set -g history-limit 100000     # deep scrollback buffer
set -g base-index 1             # windows start at 1 (easier to reach than 0)
setw -g pane-base-index 1       # panes start at 1 too

# True color so 24-bit themes render correctly inside tmux
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"

setw -g mode-keys vi            # vi-style keys in copy mode

# A bigger, more informative status bar
set -g status-interval 5
set -g status-left-length 30
set -g status-right-length 60
set -g status-left  " #S "
set -g status-right " #H  %Y-%m-%d %H:%M "
TMUXCONF
  echo "    wrote ~/.tmux.conf"
fi

echo "==> Configuring git defaults (no name/email — those are per-user)"
# Safe, opinionated global git defaults. Name + email are intentionally NOT set here.
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global push.default simple
git config --global core.editor vim
if [[ ! -f "$HOME/.gitignore_global" ]]; then
  cat > "$HOME/.gitignore_global" <<'GITIGNORE'
# Global gitignore (written by carepackage.sh) — common junk across all repos.
.DS_Store
__pycache__/
*.pyc
.venv/
node_modules/
.env
*.swp
GITIGNORE
  echo "    wrote ~/.gitignore_global"
fi
git config --global core.excludesfile "$HOME/.gitignore_global"

# ---------------------------------------------------------------------------
# Mobile/console SSH: auto-land interactive logins on the primary work user
#   Linux server only (skipped on macOS + WSL).
# ---------------------------------------------------------------------------
# On GCP with OS Login OFF, the console/mobile SSH creates a Linux user named after your
# Google account on first connect. This drops an interactive login by any non-primary,
# non-root human user straight into PRIMARY_USER (where your tools + auth live), and gives
# PRIMARY_USER passwordless sudo so that switch (and admin) needs no password.
# Guarded: scp/sftp/non-interactive sessions are untouched, and there is no switch loop.
# Opt out per-session with AUTO_NO_SWITCH=1; disable by removing the profile.d file below.
PRIMARY_USER="${PRIMARY_USER:-$(id -un)}"
if [[ "$IS_MAC" == 0 && "$IS_WSL" == 0 ]] && [[ "$PRIMARY_USER" != "root" ]] && id "$PRIMARY_USER" >/dev/null 2>&1; then
  echo "==> Configuring mobile/console SSH to land on '$PRIMARY_USER'"
  printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "$PRIMARY_USER" \
    | $SUDO tee "/etc/sudoers.d/90-${PRIMARY_USER}-nopasswd" >/dev/null
  $SUDO chmod 0440 "/etc/sudoers.d/90-${PRIMARY_USER}-nopasswd"
  $SUDO visudo -cf "/etc/sudoers.d/90-${PRIMARY_USER}-nopasswd" >/dev/null \
    || $SUDO rm -f "/etc/sudoers.d/90-${PRIMARY_USER}-nopasswd"
  # System-wide login hook — also covers users created later (e.g. on first phone SSH).
  $SUDO tee /etc/profile.d/00-land-on-primary.sh >/dev/null <<PROFILE
# Auto-switch an interactive login into the primary work user. Added by carepackage.sh.
PRIMARY_USER="$PRIMARY_USER"
if [ -t 0 ] && [ -t 1 ] && [ -z "\${AUTO_NO_SWITCH:-}" ]; then
  _me="\$(id -un)"
  if [ "\$_me" != "\$PRIMARY_USER" ] && [ "\$_me" != "root" ] && id "\$PRIMARY_USER" >/dev/null 2>&1; then
    exec sudo -iu "\$PRIMARY_USER"
  fi
fi
PROFILE
  $SUDO chmod 0644 /etc/profile.d/00-land-on-primary.sh
  echo "    interactive SSH (incl. from your phone) will land on '$PRIMARY_USER' (AUTO_NO_SWITCH=1 to skip)"
fi

# ---------------------------------------------------------------------------
# Help file (~/CAREPACKAGE.txt) — platform-aware, regenerated each run
# ---------------------------------------------------------------------------
echo "==> Writing help file to ~/CAREPACKAGE.txt"
# Compute a human-readable platform label + which sections were skipped.
if [[ "$IS_MAC" == 1 ]]; then
  PLATFORM_LABEL="macOS ($(uname -m)) via Homebrew"
  SKIP_NOTE="Server-only sections (swapfile, mobile-SSH land-on-primary, hardening trio) are AUTO-SKIPPED on macOS — this is treated as a personal machine."
elif [[ "$IS_WSL" == 1 ]]; then
  PLATFORM_LABEL="WSL (Windows Subsystem for Linux, $(uname -m)) via apt"
  SKIP_NOTE="Server-only sections (swapfile, mobile-SSH land-on-primary, hardening trio) are AUTO-SKIPPED under WSL."
elif [[ "$IS_PI" == 1 ]]; then
  PLATFORM_LABEL="Raspberry Pi ($(uname -m)) via apt"
  SKIP_NOTE="Swapfile is AUTO-SKIPPED on Raspberry Pi (Pi OS manages swap via dphys-swapfile; avoids SD-card write-wear). Other server sections still run if this is a real server."
else
  PLATFORM_LABEL="Linux ($(uname -m)) via apt"
  SKIP_NOTE="Full server setup ran (swapfile, mobile-SSH land-on-primary, hardening trio)."
fi

# Generated documentation — overwritten each run so it always reflects this script.
# Header block is dynamic (platform-aware); the rest is a static heredoc appended below.
cat > "$HOME/CAREPACKAGE.txt" <<CAREPKGHEAD
================================================================================
 CAREPACKAGE — what this box was set up with
================================================================================
This machine was bootstrapped by carepackage.sh (https://atawfeek.com/carepackage.sh).

Detected platform:  $PLATFORM_LABEL
Skip behavior:      $SKIP_NOTE

The same one-liner runs on macOS (Homebrew), Ubuntu/Debian server + desktop,
Raspberry Pi, and WSL. It installs dev + CLI tooling, Python tooling, a few AI
CLIs, and mobile-friendly SSH/tmux/vim/git defaults. On Linux servers it also
adds a swapfile, light hardening, and mobile-SSH land-on-primary; those
auto-skip on macOS/WSL, and the swapfile auto-skips on Raspberry Pi.
Everything is idempotent — re-running is a fast no-op.

No secrets live in the script; auth (gh, claude, codex) is configured
separately per box.
CAREPKGHEAD

cat >> "$HOME/CAREPACKAGE.txt" <<'CAREPKGHELP'

Tip: open a fresh shell (or source your shell rc) so aliases + PATH take effect.
     macOS uses ~/.zshrc; Linux/WSL uses ~/.bashrc.

--------------------------------------------------------------------------------
 TABLE OF CONTENTS
--------------------------------------------------------------------------------
System (Linux servers only; auto-skipped on macOS/WSL)
  * swapfile (also skipped on Raspberry Pi)
  * mobile/console SSH land-on-primary (+ AUTO_NO_SWITCH)
  * passwordless sudo (primary user)

Core dev + CLI tools (brew on macOS, apt on Linux)
  * tmux
  * vim
  * htop
  * btop
  * jq
  * tree
  * ncdu
  * ripgrep (rg)
  * mosh
  * fzf
  * rsync

Quirky-named CLI tools
  * fd  (Linux: fd-find / fdfind + alias; macOS: fd)
  * bat (Linux: batcat + alias; macOS: bat)
  * eza
  * zoxide (z)

Python
  * python3 / pip / venv
  * uv
  * pipx

AI / dev CLIs
  * gh
  * claude
  * codex

Server hardening (Linux servers only)
  * unattended-upgrades
  * fail2ban
  * ufw (installed but DISABLED)

Dotfiles / config (all platforms)
  * ~/.vimrc
  * ~/.tmux.conf
  * git defaults
  * ~/.gitignore_global

--------------------------------------------------------------------------------
 SYSTEM  (Linux servers only)
--------------------------------------------------------------------------------
swapfile
  A /swapfile giving the box virtual memory headroom (default 4G).
  Skipped on macOS (OS-managed VM), WSL (Windows-managed), and Raspberry Pi
  (Pi OS manages swap; avoids SD-card wear).
  Check:   swapon --show
  Resize:  re-run with  SWAP_SIZE=8G bash carepackage.sh  (removes nothing if present)

mobile/console SSH land-on-primary
  Interactive logins by a non-primary, non-root user auto-switch into the primary
  work user (where your tools + auth live) via /etc/profile.d/00-land-on-primary.sh.
  scp/sftp/non-interactive sessions are untouched. (Linux servers only.)
  Skip once:  AUTO_NO_SWITCH=1 ssh user@host
  Disable:    sudo rm /etc/profile.d/00-land-on-primary.sh

passwordless sudo (primary user)
  The primary user gets NOPASSWD sudo via /etc/sudoers.d/90-<user>-nopasswd, so the
  auto-switch and admin tasks need no password. (Linux servers only.)
  Use:  sudo <cmd>

--------------------------------------------------------------------------------
 CORE DEV + CLI TOOLS
--------------------------------------------------------------------------------
tmux — terminal multiplexer (persistent sessions, splits).
  tmux new -s work       # start/named session
  tmux attach -t work    # reattach (survives disconnects)
  See ~/.tmux.conf: mouse on, 100k-line scrollback, true color.

vim — modal text editor. Config in ~/.vimrc (Galaxy theme, hybrid line numbers).
  vim file.txt           # edit;  :w write, :q quit, :wq both

htop — interactive process viewer.
  htop                   # F6 sort, F9 kill, / search

btop — prettier resource monitor (CPU/mem/net/disk).
  btop

jq — command-line JSON processor.
  cat data.json | jq '.items[].name'
  curl -s api/url | jq .

tree — recursive directory listing as a tree.
  tree -L 2              # limit depth to 2

ncdu — interactive disk-usage explorer.
  ncdu /                 # navigate to find space hogs

ripgrep (rg) — very fast recursive code search.
  rg "TODO"              # search from cwd
  rg -i pattern src/     # case-insensitive, scoped

mosh — SSH that survives roaming/sleep/disconnects (great from a phone).
  mosh user@host         # connect (uses UDP 60000-61000)

fzf — fuzzy finder wired into your shell.
  Ctrl-R                 # fuzzy-search command history
  Ctrl-T                 # fuzzy-pick a file path into the command line
  fzf                    # standalone; pipe anything in

rsync — fast incremental file copy/sync (local or over SSH).
  rsync -avz src/ user@host:dst/

--------------------------------------------------------------------------------
 QUIRKY-NAMED CLI TOOLS
--------------------------------------------------------------------------------
fd — fast, friendly file finder.
  Linux: package fd-find, binary fdfind, aliased to `fd`. macOS: package + binary `fd`.
  fd pattern             # find files matching pattern
  fd -e py               # by extension

bat — `cat` with syntax highlighting + git.
  Linux: package bat, binary batcat, aliased `bat`. macOS: package + binary `bat`.
  bat file.py            # view with highlighting + line numbers

eza — modern `ls` replacement (colors, icons, git, tree).
  eza -la                # long listing, all files
  eza --tree --level=2   # tree view

zoxide — smarter `cd` that learns your most-used dirs (command `z`).
  z proj                 # jump to the best-matching frecent dir
  zi                     # interactive pick

--------------------------------------------------------------------------------
 PYTHON
--------------------------------------------------------------------------------
python3 / pip / venv — interpreter + package installer + virtual environments.
  python3 -m venv .venv && source .venv/bin/activate
  pip install requests

uv — very fast Python package/venv manager (drop-in for pip/venv).
  uv venv                # create a .venv
  uv pip install requests
  uv run script.py       # run in an ephemeral managed env

pipx — install Python CLI apps in isolated environments.
  pipx install ruff
  pipx list

--------------------------------------------------------------------------------
 AI / DEV CLIs
--------------------------------------------------------------------------------
gh — GitHub CLI.
  gh auth status
  gh repo clone owner/name
  gh pr create

claude — Anthropic Claude Code CLI (macOS + Linux).
  claude                 # start an interactive session in the repo

codex — OpenAI Codex CLI.
  codex                  # interactive session
  Reauth:  codex login   (headless box: codex login --device-auth)

--------------------------------------------------------------------------------
 SERVER HARDENING  (Linux servers only)
--------------------------------------------------------------------------------
unattended-upgrades — automatic security updates.
  Enabled via /etc/apt/apt.conf.d/20auto-upgrades.
  Check:  systemctl status unattended-upgrades

fail2ban — bans IPs after repeated failed SSH logins (default sshd jail).
  sudo fail2ban-client status sshd

ufw — host firewall. INSTALLED BUT LEFT DISABLED on purpose (these GCP boxes are
  already firewalled at the cloud layer; enabling the host firewall is your call).
  SSH (OpenSSH/22) and mosh (60000-61000/udp) rules are pre-staged.
  Enable when ready:  sudo ufw enable
  Check rules:        sudo ufw status verbose

--------------------------------------------------------------------------------
 DOTFILES / CONFIG  (all platforms)
--------------------------------------------------------------------------------
~/.vimrc — vim config: Galaxy theme, hybrid line numbers, persistent undo, 4-space
  indent. Written only if missing (won't clobber an existing one).

~/.tmux.conf — mouse on, 100k scrollback, 1-based windows/panes, true color,
  vi copy-mode keys, informative status bar. Written only if missing.

git defaults — global, safe, no name/email (set those per-user yourself):
  init.defaultBranch=main, pull.rebase=true, push.default=simple, core.editor=vim.
  Set your identity:  git config --global user.name "..."; git config --global user.email "..."

~/.gitignore_global — global ignore (.DS_Store, __pycache__/, *.pyc, .venv/,
  node_modules/, .env, *.swp), wired via core.excludesfile.
================================================================================
CAREPKGHELP
echo "    wrote ~/CAREPACKAGE.txt"

echo ""
if [[ "$IS_MAC" == 1 ]]; then
  echo "==> Done. Open a new shell or run: source ~/.zshrc"
else
  echo "==> Done. Open a new shell or run: source ~/.bashrc"
fi
echo ""
echo "Installed versions:"
python3 --version || true
gh --version 2>/dev/null | head -1 || true
mosh-server --version 2>/dev/null | head -1 || true
{ claude --version 2>/dev/null || "$HOME/.local/bin/claude" --version 2>/dev/null; } || echo "claude: run your shell rc"
{ codex --version 2>/dev/null || "$HOME/.npm-global/bin/codex" --version 2>/dev/null; } || echo "codex: not on PATH yet (open a new shell)"
source "$SHELL_RC" 2>/dev/null || true
echo ""
echo "==> Full help + usage for everything installed: ~/CAREPACKAGE.txt"
