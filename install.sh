#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${HOME}/.claude/skills"
HOOKS_DEST_DIR="${HOME}/.claude/hooks"
CMUX_VERSION="0.64.17"
# Pinned to the upstream tag matching CMUX_VERSION (verified: `git ls-remote --tags
# https://github.com/manaflow-ai/cmux.git` resolves refs/tags/v0.64.17 to this commit,
# which also matches this machine's installed `cmux --version` build hash). Pinning by
# commit SHA (not the `main` branch) means skills.sh content here cannot change out from
# under us between installs.
UPSTREAM_CMUX_REF="9ed29d81a39de3ba44e0654bbcf6bf67ca86d1fb"

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
  curl -fsSL "https://raw.githubusercontent.com/manaflow-ai/cmux/${UPSTREAM_CMUX_REF}/skills.sh" \
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
  copy_kit_skill "cmux-browser-human"
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

install_guard_hook() {
  local src="${SCRIPT_DIR}/hooks/guard-cmux.sh"
  local dest="${HOOKS_DEST_DIR}/guard-cmux.sh"

  [[ -f "$src" ]] || die "Missing kit hook source: ${src}"

  info "cmux-kit ships a PreToolUse hook (hooks/guard-cmux.sh) that fail-closes on"
  info "'cmux browser' mutation subcommands (click/type/fill/press/select/eval/...)"
  info "targeting a non-dev-shaped URL. Without it, the Bash(cmux:*) permission this"
  info "installer grants has no mechanical backstop against acting on production-like"
  info "pages by mistake."

  if ! confirm "Install and register the cmux browser-mutation guard hook now?"; then
    info "Skipped. You can install it later by re-running ./install.sh, or manually:"
    info "  cp ${src} ${dest}"
    info '  Register it in ~/.claude/settings.json under hooks.PreToolUse (matcher "Bash").'
    return
  fi

  mkdir -p "$HOOKS_DEST_DIR"
  if [[ -e "$dest" ]] && diff -q "$src" "$dest" >/dev/null 2>&1; then
    info "Guard hook already up to date at ${dest}."
  else
    if [[ -e "$dest" ]]; then
      local backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
      info "Backing up existing ${dest} to ${backup}"
      cp "$dest" "$backup"
    fi
    cp "$src" "$dest"
    chmod +x "$dest"
    info "Copied guard hook to ${dest}."
  fi

  register_guard_hook "$dest"
}

register_guard_hook() {
  local hook_path="$1"
  local hook_cmd="\$HOME/.claude/hooks/guard-cmux.sh"

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found — skipping automatic hook registration."
    warn 'Add this manually to ~/.claude/settings.json under "hooks.PreToolUse":'
    warn '  {"matcher": "Bash", "hooks": [{"type": "command", "command": "'"$hook_cmd"'"}]}'
    return
  fi

  local settings_path="${HOME}/.claude/settings.json"
  mkdir -p "${HOME}/.claude"

  local real_path="$settings_path"
  if [[ -L "$settings_path" ]]; then
    real_path="$(readlink -f "$settings_path" 2>/dev/null || python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$settings_path")"
  fi

  if [[ ! -e "$real_path" ]]; then
    info "Creating ${real_path} with the guard hook registered."
    jq -n --arg cmd "$hook_cmd" \
      '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $cmd}]}]}}' \
      > "$real_path"
    return
  fi

  if ! jq -e . "$real_path" >/dev/null 2>&1; then
    warn "${real_path} is not valid JSON — skipping automatic hook registration."
    warn 'Add this manually under "hooks.PreToolUse":'
    warn '  {"matcher": "Bash", "hooks": [{"type": "command", "command": "'"$hook_cmd"'"}]}'
    return
  fi

  if jq -e --arg cmd "$hook_cmd" \
      '.hooks.PreToolUse // [] | any(.matcher == "Bash" and ((.hooks // []) | any(.command == $cmd)))' \
      "$real_path" >/dev/null 2>&1; then
    info "Guard hook already registered in ${real_path}."
    return
  fi

  local backup="${real_path}.backup.$(date +%Y%m%d%H%M%S)"
  cp "$real_path" "$backup"
  info "Backed up existing settings to ${backup}"

  local tmp
  tmp="$(mktemp)"
  jq --arg cmd "$hook_cmd" '
    .hooks = (.hooks // {}) |
    .hooks.PreToolUse = (.hooks.PreToolUse // []) |
    (.hooks.PreToolUse | map(.matcher == "Bash") | index(true)) as $i |
    if $i == null then
      .hooks.PreToolUse += [{matcher: "Bash", hooks: [{type: "command", command: $cmd}]}]
    else
      .hooks.PreToolUse[$i].hooks = ((.hooks.PreToolUse[$i].hooks // []) + [{type: "command", command: $cmd}] | unique_by(.command))
    end
  ' "$real_path" > "$tmp" && mv "$tmp" "$real_path"
  info "Registered guard-cmux.sh in ${real_path} (merged with existing hooks)."
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
  local theme_err
  theme_err="$(mktemp -t cmux-kit-theme-err.XXXXXX)"
  if ! python3 "${SCRIPT_DIR}/theme/extract-terminal-theme.py" > "$ghostty_config" 2>"$theme_err"; then
    warn "Could not extract your Terminal.app theme ($(cat "$theme_err"))."
    warn "You can copy ${SCRIPT_DIR}/theme/ghostty-config.example manually instead."
    rm -f "$ghostty_config" "$theme_err"
    return
  fi
  rm -f "$theme_err"

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
  install_guard_hook
  configure_theme
  print_next_steps
}

main "$@"
