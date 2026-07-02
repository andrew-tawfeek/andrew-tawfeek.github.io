#!/usr/bin/env bash
# carepackage.sh — quick-start a fresh Ubuntu/Debian box: swap, devtools, python, gh,
# claude, codex, mosh, and mobile-friendly SSH (auto-land interactive logins on your
# primary user).
#
# No secrets live in this script. Auth is configured separately: copy ~/.config/gh and
# ~/.claude over, and run `codex login` (e.g. `codex login --device-auth` on a headless box).
#
# Runs on a fresh Ubuntu/Debian server OR under WSL — on WSL the server-only sections
# (swapfile, mobile-SSH land-on-primary, and the hardening trio) auto-skip; the dev tooling
# still installs. Same one-liner works in both.
#
# Usage:   curl -fsSL https://atawfeek.com/carepackage.sh | bash
#   Vars:  SWAP_SIZE=8G              swapfile size (default 4G)
#          PRIMARY_USER=<name>       user to land mobile/console SSH on (default: current user)

set -euo pipefail

# Swap size for the swapfile (override at runtime, e.g. SWAP_SIZE=8G bash carepackage.sh).
# Accepts a fallocate-style size like 2G, 4G, 512M.
SWAP_SIZE="${SWAP_SIZE:-4G}"

SUDO=""
if [[ $EUID -ne 0 ]]; then
  SUDO="sudo"
fi

# Detect WSL (Windows Subsystem for Linux). On WSL we skip the server-only sections
# (swapfile, mobile-SSH land-on-primary, and unattended-upgrades/fail2ban/ufw) — they are
# unnecessary there and can error under `set -e`. All dev + CLI + Python tooling still installs.
IS_WSL=0
if grep -qiE "microsoft|WSL" /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  IS_WSL=1
  echo "==> WSL detected — skipping server-only sections (swap, SSH land-on-primary, hardening)"
fi

echo "==> Configuring ${SWAP_SIZE} swapfile"
if [[ "$IS_WSL" == 1 ]]; then
  echo "    WSL — skipping (swap is managed by Windows via .wslconfig)"
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

echo "==> apt update"
$SUDO apt-get update -qq

echo "==> Installing devtools and python"
$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git curl wget unzip ca-certificates rsync \
  tmux vim htop btop jq tree ncdu ripgrep mosh fzf \
  python3 python3-pip python3-venv
# mosh = SSH that survives roaming/disconnects (great from a phone); ripgrep=rg, ncdu=disk usage.
# btop = prettier top; fzf = fuzzy finder (Ctrl-R history, Ctrl-T files).

echo "==> Installing fd (fd-find) + bat (batcat) with aliases"
# Debian/Ubuntu ship these under quirky binary names: fd-find -> fdfind, bat -> batcat.
$SUDO apt-get install -y fd-find bat || true
if ! grep -q '^alias fd=fdfind' "$HOME/.bashrc" 2>/dev/null; then
  echo 'alias fd=fdfind' >> "$HOME/.bashrc"
  echo "    added 'alias fd=fdfind' to ~/.bashrc"
fi
if ! grep -q '^alias bat=batcat' "$HOME/.bashrc" 2>/dev/null; then
  echo 'alias bat=batcat' >> "$HOME/.bashrc"
  echo "    added 'alias bat=batcat' to ~/.bashrc"
fi

echo "==> Installing eza (modern ls)"
if command -v eza >/dev/null 2>&1; then
  echo "    eza already installed"
elif apt-cache show eza >/dev/null 2>&1; then
  $SUDO apt-get install -y eza
else
  # Older Ubuntu has no eza package; grab the latest release binary for this arch.
  echo "    no eza apt package; downloading release binary"
  case "$(dpkg --print-architecture)" in
    amd64) eza_arch="x86_64-unknown-linux-gnu" ;;
    arm64) eza_arch="aarch64-unknown-linux-gnu" ;;
    *)     eza_arch="" ;;
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
    echo "    WARN: unsupported arch for eza binary; skipping"
  fi
fi

echo "==> Installing zoxide (smarter cd)"
if command -v zoxide >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/zoxide" ]]; then
  echo "    zoxide already installed"
else
  if ! curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh; then
    echo "    installer failed; falling back to apt"
    $SUDO apt-get install -y zoxide || echo "    WARN: zoxide install failed; skipping"
  fi
fi
if ! grep -q 'zoxide init bash' "$HOME/.bashrc" 2>/dev/null; then
  echo 'eval "$(zoxide init bash)"' >> "$HOME/.bashrc"
  echo "    added zoxide init to ~/.bashrc (use: z <dir>)"
fi

echo "==> Installing uv (fast Python package/venv manager)"
if command -v uv >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/uv" ]]; then
  echo "    uv already installed"
else
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

echo "==> Installing pipx (isolated Python app installer)"
if command -v pipx >/dev/null 2>&1; then
  echo "    pipx already installed"
elif ! $SUDO apt-get install -y pipx; then
  echo "    apt pipx unavailable; falling back to pip --user"
  python3 -m pip install --user --break-system-packages pipx || echo "    WARN: pipx install failed"
fi
pipx ensurepath >/dev/null 2>&1 || true

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

if [[ "$IS_WSL" == 0 ]]; then
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
else
  echo "==> WSL — skipping server hardening (unattended-upgrades / fail2ban / ufw)"
fi

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

# --- Mobile/console SSH: auto-land interactive logins on the primary work user ---
# On GCP with OS Login OFF, the console/mobile SSH creates a Linux user named after your
# Google account on first connect. This drops an interactive login by any non-primary,
# non-root human user straight into PRIMARY_USER (where your tools + auth live), and gives
# PRIMARY_USER passwordless sudo so that switch (and admin) needs no password.
# Guarded: scp/sftp/non-interactive sessions are untouched, and there is no switch loop.
# Opt out per-session with AUTO_NO_SWITCH=1; disable by removing the profile.d file below.
PRIMARY_USER="${PRIMARY_USER:-$(id -un)}"
if [[ "$IS_WSL" == 0 ]] && [[ "$PRIMARY_USER" != "root" ]] && id "$PRIMARY_USER" >/dev/null 2>&1; then
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

echo "==> Writing help file to ~/CAREPACKAGE.txt"
# Generated documentation — overwritten each run so it always reflects this script.
cat > "$HOME/CAREPACKAGE.txt" <<'CAREPKGHELP'
================================================================================
 CAREPACKAGE — what this box was set up with
================================================================================
This machine was bootstrapped by carepackage.sh (https://atawfeek.com/carepackage.sh).
It installs a swapfile, dev + CLI tooling, Python tooling, a few AI CLIs, light
server hardening, and mobile-friendly SSH/tmux/vim/git defaults. No secrets live
in the script; auth (gh, claude, codex) is configured separately per box.

Tip: open a fresh shell (or `source ~/.bashrc`) so aliases + PATH take effect.

--------------------------------------------------------------------------------
 TABLE OF CONTENTS
--------------------------------------------------------------------------------
System
  * swapfile
  * mobile/console SSH land-on-primary (+ AUTO_NO_SWITCH)
  * passwordless sudo (primary user)

Core dev + CLI tools (apt)
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
  * fd  (fd-find / fdfind)
  * bat (batcat)
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

Server hardening
  * unattended-upgrades
  * fail2ban
  * ufw (installed but DISABLED)

Dotfiles / config
  * ~/.vimrc
  * ~/.tmux.conf
  * git defaults
  * ~/.gitignore_global

--------------------------------------------------------------------------------
 SYSTEM
--------------------------------------------------------------------------------
swapfile
  A /swapfile giving the box virtual memory headroom (default 4G).
  Check:   swapon --show
  Resize:  re-run with  SWAP_SIZE=8G bash carepackage.sh  (removes nothing if present)

mobile/console SSH land-on-primary
  Interactive logins by a non-primary, non-root user auto-switch into the primary
  work user (where your tools + auth live) via /etc/profile.d/00-land-on-primary.sh.
  scp/sftp/non-interactive sessions are untouched.
  Skip once:  AUTO_NO_SWITCH=1 ssh user@host
  Disable:    sudo rm /etc/profile.d/00-land-on-primary.sh

passwordless sudo (primary user)
  The primary user gets NOPASSWD sudo via /etc/sudoers.d/90-<user>-nopasswd, so the
  auto-switch and admin tasks need no password.
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

fzf — fuzzy finder wired into bash.
  Ctrl-R                 # fuzzy-search command history
  Ctrl-T                 # fuzzy-pick a file path into the command line
  fzf                    # standalone; pipe anything in

rsync — fast incremental file copy/sync (local or over SSH).
  rsync -avz src/ user@host:dst/

--------------------------------------------------------------------------------
 QUIRKY-NAMED CLI TOOLS  (Debian/Ubuntu rename the binaries)
--------------------------------------------------------------------------------
fd — fast, friendly file finder. Package fd-find, binary fdfind; aliased to `fd`.
  fd pattern             # find files matching pattern
  fd -e py               # by extension

bat — `cat` with syntax highlighting + git. Package bat, binary batcat; aliased `bat`.
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

claude — Anthropic Claude Code CLI.
  claude                 # start an interactive session in the repo

codex — OpenAI Codex CLI.
  codex                  # interactive session
  Reauth:  codex login   (headless box: codex login --device-auth)

--------------------------------------------------------------------------------
 SERVER HARDENING
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
 DOTFILES / CONFIG
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
echo "==> Done. Open a new shell or run: source ~/.bashrc"
echo ""
echo "Installed versions:"
python3 --version || true
gh --version 2>/dev/null | head -1 || true
mosh-server --version 2>/dev/null | head -1 || true
{ claude --version 2>/dev/null || "$HOME/.local/bin/claude" --version 2>/dev/null; } || echo "claude: run 'source ~/.bashrc'"
{ codex --version 2>/dev/null || "$HOME/.npm-global/bin/codex" --version 2>/dev/null; } || echo "codex: not on PATH yet (run: source ~/.bashrc)"
source ~/.bashrc 2>/dev/null || true
echo ""
echo "==> Full help + usage for everything installed: ~/CAREPACKAGE.txt"
