# kutu

Workspace containers for macOS. A *box* is a named development context that
owns a set of windows; switching boxes hides every window that is not in the
target box, without using Spaces — so cmd+tab can never teleport you somewhere
unexpected.

## Requirements

- macOS 14+
- **Stage Manager must be off.** It intercepts window positioning and leaves a
  284px fragment of every hidden window on screen.
- Accessibility permission
- A code-signing identity (`security find-identity -v -p codesigning`)

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
    pinned = ["com.spotify.client"]
    cmd_tab = "notify"   # or "switch" for the old auto-switch behaviour

    [[box]]
    name = "orchard"
    dir  = "~/workspace/orchard"

Optional `kutu.toml` in a box directory declares what `kutu open` launches:

    name = "orchard"

    [[app]]
    kind = "iterm"
    cmd  = "claude"

    [[app]]
    kind    = "chrome"
    profile = "orchard"
    urls    = ["http://localhost:3000"]

## Use

- `⌥Space` — palette; type to filter, Enter to switch
- Menu bar — box list with live Claude status, unpark everything, reload config
- `kutu go <box>` / `kutu open <box>` / `kutu ls` / `kutu panic`
- `kutu status <box> working|waiting|idle` — light up a box from any tool
- cmd+tab to an app whose windows are all in another box does **not** switch
  you there by default — it briefly shows which box the app lives in, and you
  switch on purpose with `⌥Space`. Set `cmd_tab = "switch"` in `boxes.toml` to
  restore the old auto-switch-on-activate behaviour.

kutu has no dependency on Claude Code. Boxes are just windows plus an optional
directory. The status dot is a generic channel: Claude Code's hooks are one
optional adapter, and anything else can report the same way:

    echo '{"kutu":"status","arg":"myBox","state":"working"}' \
      | nc -U ~/.local/state/kutu/kutu.sock

Windows you never classify live in `lobby`. Windows opened while a box is
active join that box. Pinned applications stay visible in every box.

## If something goes wrong

A crash leaves your windows recoverable: kutu reconciles at launch, restoring
anything that belongs in the active box, and "Unpark everything" restores the
rest.

## Tests

    swift test          # pure logic
    scripts/axcheck.sh  # accessibility integration, needs its own grant
