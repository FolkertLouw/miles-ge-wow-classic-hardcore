# StitchLogger 0.3.0

Your Classic Era / Hardcore field recorder. Updated for the installed 1.15.9 client (Interface 11509).

## Start and check

Restart WoW when safe, enable StitchLogger in AddOns, then use:

- `/stitch status` — session and event count.
- `/stitchdebug show` — live feed, including encounter changes and transaction outcomes.
- `/stitchmob kodo` — combined summaries of up to five recent matching creature encounters. Also accepts an NPC ID.
- `/stitchfind leather` — search the latest 15 matching raw saved events.
- `/stitch note <text>` — context you want to remember.
- `/stitch stop` and `/stitch start` — persistent pause/resume.

Recording starts automatically unless paused. Open profession, trainer and merchant windows to expose their data. Expand recipe categories and clear filters to record more recipes. Route observations are sampled every 30 seconds when you move at least one map percentage point, plus zone transitions.

## What changed

**Encounters:** creature GUID + observer identifies each encounter. Target/mouseover observations, solo/pet/group kill evidence, loot inspections, and skinning are linked without using the most recent kill as a guessed source. A known kill without a linked inspection stays `not_inspected`.

**Loot:** localized self-loot messages supply received quantities. Other players' messages remain raw evidence. Loot windows retain actual source GUIDs, per-source quantities, and slot-clearing information. Reopening the same creature preserves maximum observed item quantities rather than summing them. Receipt-to-source links are explicitly correlated; ambiguous multiple sources/windows remain unresolved. Skinning requires a matching source GUID and successful skinning cast context. The previous Skinning and SkinningPostProcessor files are retained as source history but are no longer loaded.

**Crafting:** recipe snapshots record ingredients, amounts, output ranges and skill rank. Known recipe casts are reconciled against before/after inventory, successful/failed casts, skills and money. A matching batch is confirmed; concurrent or missing changes remain unresolved. Crafting must have been exposed through a recipe window first. Enchants or other crafts without an observable inventory output retain cast evidence without claiming a fully reconciled production result.

**Training:** trainer snapshots include level, skill and ability requirements exposed by the UI. Learning is verified through trainer-state changes or matching learned-spell evidence; spending alone does not confirm training. New spell and recipe observations are separate from proof of learning. Recipe-item use can be correlated to a learned spell and item consumption, but is not treated as certain provenance.

**Economy:** purchase attempts are reconciled against item and copper changes. Right-click sales at merchants and repair-all requests receive the same checks. Rapid operations of the same kind can form one batch. Unmatched activity, individual-item repairs, drag-to-vendor sales and currency/barter purchases remain available as raw money/bag observations rather than exact confirmed transactions. Prices are in copper; reagent market prices and acquisition costs are never invented.

**Exploration:** herb gathering, mining, fishing and opening casts record activity and location context, with loot-window evidence where exposed. Game-object identifiers are retained when provided. The add-on records gossip options, offered/active quests, banks, mailboxes, flight masters, merchants, trainers and auction services. It records observed quest availability with player state; it cannot discover hidden quest prerequisites.

## Evidence limits

Coordinates describe the observer's position, not exact creature or object coordinates. Empty loot windows often provide no source GUID: they are recorded as source-unknown, not attributed to the selected target or counted as a zero-drop kill. Slot clearing alone does not prove you received the item. Skinning/gathering events outside a matching cast context stay uncertain. Drop probabilities are deliberately not calculated from incomplete inspections or kill counts. Visible drops are not the complete hidden loot table.

Recent encounter state survives reloads and is retained for 24 hours (pruned at login). Older immutable encounter events stay in sessions and the external archive. Previously collected events are kept unchanged; their older attribution limitations still apply. Recorded sessions grow until you archive/manage them; no automatic deletion is performed.

## Save, archive and search

`/reload` or normal logout writes:

`World of Warcraft/_classic_era_/WTF/Account/<ACCOUNT>/SavedVariables/StitchLogger.lua`

A crash can lose data since the last save. The add-on never uploads anything.

In the delivered outputs folder, double-click `Archive-session.cmd` after saving. It creates `local-archive/raw/<sha256>.lua`, `archive.sqlite3`, `events.jsonl`, `encounters.jsonl` and `transactions.jsonl`. Raw backups are retained. Repeated imports deduplicate events; old saves cannot roll encounter summaries back to earlier revisions.

From that outputs folder:

```powershell
python archive-tools/archive.py --archive local-archive encounters kodo
python archive-tools/archive.py --archive local-archive transactions crafting
python archive-tools/archive.py --archive local-archive find leather
```

For a separate source checkout, install `tools/requirements.txt` and use `tools/archive.py import <SavedVariables path>`. Local archives are excluded from Git. Earlier curated observations remain in `field-data/` and `knowledge/`.

## Verification

Lua 5.1 tests load every active addon module using a controllable Classic API fixture. They exercise event reordering, duplicate corpses, early and delayed loot, source ambiguity, locale-specific quantities, group kills, pause/resume, reload persistence, crafting batches, purchases, sales, repairs, learning, gathering and route capture. End-to-end tests serialize the recorder's actual tables and import them through the data-only parser into SQLite/JSONL, including repeated and older saves.

These are automated simulations, not a live-client certification. After restarting, check `/stitch status` and `/stitchdebug show`, kill/loot one mob, skin it if applicable, open your profession window, then `/reload`. The resulting saved log can be inspected without uploading it.

API shapes were checked against the downloaded Blizzard Classic Era UI source mirror at https://github.com/Gethe/wow-ui-source/tree/classic_era, including LootDocumentation, UnitDocumentation, the Vanilla merchant/trade-skill UI and trainer UI.
