# Changelog

All notable changes to this mod. Dates are the release dates on Nexus Mods.

## 1.0.3 - 2026-09-30

### Fixed
- The vanilla bug where the wolf stays stuck in one pose and slides around after wolf Haste followed by Shadowstep. The stale Shadowstep montage and foreign animation layers on the hidden wolf mesh are now removed automatically once Coen is walking normally again.

### Added
- Setting `FixWolfHaste` (on by default) in `config.ini`, and "Fix stuck wolf" on the Mod Setting Menu page.

### Changed
- No animation layer changes while Coen is in wolf form.
- A wall entry within 5 seconds of wolf form waits 2 seconds before the first layer change.
- Optional log now records wall state, form, linked layers and visible meshes on every change.

Tested in game on 2026-09-30 over several wall runs.

## 1.0.1 - 2026-09-28

### Fixed
- Coen T-posing on walls. The mod unlinked the wall layer but only looked up the default layer while on the wall, when the game had already unlinked it. The default layer's class is now cached while Coen is off the wall, with a path lookup once per wall entry as a fallback. The wall layer is only unlinked once the default layer is known.

### Changed
- Default hotkey is F7.

Tested in game on 2026-09-28 over two sessions (no T-pose after loading a save).

## 1.0.0 - 2026-09-28

- First release: Coen stands upright while clinging to walls.
