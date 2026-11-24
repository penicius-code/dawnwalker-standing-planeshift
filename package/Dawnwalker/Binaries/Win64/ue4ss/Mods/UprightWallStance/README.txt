UPRIGHT WALL STANCE 1.0.3
The Blood of Dawnwalker, UE4SS mod

Coen stands upright when clinging to walls with Shadowstep, instead of the
vanilla crouched pose. Walking along walls, corners and leaving the wall work
as usual. Shadowstep and Claw Ride transitions off the wall stay vanilla.

REQUIREMENTS
  UE4SS for Dawnwalker (required)
  Mod Setting Menu (optional, adds an in game settings page)

INSTALL
  Vortex: install the archive, choose Root (game folder) if asked, deploy.
  Manual: extract the archive into the game folder so this file exists:
    The Blood of Dawnwalker\Dawnwalker\Binaries\Win64\ue4ss\Mods\UprightWallStance\Scripts\main.lua

USAGE
  F7 toggles between upright and vanilla crouched in game.
  Settings live in ue4ss\Mods\UprightWallStance\config.ini
    Enabled    1 upright, 0 vanilla
    FixWolfHaste  1 repairs the stuck wolf after wolf Haste + Shadowstep, 0 vanilla
    ToggleKey  UE4SS key name (NUM_FOUR, F7, INS, HOME...), empty disables it
    Logging    1 writes UprightWallStance.log next to Dawnwalker.exe
  Changes to config.ini and Mod Setting Menu apply live, no restart needed.

HOW IT WORKS
  On walls the game attaches a dedicated animation layer holding the crouched
  wall poses. While Coen clings to a wall the mod detaches that layer, so his
  default locomotion layer takes over, rotated to the wall. No game files and
  nothing in your save are changed. Delete the folder to uninstall.

  Found through a vanilla bug: haste, wolf form, then Shadowstep onto a wall
  skips the wall layer and leaves Coen standing. This mod makes that on purpose.

COMPATIBILITY
  Works with mods that enable Shadowstep or wall walking in human form.
  May conflict with mods that replace or relink Coen's animation layers.

BUG REPORTS
  Set Logging = 1, reproduce the problem, attach UprightWallStance.log.

CHANGES
  1.0.3  Fixes the vanilla bug where the wolf stays stuck in one pose and slides
         around after wolf Haste + Shadowstep (FixWolfHaste, on by default).
         No layer changes while in wolf form.
  1.0.1  Fixed Coen T-posing on walls (the default layer is now found before
         the first wall latch). Default hotkey F7.
  1.0.0  First release.
