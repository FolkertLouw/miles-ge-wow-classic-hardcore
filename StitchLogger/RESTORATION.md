# StitchLogger 0.2.0 — restored September 23, 2026

Recovered from FolkertLouw/miles-ge-wow-classic-hardcore, including the original July field observations. Targets the installed Classic Era 1.15.9 client (Interface 11509). Works with any character; sessions include realm, client build and Hardcore status when the API supplies it.

## Start playing

After installing a new addon folder, fully exit and reopen WoW when safe. Enable StitchLogger in the character-select AddOns menu. Recording starts automatically, unless previously paused.

- `/stitch status` — check the active session and event count.
- `/stitchdebug show` — movable live event feed.
- `/stitchfind kodo` — search saved evidence, latest 15 matches.
- `/stitch note Lost Barrens Kodo found near the road` — add exploration context.
- `/stitch stop` / `/stitch start` — pause/resume, including across reloads.
- Open merchants, trainers and profession windows to capture the information they expose. Expand recipe categories and clear filters to capture all visible recipes.
- `/reload` or a normal logout flushes SavedVariables to disk. A game crash can lose observations since the last flush.

Saved data: `_classic_era_/WTF/Account/<ACCOUNT>/SavedVariables/StitchLogger.lua`.

## Archive and query

Install `tools/requirements.txt` with Python, then:

```powershell
python tools/archive.py import "C:/path/to/SavedVariables/StitchLogger.lua"
python tools/archive.py find "kodo"
```

This creates `local-archive/raw/<sha256>.lua`, a searchable SQLite database and `events.jsonl`. Repeat imports update existing event identities rather than duplicating them. Raw input is parsed as data, never executed. Keep this private local archive backed up; it is excluded from Git by default. Earlier curated observations remain in `field-data/` and `knowledge/`.

## Evidence boundaries

This records discoveries, not the complete hidden game database. Coordinates are the player's position when observing; they are not exact creature coordinates. Loot chat and the old skinning modules use temporal attribution and can be ambiguous. The new loot-window events retain source GUIDs and quantities, but seeing an item is not proof of receiving it. Reopening a corpse can record another observation: do not sum window events into drop rates. No automatic drop-rate calculation is introduced.

Known recipes include ingredients, required amounts, output quantities (trade skills), skill rank and difficulty. Recipe material market costs are not invented; trainer and vendor prices are observed copper values. Merchant/trainer hooks are purchase attempts, with money and inventory changes recorded separately. Trainer and recipe filters can hide entries.

Classic Era and Hardcore observations retain session context so future analysis can choose whether to combine them. Existing source records are preserved. The addon does not upload anything or write arbitrary external files.

## Verification

Regression harness uses `lupa.lua51` with mocked game APIs; all addon modules are loaded. Checks cover recipes/reagents, loot source IDs and quantities, merchant bundle cost, persistent pause, session boundaries and search. Importer tests cover deduplication, character isolation and executable-input rejection. Live client behavior must still be checked after enabling the addon.

API reference: Blizzard Classic Era UI source mirrored at https://github.com/Gethe/wow-ui-source/tree/classic_era (read during restoration), especially the Vanilla TradeSkillUI, CraftUI, TrainerUI and MerchantFrame. Installed executable version was inspected locally.
