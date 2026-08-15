# kutu

Workspace containers for macOS. A box is a named set of windows; switching boxes parks every window not in the target box far off-screen via the Accessibility API.

## Requirements
macOS 14+, Stage Manager off, Accessibility permission, a code-signing identity (`security find-identity -v -p codesigning`).

## Install

    export KUTU_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
    scripts/build-app.sh kutu-app co.halit.kutu Kutu
    swift build -c release --product kutu
    open ~/Applications/Kutu.app
    scripts/install-claude-hooks.sh   # optional: live Claude Code status

Grant Accessibility to Kutu when prompted.

## Configure

`~/.config/kutu/boxes.toml`:

    hotkey = "alt+space"
    move_hotkey = "alt+shift+space"
    [[box]]
    name = "orchard"
    dir  = "~/workspace/orchard"

`kutu.toml` in a box directory, read by `kutu open`/`kutu register`:

    name = "orchard"
    [[app]]
    kind = "iterm"
    cmd  = "claude"

## Use
`⌥Space` switch boxes, `⌥⇧Space` move the frontmost window to a box.
`kutu go/open/ls/register/reload/move/status/panic`. If something goes wrong: unpark everything in the menu bar, or `kutu panic`.

## Known limits

- single display only — park coordinates and the corner chip use the main screen
- depends on `_AXUIElementGetWindow`, a private API, so it could break in a macOS update and it cannot ship on the Mac App Store
- Stage Manager must be off — it clamps windows differently and kutu refuses to park while it is on
- `kutu open` hydration is lightly tested
