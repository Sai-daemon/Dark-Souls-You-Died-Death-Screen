# Dark Souls You Died Death Screen — Game API & Dead-End Reference

> **What this is:** a code-derived catalogue of every *game* function / API / event /
> data-file convention these mods call into, plus a catalogue of everything that was
> **confirmed not to work** while building them, so anyone modifying a death screen (or
> building one from scratch) does not have to rediscover any of it.
>
> **Verification:** every API claim below was checked against the game's own files —
> vanilla Lua under `media/lua/`, data scripts under `media/scripts/`, shaders under
> `media/shaders/`, and the class definitions inside `projectzomboid.jar` — and/or
> exercised in a running **Build 42 Stable (42.20.x)** game. The game updates often;
> re-verify anything here on the build you target.
>
> **Scope:** the two mods in this package and the engine surface they use. Paths are
> written generically: `<game>` = the Project Zomboid install's `projectzomboid/`
> directory, `<mods>` = the player's local mods folder (e.g. `~/Zomboid/mods/` on Linux,
> `%UserProfile%\Zomboid\mods\` on Windows).

---

## 1. The two mods and what each one is

| Mod id (folder) | Purpose |
|---|---|
| `DarkSoulsYouDied` ("Dark Souls You Died Death Screen") | Full death-screen replacement: custom music sting + greyscale → fade-to-black + "YOU DIED" image/bar animation + custom button window. |
| `DarkSoulsDeathAudioOnly` | Audio treatment only (same sting/muffle/silence timeline), vanilla death UI visuals kept. |

Both ship together in one Steam Workshop item (a `workshop.txt` at the item root, with
the two mods under `Contents/mods/<mod id>/`). Each mod declares the other
`incompatible` in its `mod.info`, and the audio-only Lua guards itself with a
`DarkSoulsDeathAudioOnlyLoaded` flag in case both load anyway.

Each mod resolves its content from a **version layer**: Build 42 looks for the highest
direct subdirectory name that parses as a version and falls within `[42000, current build]`
(`ChooseGameInfo$Mod` / `ZomboidFileSystem.getModVersionDirName`), which is `<mod>/42/`
here. A mod may also carry a legacy root `<mod>/media/` layer — the loader resolves one
canonical file per layer and does **not** fall back from `42/media` to `media`, so when a
mod ships both they must stay byte-identical. **This package now ships only the `42/`
tree**, so there is nothing to keep in sync.

### File map (mod-relative; `M` = DarkSoulsYouDied, `A` = DarkSoulsDeathAudioOnly)

| Path inside the mod | M | A | Role |
|---|---|---|---|
| `mod.info` (+ `42/mod.info`) | ✔ | ✔ | Metadata, incl. mutual `incompatible` |
| `poster.png` (+ `42/poster.png`) | ✔ | ✔ | Mod-manager thumbnail |
| `media/lua/client/DarkSoulsDeath.lua` | ✔ | – | M: timing table, the `DarkSoulsDeathSilence` flag table, volume snapshot + live refresh, per-sound duck/restore, per-frame zombie/ambient/world stoppers, death/respawn hooks, diagnostic logging |
| `media/lua/client/DarkSoulsDeathAudioOnly.lua` | – | ✔ | A: same audio machinery without any visual/overlay code |
| `media/lua/client/ISUI/ISPostDeathUI.lua` | ✔ | ✔ | **Full-file override** of the vanilla death panel (identical path in `42/`); M = custom panel, A = vanilla copy + 3 hooks (§6.4) |
| `media/lua/shared/Translate/EN/UI.json` | ✔ | – | M only: the mod's four `UI_DarkSoulsDeath_*` keys; one folder per language (§11.1) |
| `media/scripts/generated/sounds/player/sounds_player_death.txt` | ✔ | ✔ | Overrides the vanilla `PlayerDied` sound script → raw `.ogg` |
| `media/scripts/sounds_DarkSoulsDeath.txt` | ✔ | ✔ | New `YouDiedSting` sound script (UI category) |
| `media/sound/DarkSoulsDeath/you_died.ogg` | ✔ | ✔ | The sting audio (raw OGG Vorbis) |
| `media/ui/DarkSoulsDeath/you_died.png` + `bar.png` | ✔ | – | "YOU DIED" image + gradient bar (primary texture paths) |
| `media/textures/DarkSoulsDeath/you_died.png` + `bar.png` | ✔ | – | Fallback texture paths tried when `media/ui/...` misses |

The mods live entirely under the `Contents/mods/<mod id>/` folders above; `workshop.txt`
and `preview.png` sit at the package root.

---

## 2. Loader / data-file features the mod relies on

These are "modding contract" features of the game, not Lua APIs, but every one of them
is load-bearing:

1. **Media overlay.** Files under a mod's `media/` shadow the base game's files with the
   same relative path. Used here for:
   - **Wholesale Lua file replacement**: `media/lua/client/ISUI/ISPostDeathUI.lua` in the
     mod completely replaces the vanilla class definition of the same name/path. There is
     no merge — two mods shipping this file conflict (one silently wins).
   - **Sound script replacement**: `media/scripts/generated/sounds/player/sounds_player_death.txt`
     replaces the vanilla script file (see §7 for the DSL).
2. **The `42/` subfolder** (Build 42 only). Content under `<mod>/42/` layers on top of the
   mod's own root `media/`; runtime resolution prefers the `42/` copy.
3. **`media/ui/` vs `media/textures/`** — PNGs dropped in either are resolvable via
   `getTexture("media/ui/...")` / `getTexture("media/textures/...")`; this mod loads `ui`
   first and falls back to `textures` at runtime (§5.4).
4. **`mod.info` keys used:** `name`, `author`, `id`, `description`, `poster`,
   `modversion`, and `incompatible=\<otherModId>` (the `incompatible` value begins with a
   backslash in these files) to make the in-game mod manager refuse loading both variants.
5. **`workshop.txt` keys used:** `version`, `id`, `title`, `description`, `tags`,
   `visibility`; combined with the `Contents/mods/<id>/...` folder layout for the Steam
   uploader, which is what the mod package layout mirrors.

---

## 3. The game behaviour we depend on (Java side, decompiled)

The mod is only possible because of these engine behaviours.

1. **`IsoPlayer.OnDeath()` ordering** (`zombie/characters/IsoPlayer.class`):
   - Returns early on the server (`GameServer.server` active) → server-side death makes
     no music/UI calls.
   - **Only when `IsoPlayer.allPlayersDead()` is true** it calls
     `SoundManager.instance.playMusic("PlayerDied")`.
   - Then, **only for the local player**, it fires the Lua event
     `OnPlayerDeath(player)` via `LuaEventManager.triggerEvent(...)`.
   - Consequences the mod is built around:
     - Java's death sting fires **before** our Lua hook runs → every variant calls
       `getSoundManager():StopMusic()` immediately in the `OnPlayerDeath` hook to kill the
       instant sting, then re-triggers it on our own timeline.
     - In co-op a dying player never triggers the `allPlayersDead()` music path, so
       hooking the always-firing `OnPlayerDeath` event is the only reliable music kill.
2. **`SoundManager.DoMusic()`** (`zombie/SoundManager.class`): early-outs if music is
   disabled or volume 0; otherwise stops current music, resolves the sound script via
   `GameSounds.getSound(name)`, and plays the clip's FMOD `event` if present, else its
   raw `file`. `GameSoundClip` carries both fields (`event`, `file`, plus `volume`,
   `pitch`, `distanceMin/Max`, ...). Because `file` is a supported fallback, a mod can
   override a scripted sound with a **plain `.ogg`** and never touch the compiled FMOD
   banks (`media/sound/banks/Desktop/ZomboidMusic.bank` must stay untouched).
3. **Search-mode overlay as a free post-processing pass.** `getSearchMode()` exposes the
   foraging SearchMode overlay (`zombie/iso/SearchMode`, inner classes
   `PlayerSearchMode`/`SearchModeFloat`), whose per-player floats feed uniforms in
   `media/shaders/screen.frag` (e.g. `DesaturationVal` for greyscale). Enabling the
   overlay for a player and driving its floats gives a **full-screen desaturate and
   blacken** with no extra shaders and no FMOD work.

---

## 4. Event hooks used (engine → Lua callbacks)

All code subscribes through the global `Events` table
(`Events.<Name>.Add(fn)`), the standard engine event bus (Java fires them via
`LuaEventManager`; vanilla Lua files subscribe the same way).

| Event | Who subscribes | Why |
|---|---|---|
| `OnPlayerDeath` | M `DarkSoulsDeath.lua`; A `DarkSoulsDeathAudioOnly.lua`; both `ISPostDeathUI.lua` files | Kill the Java sting, seed the volume baselines from the game options, enable the advanced-sound flag and snapshot per-sound volumes, zero the overlay, create the death panel, record death time |
| `OnTick` | M `DarkSoulsDeath.lua`; A `DarkSoulsDeathAudioOnly.lua` | Per-frame: refresh the volume baselines from the options, then while the "stop everything" flag is set stop zombie emitters, ambient pieces and ambient streams, and mute the engine VCA |
| `OnPlayerUpdate` | M `DarkSoulsDeath.lua`; A `DarkSoulsDeathAudioOnly.lua` | Detect that the same player number is alive again after respawn → restore all volumes/snapshots and the advanced-sound flag |
| `OnKeyPressed` | M `ISPostDeathUI.lua` | Any key exits the CHARACTER STATS view back to the button window |
| `OnMainMenuEnter` | A `DarkSoulsDeathAudioOnly.lua` | Restore volumes if the player bails to the main menu instead of respawning |

Callback payloads used: `OnPlayerDeath(playerObj)` — an `IsoPlayer` with
`getPlayerNum()`; `OnPlayerUpdate(player)` — an `IsoPlayer` with `getPlayerNum()` and
`isDead()`; `OnTick()` / `OnKeyPressed()` / `OnMainMenuEnter()` — no payload used.

---

## 5. Lua API catalogue (game functions & methods called)

Mod-relative file shorthand: `M-DS` = `DarkSoulsDeath.lua`, `M-UI` = M's
`ISPostDeathUI.lua`, `A-DS` = `DarkSoulsDeathAudioOnly.lua`, `A-UI` = A's
`ISPostDeathUI.lua`. Identical code also lives under each mod's `42/` copy. Arg lists are
the exact forms the code uses.

### 5.1 Global functions (engine-provided)

| Call (as used) | Returns | Purpose / where |
|---|---|---|
| `getSoundManager()` | `SoundManager` | Every sound/bus operation (below). All files. |
| `getSearchMode()` | `SearchMode` | Full-screen overlay control. `M-DS`, `M-UI`. |
| `getAmbientStreamManager()` | `AmbientStreamManager` | `am:stop()` silences ambient streams **and rain**, and clears `alarmList` (§9.15). `M-DS`, `A-DS`. |
| `getCell()` | `IsoCell` | Iterating world objects to find zombies / vehicles; `getAnimals()` for animals. `M-DS`, `A-DS`. |
| `getWorldSoundManager()` | `WorldSoundManager` | Exposed, but this is the AI **hearing** list, not audio (§9.14). |
| `getCore()` | `Core` | Options/getters + menu/quit actions. All files. |
| `SystemDisabler.get/setEnableAdvancedSoundOptions()` | bool | **Gates whether `GameSound:getUserVolume()` returns the stored value or a hardcoded 1.0** (§9.12). Static calls on an exposed class; vanilla precedent `MainOptions.lua:2130`. |
| `getClimateManager()` | `ClimateManager` | `:getThunderStorm():stopAllClouds()` stops future thunder. |
| `unpack(t)` / `select("#", ...)` | – | Standard Lua, both used by vanilla Lua; needed to forward varargs correctly (§15.2). |
| `getGameTime()` | `GameTime` | Death-stat strings for the panel. Both `OnPlayerDeath` handlers. |
| `getTextManager()` | `TextManager` | Font heights, string measurement, centred drawing. Both `ISPostDeathUI` files. |
| `getTexture(path)` | `Texture` or `nil` | Lazy texture load. `M-UI`. |
| `getTimestamp()` | seconds (integer) | Death-time marker used by A's vanilla-style wait (`timeOfDeath + 3/6`). Both UIs set it. |
| `getTimestampMs()` | milliseconds | **The mod's master clock** — every timeline value is `(now - timeOfDeathMs)/1000`. All files. |
| `getPlayerScreenLeft/Top/Width/Height(index)` | int | Per-player screen rect (split-screen aware). Both UIs. |
| `getText("IGUI_...")` | translated string | Button labels (§11 for key list). Both UIs. |
| `getNumActivePlayers()` | int | Respawn availability. Both UIs. |
| `isClient()` | bool | Respawn availability. Both UIs. |
| `getServerOptions()` | server options | `:getBoolean("DropOffWhiteListAfterDeath")` kills respawn on whitelist servers. Both UIs. |
| `instanceof(obj, "IsoZombie")` | bool | Object-list filter. `M-DS`, `A-DS`. |
| `setGameSpeed(1)` | – | Un-pause game time on exit/respawn/quit. Both UIs. |
| `pauseSoundAndMusic()` | – | Halt audio before quitting to desktop. Both UIs. |
| `setShowPausedMessage(true)` | – | Show the pause overlay after quitting to desktop. Both UIs. |
| `setJoypadFocus(player, ui)` | – | Give the modal quit dialog joypad focus. Both UIs. |

### 5.2 SoundManager (object from `getSoundManager()`)

| Method (as used) | Purpose |
|---|---|
| `StopMusic()` | Kill Java's `PlayerDied` sting (and any music) the instant death fires. Only calls `Music.stop()` — it does **not** touch the `musicVolume` field, so it is safe to call before capturing baselines. |
| `playUISound(name)` | Fire `YouDiedSting` at `showDelay` and `UIActivateButton` on button clicks. |
| `getMusicVolume() / getSoundVolume() / getVehicleEngineVolume()` | Honest field mirrors — safe baselines. |
| `getAmbientVolume()` | **A stub: `return 1.0f`.** Never use it as a baseline; read `getCore():getOptionAmbientVolume() / 10` (§9.16). |
| `setMusicVolume(v) / setSoundVolume(v) / setAmbientVolume(v) / setVehicleEngineVolume(v)` | VCA writes. Drive the muffle ramp, the blackout silence, the click re-raise and the restore. `pcall`-wrapped throughout. |
| `getAmbientPieces()` | ArrayList of ambient "pieces"; each `piece:stop()` kills ambient music loops. |
| `stop()` | Stops every registered emitter, the UI emitter and music, then clears the emitter registry. One-shot only, flag `stopAllEmitters` (§9.14). |
| `dumpEventInstancesToTextFile()` | Writes every live FMOD event instance to `sound-event-instances.txt` (§9.17). |

### 5.3 GameSounds / GameSound (static `GameSounds`, objects from it)

Used to silence **scripted sounds** (house alarm, fire, generators, guns, thunder…) that no
VCA covers. `M-DS`, `A-DS`. **None of this works unless
`SystemDisabler.setEnableAdvancedSoundOptions(true)` is set first** (§9.12):

| Call | Purpose |
|---|---|
| `GameSounds.getCategories()` | ArrayList of category name strings (e.g. `World`, `Object`, `Player`…). |
| `GameSounds.getSoundsInCategory(cat)` | ArrayList of `GameSound` objects for one category. |
| `GameSounds.getSound(name)` | Single sound by name, **null** if unknown (`getOrCreateSound` is the creating variant). Used for named stragglers the category walk misses. |
| `gs:getName()` | Key for the per-sound snapshot table. |
| `gs:getUserVolume()` | Record the original user volume — only truthful with the flag on. |
| `gs:setUserVolume(v)` | Duck (clamped to `[0, 2]`), restore later. **`UI` and `Music` categories are skipped** so clicks/music survive. Duck to `0.0001`, never 0 (§9.13). |

(Vanilla usage of the same API exists in `media/lua/client/OptionScreens/ISGameSounds.lua`.)

### 5.4 Textures (main mod UI only)

| Call | Purpose |
|---|---|
| `getTexture("media/ui/DarkSoulsDeath/you_died.png")` → fallback `getTexture("media/textures/DarkSoulsDeath/you_died.png")` | Load the image lazily inside `render()` (file-scope loads return nil). |
| same for `bar.png` | Gradient strip. |
| `tex:getWidth() / tex:getHeight()` | Derive aspect ratio → image height is computed, any exported aspect works. |
| `self:drawTextureScaled(tex, x, y, w, h, a, r, g, b)` | **Stretch exactly** — used for the full-width bar and the joypad icon. |
| `self:drawTextureScaledAspect(tex, x, y, w, h, a, r, g, b)` | **Preserve aspect** — used for the "YOU DIED" image. |

### 5.5 SearchMode overlay (`zombie/iso/SearchMode`, inner `PlayerSearchMode`)

| Call | Purpose |
|---|---|
| `getSearchMode():setEnabled(playerNum, true)` | Turn on the post-processing pass for that player. |
| `getSearchMode():getSearchModeForPlayer(playerNum)` | The per-player overlay object. |
| `overlay:getDesat():setTargets(a, a)` | Greyscale target (also `getBlur`, `getDarkness`, `getRadius`, `getGradientWidth` — the death hook zeroes all five once). |
| `overlay:getDesat():setExterior(v)` / `setInterior(v)` | **Direct** value set — `setTargets` alone is eased by the engine and lands late; direct setters hit exact timeline marks. Same pattern on `getDarkness()`. |

`getBlur`/`getRadius`/`getGradientWidth` are only **zeroed** at death (they are the
foraging search-mode visuals that must not show); `getDesat`/`getDarkness` are the ones
driven every frame. Vanilla precedent for all of these:
`media/lua/client/Foraging/ISSearchManager.lua` (calls `setTargets`), and
`media/lua/client/DebugUIs/DebugMenu/General/ISSearchMode.lua` (exposes every float plus
its `get/setExterior`/`get/setInterior`).

### 5.6 World iteration & zombie emitters (stopper loop)

Runs every `OnTick` while `DarkSoulsDeathStopZombiesActive` is true (set at blackout,
cleared on restore/respawn):

| Call | Purpose |
|---|---|
| `getCell():getObjectListForLua()` | ArrayList of world objects **with** `size()`/`get(i)` — the plain `getObjectList()` variant is unusable from Lua (dead end §9.2). |
| `list:size()`, `list:get(i)` | Iteration. |
| `instanceof(obj, "IsoZombie")` | Filter to zombies only. |
| `obj:getEmitter()` | The zombie's sound emitter. |
| `em:stopAll()` | Kill every vocal/step sound the zombie is playing. |
| `getAmbientStreamManager():stop()` | Stop ambient streams (wind/bugs). |
| `getSoundManager():getAmbientPieces()` → `piece:stop()` | Stop ambient music pieces. |

### 5.7 Core / game state (from `getCore()`, globals)

| Call | Purpose |
|---|---|
| `getCore():getGameMode()` | `"A Really CD DA"` → "CONTINUING DISABLED…" challenge label + no respawn; `"Tutorial"` → no respawn. |
| `getCore():getOptionMusicVolume()/getOptionSoundVolume()/getOptionAmbientVolume()` | Baseline fallbacks when the SoundManager getters fail. |
| `getCore():quitToDesktop()` / `getCore():exitToMenu()` | End-game actions (after volume restore). |
| `IsoPlayer.allPlayersDead()` | Static: shows **Quit**/**Exit** only when the whole session is dead. |
| `playerObj:getPlayerNum()` | Index into overlay/UIManager/joypad tables (Lua tables keyed `playerNum+1`). |
| `getGameTime():getDeathString(playerObj)` / `getZombieKilledText(playerObj)` / `getGameModeText()` | The real survival stats shown in the CHARACTER STATS view. |

### 5.8 UI construction & drawing (both `ISPostDeathUI` overrides)

Inheritance: `ISPostDeathUI = ISPanelJoypad:derive("ISPostDeathUI")` — the vanilla base
class is `ISPanelJoypad` (itself an `ISUIElement`/`ISPanel` derivative), so the mod gets
joypad focus plumbing for free.

Base-object lifecycle used:

| Call | Where |
|---|---|
| `ISPanelJoypad:new(x,y,w,h)`, `setmetatable`, `instantiate()` | Both UIs (`new`) |
| `addToUIManager()` / `ISUIElement.removeFromUIManager(self)` | Both UIs |
| `setX/Y/Width/Height(...)`, `setAnchorLeft/Top(false)` | Both UIs |
| `setAlwaysOnTop(true)` + `bringToTop()` every frame | Both UIs — keeps the death UI above other UI mods |
| `javaObject:setIgnoreLossControl(true)` | Both UIs — full-screen panel must not eat mouse on other players' loss of control |
| `setStencilRect(...)` / `clearStencilRect()` | Both UIs — clip rendering to this player's screen area |
| `setVisible(false)` | Respawn path |
| `ISUIElement.setVisible`, `isReallyVisible()` | Both UIs |
| `getMouseX()/getMouseY()` | M manual hit-testing |
| `getAbsoluteX()/getAbsoluteY()` | M coordinate conversion (§10) |
| `getWidth()/getHeight()` on textures | M |
| `ISUIHandler.visibleUI` + `panel.javaObject:toString()` | Both UIs — register the panel as "visible UI" when the main menu is behind us (vanilla pattern) |

Panel drawing helpers (M draws everything itself; A delegates to vanilla):
`drawRect`, `drawRectBorder`, `drawText`, `drawTextCentre`, `drawTextureScaled`,
`drawTextureScaledAspect` — plus `getTextManager():MeasureStringX(font, s)`,
`getTextManager():getFontHeight(UIFont.X)` and (A's vanilla render)
`getTextManager():DrawStringCentre(font, x, y, s, r, g, b, a)`. Fonts come from the
engine `UIFont` table (`UIFont.Small/Medium/Large`). Frame time comes from
`UIManager.getMillisSinceLastRender()`.

Modal quit dialog (both UIs, identical vanilla pattern): `ISModalDialog:new(x, y, w, h,
text, true, owner, ISPostDeathUI.onConfirmQuitToDesktop, player)` then
`modal:initialise()`, `modal:addToUIManager()`, `modal:setAlwaysOnTop(true)`,
`modal:bringToTop()`; answer arrives as `button.internal == "YES"`. A re-brings it to
top every frame while visible; M does the same and additionally **stops drawing its own
window/text while the dialog is up** so the dialog floats over pure black (§10).

Joypad API (controller support): `JoypadState.players[playerNum+1]` (exists = controller
active), `JoypadState.saveFocus[...]`, `JoypadState.players[i].focus`, `.prevFocus`,
`.id`; button constants `Joypad.AButton/XButton/BButton/YButton` and face-button icons
`Joypad.Texture.AButton/XButton/BButton/YButton`; focus helpers
`setISButtonForA/B/X`, `clearJoypadButton()` (A's vanilla-style buttons), manual
`onJoypadDown` dispatch (M's custom window). Respawn opens character creation through
`CoopCharacterCreation.newPlayer(joypadData.id, joypadData)` or
`CoopCharacterCreation:newPlayerMouse()` (vanilla API).

### 5.9 Controller glyphs — how PZ expects them to be drawn

- `Joypad.Texture.*` values are **not** textures. `media/lua/client/ISUI/Gamepad/
  JoyPadSetup.lua` builds each as a `JoypadIconTextureGetter` (an `ISUITextureGetter`)
  whose file is resolved lazily as
  `media/ui/controller/<getCore():getOptionControllerButtonStyleString()>_<suffix>.png`.
  Verified shipped prefixes: `XBOX_*`, `PS4_*`, `STEAMDECK_*`; every glyph is 32x32.
- Passing the getter object straight to any `ISUIElement:draw*Texture*` helper is correct:
  each of those calls `ISUITextureGetter.checkGetTexture(texture)` before the Java draw.
  Calling `Joypad.Texture.AButton:getTexture()` first also works but freezes the choice.
- The glyph follows the user's controller automatically. `Joypad.initControllerButtonStyle`
  is re-run on `Events.OptionControllerButtonStyleChanged`, and connecting a PlayStation
  pad forces style 2 (PS4) in `onJoypadActivate`. `ISUITextureGetter:setFileNamePrefix`
  drops the cached texture when the style changes.
- Vanilla's own death panel registers its buttons with `setISButtonForA/B/X` inside
  `onGainJoypadFocus` (`ISPanelJoypad` stores `ISButtonA/B/X` and calls `setJoypadButton`
  on the `ISButton`). A hand-drawn window cannot use that path, so drawing
  `Joypad.Texture.*` per frame plus dispatching input in `onJoypadDown` is the equivalent.
- Button *mapping* must match vanilla or the glyphs lie: vanilla is A = respawn,
  X = quit to menu, B = quit to desktop. The main mod adds Y = character stats and
  LBumper = reveal other windows.

---

## 6. Per-file call inventory (quick audit trail)

### 6.1 `M: DarkSoulsDeath.lua`
- Module-level: `Events.OnPlayerDeath.Add`, `Events.OnTick.Add`, `Events.OnPlayerUpdate.Add`.
- `snapshotGameSounds()`: `SystemDisabler.get/setEnableAdvancedSoundOptions` (§9.12),
  `GameSounds.getCategories()`, `cats:size()/get(i)`, `GameSounds.getSoundsInCategory(cat)`,
  `sounds:size()/get(j)`, `gs:getName()`, `gs:getUserVolume()`, then `GameSounds.getSound(name)`
  then `GameSounds.getSound(name)` for the `extraSounds` stragglers.
- `DarkSoulsDeathDuckGameSounds` / `DarkSoulsDeathRestoreGameSounds`:
  `entry.sound:setUserVolume(duckTo)` / `(...entry.volume)`, plus the one-shot
  `getSoundManager():stop()` when `stopAllEmitters` is on, and the flag save/restore.
- `DarkSoulsDeathStopZombieSounds`: `getCell()`, `cell:getObjectListForLua()`,
  `list:size()/get(i)`, `instanceof`, `obj:getEmitter()`, `em:stopAll()`.
- `DarkSoulsDeathStopAmbient`: `getAmbientStreamManager():stop()` (delay-gated, §9.15),
  `getSoundManager():getAmbientPieces()`, `pieces:size()/get(i)`, `p:stop()`.
- `DarkSoulsDeathStopWorldSounds`: `getSoundManager():setVehicleEngineVolume(0)` — the engine
  VCA, the only lever that reaches engine loops.
- `DarkSoulsDeathRefreshVolumes`: the four `getCore():getOption*Volume()` getters (§9.16).
- `DarkSoulsDeathRestoreAll`: `getSoundManager():setMusic/Sound/Ambient/VehicleEngineVolume(...)`.
- `onPlayerDeath`: `playerObj:getPlayerNum()`, `getSoundManager():StopMusic()`,
  `getSearchMode():setEnabled` / `getSearchModeForPlayer`,
  `overlay:getDesat/getBlur/getDarkness/getRadius/getGradientWidth` → `setTargets(0,0)`,
  volume getters, `getCore()` option getters, `SystemDisabler` statics.
- `OnTick` closure: volume refresh and the three stopper functions.
- `OnPlayerUpdate` closure: `player:getPlayerNum()`, `player:isDead()`.

### 6.2 `M: ISPostDeathUI.lua`
Full list is long; the distinct game APIs beyond the module file are:
`getTextManager()` (font heights/measure), `getPlayerScreenLeft/Top/Width/Height`,
`getTimestamp()`/`getTimestampMs()`, `getSoundManager():playUISound(...)` +
volume setters, `getSearchMode():getSearchModeForPlayer` + `getDesat()/getDarkness()`
`setTargets`/`setExterior`/`setInterior` (`pcall`), `IsoPlayer.allPlayersDead()`,
`isClient()`, `getNumActivePlayers()`, `getServerOptions():getBoolean(...)`,
`getCore():getGameMode()`, `UIManager.getMillisSinceLastRender()`, `getTexture(...)`,
texture `getWidth/getHeight`, all `self:draw*`/`drawTextCentre`, `JoypadState.players`,
`Joypad.Texture.*`, `MainScreen.instance`, `ISModalDialog` (full dance),
`setJoypadFocus`, `setGameSpeed`, `pauseSoundAndMusic`, `setShowPausedMessage`,
`getCore():quitToDesktop()/exitToMenu()`, `CoopCharacterCreation:newPlayer(Mouse)`,
`ISUIElement.*`, `ISUIHandler.visibleUI`, `Events.OnPlayerDeath.Add`,
`Events.OnKeyPressed.Add`, `getGameTime():getDeathString/getZombieKilledText/getGameModeText`,
plus `getText("UI_DarkSoulsDeath_*")` through the `dsText` fallback helper (§11.1).

Mod-specific UI state worth knowing: `revealOtherUI` (the SHOW/HIDE OTHER WINDOWS toggle,
which zeroes the darkness overlay and skips this panel's own black rect and "YOU DIED" art so
other mods' windows show through), and `firstFrameMs`/`soundEventsDumped` diagnostics.

### 6.3 `A: DarkSoulsDeathAudioOnly.lua`
Same audio machinery as M's module file (snapshot/duck/restore, zombie stopper, ambient
stopper, baselines, click re-raise) but the whole **timeline runs from an `OnTick`
handler** (no UI panel involvement) and it also subscribes `Events.OnMainMenuEnter` for a
clean restore when quitting to menu.

### 6.4 `A: ISPostDeathUI.lua`
This file is the **vanilla** B42 `ISPostDeathUI.lua` with exactly three injected hooks —
everything else is vanilla behaviour:
1. `configButton`: wraps each button's `onclick` so a press first calls
   `DarkSoulsDeathAudioPlayClick()` (which stops zombies, raises the SFX bus for 250 ms,
   plays `UIActivateButton`), then runs the original handler.
2. `onRespawn`: calls `DarkSoulsDeathAudioRespawn()` (stop zombie sounds once, keep SFX
   bus audible for character-creation clicks).
3. `removeFromUIManager`: calls `DarkSoulsDeathAudioRestore()` before the vanilla removal.

So A **does** ship an `ISPostDeathUI.lua` override even though it changes no visuals — see
the compatibility note in §12. It reuses the vanilla `ISButton` children, the vanilla
scroll-up text animation, and vanilla joypad focus (`setISButtonForA/B/X`,
`clearJoypadButton`), and its vanilla render path is why its buttons still work under the
vanilla draw order.

---

## 7. Sound script DSL used (data API)

Files: `media/scripts/sounds_DarkSoulsDeath.txt` and the override of
`media/scripts/generated/sounds/player/sounds_player_death.txt`.

Grammar used (semantics verified against the vanilla files, e.g.
`media/scripts/generated/sounds/zombies/sounds_zombie_voice_tutorial.txt` for `file=`):

```
module Base
{
    sound <Name>
    {
        category = <Player|UI>,          -- bus/category membership
        clip
        {
            event = <FMOD/event/path>,   -- OR:
            file  = media/sound/DarkSoulsDeath/you_died.ogg,   -- raw file fallback
            volume = 1.5,                -- per-clip gain (1.5 compensates the quiet raw ogg)
        }
    }
}
```

- `sounds_player_death.txt` re-declares **all three** sounds in the file: `PlayerDied`
  (→ `file = ...you_died.ogg`) plus the other two vanilla entries
  (`FemaleBeingEatenDeath`, `MaleBeingEatenDeath` with their FMOD `event`s) copied
  verbatim. A partial file containing only `PlayerDied` was **not tested** — treat
  script-file overrides as wholesale replacement and re-declare everything you want to
  keep.
- `YouDiedSting` is declared with `category = UI` **on purpose**: the per-sound
  user-volume duck skips `UI`/`Music`, so the sting is never ducked at the `GameSound`
  level. Caveat (unverified): UI sounds ride the same SFX bus as clicks (that is why
  clicks need the 250 ms bus re-raise), and the bus sits at `muffleLevel` (0.25) when the
  sting fires at 3 s — so the sting may be bus-muffled to ~25% (×1.5 clip gain ≈ 37.5%)
  rather than full-volume. It sounds correct in-game; if full volume is required,
  re-raise the SFX bus around the sting like the click path.
- `file =` paths are relative to the game's `media/` root, i.e. the shipped asset at
  `<mod>/media/sound/DarkSoulsDeath/you_died.ogg`.

---

## 8. Rendering semantics that shape the code

1. **Draw order inside a panel**: the panel's own `render()` executes after its child
   elements are drawn — i.e. **custom `render()` draws land *above* `ISButton`/child
   elements**. The M panel must therefore draw its entire window (buttons included)
   manually inside `render()` — real `ISButton` children would slide *under* the black
   rect. The A variant never draws a black rect, so it can keep real vanilla
   `ISButton`s.
2. **Panel-local coordinates**: draw calls take coordinates relative to the panel's
   top-left, not the screen. M's panel is sized to the player's screen rect
   (`getPlayerScreen*`) but draws using `screenX/Y − self:getAbsoluteX()/Y`.
3. **Top-most wins / UIManager order**: M is `setAlwaysOnTop(true)` and calls
   `bringToTop()` every frame so its black rect covers other UI mods; while the modal
   quit dialog is visible, M instead lets the dialog win (see §9.8).
4. **Search overlay is per-player** — indices come from `getPlayerNum()`, which is also
   why respawn restore is keyed on the same player number (§4 `OnPlayerUpdate`).

---

## 9. Confirmed NOT working / dead ends (do not retry)

Evidence basis: each item was confirmed on **Build 42 Stable 42.20.x** by inspecting the
game's own class files inside `projectzomboid.jar` (and the relevant vanilla scripts under
`media/scripts/`), and/or by exercising it in a running game. Re-verify per game build.

### 9.1 Audio — emitter volume control
- `BaseCharacterSoundEmitter.setVolume` takes **two** required args `(J, F)` (object +
  float) and is not a master-volume knob. There is **no per-emitter master volume**
  exposed; `em:stopAll()` (zero args) is what works. Consequences: zombies are silenced
  by *stopping* them every frame while the death menu is up, not by muting them.
  (Confirmed against `zombie/characters/BaseCharacterSoundEmitter.class`.)
- A master-mute knob for emitters does not surface from Lua (`GameSound`-level master
  volume / vocal-manager style APIs are not usable for this). The working model is:
  per-sound user volumes + per-emitter `stopAll()` + bus volumes.

### 9.2 World object iteration
- `IsoCell:getObjectList()` exists but its result is **not indexable from Lua**
  (no `get` method on it in 42.20). Use `IsoCell:getObjectListForLua()`, which returns
  an ArrayList with `size()`/`get(i)`. (Confirmed against `zombie/iso/IsoCell.class`.)

### 9.3 Ambient audio
- `AmbientStreamManager:stopAll()` is **not exposed** to Lua — calling it is a nil
  call. `stop()` (inherited from `BaseAmbientStreamManager`) is the exposed one.
  (Confirmed against the ambient manager classes in the jar.)
- `getSoundManager():getAmbientPieces()` → `piece:stop()` works for ambient music
  pieces and is used every frame.

### 9.4 Vehicles / world one-shots
- `BaseVehicle:stopAll()` is **not exposed** to Lua (nil call). (Confirmed against
  `zombie/vehicles/BaseVehicle.class`.)
- `WorldSoundManager:clear()` is **not exposed** to Lua (nil call). (Confirmed against
  `zombie/WorldSoundManager.class`.) `KillCell()` exists but `WorldSoundManager` is the AI
  **hearing** list, not audio, so it silences nothing audible (§9.14).
- What actually works for vehicles: `BaseVehicle:getEmitter()` +
  `BaseSoundEmitter:stopAll()` (public), `BaseVehicle:getVehicleSounds():remove()`, and above
  all the `vca:/Settings_VehicleEngines` write — engine loops read the static
  `VehicleSounds.SOUND_VOLUME` and ignore per-sound volumes entirely, so the VCA is the only
  reliable lever. **Confirmed silent in game.**
- Superseded note: the earlier conclusion that a playing alarm or world one-shot cannot be
  silenced during the character-creation screen was wrong — it was the
  `GameSound:getUserVolume()` gate (§9.12), not a missing API. Alarms, fire, generators and
  engines are all confirmed silent now.

### 9.5 Lua error handling
- Kahlua `pcall` **does not catch Java-side nil-call / wrong-arity exceptions** — they
  propagate into the Mod Report. All risky setters are still `pcall`-wrapped (defensive),
  but the real protection is checking the method exists in the `.class` file first.
  This is why every dead end above was confirmed against the class files before being
  trusted.

### 9.6 Images
- PZ's PNG loader **rejects 16-bit PNGs** (`Unsupported bit depth: 16`). Shipped PNGs must
  be 8-bit (palette images were converted to 8-bit RGBA).
- `getTexture()` at **file scope returns nil** before the asset is available — must be
  called lazily inside `render()`.
- `drawTextureScaledAspect` preserves aspect ratio, so using it for the 1px-wide
  `bar.png` leaves it ~1px wide — the full-width bar needs `drawTextureScaled` (exact
  stretch). The "YOU DIED" png conversely needs `drawTextureScaledAspect`.

### 9.7 Overlay timing
- `SearchModeFloat.setTargets(a, a)` alone is engine-eased and lands **late** against the
  mod's exact timeline; the per-frame code also calls the **direct** setters
  `setExterior(v)`/`setInterior(v)` so desaturation completes at exactly 4 s and blackout
  at exactly 8 s.

### 9.8 UI stacking
- Child UI elements (incl. `ISButton`s and other mods' panels) render **below** a
  parent's custom `render()` draws → the M window is manually drawn + hit-tested
  (`buttonAt` from stored `buttonRects`, pressed state from `onMouseDown/Up`) instead of
  using `ISButton` children.
- A full-screen always-on-top panel **steals clicks from a modal dialog** below it:
  the quit-confirm `ISModalDialog` must be `setAlwaysOnTop(true)` and re-brought to top
  every frame while visible, and while it is up M draws only the black rect and lets
  mouse events pass through (`onMouseDown/Up` return false).

### 9.9 Audio "mute everything but UI" does not exist
- There is **no single engine switch** for "SFX silent, UI clicks audible": UI clicks
  live on the same SFX VCA as game sounds. The mod therefore combines: SFX VCA → 0 at
  blackout, briefly re-raised for 250 ms per click (`clickUntil`) and held for the
  character-creation screen; music VCA kept alive and ramped back; ambient VCA → 0;
  vehicle-engine VCA → 0; the advanced-sound flag enabled so per-sound volumes count;
  every non-UI/non-Music `GameSound` ducked to `0.0001` (snapshot/restore); ambient
  streams, ambient pieces and zombie emitters stopped per frame; `am:stop()` delayed until
  the duck has landed.
- Click sounds are the reason the SFX VCA has to come back up at all, and that window is
  exactly where anything still on the SFX VCA becomes audible — so the per-sound duck, not
  the VCA, is what makes the button presses quiet.

### 9.10 Death-music ordering
- Trying to just override the music and *not* stop it fails in co-op and double-plays
  the sting: Java's `playMusic("PlayerDied")` fires **before** the Lua `OnPlayerDeath`
  event and **only when `allPlayersDead()`** (§3.1). Required sequence: kill in the
  event hook, re-trigger via `playUISound("YouDiedSting")` exactly at `showDelay`.

### 9.11 Java *instance* fields are not reachable from Lua
- PZ's Lua exposes a curated set of Java classes (`zombie/Lua/LuaManager$Exposer extends
  se/krka/kahlua/integration/expose/LuaJavaClassExposer`, `shouldExpose`). Verification of
  `LuaJavaClassExposer.exposeStatics(Class, KahluaTable)`: it is the **only** method that
  reads `Class.getFields()`, and every field it publishes is guarded by
  `isStatic(Member)`. `exposeMethods` reads `getDeclaredMethods()` only. There is no
  `FieldCaller` in `se/krka/kahlua/integration/expose/caller/` — only
  `MethodCaller`/`ConstructorCaller`.
- Consequence: **public methods work, public STATIC fields work, public INSTANCE fields do
  not.** So `getSoundManager().soundVolume`, `getAmbientStreamManager().alarmList`,
  `getWorldSoundManager().soundList` and `WorldSound.volume` are all unreachable, even
  though javap shows them as `public`. Do not plan an implementation around reading or
  writing an instance field.

### 9.12 Per-sound volumes lie unless a system flag is on
This is the single most important finding in this document. Everything in §9.13 depends on it.

```java
// zombie/audio/GameSound
public float getUserVolume() {
    if (!SystemDisabler.getEnableAdvancedSoundOptions()) return 1.0f;   // hardcoded
    return this.userVolume;
}
```

- `GameSound.setUserVolume(F)` clamps to `[0, 2]` and stores the value, but the getter above
  may ignore it entirely. With the flag off, **every per-sound duck is a silent no-op**: the
  call succeeds, no error is raised anywhere, and the engine keeps using 1.0.
- `SystemDisabler` is exposed to Lua and the accessors are public statics:
  `SystemDisabler.getEnableAdvancedSoundOptions()` / `setEnableAdvancedSoundOptions(Z)`.
  Vanilla calls other statics on the same class (`MainOptions.lua:2130`,
  `DebugUIs/Scenarios/LotsaZombies.lua:36`), which is what proves both are reachable.
- Only one class reads the flag: `zombie/audio/GameSound` (verified by scanning every class
  in the jar for the string). Turning it on therefore changes nothing except making
  `userVolume` meaningful.
- Consequences for any mod that ducks per-sound volumes: enable the flag **before**
  snapshotting (otherwise every captured value reads 1.0 and the restore wipes a player's
  custom per-sound mix), restore the volumes, then restore the flag to its previous value.

### 9.13 Duck to a tiny value, never to exactly 0
`zombie/iso/Alarm.updateSound()`, runs every frame while the alarm is updated:

```java
float vol = SoundManager.instance.getSoundVolume();   // fetched, then discarded
vol = 1.0f;                                           // the SFX bus never affects an alarm
GameSound gs = GameSounds.getSound("HouseAlarm");
if (gs != null) vol *= gs.getUserVolume();
if (vol != this.volume) { SetVolume(Alarm.inst, vol); this.volume = vol; }
```

- **The house alarm ignores the SFX bus entirely.** `getSoundVolume()` is called and thrown
  away in favour of a hardcoded `1.0f`, so no VCA or bus trick can ever silence it. Its only
  lever is `GameSound("HouseAlarm").getUserVolume()`.
- `Alarm.<init>(int, int)` sets only `x`, `y` and `endGameTime` — a **fresh** `Alarm` has
  `volume == 0.0f`. Ducking to exactly `0` therefore makes the guard `0.0 != 0.0` false,
  `SetVolume` is never called, and the new event plays at FMOD's default volume. The symptom
  is a *new* alarm sounding after the death screen began while an alarm already playing at
  death is silenced correctly (its `volume` is still `1.0`, so the guard holds).
- So duck to `0.0001` (≈ −80 dB) rather than 0. The mod exposes this as
  `DarkSoulsDeathSilence.duckTo`. The same guard shape may exist elsewhere, so the epsilon is
  applied to every ducked sound rather than special-cased.

### 9.14 Silencing sound sources — what is actually reachable

**The bus model.** Each `SoundManager` volume setter is a thin wrapper over one FMOD Studio
VCA (`FMOD_Studio_System_GetVCA` + `FMOD_Studio_VCA_SetVolume`), and `zombie/SoundManager.class`
contains exactly four VCA paths:

| Setter | FMOD VCA |
|---|---|
| `setSoundVolume(F)` | `vca:/Settings_Sfx` |
| `setAmbientVolume(F)` | `vca:/Settings_Ambience` |
| `setMusicVolume(F)` | `vca:/Settings_Music` |
| `setVehicleEngineVolume(F)` | `vca:/Settings_VehicleEngines` |

A VCA at 0 is a hard mute for everything routed through it, whatever object started the
sound. Which events are routed where lives in the FMOD bank and is **not** derivable from the
jar — the table below records what was confirmed in game.

| Source | Call (0 args unless shown) | Notes |
|---|---|---|
| Everything on the SFX VCA | `getSoundManager():setSoundVolume(0)` | Covers alarms, generators, guns, thunder and the UI clicks (which is why clicks need the 250 ms re-raise). Not the engine VCA. |
| Ambient VCA | `getSoundManager():setAmbientVolume(0)` | Works, but **not** for rain/world ambience (§9.15). |
| **Vehicle engines** | `getSoundManager():setVehicleEngineVolume(0)` | The only lever that reaches engine loops: `EngineSound.update()` writes its instance volume straight from the static `VehicleSounds.SOUND_VOLUME` and never consults `GameSoundClip.getEffectiveVolume()`. Confirmed silent in game. |
| Music (kept audible) | `getSoundManager():setMusicVolume(v)` | Driven on the mod's timeline. |
| Scripted one-shots | `GameSounds.getCategories()` → `getSoundsInCategory(cat)` → `setUserVolume(duckTo)` | Skips the `UI` and `Music` categories. **Only works with the flag from §9.12 enabled.** |
| Named stragglers | `GameSounds.getSound(name)` → `setUserVolume(duckTo)` | `getSound` returns null for unknown names (`getOrCreateSound` is the creating variant). Used for `HouseAlarm`, `Fire`, `Generator`, `GeneratorLoop` on top of the category walk. |
| Ambient streams, ambience emitters, rain | `getAmbientStreamManager():stop()` | See §9.15 for exactly what it stops and the ordering rule. |
| Ambient "pieces" | `getSoundManager():getAmbientPieces()` → `piece:stop()` | Real `Audio` handles; safe. |
| Queued world one-shots | `getWorldSoundManager():KillCell()` | `WorldSoundManager` is the **AI hearing** list, not audio — `WorldSound` has no event handle and there is no `clear()`. Silences nothing audible, so the mod does not call it. |
| Every registered emitter + all channels | `getSoundManager():stop()` | Stops parameter-bound event instances, the UI emitter, `StopMusic()` when the current music matches, `stopAll()` on every emitter in the private `emitters` HashSet (then clears it), and `FMOD_ChannelGroup_Stop(masterChannelGroup)`. Nuclear and destructive — the registry has no getter and is repopulated only by emitter constructors. One-shot only, never per tick, and it also kills music and the UI emitter, so the mod does not use it. |
| Vehicle emitters | `instanceof(obj, "BaseVehicle")` → `obj:getEmitter():stopAll()` | Public, but redundant with the engine VCA and walks the whole cell object list every tick, so the mod does not use it. |
| Animal emitters | `getCell():getAnimals()` → `animal:getEmitter():stopAll()` | Public, and covered by the per-sound duck. Not used by the mod. |
| Fire | `IsoFireManager.FireStack` (public static `ArrayList`) → `IsoFireManager.stopSound(fire)` (public static) | `stopSound` only calls `FireSounds.removeFire`, which is `fires.remove(fire)` — it **orphans** the sound slot rather than stopping it, and `IsoFireManager.Update()` re-adds burning fires each frame. Measured in game: the fire stayed audible, so the mod relies on the per-sound duck instead. `IsoFireManager.Reset()` is an instance method with no getter, so it is unreachable. |
| House alarm (`zombie/iso/Alarm`) | none | Owns a raw FMOD studio event; `finished`/`volume`/`endGameTime` are **instance** fields (§9.11) and the class is not exposed. Its volume is `1.0 × userVolume` (§9.13), so the per-sound duck is the only lever. |
| Generator (`zombie/iso/objects/IsoGenerator`) | none | `stopAllSounds()` is private; `setActivated(false)` is public but mutates world state. Covered by the duck and the SFX VCA. |
| Flies (`zombie/FliesSound`) | none | Not exposed, and no getter exists anywhere in the jar. Covered only by the SFX VCA. |
| Thunder | none | Thunder **rumbles are unreachable**: `ThunderStorm.events` is a private `ThunderEvent[]`, `ThunderEvent` has a private constructor and no stop method, and `stopCloud(i)` / `stopAllClouds()` act on lightning clouds, not rumbles. A rumble that *starts* while the mod is muted is silent (its volume is read from the ducked `GameSound` at start — confirmed in game). One that started **before** the duck keeps its volume and is governed only by the SFX VCA, so it can return when character creation raises that VCA (§9.15). |
| Gunshots / explosions | SFX VCA + per-sound duck | Confirmed by ear against a **control**: `M1911Shoot` played via `PlayWorldSound` at 2 s after death is clearly audible, and the same call during the character-creation screen is silent. |
| TVs / radios | SFX VCA + per-sound duck | Confirmed silent in game; media devices are ordinary emitters on the SFX VCA, so both levers apply. |

### 9.15 `AmbientStreamManager:stop()` — the only lever for rain, and its ordering rule
- **Rain is not a scripted sound.** There is no `sound *Rain*` anywhere under
  `media/scripts/`; it is the **world ambience** event driven by
  `ParameterRainIntensity` on the ambience emitter. The four VCAs do not reach it and there is
  no `GameSound` to duck, which is why zeroing `Settings_Ambience` never touched it.
- `AmbientStreamManager.stop()` (bytecode, in order): iterates `allAmbient` calling
  `AmbientLoop.stop()`; clears `ambient`, `dayAmbient`, `indoorAmbient`, `nightAmbient`,
  `outdoorAmbient`, `rainAmbient`, `windAmbient` **and `alarmList`**; stops
  `electricityShutOffEmitter`; runs `stopWorldAmbiance()` → `worldAmbienceEmitter.stopAll()`;
  then `worldAmbienceEmitter.stopAll()` again.
- `worldAmbienceEmitter.stopAll()` is what kills rain, and `stop()` is the only public route
  to it (`stopWorldAmbiance` is private and there is no other stopper on the class).
- **Ordering rule:** clearing `alarmList` is permanent, because `doAlarm(RoomDef)` is a
  one-shot trigger called only when an alarm starts (`IsoWindow`, `BaseVehicle`,
  `IsoGameCharacter`, `AlarmCommand`, `GameClient`) — nothing re-adds it per frame. Once the
  list is cleared, `Alarm.update()` never runs again, so the alarm's volume is frozen at
  whatever was last applied and its `endGameTime` check never fires either.
  Therefore the per-sound duck must land on a sounding alarm **before** the first `stop()`.
  The duck runs at blackout (in `prerender`, render phase) and `stop()` is held back by
  `DarkSoulsDeathSilence.ambientStreamStopDelay` (default 0.5 s) and then called every tick.
  Without the delay the alarm can be orphaned a frame early at its pre-duck volume of 1.0 —
  audible on every button press and through character creation.
- Known side effect: an alarm sounding at the moment of death may stay silent for the rest of
  the session, because clearing the list also prevents its timer from ever expiring.

### 9.16 Volume baselines must follow the live options
- The four option getters return **int** in 42.x and `Core.setOption*Volume(int)` feeds the
  VCA with `option / 10.0`, so a VCA value is in `0 .. 2`. Never mix the option scale and the
  `SoundManager` scale in one baseline.
- `SoundManager.getAmbientVolume()` is a **stub** whose whole body is `return 1.0f`, so it
  cannot be used as a baseline at all — read `getCore():getOptionAmbientVolume() / 10` instead.
  `getMusicVolume()`, `getSoundVolume()` and `getVehicleEngineVolume()` are honest field
  mirrors (`getfield`/`putfield` on the matching field).
- The player can open the ESC options screen **while the death screen is up**, and the options
  screen writes through `getCore():setOption*Volume()` (`MainOptions.lua:1919`, `:1940`). A mod
  that captures baselines once at death and re-applies them every frame will overwrite that
  change on the next frame, and write the stale value back on restore. The mod therefore
  re-reads the options every tick while a death is active
  (`DarkSoulsDeathRefreshVolumes()` / `refreshBaselines()`), so the live option always wins.

### 9.17 Diagnosing a leak: dump live FMOD events
- `getSoundManager():dumpEventInstancesToTextFile()` writes **every live FMOD studio event
  instance** (path + instance count, sorted, highest first) to
  `sound-event-instances.txt`, overwriting it each call.
- The path is built from `ZomboidFileSystem.getCacheDir()`, which returns the Zomboid folder
  **without a trailing separator** (use `getCacheDirSub(name)` or append one). On this install
  the file lands at `~/Zomboid/sound-event-instances.txt`, not in a `cache/` subfolder.
- Lua **cannot read that file back**: `getFileReader`/`getFileWriter` resolve every path
  against `LuaManager.getLuaCacheDir()` and return null for any path containing `..`. Read it
  from outside the game instead.
- This is the fastest way to name a leak: dump on a schedule, reproduce the death, then read
  the file and compare against what you heard. It replaces guesswork about which class started
  an event — that is how the house alarm, the vehicle alarm, the generator loop, the fire and
  the world ambience were each identified.

### 9.18 Test plan for the remaining unknowns
The mod itself now ships no test hooks; these are methods to reach for when something is
reported. Re-add logging locally, change one thing at a time, and restart the game (mod Lua
loads at boot).

1. **To name an unheard sound:** call `dumpEventInstancesToTextFile()` on a schedule (§9.17)
   and log the bus values and the effective `getUserVolume()` of the suspects next to it —
   the pair is what turns "I still hear something" into a cause. Print with a greppable prefix
   so the lines can be pulled out of a multi-megabyte `console.txt`.
2. **Still untested by ear:** car horns and vehicle collisions, and any sound started by a
   third-party mod rather than the base game. Multiplayer sound paths are untested.
3. **Per-sound restore vs a player edit.** The duck snapshots ~3300 `GameSound` volumes and
   writes them back on restore, so per-sound edits made on the hidden advanced-sound screen
   during the death screen would be reverted.
4. **Character-creation window.** `DarkSoulsDeathRestoreAll` raises the SFX VCA while the
   new-character screen is up so its buttons click. Anything still audible there must be on
   the SFX VCA, be the engine VCA, or not be a scripted sound at all.

### How a sound was proved blocked

"Silent when muted" is worthless without knowing the sound *would* have played. Anything
verified here was tested with a **control**: the same sound triggered once in a window where
the mod is not silencing (before the blackout, where the buses are only part-muffled) and once
in the strict window (the character-creation screen, where the SFX VCA is raised). Audible
control plus silent test is the only combination that means anything.

Confirmed that way, in game: house alarms (including one starting *after* the death screen
began), fire, generators, car engines, TVs, rain/world ambience, **thunderclaps** and
**gunshots** are all silent on the death menu, on every button press and throughout character
creation, while music and UI clicks stay audible.

One residual limit is documented in §9.14: a thunder rumble that started **before** the duck
keeps the volume it was given, because `ThunderStorm` keeps its events in a private array with
no public stopper. Such a rumble is inaudible while the death menu holds the SFX VCA at 0, and
can become audible again when the character-creation screen raises that VCA for its buttons.




---

## 10. Lesser gotchas (worked around, worth knowing)

- All timing lives in one table (`DarkSoulsDeathTiming` / `DarkSoulsDeathAudioTiming`),
  with **fallback defaults duplicated inline in `ISPostDeathUI.lua`** because mod Lua
  load order is not guaranteed — a missing table must not nil-crash the panel. Every extra
  silencing behaviour is likewise a flag on `DarkSoulsDeathSilence`.
- **Death panel lifecycle (verified):** vanilla `ISPostDeathUI.OnPlayerDeath` creates a new
  panel per death and never removes the previous one — the previous panel is removed by
  `CoopCharacterCreation:accept()` (`instance[playerIndex]:removeFromUIManager()` +
  `instance[playerIndex] = nil`), and `CoopCharacterCreation:cancel()` re-shows it with
  `setVisible(true)`. So "the old death menu is only cleared on the next death" is *not*
  vanilla; vanilla clears it on respawn and the main mod additionally removes a stale panel
  in its own `OnPlayerDeath` (via `ISUIElement.removeFromUIManager`, deliberately bypassing
  its own `removeFromUIManager` override so volumes are not restored early). Harmless in
  the normal flow — at that point `instance[playerNum]` is already nil.
- **Revealing other mods' windows (mod-agnostic).** The black screen is drawn twice: by the
  `SearchMode` **darkness** overlay and by the panel's own full-screen `drawRect`. A mod
  that pops a window up on death (e.g. a report viewer) renders *below* the always-on-top
  panel, so it is invisible. Zeroing both darkness values while keeping the panel
  transparent is enough to reveal those windows **without knowing their names**: the panel
  is `background = false` and only draws the black rect, the "YOU DIED" art and its button
  window. `ISUIElement:onMouseDown/onMouseUp` returning `false` also lets clicks fall
  through — `UIManager.updateMouseButtons` walks `UIManager.UI` from the end and stops only
  at the first element whose `onConsumeMouseButtonDown` returns `true`, which is exactly the
  Lua `onMouseDown` return value. The desaturation part of the overlay is deliberately kept,
  so revealing returns the player to a greyscale world, matching the original design.

- Restore points differ by exit path on purpose: **Exit/Quit/panel-removal restore
  everything**; **Respawn does not** (SFX bus is kept up for character-creation clicks,
  the stopper stays on) and full restore waits for `OnPlayerUpdate` to report the same
  player number alive again.
- Busy-loop stoppers run every `OnTick` *only while a flag is set*
  (`DarkSoulsDeathStopZombiesActive`) so they cost nothing the rest of the game.
- Button hover is replicated (M) with the standard `ISButton` look
  (`backgroundColor` 0.8 alpha → hover fill `{0.3,0.3,0.3,1.0}`, border unchanged) via a
  0.15 s ease on `hoverFade`, driven by hit-testing the **previous frame's** rects.
- The strings `"CHARACTER STATS"` and `"YOU DIED"` (the panel's `lines[1]` placeholder)
  are **no longer hardcoded**: they are `UI_DarkSoulsDeath_*` keys resolved through `dsText`,
  which falls back to an inline English table when `getText` returns the key unchanged
  (§11.1). Labels that were always engine keys (`IGUI_PostDeath_*`) are localized by the game
  in all 30 shipped languages.
- **The volume baselines are live, not captured.** They are re-read from the game options
  every tick while a death is active, because the player can change them from the ESC menu
  mid-death-screen; a captured snapshot would overwrite the change on the next frame and
  write the stale value back on restore (§9.16).
- **Duck to `0.0001`, not 0**, and only while the advanced-sound flag is on — otherwise the
  duck is a silent no-op or is skipped by an instance's `vol != this.volume` guard (§9.12,
  §9.13). The flag is snapshot before and restored after, and it must be enabled *before* the
  per-sound snapshot so the captured values are real.
- `am:stop()` is held back by `ambientStreamStopDelay` after the duck so a sounding alarm
  gets at least one frame with the ducked volume before `alarmList` is cleared (§9.15).
- One latent edge case: the per-sound restore writes back every captured `GameSound`
  `userVolume`, so per-sound edits made on the hidden advanced-sound screen *during* the death
  screen would be reverted.
- `IsoPlayer.allPlayersDead()` gates Quit/Exit buttons; respawn is additionally gated by
  `isClient() or getNumActivePlayers() > 1`, game mode `~= "Tutorial"`, and the
  `DropOffWhiteListAfterDeath` server option — logic copied from vanilla so behaviour
  matches the base game.

---

## 11. Translation keys and literal strings used

`getText()` keys (EN values as shipped):
`IGUI_PostDeath_Respawn` = "CONTINUE WITH NEW CHARACTER",
`IGUI_PostDeath_Challenge` = "CONTINUING DISABLED IN THIS GAME CHALLENGE",
`IGUI_PostDeath_Exit` = "QUIT TO MENU", `IGUI_PostDeath_Quit` = "QUIT TO DESKTOP",
`IGUI_ConfirmQuitToDesktop` = "Quit to desktop?" (keys live under
`media/lua/shared/Translate/<LANG>/` in the game).

Literal strings that stay in code on purpose: `"A Really CD DA"`, `"Tutorial"`,
`"DropOffWhiteListAfterDeath"` — these are game-mode / server-option identifiers, not
display text. Sound names `"YouDiedSting"`, `"UIActivateButton"`, script sound `PlayerDied`
and the texture paths `media/ui|textures/DarkSoulsDeath/{you_died,bar}.png` are literals
too.

### 11.1 Adding a mod translation (Build 42 format)

1.14/42.15 moved game translations from `Translate/<LANG>/<Name>_<LANG>.txt` to **JSON**.
Verified behaviour (from `zombie/core/Translator` bytecode, real Workshop mods, and an in-game
test of this mod's own files):

- Path: `<mod>/<versionDir>/media/lua/shared/Translate/<LANG>/<Name>.json` — with a `42/`
  folder that is `42/media/lua/shared/Translate/...`. `Translator.readModTranslation`
  calls `mod.getVersionDir()`, so the root `media/` layer is *not* consulted for these.
- The `<Name>` must be one of the loader's known file names: `UI`, `IG_UI`, `ItemName`,
  `Recipes`, `RecipeGroups`, `ContextMenu`, `Tooltip`, `Moodles`, `Attributes`,
  `BodyParts`, `Challenge`, `Credits`, `DynamicRadio`, `Entity`, `Farming`, `Fluids`,
  `GameSound`, `MakeUp`, `MapLabel`, `Moveables`, `Print_Media`, `Print_Text`,
  `RadioData`, `Recorded_Media`, `Sandbox`, `Stash`, `SurvivalGuide`, `SurvivorNames`,
  `EvolvedRecipeName` (see the game's own `media/lua/shared/Translate/EN/`).
- `getTextInternal(key)` dispatches on the key **prefix**: `UI_*` → the `UI.json` map,
  `IGUI_*` → `IG_UI.json`, and so on. A mod key must therefore both start with the right
  prefix and live in the matching file.
- Content is a flat JSON object, e.g.
  `{"UI_DarkSoulsDeath_YouDied": "YOU DIED"}`. A mod only ships **its own** keys —
  `tryFillMapFromFile` puts each entry into the shared map, so a partial file merges and
  never wipes the vanilla strings.
- Fallback is automatic: `Translator.forLanguageStack` walks current language → its
  `base()` → the default language, iterating the collected set in reverse, so EN is read
  first and the active language overwrites it. Shipping only `EN/UI.json` therefore gives
  every other language English text instead of a missing key. This is **per key**, so a
  partial translation only leaves the untranslated entries in English.
- A missing key makes `getText` return **the key itself**, so the shipped Lua keeps a tiny
  English fallback table and only trusts `getText` when it differs from the key.

**Which language is active** is the game's own option, not the OS locale:

`Translator.getLanguage()` reads `Core.getOptionLanguageName()` (persisted as
`language=EN` in `~/Zomboid/options.ini`), and only falls back to the system locale property
when that option is blank, then to EN. Changing it in **Options → Language** applies without
a restart: the dropdown's `apply` calls `setOptionLanguageName` + `Translator.setLanguage` +
`resetLua()` (`MainOptions.lua:1838`), and the resulting `Core.ResetLua(...)` calls
`Translator.loadFiles()`, which re-reads every file for the new language stack — mod files
included — and resets Lua so panels rebuild their cached labels.

**To add a language** (confirmed working end to end with a throwaway German file):

1. Create `<mod>/42/media/lua/shared/Translate/<LANG>/UI.json`, where `<LANG>` is the game's
   language code — the same names the game uses for its own folders (`EN`, `DE`, `FR`, `ES`,
   `ES_MX`, `PTBR`, `RU`, `UA`, `CN`, `JP`, `KO`, `PL`, …), because the option stores
   `Language.name()`.
2. Copy the four keys from `EN/UI.json` **verbatim** and translate only the values. The keys
   must not be renamed or re-prefixed, and the file must stay UTF-8 (no BOM).
3. Restart, or just switch language in-game — the maps are re-read either way.
4. Run `TEST_FILES/TEST-FILE_translation_keys.py`: it checks every shipped language against
   the Lua usage and the EN key set, so a typo'd or missing key is caught without launching
   the game.

**The trap worth knowing:** while only EN is shipped, a completely ignored translation file
looks identical to a working one — the Lua fallback prints the same English text and nothing
errors. To prove the JSON path is live, ship a second language (or temporarily mark an EN
string) and confirm the text actually changes. That is how this mod's mechanism was verified.

The "YOU DIED" artwork stays English: it is a PNG, not text.


---

## 12. Compatibility & re-use notes

- **Both mods override `ISPostDeathUI.lua`.** M replaces it with a full custom panel; A
  ships a copy of the vanilla file with three audio hooks. Either way it is a
  whole-file override, so any other mod that also overrides
  `media/lua/client/ISUI/ISPostDeathUI.lua` will conflict (one silently wins). The two
  mods in this package cannot be enabled together — `mod.info` declares them mutually
  `incompatible`.
- **Deployment convention:** install each mod as `<mods>/<mod id>/` (folder name matching
  the `id` in `mod.info`) so the mod manager and Workshop packaging line up; the folder
  name is what players see referenced in conflicts and logs.
- **Verification scope:** all API behaviour here was confirmed on Build 42 **Stable
  42.20.x**. APIs, class names, and even method arities change between builds — treat
  this document as build-specific and re-check against the game files and the in-game
  Mod Report after any update.

---

## 13. Game-install reference map (where the ground truth lives)

Game content root (Build 42.20.x): `<game>` = the game install's `projectzomboid/`
directory, e.g. `.../steamapps/common/ProjectZomboid/projectzomboid/` on a Steam install
(`C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\projectzomboid\` on a
default Windows install).

| Path in game | Why it matters |
|---|---|
| `media/lua/client/ISUI/ISPostDeathUI.lua` | The file both mods override; A's copy = this file + 3 hooks |
| `media/scripts/generated/sounds/player/sounds_player_death.txt` | Vanilla `PlayerDied` script the mod overrides |
| `media/scripts/generated/sounds/zombies/sounds_zombie_voice_tutorial.txt` | Vanilla `file =` raw-clip syntax example |
| `media/shaders/screen.frag` | `DesaturationVal` uniform the SearchMode overlay drives |
| `media/lua/client/Foraging/ISSearchManager.lua` | Vanilla user of `getSearchMode()` overlay floats (`setTargets`) |
| `media/lua/client/DebugUIs/DebugMenu/General/ISSearchMode.lua` | Exposes every `PlayerSearchMode` float + exterior/interior setters |
| `media/lua/client/OptionScreens/ISGameSounds.lua` | Vanilla `GameSounds`/`GameSound` category + user-volume usage |
| `media/lua/client/OptionScreens/MainOptions.lua` | The volume options: writes through `getCore():setOption*Volume()` (`:1919`, `:1940`) and reads `SystemDisabler.getEnableAdvancedSoundOptions()` (`:2130`) |
| `media/lua/client/OptionScreens/MainScreen.lua` | `OnMainMenuEnter` trigger site |
| `media/lua/shared/Translate/EN/…` | String keys (§11) |

Inside `<game>/projectzomboid.jar` (inspect with `javap` or by reading the class bytes):
`zombie/characters/IsoPlayer` (`OnDeath`), `zombie/SoundManager`, `zombie/GameSounds`,
`zombie/audio/GameSound*` (`GameSoundClip` fields `event`/`file`/`volume`, and the
`getUserVolume` flag gate), `zombie/SystemDisabler`, `zombie/iso/SearchMode`
(+ `PlayerSearchMode`, `SearchModeFloat`), `zombie/iso/Alarm` (`updateSound`),
`zombie/AmbientStreamManager` (`stop`, `stopWorldAmbiance`),
`zombie/iso/objects/IsoFireManager` (+ `FireSounds`), `zombie/iso/IsoCell`
(`getObjectListForLua`, `getVehicles`, `getAnimals`),
`zombie/characters/BaseCharacterSoundEmitter` (`setVolume(J,F)`), plus the ambient, vehicle,
and world-sound classes referenced in §9. These class files are the decompiled ground truth
for §3 and §9.

`javap` is not required — `TEST_FILES/TEST-FILE_classdump.py` and
`TEST-FILES_bytecode.py` read the class bytes directly and print fields/methods with real
JVM descriptors and disassembled bodies (§15).

---

## 14. Checklist for a future death-screen modder

If you copy this approach for your own death screen, the minimum API surface you will
touch is:

1. Override `media/lua/client/ISUI/ISPostDeathUI.lua` (visuals) — ship it in `<mod>/42/media/`
   for Build 42.
2. Override `media/scripts/generated/sounds/player/sounds_player_death.txt` (or add a new
   sound + play it) for the music/sting; keep other sounds in the file intact.
3. Hook `Events.OnPlayerDeath` → `getSoundManager():StopMusic()`, then capture baselines
   **from the game options** and re-read them every tick (§9.16).
4. To silence the world: enable `SystemDisabler.setEnableAdvancedSoundOptions(true)` (§9.12),
   duck every non-`UI`/`Music` `GameSound` to `0.0001` (§9.13), drive
   `set{Music,Sound,Ambient,VehicleEngine}Volume()`, zero the `SearchMode` darkness/desat via
   the direct setters, and run the stoppers: zombie `em:stopAll()`, ambient pieces `stop()`,
   and `getAmbientStreamManager():stop()` **only after** the duck has landed (§9.15).
5. Restore on `OnPlayerUpdate` (same player alive) or `OnMainMenuEnter`, including the
   `SystemDisabler` flag and the per-sound volumes.
6. Label every user-facing string with a `UI_*` key in `Translate/<LANG>/UI.json` (§11.1).
7. Do **not** retry anything in §9 without new evidence; re-verify signatures against the jar
   when the game updates, using the scripts in §15.

---

## 15. Verification tooling shipped with this repo

`TEST_FILES/` (gitignored) holds the scripts that produced every claim in §9. They are the
fastest way to re-verify after a game update, and they need no JDK — only Python 3.

| Script | What it does |
|---|---|
| `TEST-FILES_classdump.py` | Prints fields + methods (with JVM descriptors) for any class in the jar. `-m <class>` to dump, `-s <class> <needle>` to grep its strings. |
| `TEST-FILES_bytecode.py` | Disassembles a method with resolved constant-pool references and absolute branch targets, so you can trace `if (vol != this.volume)` style guards. |
| `TEST-FILES_verify_sound_api.py` | Asserts every method/field the mod's audio depends on still exists with the right descriptor. Exits non-zero on a game update that breaks one. |
| `TEST-FILES_verify_lua_globals.py` | Collects every real Lua global (exposed `LuaManager$GlobalObject` methods plus globals vanilla Lua defines) and reports any **bare call** in the mod's Lua that is not one of them. |
| `TEST-FILES_lua_balance.py` | Lua 5.1 lint: block balance, `...` outside a vararg function, and Lua 5.2+/5.3+ syntax Kahlua cannot compile. |
| `TEST-FILES_translation_keys.py` | Checks that Lua keys, the EN file and every other shipped language agree. |
| `TEST-FILES_lint_fixture.lua` | Regression fixture for the lint: one deliberately broken vararg block plus three legal ones. |

### 15.1 A constant-pool string is not proof of an API
The single most expensive mistake made while building this was checking that a name is
*mentioned* in a class's constant pool and concluding the Lua global exists. It does not:
`getCacheDir` appears in `LuaManager$GlobalObject`'s strings and is **not** a global, and
calling it threw at boot and aborted the whole `OnPlayerDeath` handler. The authoritative
list is the class's own public method set — which is what `TEST-FILES_verify_lua_globals.py`
reads.

### 15.2 Kahlua is Lua 5.1, and a compile error kills the whole file
`...` cannot be used inside a nested function — only in the vararg function itself:

```lua
local function log(fmt, ...)
	local args = {...}                                  -- OK: captured in the vararg function
	pcall(function() print(string.format(fmt, unpack(args))) end)   -- OK: closure sees args
	-- pcall(function() print(string.format(fmt, ...)) end)        -- ERROR: '...' outside a vararg function
end
```

`unpack` and `select("#", ...)` are both used by vanilla B42 Lua, so both are safe. A syntax
error is reported at boot as `KahluaException ... cannot use '...' outside a vararg function`
and **no part of that file loads** — the mod silently disappears from the death screen.
`TEST-FILES_lua_balance.py` exists to catch this before launching the game.
