# kutu

Workspace containers for macOS. A box is a named set of windows; switching boxes parks every window not in the target box far off-screen via the Accessibility API.

## Requirements
macOS 14+, Stage Manager off, Accessibility permission.

## Install

    scripts/build-app.sh kutu-app ca.halit.kutu Kutu
    swift build -c release --product kutu
    open ~/Applications/Kutu.app
    scripts/install-claude-hooks.sh   # optional: live Claude Code status

Grant Accessibility to Kutu when prompted.

### Signing

The build signs ad-hoc by default, so the above works with no Apple account.
The cost is that macOS identifies an ad-hoc signature by its hash: every
rebuild looks like a new app, so you have to remove Kutu from
Privacy & Security > Accessibility and grant it again.

To keep the grant across rebuilds, sign with a certificate. A free Apple ID is
enough — add it in Xcode > Settings > Accounts and it will issue an
`Apple Development` certificate under a personal team. No paid membership is
involved; that is only needed to distribute builds to other people.

    security find-identity -v -p codesigning
    export KUTU_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"

## Configure

`~/.config/kutu/boxes.toml`:

    hotkey = "alt+space"
    move_hotkey = "alt+shift+space"
    [[box]]
    name = "myproject"
    dir  = "~/code/myproject"

`kutu.toml` in a box directory, read by `kutu open`/`kutu register`:

    name = "myproject"
    [[app]]
    kind = "iterm"
    cmd  = "claude"

## kutu.toml is executable

`cmd` in an `[[app]]` block is a shell command line, run as you when you
`kutu open` that box. Treat a kutu.toml from a repo you did not write the way
you would treat its Makefile — read it first. `kutu register` prints the exact
commands the manifest produces, every time you run it; that output is the thing
to check.

Only `kind = "iterm"` interprets a shell line. The other kinds build an argument
list for `open` and pass no shell.

## Use
`⌥Space` switch boxes, `⌥⇧Space` move the frontmost window to a box.
`kutu go/open/ls/register/reload/move/status/panic`. If something goes wrong: unpark everything in the menu bar, or `kutu panic`.

## Known limits

- single display only — park coordinates and the corner chip use the main screen
- depends on `_AXUIElementGetWindow`, a private API, so it could break in a macOS update and it cannot ship on the Mac App Store
- Stage Manager must be off — it clamps windows differently and kutu refuses to park while it is on
- `kutu open` hydration is lightly tested
