# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This is **Simply Nino**, a personal ZMOD fork of the [Simply Love](https://github.com/Simply-Love/Simply-Love-SM5) theme for **ITGmania** (a StepMania fork). It is not a standalone application — it's a Lua/INI theme that ITGmania loads at runtime. There is no build step, package manager, or compiler; ITGmania's engine parses these files directly.

Lineage:
1. **upstream Simply Love** (original theme for SM5)
2. → **zarzob/Simply-Love-SM5** ("ZMOD" fork — adds ITL/GrooveStats-focused features, see https://github.com/zarzob/Simply-Love-SM5)
3. → **this fork** ("Simply Nino" / "Nino Edition") — personal build by Nino, adds ArrowCloud integration, the "Nino" visual style, and misc fixes

`git log` is the authoritative source for what has changed locally — the README's feature list is not kept perfectly in sync with `git log`.

## What has been added/changed in this fork (vs ZMOD upstream)

All of the following was added by Nino on top of zarzob's ZMOD:

### ArrowCloud integration
- `Modules/ArrowCloud.lua` — full module: score submission, device-login via QR code, offline retry queue
- `Scripts/SL-Helpers-ArrowCloud.lua` — shared networking/helper logic for ArrowCloud across screens
- ArrowCloud leaderboards integrated into Scorebox and the Leaderboard popup
- ArrowCloud logo sizing fixed (source image was 1196x1196 vs 128x128 of others)
- Fix: overlapping loading logos in Scorebox
- Fix: restored HardEX red color for ArrowCloud score text (had been lost in a local edit)
- Fix: `stale Actor referenced` crash from late ArrowCloud async responses
- Added missing `OptionTitles`/`OptionExplanations` strings for `EnableArrowCloud`

### Nino visual style
- `Graphics/_VisualStyles/Nino/` — cartella grafica del nuovo stile visivo
- `Scripts/99 SL-ThemePrefs.lua` — `visualStyleValues` modificato per includere "Nino"
  nell'elenco degli stili selezionabili (fatto nel commit baseline `f3284b6a`, insieme alla cartella)
- Had a dedicated `SL.Nino.Colors` palette (anchored to `#3db0ff`) from the baseline through `84e53e33`;
  removed afterward because several of its darker entries were unreadable when selected — Nino now
  uses the same default `SL.Colors`/`SL.DecorativeColors` as upstream, like any non-SRPG10 style
- ArrowCloud colors tweaked to match Nino palette (EX slot uses red instead of blue/cyan)

### Theme identity
- `ThemeInfo.ini` renamed DisplayName to "Simply Nino"
- Version set to "5.9.0 - Nino Edition"
- Author updated to credit original authors + note personal build
- Fix: crash on Title Menu caused by empty Version string in ThemeInfo.ini

### ITGLiveScore integration
- `Modules/ITGLiveScore.lua` — writes a live snapshot of the current song/scores to
  `Save/RealTimeResults.json` every 0.5s while `ScreenGameplay` is active (`Active: true`), and
  appends a final snapshot to `Save/RealTimeResultsHistory.json` (last 50, FIFO) plus a per-song
  detail file in `Save/RealTimeScoreDetails/<id>.json` (per-note offsets + life curve, reused from
  data the theme already tracks for its own graphs) once the song ends on `ScreenEvaluationStage`
  (`Active: false`). Gated behind the `EnableLiveScoreExport` ThemePref.
- `Tools/ITGLiveScore/` — companion Node.js app (`ITGWebAPP/server.js` + `public/index.html`), **not
  loaded by the theme/engine at all** — a separate process that reads those JSON files from the
  configured `ITGMANIA_SAVE_DIR` and re-serves them over HTTP (default port 3000) and WebSocket
  (default port 8081) to a browser overlay (LIVE tab via WebSocket, HISTORY tab with a per-score
  detail modal: judgments, offset scatter, life curve). Start via `Tools/ITGLiveScore/start-server.bat`
  (has `ITGMANIA_SAVE_DIR` hardcoded per-machine — update it if the ITGmania install path changes).
  See `Tools/ITGLiveScore/README.md` for the full JSON schema and diagnostics (`GET /info`).
- New operator-menu submenu **"Simply Nino Options"** (`metrics.ini [ScreenSimplyNinoOptions]`,
  wired into `[ScreenOptionsService]` next to `ZmodOptions`/`GrooveStatsOptions`/`TournamentModeOptions`)
  groups this fork's own toggles: `EnableLiveScoreExport` (moved here from `ZmodOptions`), plus three
  new ThemePrefs — `ShowSessionTimer`/`ShowPlayTimer` (independently hide either of the two EventMode
  timers in `Graphics/ScreenSelectMusic header.lua`) and `ShowStageNumber` (wired to the engine's
  native `ShowStageDisplay` metric under `[ScreenSelectMusic]`, previously hardcoded `true`).

### Bug fixes (session-only, not tied to a feature area above)
- Fix: rejoining mid-session (e.g. after an accidental profile switch) wiped `SL[pn].Stages.Stats`
  — losing prior songs from the `ScreenEvaluationSummary` recap and resetting the header's Play
  Timer to 0. Root cause: `Graphics/MusicWheelItem Song NormalPart/Unlocks.lua` and `Favorites.lua`
  (one instance per music-wheel item!) each independently reset `SL[pn]` on a guest
  `PlayerJoinedMessageCommand` *without* preserving `Stages`, racing against `LoadGuest()`
  (`Scripts/SL-PlayerProfiles.lua`) which is the one place that's supposed to own that reset and
  does preserve it. Removed the redundant/buggy resets from both files.
- Fix: `BGAnimations/ScreenGameplay underlay/PerPlayer/StepStatistics/DensityGraph.lua`'s "Peak
  NPS/eBPM" text used absolute-screen-based positioning nested inside an already-offset pane; in
  Double it landed near screen center, on top of the notefield. Now simply not shown when
  `style == "double"` (rest of the Step Statistics pane is positioned correctly and unaffected).

## Running / testing changes

There is no test suite, linter, or CI in this repo. The only way to validate a change is to run it inside ITGmania:

1. This folder must live at (or be symlinked into) ITGmania's `Themes/` directory, named to match `ThemeInfo.ini`'s expectations.
2. Launch ITGmania and switch to this theme (Options → Display Options → Appearance Options → Theme), or select it at the theme prompt on first boot.
3. Watch ITGmania's `Logs/log.txt` (and the in-game overlay, if enabled) for Lua errors — the engine does not fail loudly on most script errors, it just skips the broken actor/screen element.
4. Metrics/preference changes generally require a full game restart, since `ThemePrefs` and `SL_Init.lua` initialize once per game cycle (see below). Editing `.lua` files under `BGAnimations`/`Graphics` can often be picked up with the in-game "Reload Scripts" / theme reload operator-menu options, but when in doubt, restart.

When asked to "test" or "verify" a change, be explicit that this means launching ITGmania and checking the relevant screen — it cannot be done headlessly.

## Big-picture architecture

### Screen-driven file resolution (StepMania/ITGmania convention)
The engine resolves most content by **filename pattern matching against the current screen name**, not by explicit wiring. For a screen named `ScreenFoo`, the engine looks for files like `BGAnimations/ScreenFoo underlay.lua`, `ScreenFoo overlay.lua`, `ScreenFoo background.lua` (or `.redir` pointing elsewhere), `ScreenFoo in`/`out`/`cancel` transition folders, etc. This is why `BGAnimations/` is flat with hundreds of loosely-named files/folders rather than nested by feature — the naming *is* the routing. When looking for "where does X screen get its look/behavior," search `BGAnimations/` and `Graphics/` for files prefixed with that screen's name before searching Lua logic.

`.redir` files are one-line text pointers that redirect one screen element to reuse another file/folder — follow them when tracing behavior.

### Screen flow is data-driven via `Branch.*` functions
`Scripts/SL-Branches.lua` defines `Branch.AfterX()` / `Branch.AllowScreenY()` functions that compute the *next* screen name based on `ThemePrefs`, `SL.Global` state, game mode, coin mode, etc. Screens reference these (via metrics.ini `NextScreen`-style hooks) instead of hardcoding a linear sequence. To trace "what screen comes after X," start in `SL-Branches.lua`, not in the screen's own files.

### `SL` global table — cross-screen state
`Scripts/SL_Init.lua` (loaded first) defines the global `SL` table: `SL.P1`, `SL.P2` (per-player active modifiers, parsed chart stats, high scores, GrooveStats/ArrowCloud auth, favorites, etc.) and `SL.Global` (session/game-cycle state, stage counts, menu timers). `SL.P1`/`SL.P2`/`SL.Global` are reset via `initialize()` metatables — `InitializeSimplyLove()` is called once at load and again whenever a new "game cycle" starts (see `BGAnimations/ScreenTitleMenu underlay/default.lua`). `SL` also holds the theme's color palettes (`SL.Colors`, `SL.ITGDiffColors`, `SL.DecorativeColors`, `SL.JudgmentColors`) and per-gamemode scoring config (`SL.Preferences.{Casual,ITG,FA+}`, `SL.Metrics.{Casual,ITG,FA+}` — these map to StepMania's `TimingWindowSeconds*`/`PercentScoreWeight*`/`GradeWeight*`/`LifePercentChange*` engine preferences).

Never introduce new bare globals in Lua scripts — everything theme-wide should live under `SL` (or another established namespace like `Branch`, `ThemePrefs`) to avoid polluting StepMania's global Lua environment (see `Modules/README.md`).

### `ThemePrefs` — user-configurable theme options
`Scripts/99 SL-ThemePrefs.lua` defines `SL_CustomPrefs.Get()`, a big table of theme preference definitions (default, choices, values) surfaced in the theme's options menus and persisted to `Save/ThemePrefs.ini`. Read via `ThemePrefs.Get("PrefName")` anywhere in the theme. New user-facing theme options go here. The file numbering prefix (`99 …`) controls Lua load order across `Scripts/`; `06 SL-Utilities.lua` and `99 SL-ThemePrefs.lua` are intentionally ordered relative to unprefixed scripts — check existing numeric prefixes before adding a new script if load order matters.

### `metrics.ini` — per-screen layout/behavior config
`metrics.ini` is a single large INI file with one `[ScreenName]` (or shared `[Common]`, `[OptionRow]`, etc.) section per screen/component, defining engine metrics (positions, `NextScreen`, `OptionRow` behavior, timers, etc.). Screens/components inherit from `[Screen]`/`[ScreenWithMenuElements]`/etc. via StepMania's metrics fallback chain. When changing a screen's timing, transitions, or menu behavior, check its `metrics.ini` section first.

### `Modules/` — third-party/optional code injection points
Files under `Modules/*.lua` (see `Modules/README.md`) each return a table mapping `ScreenName → Actor`, which gets auto-attached to `ScreenSystemLayer` as that screen loads and executed via `ModuleCommand`. This is the extension point used for larger self-contained integrations without touching core theme files — e.g. `Modules/ArrowCloud.lua` (a third-party score/leaderboard service integration: device-login QR auth, score submission with offline retry queue, leaderboard popups). `Scripts/SL-Helpers-ArrowCloud.lua` and `Scripts/SL-Helpers-GrooveStats.lua` hold the equivalent helper/networking logic for GrooveStats and ArrowCloud that's shared across screens rather than module-scoped.

### Visual Styles
`Graphics/_VisualStyles/<Name>/` holds swappable cosmetic themes (Hearts, Arrows, Bears, Nino, SRPG10, etc.), selected via the `VisualStyle` ThemePrefs choice list built in `99 SL-ThemePrefs.lua`. Adding a new visual style means adding a `Graphics/_VisualStyles/<Name>/` folder and registering its emoji/name pair in `visualStyleChoices`/`visualStyleValues` there (note the date-gated / save-file-gated logic used for limited-time styles like `SRPG10`).

### Languages
`Languages/*.ini` are locale string tables (`en.ini` is the reference/most complete). New user-facing strings must be added to `en.ini` at minimum; other locale files may lag behind and fall back to English via StepMania's string fallback.

### Scripts load order
Files in `Scripts/` are loaded alphabetically by filename; the leading two-digit numeric prefixes (`06 SL-Utilities.lua`, `99 SL-ThemePrefs.lua`) exist specifically to force early/late load order relative to unprefixed files like `SL_Init.lua`, `SL-Branches.lua`, `SL-Colors.lua`, etc. Respect this when a new script depends on globals defined elsewhere.

## Conventions

- Line endings are normalized to LF via `.gitattributes` (`* text=auto eol=lf`).
- `.git-blame-ignore-revs` exists for whitespace/formatting-only commits — configure `git blame --ignore-revs-file .git-blame-ignore-revs` locally if blame history matters for your task.
- This is a single-maintainer fork; commit messages are in **Italian**, short, imperative, and describe the specific bug/feature. Follow that style for new commits.
- Never introduce bare globals — use `SL.*` or established namespaces.
- When in doubt about upstream behavior, check zarzob's ZMOD repo: https://github.com/zarzob/Simply-Love-SM5
