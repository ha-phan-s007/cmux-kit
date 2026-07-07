#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${HOME}/.claude/skills"
CMUX_VERSION="0.64.17"

info() {
  printf '==> %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1" >&2
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

confirm() {
  local prompt="$1"
  local answer

  printf '%s [y/N] ' "$prompt"
  if ! read -r answer; then
    return 1
  fi

  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

version_major() {
  printf '%s' "$1" | awk -F. '{print $1}'
}

check_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "cmux-kit requires macOS 14+."

  local version
  version="$(sw_vers -productVersion)"
  local major
  major="$(version_major "$version")"

  [[ "$major" =~ ^[0-9]+$ ]] || die "Cannot parse macOS version: $version"
  (( major >= 14 )) || die "cmux-kit requires macOS 14+; detected macOS $version."
}

check_brew() {
  command -v brew >/dev/null 2>&1 || die "Homebrew is required. Install it from https://brew.sh, then rerun ./install.sh."
}

cmux_installed() {
  command -v cmux >/dev/null 2>&1 && return 0
  [[ -d "/Applications/cmux.app" ]] && return 0
  [[ -d "${HOME}/Applications/cmux.app" ]] && return 0
  return 1
}

install_cmux_if_needed() {
  if cmux_installed; then
    info "Cmux is already installed."
    return
  fi

  warn "Cmux app was not found."
  if ! confirm "Install Cmux via Homebrew now?"; then
    die "Cmux is required. Install with: brew tap manaflow-ai/cmux && brew install --cask cmux"
  fi

  info "Installing Cmux via Homebrew..."
  brew tap manaflow-ai/cmux
  brew install --cask cmux
}

install_official_skills() {
  info "Installing official Cmux skills into ${DEST_DIR}..."
  mkdir -p "$DEST_DIR"
  curl -fsSL https://raw.githubusercontent.com/manaflow-ai/cmux/main/skills.sh \
    | bash -s -- \
      --dest "$DEST_DIR" \
      --skill cmux \
      --skill cmux-browser \
      --skill cmux-workspace \
      --skill cmux-diagnostics
}

copy_kit_skill() {
  local skill="$1"
  local src="${SCRIPT_DIR}/skills/${skill}"
  local dest="${DEST_DIR}/${skill}"

  [[ -d "$src" ]] || die "Missing kit skill source: ${src}"

  mkdir -p "$DEST_DIR"

  if [[ -e "$dest" ]]; then
    if diff -qr "$src" "$dest" >/dev/null 2>&1; then
      info "Kit skill ${skill} is already up to date."
      return
    fi

    local backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
    info "Backing up existing ${dest} to ${backup}"
    mv "$dest" "$backup"
  fi

  info "Copying kit skill ${skill}..."
  cp -R "$src" "$dest"
}

copy_kit_skills() {
  copy_kit_skill "ask-gemini"
  copy_kit_skill "qc-browse"
}

configure_permissions() {
  info "Configuring permission allowlist for cmux CLI (Bash(cmux:*))..."

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found — skipping automatic permission setup."
    warn 'Add this manually to ~/.claude/settings.json: {"permissions":{"allow":["Bash(cmux:*)"]}}'
    return
  fi

  local settings_path="${HOME}/.claude/settings.json"
  mkdir -p "${HOME}/.claude"

  # Resolve through symlinks (e.g. dotfiles-managed settings.json) so we write
  # the real file, not a symlink target that fails on some systems.
  local real_path="$settings_path"
  if [[ -L "$settings_path" ]]; then
    real_path="$(readlink -f "$settings_path" 2>/dev/null || python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$settings_path")"
  fi

  if [[ ! -e "$real_path" ]]; then
    info "Creating ${real_path} with the cmux permission rule."
    printf '{\n  "permissions": {\n    "allow": [\n      "Bash(cmux:*)"\n    ]\n  }\n}\n' > "$real_path"
    return
  fi

  if ! jq -e . "$real_path" >/dev/null 2>&1; then
    warn "${real_path} is not valid JSON — skipping automatic permission setup."
    warn 'Add this manually: {"permissions":{"allow":["Bash(cmux:*)"]}}'
    return
  fi

  if jq -e '.permissions.allow // [] | index("Bash(cmux:*)")' "$real_path" >/dev/null 2>&1; then
    info "Permission rule Bash(cmux:*) already present."
    return
  fi

  local backup="${real_path}.backup.$(date +%Y%m%d%H%M%S)"
  cp "$real_path" "$backup"
  info "Backed up existing settings to ${backup}"

  local tmp
  tmp="$(mktemp)"
  jq '.permissions.allow = ((.permissions.allow // []) + ["Bash(cmux:*)"] | unique)' "$real_path" > "$tmp" \
    && mv "$tmp" "$real_path"
  info "Added Bash(cmux:*) to ${real_path} (merged with existing permissions)."
}

configure_theme() {
  local ghostty_config="${HOME}/.config/ghostty/config"

  if [[ -e "$ghostty_config" ]]; then
    info "~/.config/ghostty/config already exists — leaving your theme as-is."
    info "To match your Terminal.app theme later, run: python3 ${SCRIPT_DIR}/theme/extract-terminal-theme.py"
    return
  fi

  if ! confirm "No Ghostty/Cmux terminal theme configured yet. Generate one from your current Terminal.app profile?"; then
    info "Skipped. A reference theme is available at ${SCRIPT_DIR}/theme/ghostty-config.example."
    return
  fi

  mkdir -p "${HOME}/.config/ghostty"
  if ! python3 "${SCRIPT_DIR}/theme/extract-terminal-theme.py" > "$ghostty_config" 2>/tmp/cmux-kit-theme-err; then
    warn "Could not extract your Terminal.app theme ($(cat /tmp/cmux-kit-theme-err))."
    warn "You can copy ${SCRIPT_DIR}/theme/ghostty-config.example manually instead."
    rm -f "$ghostty_config"
    return
  fi

  info "Wrote ${ghostty_config} from your Terminal.app profile."
  info "Review the font-family line (PostScript vs. family name caveat is noted inline)."
  if cmux_installed && command -v cmux >/dev/null 2>&1; then
    cmux reload-config 2>/dev/null && info "Reloaded Cmux config." || true
  fi
}

print_next_steps() {
  cat <<EOF

cmux-kit install complete.

Next steps:
1. Open the Cmux app.
2. Open a terminal pane inside Cmux.
3. cd into your project.
4. Run claude from that Cmux pane.
5. First Gemini use: open https://gemini.google.com in the Cmux browser surface and login with your mouse once.

Important socket policy: Claude Code must run inside a Cmux pane. Running Claude outside Cmux will not be allowed to control the browser socket.

Packaged with Cmux version reference: ${CMUX_VERSION}
EOF
}

main() {
  check_macos
  check_brew
  install_cmux_if_needed
  install_official_skills
  copy_kit_skills
  configure_permissions
  configure_theme
  print_next_steps
}

main "$@"
