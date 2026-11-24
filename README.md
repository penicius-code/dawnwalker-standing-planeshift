# Standing Planeshift

Coen stands upright on walls instead of crouching, for The Blood of Dawnwalker. Single-player only.
Version 1.0.3 | Tested in game on 2026-09-30 | Status: working, released

**Download:** [latest release](https://github.com/penicius-code/dawnwalker-standing-planeshift/releases/latest) (zip; install steps below), or [Nexus Mods](https://www.nexusmods.com/thebloodofdawnwalker/mods/676)

> Unofficial fan-made modification, not affiliated with or endorsed by Rebel Wolves or Bandai Namco Entertainment. No game files are included.

The mod folder and its internal name are `UprightWallStance`. It is published on Nexus Mods as "Wallwalker - Standing Planeshift": <https://www.nexusmods.com/thebloodofdawnwalker/mods/676>

## The problem

When Coen clings to a wall with Shadowstep, the game switches him to a crouched wall pose. A vanilla bug (wolf Haste, then Shadowstep onto a wall) sometimes left him standing upright on the wall instead, which looked better. The same combination has a second, unwanted effect: afterwards the wolf can stay stuck in one pose and slide around until Coen transforms a few times.

## What I built

A UE4SS Lua script that makes the upright stance the normal behaviour on walls, and repairs the stuck wolf automatically. It changes: which animation layer is linked to Coen's mesh while he is on a wall, and the leftover animation state of the hidden wolf mesh. Nothing in the game files or the save is changed.

## How it works

- Every 100 ms the script checks whether Coen has custom gravity (the game's sign that he is on a wall).
- On a wall the game links a dedicated animation layer that holds the crouched poses. The script unlinks that layer and links the default locomotion layer, so the normal standing pose is used, rotated to the wall.
- The default layer's class is cached while Coen is off the wall, because on the wall the game has already unlinked it. (That was the cause of a T-pose in 1.0.0.)
- Transitions off the wall (Shadowstep, Claw Ride) stay vanilla. No layer changes are made while Coen is in wolf form.
- Wolf repair: when Coen is walking normally and the hidden wolf mesh still carries the Shadowstep loop montage or foreign layers, the script stops that montage and unlinks those layers.
- `config.ini` is read again every 2 seconds, so settings apply while the game runs.

```text
package/Dawnwalker/Binaries/Win64/ue4ss/Mods/UprightWallStance/
  Scripts/main.lua      the mod (532 lines)
  config.ini            settings
  mod_settings.ini      page for the optional in-game settings menu
  enabled.txt           tells UE4SS to load the mod
  README.txt            short readme shipped with the mod
```

## Requirements

| Requirement | Version | Link |
|---|---|---|
| The Blood of Dawnwalker | see "Compatibility" | |
| UE4SS for Dawnwalker | the build current on 2026-09-30; exact build not recorded | [Nexus Mods, mod 18](https://www.nexusmods.com/thebloodofdawnwalker/mods/18) |
| Mod Setting Menu (optional) | 1.0.7.1 or later | [Nexus Mods, mod 271](https://www.nexusmods.com/thebloodofdawnwalker/mods/271) |

Requirements are not bundled. Install them first from their own pages.

## Install

1. Install UE4SS for Dawnwalker.
2. Download the zip from the [latest release](https://github.com/penicius-code/dawnwalker-standing-planeshift/releases/latest) (the same files as `package/` in this repository) and extract it into the game folder, so that this file exists:
   `The Blood of Dawnwalker\Dawnwalker\Binaries\Win64\ue4ss\Mods\UprightWallStance\Scripts\main.lua`
3. Start the game and Shadowstep onto a wall. Coen stands upright.

Upgrading: copy over the previous version. An existing `config.ini` keeps working; add the line `FixWolfHaste = 1` if it is missing.

## Uninstall / roll back

1. Close the game.
2. Delete the folder `Dawnwalker\Binaries\Win64\ue4ss\Mods\UprightWallStance`.
3. Saves are not affected: the mod stores nothing in them.
4. UE4SS is left alone. To switch the mod off without removing it, set `Enabled = 0` in `config.ini` or press the toggle key.

## Configuration

`config.ini`, section `[Settings]`:

| Key | Default | Meaning |
|---|---|---|
| `Enabled` | `1` | `1` upright on walls, `0` vanilla crouched pose |
| `ToggleKey` | `F7` | UE4SS key name (`F7`, `NUM_FOUR`, `INS`, `HOME` ...). Empty = no hotkey |
| `FixWolfHaste` | `1` | `1` repairs the stuck wolf after wolf Haste + Shadowstep, `0` vanilla |
| `Logging` | `0` | `1` writes `UprightWallStance.log` next to `Dawnwalker.exe` |

With Mod Setting Menu installed, the same three switches appear on an in-game page ("Upright on walls", "Fix stuck wolf", "Debug log").

## Compatibility

| Item | Status | Notes |
|---|---|---|
| Game version | tested 2026-09-30 | The exact game build was not written down at the time. The project notes from mid-October 2026 list game version 1.0.5. |
| Mods that allow Shadowstep or wall walking in human form | works | |
| Mods that replace or relink Coen's animation layers | may conflict | Both would change the same layers. |

## Known issues

- A wall entry within 5 seconds of wolf form waits 2 seconds before the first layer change. This was added while hunting the wolf bug described below and is probably no longer needed; it is kept because it was part of the tested build.
- For a bug report: set `Logging = 1`, reproduce the problem and attach `UprightWallStance.log`.

## Engineering notes

**Symptom.** After wolf Haste followed by Shadowstep onto a wall, the wolf model appeared under Coen's feet, or stayed frozen in one pose and slid around. Dropping down and transforming a few times cleared it.

**First suspicion: this mod.** A logging-only test build recorded every change of wall state, form, linked layers and visible meshes. In two reproductions the mod had changed layers shortly before the game turned Coen back into the wolf on the wall, so the mod looked like the cause. A guard was added (no layer changes in wolf form, a 2-second wait after a wall entry that follows wolf form).

**Actual cause, found with a read-only probe on the unmodified game.** The wolf is a separate mesh component. In wolf form the pawn's main mesh reference points at the wolf mesh. Shadowstep out of wolf Haste plays its loop montage and links the wall layers on the wolf mesh, then turns Coen human and hides the wolf with that montage and those layers still on it. The next time the wolf is shown it is stuck. So the bug is in the game, and it is also the reason Coen sometimes stood upright in vanilla.

**Fix.** When Coen is calm (walking, normal gravity, no Shadowstep), stop the stale montage on the hidden wolf and unlink the foreign layers. Three ways of stopping a montage were tried and each result was logged: stopping all montages did not clear it (the error had been hidden by a protected call), stopping that specific montage cleared it every time in 8 wall runs, and the third method was never needed. One more round fixed two timing details: the "calm" test had read a flag on the hidden wolf that stays stale, and the cleanup had also removed the wolf's own layers.

**Result.** The final test build passed several wall runs with the cleanup running about one second after leaving the wall, no stuck wolf and no errors. It was released as 1.0.3.

**Rollback.** `FixWolfHaste = 0` switches only the wolf repair off. `Enabled = 0` or the toggle key restores the vanilla wall pose. Deleting the folder removes everything.

## Changelog

See [CHANGELOG.md](CHANGELOG.md). Latest: 1.0.3 (2026-09-30): automatic repair of the stuck wolf after wolf Haste + Shadowstep.

## Credits and licence

Loaded by UE4SS; the optional settings page uses Mod Setting Menu by mmarcussa. Neither is included here.

MIT, see [LICENSE](LICENSE). The licence covers my code only. The game, its names and its assets belong to their owners and are not included. A legitimate copy of the game is required.

Built with AI assistance (Claude); designed, tested and maintained by me.
