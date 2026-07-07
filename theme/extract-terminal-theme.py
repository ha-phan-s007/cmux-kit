#!/usr/bin/env python3
"""
Extract the active macOS Terminal.app profile (font + 16-color ANSI palette +
background/foreground) and print it as a Ghostty config block.

Cmux is built on libghostty and reads ~/.config/ghostty/config for terminal
appearance, so writing this output there makes Cmux panes visually match your
existing Terminal.app theme.

Usage:
    python3 theme/extract-terminal-theme.py > ~/.config/ghostty/config
    cmux reload-config

Terminal.app profile font/color fields are stored as NSKeyedArchiver-encoded
NSFont/NSColor blobs inside the plist (not plain values), so this parses that
inner archive structure directly rather than shelling out to `defaults`.
"""
import plistlib
import sys
from pathlib import Path

PLIST_PATH = Path.home() / "Library/Preferences/com.apple.Terminal.plist"


def load_plist():
    if not PLIST_PATH.exists():
        sys.exit(f"Terminal.app preferences not found at {PLIST_PATH}")
    with open(PLIST_PATH, "rb") as f:
        return plistlib.load(f)


def active_profile_name(data):
    # "Default Window Settings" holds the name of the profile used for new
    # windows — this is what a user perceives as "my Terminal theme".
    name = data.get("Default Window Settings") or data.get("Startup Window Settings")
    if not name:
        profiles = list(data.get("Window Settings", {}).keys())
        sys.exit(
            "Could not detect the default Terminal.app profile. "
            f"Available profiles: {profiles}. "
            "Pass one as an argument, e.g.: extract-terminal-theme.py 'Pro'"
        )
    return name


def parse_font(raw_font_data):
    inner = plistlib.loads(bytes(raw_font_data))
    objs = inner.get("$objects", [])
    size = None
    name = None
    for o in objs:
        if isinstance(o, dict) and "NSSize" in o:
            size = o["NSSize"]
        if isinstance(o, str) and o not in ("$null", "NSFont", "NSObject"):
            # Heuristic: the font PostScript name is the plain string object
            # in the archive that isn't a class name.
            if name is None:
                name = o
    return name, size


def parse_color_hex(raw_color_data):
    inner = plistlib.loads(bytes(raw_color_data))
    for o in inner.get("$objects", []):
        if isinstance(o, dict) and "NSRGB" in o:
            s = o["NSRGB"].decode("ascii", errors="ignore").strip("\x00").strip()
            parts = [float(x) for x in s.split()]
            r, g, b = parts[0], parts[1], parts[2]
            return "#{:02x}{:02x}{:02x}".format(
                round(r * 255), round(g * 255), round(b * 255)
            ), (parts[3] if len(parts) > 3 else 1.0)
    return None, None


ANSI_KEYS = [
    "ANSIBlackColor", "ANSIRedColor", "ANSIGreenColor", "ANSIYellowColor",
    "ANSIBlueColor", "ANSIMagentaColor", "ANSICyanColor", "ANSIWhiteColor",
    "ANSIBrightBlackColor", "ANSIBrightRedColor", "ANSIBrightGreenColor",
    "ANSIBrightYellowColor", "ANSIBrightBlueColor", "ANSIBrightMagentaColor",
    "ANSIBrightCyanColor", "ANSIBrightWhiteColor",
]


def main():
    data = load_plist()
    profile_name = sys.argv[1] if len(sys.argv) > 1 else active_profile_name(data)
    profile = data.get("Window Settings", {}).get(profile_name)
    if not profile:
        available = list(data.get("Window Settings", {}).keys())
        sys.exit(f'Profile "{profile_name}" not found. Available: {available}')

    font_name, font_size = (None, None)
    if profile.get("Font"):
        font_name, font_size = parse_font(profile["Font"])

    bg_hex, bg_alpha = (None, None)
    if profile.get("BackgroundColor"):
        bg_hex, bg_alpha = parse_color_hex(profile["BackgroundColor"])

    fg_hex, _ = (None, None)
    if profile.get("TextColor"):
        fg_hex, _ = parse_color_hex(profile["TextColor"])

    sel_hex, _ = (None, None)
    if profile.get("SelectionColor"):
        sel_hex, _ = parse_color_hex(profile["SelectionColor"])

    palette = {}
    for i, key in enumerate(ANSI_KEYS):
        raw = profile.get(key)
        if raw:
            hex_val, _ = parse_color_hex(raw)
            if hex_val:
                palette[i] = hex_val

    print(f"# Ghostty config generated from Terminal.app profile \"{profile_name}\"")
    print("# by cmux-kit/theme/extract-terminal-theme.py — review before using.")
    print()
    if font_name:
        print(
            f"# NOTE: \"{font_name}\" is the font's PostScript name, not always "
            "the Ghostty family name."
        )
        print(f'# Verify with: fc-list | grep -i "{font_name.split("-")[0]}"')
        print(f"font-family = {font_name}")
    if font_size:
        print(f"font-size = {int(font_size)}")
    print()
    if bg_hex:
        print(f"background = {bg_hex}")
    if fg_hex:
        print(f"foreground = {fg_hex}")
    if bg_alpha and bg_alpha < 1.0:
        print(f"background-opacity = {round(bg_alpha, 2)}")
    if sel_hex:
        print(f"selection-background = {sel_hex}")
    if fg_hex:
        print(f"cursor-color = {fg_hex}")
    print()
    if palette:
        print("# ANSI 0-7 (normal) then 8-15 (bright)")
        for i in sorted(palette):
            print(f"palette = {i}={palette[i]}")


if __name__ == "__main__":
    main()
