# Psychonauts Collectible Scout

Collectible Scout is an Astralathe mod for Psychonauts that makes late-game collectible cleanup less painful. It finds the nearest currently loaded collectible, highlights it in-game, and briefly shows the target type, rounded distance, and direction.

## Features

- Highlights the closest loaded collectible for 5 seconds.
- Follows moving spline figments at their live pickup position during the highlight.
- Shows a compact HUD label with collectible type, distance, and direction.
- Re-scans when no target is found, which helps in levels that stream or load small sections at a time.
- Optional target switching support for builds of Astralathe that expose D-pad Down to Lua.
- Filters noisy non-collectibles such as 1UPs and level configuration props.
- Skips collected and script-hidden targets, including figments that are still dissipating.
- Skips placed figment objects that have not been initialized as collectible pickups.
- Writes debug scan reports to `ModData/CollectibleScout/last_scan.txt`.

## Tracked Collectibles

- PSI challenge cards, markers, and cores
- Scavenger hunt items
- Brain jars
- Mental cobwebs
- Figments and spline figments
- Emotional baggage and tags
- Memory vaults
- Max lives and max ammo upgrades
- Psi powers

## Controls

With the included Lua hotkey entrypoint:

- `F3`: scan and highlight the closest currently loaded target.

With a patched Astralathe build that supports controller hotkeys:

- `D-pad Up`: scan and highlight the closest currently loaded target.
- `D-pad Down`: switch to the next cached target when the current target is not useful.

The visual target highlight and HUD text automatically disappear after 5 seconds.

## Installation

### Windows installer

1. Install [Astralathe](https://gitlab.com/scrunguscrungus/astralathe/-/wikis/Installing%20Astralathe) if you do not already use it, and close Psychonauts.
2. Download `CollectibleScout-0.2.2.zip` from the [latest release](https://github.com/lorenfa99/psychonauts-collectible-scout/releases/latest) and extract it.
3. Double-click `Install.cmd`. It finds Steam installs automatically, or lets you choose the game folder.
4. Launch the game through `AstralatheLauncher.exe` and press **F3** to scan.

The installer enables the mod, updates an existing installation in place, and backs up overwritten files under `Psychonauts/CollectibleScout-Backups/`. Other files in the mod folder are preserved. If F3 already runs another script, you can choose to keep it.

### Manual installation

1. Install Astralathe for Psychonauts.
2. Copy the `CollectibleScout` folder into the game's `ModResource` folder.
3. Rename the copied folder to `Collectible Scout` if your Astralathe mod list expects the display name as the folder name.
4. Enable `Collectible Scout` in Astralathe.
5. To use the F3 hotkey, copy `CollectibleScout/astralathe_lua.lua` to the Psychonauts game folder as `astralathe_lua.lua`.

Example layout:

```text
Psychonauts/
  astralathe_lua.lua
  ModResource/
    Collectible Scout/
      mod.json
      mod_boot.lua
      Scripts/
```

## Notes

Collectible Scout only sees entities that the game has currently loaded. Some levels, especially segmented or race-like levels, may not expose every collectible at once. If the HUD says `Scout: none`, move through the level and scan again when new sections load.

D-pad support is not provided by stock Psychonauts input binding. It requires an Astralathe build or patch that calls the scanner from D-pad Up and target switching from D-pad Down.

## Development

Run the regression tests from the repository root with a Lua 4.0 interpreter:

```text
lua tests/collectible_scout_test.lua
```

The tests mock engine calls and cover moving pickup positions, cached target selection, target switching, unavailable figments, the five-second display lifetime, camp collectibles, and mental-level collectible selection across level families. The mod uses Lua 4.0 upvalue syntax, so newer Lua interpreters cannot run it unchanged. In-game verification of pickup collection in Milla's fan room and representative other levels is still needed.

On Windows, run the installer tests with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/installer_test.ps1
```

These use temporary dummy game folders to check installation, upgrades, backups, rollback, hotkey conflicts, and Steam library detection.

## Related Mods

Part of the Psychonauts Collectible Tools set:

- Psychonauts Collectible Scout
- Psychonauts Dowsing Rod Assist

## Credits

Created with Codex assistance.
