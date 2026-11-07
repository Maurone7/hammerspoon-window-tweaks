# hammerspoon-window-tweaks

Small [Hammerspoon](https://www.hammerspoon.org) Spoons that fix macOS window annoyances. Each one can be turned on separately.

| Spoon | What it does |
| --- | --- |
| **FullscreenTrafficLights** | Keeps red/yellow/green buttons visible on every fullscreen window, focused or not. Normally macOS hides them until you hover at the top of the screen. |
| **FinderCut** | Cmd+X then Cmd+V cuts and moves files in Finder. |
| **ClickThrough** | One click on an inactive app's window both activates it and clicks what's under the mouse, so you don't have to click twice. |
| **WindowSnap** | [Rectangle](https://rectangleapp.com)-style window snapping: keyboard shortcuts for halves, thirds, quarters and more, and drag a window to a screen edge to snap it. |
| **WindowTweaksMenu** | A menu-bar icon to turn the others on and off, snap the focused window, reset button positions and reload the config. |

## Install

1. Install Hammerspoon:

   ```sh
   brew install --cask hammerspoon
   ```

2. Get the Spoons, using either option:

   - **From a release:** download the `.spoon.zip` files you want from the [latest release](https://github.com/Maurone7/hammerspoon-window-tweaks/releases/latest). Unzip them and double-click each `.spoon` to install it.
   - **With git:**

     ```sh
     git clone https://github.com/Maurone7/hammerspoon-window-tweaks.git
     cd hammerspoon-window-tweaks
     ./install.sh          # copies the Spoons into ~/.hammerspoon/Spoons
     ./install.sh --link   # or symlink them, so `git pull` updates them
     ```

3. Add the Spoons you want to `~/.hammerspoon/init.lua`. Load the menu last, so it can control the others:

   ```lua
   hs.loadSpoon("FullscreenTrafficLights"):start()
   hs.loadSpoon("FinderCut"):start()
   hs.loadSpoon("ClickThrough"):start()
   hs.loadSpoon("WindowSnap"):start()
   hs.loadSpoon("WindowTweaksMenu"):start()
   ```

4. Open Hammerspoon and choose **Reload Config** from its menu-bar icon.

5. Give Hammerspoon **Accessibility** permission in System Settings → Privacy & Security → Accessibility. If you just turned it on, quit and reopen Hammerspoon, because macOS often doesn't apply the permission until the app restarts.

## FullscreenTrafficLights

In native fullscreen, macOS hides the window buttons until you hover at the top of the screen. That hover reveal often doesn't work, for example when the menu bar is set to always show in fullscreen. This Spoon draws working stand-ins on every fullscreen window currently on screen:

- **Red** closes the window.
- **Yellow** exits fullscreen and then minimizes, since macOS can't minimize a fullscreen window.
- **Green** exits fullscreen.

Hover over the buttons to see their ×, − and ↙ symbols.

**Moving them:**
- **Option-drag** the buttons anywhere, including up into the menu-bar strip. The position is saved per app.
- **Option-double-click** them to put that app's buttons back at the default position.
- To reset every app, use **Reset Button Positions** in the WindowTweaksMenu, or run:

  ```lua
  spoon.FullscreenTrafficLights:resetPositions()
  ```

**Options:** set these before `:start()`.

```lua
hs.loadSpoon("FullscreenTrafficLights")
spoon.FullscreenTrafficLights.size = 12                         -- button diameter (points)
spoon.FullscreenTrafficLights.gap = 8                           -- space between buttons
spoon.FullscreenTrafficLights.defaultOffset = { x = 12, y = 10 } -- from window's top-left
spoon.FullscreenTrafficLights.interval = 0.5                    -- seconds between position updates
spoon.FullscreenTrafficLights.scanInterval = 3                  -- fallback scan for new fullscreen windows
spoon.FullscreenTrafficLights:start()
```

These are copies drawn over the window, not the system's own buttons. They appear as soon as a window enters fullscreen, because that switches Spaces and triggers a scan. A slower background scan every `scanInterval` seconds catches anything missed.

## FinderCut

Finder can't cut files. You have to copy and then use Cmd+Option+V ("Move Item Here"). With this Spoon:

- **Cmd+X** copies the selected files and marks them to be moved.
- **Cmd+V** in another folder then moves them instead of copying.
- **Copying anything else**, in Finder or any other app, cancels a pending cut, so Cmd+V never moves files you didn't cut. Cmd+X with nothing selected does nothing.

While you're editing text, such as renaming a file or typing in the search field, the keys behave normally. Other apps are not affected.

## ClickThrough

macOS normally uses your first click on an inactive app's window just to activate it. With this Spoon, that click is held for a moment while the app activates, then replayed, so buttons, links and text positions respond to the first click.

- Clicks in the active app, the Dock, the menu bar and the desktop are not affected. Neither are clicks on a window's title bar, empty background or its own traffic lights, which already work on the first click.
- **Cmd-click** keeps its standard macOS meaning: click in a background window without bringing it forward.
- The first click can lag by up to `activationTimeout` seconds (default `0.3`) while the app comes forward. Drags that start on an inactive window are held and replayed too, so they arrive complete.

## WindowSnap

Does what [Rectangle](https://rectangleapp.com) does, with the same default shortcuts except for the corners. Instead of ⌃⌥U/I/J/K, hold two arrows together: ⌃⌥↑ then → (or → then ↑) snaps to the top right. The first arrow snaps to that half, and the second turns it into the corner. Holding ⌃⌥↑ and ↓ together toggles native macOS fullscreen, at the size the window had before the first arrow. If you also have Rectangle installed, quit it, or the two will fight over the shortcuts.

| Action | Shortcut |
| --- | --- |
| Left / Right / Top / Bottom Half | ⌃⌥← / ⌃⌥→ / ⌃⌥↑ / ⌃⌥↓ |
| Top Left / Top Right / Bottom Left / Bottom Right | ⌃⌥↑← / ⌃⌥↑→ / ⌃⌥↓← / ⌃⌥↓→ (hold both arrows) |
| First / Center / Last Third | ⌃⌥D / ⌃⌥F / ⌃⌥G |
| First / Last Two Thirds | ⌃⌥E / ⌃⌥T |
| Maximize | ⌃⌥↩ |
| Toggle native fullscreen | ⌃⌥↑↓ (hold both arrows) |
| Maximize Height | ⌃⌥⇧↑ |
| Make Smaller / Larger | ⌃⌥- / ⌃⌥= |
| Center | ⌃⌥C |
| Restore | ⌃⌥⌫ |
| Next / Previous Display | ⌃⌥⌘→ / ⌃⌥⌘← |

Center Half, Almost Maximize, fourths, sixths and Move Left/Right/Up/Down have no shortcut by default, like in Rectangle. They're in the menu, and you can give them one (see below).

- **Press a half again** to cycle its size through 1/2, 2/3 and 1/3 of the screen.
- **Thirds and fourths** are columns on a landscape screen and rows on a portrait one.
- **Make Smaller / Larger** keep any edge that touches the screen edge in place, and repeat while held.
- **Restore** puts the window back where it was before you first snapped it.
- **Drag to snap:** drag a window by its title bar to a screen edge or corner. A preview shows where it will go, and it snaps when you let go:
  - left or right edge: that half
  - top edge: maximize
  - corners: that quarter
  - bottom edge: the third of the screen under the mouse
- **Drag a snapped window away** and it gets its old size back.
- **Apps with a minimum size** that can't shrink to a third or a half are kept fully on screen instead of hanging off the edge.
- **Gaps and drag to snap** can be changed from the menu (Snap Window → Gaps Between Windows, Drag to Snap). Changes apply right away and are remembered over what `init.lua` sets.
- **Fullscreen windows:** any snapping shortcut on a fullscreen window takes it out of fullscreen first, then snaps it. ⌃⌥⌘←/→ moves it to the other display and keeps it fullscreen. Each step waits for macOS's fullscreen animation to finish, since moving a window during it cancels the exit.
- **Fullscreen apps and multiple displays:** A normal window skips any display that's showing a fullscreen app, since macOS would hide it behind that app. Drag to snap doesn't snap onto such a display either.
- **Games and other apps that draw their own windows** (Victoria 3 and many other Steam games) often don't let Accessibility see or move their window, and don't support macOS fullscreen. WindowSnap can't move them; it shows a message instead. Use the game's own display settings to change its window mode and monitor.
- **Ignore an app** from the menu (Snap Window → Ignore *App*) to leave its windows alone and let it have the shortcuts.
- Fullscreen windows and panels, dialogs and other non-standard windows are left alone.

macOS has its own tiling when you drag a window to a screen edge. To stop it from fighting drag to snap, turn off **Drag windows to screen edges to tile** in System Settings → Desktop & Dock → Windows. Or turn off drag to snap here with `dragToSnap = false`.

**Options:** set these before `:start()`. `gap` and `dragToSnap` changed from the menu take precedence; run `hs.settings.clear("windowSnap.options")` to go back to the `init.lua` values.

```lua
hs.loadSpoon("WindowSnap")
spoon.WindowSnap.gap = 10                          -- space between windows and around the screen edges
spoon.WindowSnap.cycleSizes = { 1/2, 2/3, 1/3 }    -- sizes a half cycles through
spoon.WindowSnap.arrowCorners = true               -- two half shortcuts held together: corner, or ↑↓ fullscreen
spoon.WindowSnap.sizeStep = 30                     -- points Make Smaller/Larger move each edge
spoon.WindowSnap.dragToSnap = true                 -- snap windows dragged to a screen edge
spoon.WindowSnap.snapMargin = 5                    -- how close to the edge the mouse must get
spoon.WindowSnap.cornerSize = 30                   -- how far corner areas reach along each edge
spoon.WindowSnap.ignoredApps = { "com.apple.FinalCut" } -- bundle IDs never to snap
spoon.WindowSnap.fullscreenExitWait = 0.1          -- seconds after leaving fullscreen before moving to another display
spoon.WindowSnap:start()
```

**Changing shortcuts:** `bindHotkeys` replaces all of them, so copy the ones you want to keep from `spoon.WindowSnap.hotkeys`:

```lua
local keys = spoon.WindowSnap.hotkeys
keys.almostMaximize = { { "ctrl", "alt", "shift" }, "return" }
keys.centerHalf = { { "ctrl", "alt", "shift" }, "c" }
keys.restore = nil -- no shortcut
keys.topLeft = { { "ctrl", "alt" }, "u" } -- Rectangle's corner keys, alongside the arrow chords
spoon.WindowSnap:bindHotkeys(keys)
```

Action names: `leftHalf`, `rightHalf`, `centerHalf`, `topHalf`, `bottomHalf`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `firstThird`, `centerThird`, `lastThird`, `firstTwoThirds`, `lastTwoThirds`, `firstFourth`, `secondFourth`, `thirdFourth`, `lastFourth`, `firstThreeFourths`, `lastThreeFourths`, `topLeftSixth`, `topCenterSixth`, `topRightSixth`, `bottomLeftSixth`, `bottomCenterSixth`, `bottomRightSixth`, `maximize`, `fullscreen`, `almostMaximize`, `maximizeHeight`, `smaller`, `larger`, `center`, `restore`, `moveLeft`, `moveRight`, `moveUp`, `moveDown`, `nextDisplay`, `previousDisplay`. You can also run one from your own code with `spoon.WindowSnap:doAction("leftHalf")`.

## WindowTweaksMenu

Adds a three-dot icon to the menu bar with:

- A checkbox for each of the other Spoons that's loaded. Unchecking one turns it off, and it stays off after a reload or restart until you check it again.
- **Snap Window**, a submenu with every WindowSnap action and its shortcut, applied to the focused window, and **Ignore *App*** for the frontmost app.
- **Reset Button Positions**, which moves every app's fullscreen buttons back to the default.
- **Reload Config**, which reloads Hammerspoon.

Load it after the Spoons it controls.

## Uninstall

1. Remove the `hs.loadSpoon(...)` lines from `~/.hammerspoon/init.lua`.
2. Delete the Spoons:

   ```sh
   rm -rf ~/.hammerspoon/Spoons/{FullscreenTrafficLights,FinderCut,ClickThrough,WindowSnap,WindowTweaksMenu}.spoon
   ```

## Development

Install with `./install.sh --link` so edits in this checkout apply after a Hammerspoon reload.

**Unit tests** run the real Spoon code against a fake Hammerspoon API (`tests/mock_hs.lua`). It simulates timers, key and mouse events, hotkeys, windows, screens, the clipboard and Accessibility elements, so the tests run anywhere Lua does:

```sh
brew install lua luacheck
lua tests/run.lua
luacheck Spoons tests
```

**Smoke test** on your Mac: reloads Hammerspoon and checks that the installed Spoons load at the right version, are running, show buttons on every fullscreen window, and log no errors. It only reads state; it never clicks or types:

```sh
sh tests/smoke.sh
```

GitHub Actions runs luacheck and the unit tests on every push and pull request. Pushing a tag like `v1.3.0` runs the tests and publishes a release with a zip of each Spoon.

## License

MIT. See [LICENSE](LICENSE).
