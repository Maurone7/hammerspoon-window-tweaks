# hammerspoon-window-tweaks

Three small [Hammerspoon](https://www.hammerspoon.org) Spoons that fix macOS window annoyances. Each one can be turned on separately.

| Spoon | What it does |
| --- | --- |
| **FullscreenTrafficLights** | Keeps red/yellow/green buttons visible on every fullscreen window, focused or not. Normally macOS hides them until you hover at the top of the screen. |
| **FinderCut** | Cmd+X then Cmd+V cuts and moves files in Finder. |
| **ClickThrough** | One click on an inactive app's window both activates it and clicks what's under the mouse, so you don't have to click twice. |

## Install

1. Install Hammerspoon:

   ```sh
   brew install --cask hammerspoon
   ```

2. Clone this repo and run the installer:

   ```sh
   git clone https://github.com/Maurone7/hammerspoon-window-tweaks.git
   cd hammerspoon-window-tweaks
   ./install.sh          # copies the Spoons into ~/.hammerspoon/Spoons
   ./install.sh --link   # or symlink them, so `git pull` updates them
   ```

3. Add the Spoons you want to `~/.hammerspoon/init.lua`:

   ```lua
   hs.loadSpoon("FullscreenTrafficLights"):start()
   hs.loadSpoon("FinderCut"):start()
   hs.loadSpoon("ClickThrough"):start()
   ```

4. Open Hammerspoon and choose **Reload Config** from its menu-bar icon.

5. Give Hammerspoon **Accessibility** permission in System Settings → Privacy & Security → Accessibility. If you just turned it on, quit and reopen Hammerspoon, because macOS often doesn't apply the permission until the app restarts.

## FullscreenTrafficLights

In native fullscreen, macOS hides the window buttons until you hover at the top of the screen. That hover reveal often doesn't work, for example when the menu bar is set to always show in fullscreen. This Spoon draws working stand-ins on every fullscreen window currently on screen:

- **Red** closes the window.
- **Yellow** exits fullscreen and then minimizes, since macOS can't minimize a fullscreen window.
- **Green** exits fullscreen.

Hover over the buttons to see their ×, − and ↙ symbols.

**Moving them:** Option-drag the buttons anywhere, including up into the menu-bar strip. The position is saved per app. To put every app back at the default position:

```lua
spoon.FullscreenTrafficLights:resetPositions()
```

**Options:** set these before `:start()`.

```lua
hs.loadSpoon("FullscreenTrafficLights")
spoon.FullscreenTrafficLights.size = 12                         -- button diameter (points)
spoon.FullscreenTrafficLights.gap = 8                           -- space between buttons
spoon.FullscreenTrafficLights.defaultOffset = { x = 12, y = 10 } -- from window's top-left
spoon.FullscreenTrafficLights.interval = 0.5                    -- seconds between checks
spoon.FullscreenTrafficLights:start()
```

These are copies drawn over the window, not the system's own buttons. They can take up to `interval` seconds to appear after a window enters fullscreen.

## FinderCut

Finder can't cut files. You have to copy and then use Cmd+Option+V ("Move Item Here"). With this Spoon:

- **Cmd+X** copies the selected files and marks them to be moved.
- **Cmd+V** in another folder then moves them instead of copying.
- **Cmd+C** is a normal copy and cancels a pending cut.

While you're editing text, such as renaming a file or typing in the search field, the keys behave normally. Other apps are not affected.

## ClickThrough

macOS normally uses your first click on an inactive app's window just to activate it. With this Spoon, that click is held for a moment while the app activates, then replayed, so buttons, links and text positions respond to the first click.

- Clicks in the active app, the Dock, the menu bar and the desktop are not affected.
- **Cmd-click** keeps its standard macOS meaning: click in a background window without bringing it forward.
- The first click can lag by up to `activationTimeout` seconds (default `0.3`) while the app comes forward.
- If you start dragging immediately on an inactive window, the very start of the drag may be lost.

## Uninstall

1. Remove the `hs.loadSpoon(...)` lines from `~/.hammerspoon/init.lua`.
2. Delete the Spoons:

   ```sh
   rm -rf ~/.hammerspoon/Spoons/{FullscreenTrafficLights,FinderCut,ClickThrough}.spoon
   ```

## License

MIT. See [LICENSE](LICENSE).
