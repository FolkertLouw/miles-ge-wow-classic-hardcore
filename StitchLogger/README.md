# StitchLogger

StitchLogger is a lightweight World of Warcraft Classic Hardcore addon for recording DaddyStitch field data during play.

The addon does **not** try to generate polished field-guide pages in-game. It records raw evidence into WoW SavedVariables. After a session, the SavedVariables file can be imported into the repository and transformed into structured JSONL, drop stats, skinning stats, quest pages, item pages, vendor pages, and route notes.

## Install

Copy the `StitchLogger` folder into your WoW Classic Era addon folder:

```text
World of Warcraft/_classic_era_/Interface/AddOns/StitchLogger/
```

The folder should contain:

```text
StitchLogger.toc
Tooltip.lua
DebugUI.lua
Core.lua
Skinning.lua
README.md
IMPORT_FORMAT.md
TOOLTIP_CAPTURE.md
```

Then launch/reload WoW and enable `StitchLogger` in the addon list.

If WoW marks the addon as out of date, the `## Interface` value in `StitchLogger.toc` may need to be updated to the current Classic Era client interface number.

## Commands

```text
/stitch start
/stitch stop
/stitch note <text>
/stitch snapshot
/stitch status
/stitch export
/stitch print on
/stitch print off
```

Debug window commands:

```text
/stitchdebug show
/stitchdebug hide
/stitchdebug toggle
/stitchdebug clear
```

Alias:

```text
/sldebug
```

Recommended play loop:

```text
/stitch start
/stitchdebug show
play normally
/stitch note only for human context
/stitch stop
logout or /reload
upload SavedVariables/StitchLogger.lua for import
```

## Debug window

`DebugUI.lua` adds a movable in-game dialog that shows a rolling live feed of events as they are written to the active session.

It displays short summaries for events such as:

- mob defeats
- XP gains
- loot messages
- skinning starts/completions
- skinning loot
- item tooltips from loot
- merchant opens/closes/purchases
- trainer opens/purchases
- quest panels/accepts/turn-ins
- money changes
- manual notes

The debug window is for confidence while testing. The SavedVariables file remains the source of truth.

## What it logs

### Automatic

- session start/end
- player login/logout
- player state snapshots
- zone/subzone/coordinates
- level
- XP changes
- money changes
- target changes
- combat-log defeat events credited to player/pet
- loot chat messages
- item tooltip lines from linked loot
- quest accept/turn-in events
- quest detail/progress/complete panels
- quest reward item tooltip lines
- merchant open/close
- merchant inventory
- merchant inventory tooltip lines
- merchant purchases
- bag diff across merchant session
- trainer window
- trainer services
- trainer service purchases
- profession/skill-line changes
- explicit Skinning attempts, skill checks, skill changes, and skinning loot

### Manual

Use `/stitch note <text>` for things the game cannot know:

```text
/stitch note Palemane camp feels risky because mobs are close together.
/stitch note good safe route from Bloodhoof to trainer area.
/stitch note this vendor is important before leaving town.
```

## Export

WoW writes SavedVariables when you logout or reload UI.

Global SavedVariables path:

```text
World of Warcraft/_classic_era_/WTF/Account/<ACCOUNT>/SavedVariables/StitchLogger.lua
```

Upload that file after a session. The importer should treat the SavedVariables file as the raw source of truth.

## Important design rule

The addon records raw data. It does not make final claims.

For example, loot-to-mob attribution is logged with context and confidence. The importer can later decide whether a drop relationship is high-confidence or needs review.
