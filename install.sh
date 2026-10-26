#!/bin/bash
# Baobab AI film tools - installer for macOS 13 or later.
#
# Run from Terminal (it will be one line in the onboarding email):
#   curl -fsSL https://raw.githubusercontent.com/BaobabStudios/artist-install/main/install.sh | bash
# The copy there is published from ai-film-pipeline/install/ (the source); don't edit it there.
#
# Installs what the tools need, gets the two artist repos and RV, and leaves the Mac ready for
# "Set me up" in the Claude app. Safe to run again: a re-run repairs a half-finished install and
# never deletes anything. It never asks for or stores a password or key itself: Homebrew asks for
# the Mac's password in Terminal, and GitHub sign-in happens in the browser.

set -u

ORG="BaobabStudios"
REPOS=(AIFilmPipeline NaraMediaHarness)
OPENRV_TAG="v3.1.0"
OPENRV_VERSION="3.1.0"
BASE="$HOME/Documents/Baobab"
VENV="$BASE/.venv"
RV_APPS="$HOME/Applications"
CONFIG_DIR="$HOME/.ai-film-pipeline"

say()  { echo "  $*"; }
step() { echo; echo "== $*"; }
stop() { echo; echo "Stopped: $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Homebrew's own output goes here, and its last lines are shown only if a step fails.
LOG="$(mktemp "${TMPDIR:-/tmp}/baobab-install.XXXXXX")"
show_log() { echo; echo "  Homebrew said:"; tail -n 15 "$LOG" | sed 's/^/    /'; }
# A formula can install but fail its post-install step, and Homebrew then reports a failure. Retry that
# step once, for the formula and what it depends on, before giving up.
brew_install() {
  brew install -q "$1" >>"$LOG" 2>&1 && return 0
  brew list --formula "$1" >/dev/null 2>&1 || return 1
  say "$1 - finishing Homebrew's setup for it..."
  brew postinstall $(brew deps "$1") "$1" >>"$LOG" 2>&1
}
https_ok() { "$PY312" -c "import urllib.request; urllib.request.urlopen('https://github.com', timeout=20)" >>"$LOG" 2>&1; }

echo
echo "Baobab AI film tools - installer"
echo "This takes 10-20 minutes. Leave the window open until it says 'All done'."

# ------------------------------------------------------------------ 1. the basics
step "1/7  Checking this Mac"
[ "$(uname)" = "Darwin" ] || stop "this installer is for a Mac."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] || stop "this needs macOS 13 (Ventura) or later; this Mac has $(sw_vers -productVersion)."
free_gb=$(df -g "$HOME" | awk 'NR==2 {print $4}')
[ "$free_gb" -ge 15 ] || stop "only ${free_gb} GB free; the tools need about 15 GB."
case "$(uname -m)" in arm64) ARCH=arm64 ;; *) ARCH=x64 ;; esac
say "macOS $(sw_vers -productVersion), $ARCH, ${free_gb} GB free"
# Anaconda that switches itself on in every Terminal puts its Python in front of the tools' own (its
# setup runs after the PATH line this adds), so the tools would run without their packages.
CONDA_AUTO=""
conda_exe="${CONDA_EXE:-$(command -v conda || true)}"
if [ "${CONDA_DEFAULT_ENV:-}" = "base" ] || { [ -n "$conda_exe" ] && [ -x "$conda_exe" ] &&
     "$conda_exe" config --show auto_activate_base 2>/dev/null | grep -qi true; }; then
  CONDA_AUTO=1
  say "Anaconda switches itself on in this Terminal. Installing is fine; there's one step for you at the end."
fi

step "2/7  Installing the tools the studio's tools run on"
if ! have brew; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
fi
if ! have brew; then
  say "Homebrew - installing. It will ask for this Mac's password (typing shows nothing; that's normal)."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || stop "Homebrew didn't install. Run this again."
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
  have brew || stop "Homebrew installed but can't be found. Close Terminal, open it again, and rerun this."
fi
BREW_PREFIX="$(brew --prefix)"
for f in git python@3.12 ffmpeg gh; do
  if brew list --formula "$f" >/dev/null 2>&1; then say "$f - already installed"
  else say "$f - installing..."
       brew_install "$f" || { show_log; stop "$f didn't install. Run this again; if it stops here again, send this window's text to #shine-help."; }; fi
done
if brew list --cask google-cloud-sdk >/dev/null 2>&1 || have gcloud; then say "Google Cloud SDK - already installed"
else say "Google Cloud SDK - installing..."
     brew install -q --cask google-cloud-sdk >>"$LOG" 2>&1 || { show_log; stop "Google Cloud SDK didn't install. Run this again."; }; fi
PY312="$BREW_PREFIX/opt/python@3.12/bin/python3.12"
[ -x "$PY312" ] || stop "Python 3.12 isn't where Homebrew put it ($PY312). Run this again."
# Python's secure web connections need the certificates set up in those post-install steps. A run that
# half-failed before says "already installed" above, so check they work rather than trust it.
if ! https_ok; then
  say "Python can't make secure web connections yet - finishing Homebrew's setup..."
  brew postinstall ca-certificates openssl@3 python@3.12 >>"$LOG" 2>&1
  https_ok || { show_log; stop "Python can't make secure web connections. Check you're online, run this again, and if it stops here again send this window's text to #shine-help."; }
fi

# ------------------------------------------------------------------ 2. GitHub
step "3/7  Signing in to GitHub"
if ! gh auth status >/dev/null 2>&1; then
  say "A browser window will open. Sign in with the GitHub account you sent us, and enter the code shown here."
  gh auth login --web --git-protocol https --hostname github.com || stop "GitHub sign-in didn't finish. Run this again."
fi
gh auth setup-git >/dev/null 2>&1
say "signed in as $(gh api user --jq .login)"

# ------------------------------------------------------------------ 3. the repos
step "4/7  Getting the tools"
mkdir -p "$BASE/projects"
for r in "${REPOS[@]}"; do
  dest="$BASE/$r"
  if [ -d "$dest/.git" ]; then say "$r - already here (it updates itself when you start a session)"; continue; fi
  [ -e "$dest" ] && stop "$dest exists but isn't a copy of the tools. Move it aside and run this again."
  gh repo clone "$ORG/$r" "$dest" -- -q || stop "couldn't get $r. Have you accepted the GitHub invitation for it? Check your email, accept, and run this again."
  say "$r - done"
done

# ------------------------------------------------------------------ 4. Python
step "5/7  Setting up Python for the tools"
[ -x "$VENV/bin/python" ] || "$PY312" -m venv "$VENV" || stop "couldn't make the Python environment."
"$VENV/bin/python" -m pip install -q --upgrade pip
# Both repos' packages: the pipeline's (PyYAML) and the harness's (pillow, numpy, certifi).
for req in "$BASE/AIFilmPipeline/requirements.txt" "$BASE/NaraMediaHarness/requirements.txt"; do
  [ -f "$req" ] || continue
  "$VENV/bin/python" -m pip install -q -r "$req" || stop "installing the Python packages failed. Run this again."
done
# The tools call `python`; put this environment first so that is the one they get (a Mac has no `python` otherwise).
LINE="export PATH=\"$VENV/bin:\$PATH\"   # Baobab AI film tools"
for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
  grep -qF "# Baobab AI film tools" "$rc" 2>/dev/null || { echo "$LINE" >> "$rc"; say "added the tools' Python to your PATH ($(basename "$rc"))"; }
done
export PATH="$VENV/bin:$PATH"
say "Python ready"

# ------------------------------------------------------------------ 5. RV
step "6/7  Installing RV (the review player)"
RV_EXE="$RV_APPS/RV.app/Contents/MacOS/RV"
ASSET="OpenRV-$OPENRV_VERSION-macos-$ARCH.zip"
INFO="BUILD_INFO-macos-$ARCH.txt"
if [ -x "$RV_EXE" ]; then
  say "RV - already installed"
elif ! gh release view "$OPENRV_TAG" --repo "$ORG/openrv-builds" --json assets --jq '.assets[].name' 2>/dev/null | grep -qx "$ASSET"; then
  say "RV for this Mac isn't ready yet. Everything else works; run this installer again later to add it."
  RV_EXE=""
else
  tmp="$(mktemp -d)"
  say "downloading RV (about 1 GB)..."
  gh release download "$OPENRV_TAG" --repo "$ORG/openrv-builds" --pattern "$ASSET" --pattern "$INFO" --dir "$tmp" \
    || stop "couldn't download RV. Have you accepted the GitHub invitation for openrv-builds?"
  want="$(grep -oE 'SHA-256:[[:space:]]*[0-9a-f]{64}' "$tmp/$INFO" | grep -oE '[0-9a-f]{64}')"
  got="$(shasum -a 256 "$tmp/$ASSET" | cut -d' ' -f1)"
  [ -n "$want" ] && [ "$got" = "$want" ] || stop "the RV download is damaged (checksum mismatch). Run this again."
  mkdir -p "$RV_APPS"
  say "unpacking RV..."
  ditto -x -k "$tmp/$ASSET" "$RV_APPS" || stop "couldn't unpack RV."
  [ -x "$RV_EXE" ] || stop "RV unpacked but the app isn't where expected."
  say "RV - installed in ~/Applications. The first time it opens, macOS may block it: right-click RV, choose Open, then Open."
fi

# ------------------------------------------------------------------ 6. config
# Where the tools are and where RV is, for the pipeline (pipeline/harness.py, pipeline/rv.py) and the
# harness (tools/rv_session.py). Only these two keys are set; anything else in the file is kept.
mkdir -p "$CONFIG_DIR"
cfg="$CONFIG_DIR/config.yaml"
{ [ -f "$cfg" ] && grep -vE '^(harness_root|rv_exe):' "$cfg"
  echo "harness_root: '$BASE/NaraMediaHarness'"
  [ -n "$RV_EXE" ] && echo "rv_exe: '$RV_EXE'"
} > "$cfg.new" && mv "$cfg.new" "$cfg"

# ------------------------------------------------------------------ 7. check
step "7/7  Checking everything works"
(cd "$BASE/NaraMediaHarness" && python tools/preflight.py)
(cd "$BASE/AIFilmPipeline" && python aifp.py harness)
if [ ! -d "/Applications/Claude.app" ] && [ ! -d "$HOME/Applications/Claude.app" ]; then
  say "The Claude desktop app isn't installed yet - opening the download page. Install it and sign in with your studio seat."
  open "https://claude.ai/download"
fi

echo
echo "All done."
echo "Next: open the Claude app, go to the Code tab, open this folder:"
echo "    $BASE/AIFilmPipeline"
echo "and say:  Set me up"
echo "(If preflight above listed anything as missing, 'Set me up' walks you through it.)"
if [ -n "$CONDA_AUTO" ]; then
  echo
  echo "One step for you first: Anaconda switches itself on in every Terminal window, which puts its"
  echo "Python in front of the tools' own. Stop it doing that (you can still type 'conda activate'"
  echo "whenever you want it) by running this, then closing Terminal:"
  echo "    conda config --set auto_activate_base false"
fi
