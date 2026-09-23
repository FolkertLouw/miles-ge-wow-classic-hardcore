# StitchLogger

StitchLogger records personal World of Warcraft Classic Era and Hardcore field evidence: creature encounters, loot, gathering, crafting, skills, vendors, training, quests and exploration.

**Version 0.3.0:** see [RESTORATION.md](RESTORATION.md) for installation, commands, archive tools, evidence boundaries and verification.

Install this folder in `_classic_era_/Interface/AddOns/StitchLogger` and restart WoW. SavedVariables uses `StitchLoggerDB`; existing sessions are preserved.

Useful commands: `/stitch status`, `/stitchdebug show`, `/stitchmob kodo`, `/stitchfind leather`, `/stitch note <text>`, `/stitch stop`, `/stitch start`.

The archive stores observations and confidence, not invented complete loot tables or unsupported drop rates. Older `IMPORT_FORMAT.md` and `TOOLTIP_CAPTURE.md` document the original raw-event format; the 0.3.0 guide describes the additional record types.
