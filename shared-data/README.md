# Personal Classic field archive

Observed gameplay, not a complete game database. JSONL files contain one JSON object per line and can be queried with Python, jq, DuckDB, or imported into SQLite.

- `observations.jsonl`: vendor inventories, trainer lists, recipes, quest observations, encounter summaries, and exploration observations.
- `trainer-services.jsonl`: one row per observed trainer service, including trainer, time, location, price, requirements, and rank evidence when exposed by the client. Category headings are excluded.

Repeated observations are intentional historical evidence. Use observationID plus service index to identify a row within a snapshot. Missing ranks in older data stay unknown; they are never inferred from price, level, or list order. Rank capture in 0.3.1 uses API subtext, the trainer tooltip title, and spell subtext. Only visible/filter-included trainer entries can be captured. These records do not prove the player's pet learned an ability.

Raw SavedVariables and the local SQLite index are not committed. Shared exports omit unit GUIDs, character/account identifiers and raw chat messages. Observation IDs are hashes used for stable deduplication. Coordinates are player positions at observation time.

## Manual archiving and optional publishing

The Codex heartbeat is paused at the user's request. Archiving is manually triggered by asking Codex to archive the latest session or by running the local Save-Classic-Archive.cmd launcher. WoW writes saves on `/reload` and logout. The manual launcher runs `tools/sync_archive.py` with the local source and archive paths. The user authorized public publishing on 2026-09-23; the manual launcher includes `--push`. This imports a stable save, retains raw backups locally, exports gameplay records, commits only the two generated JSONL files, and, when `--push` is enabled, pushes the `main` branch. It fetches and fast-forwards from origin/main before importing. It never force-pushes, switches branches, or commits unrelated staged work; divergence stops the sync for review. A failed push leaves the commit local for retry and reports the failure.

For another machine install Python and `pip install luadata==1.0.5`, then run:

```text
python tools/sync_archive.py --source PATH_TO_StitchLogger.lua --archive LOCAL_ARCHIVE_DIRECTORY --push
```

The local archive must be retained to preserve observations across addon resets. Clone this repository to obtain the shared history on another machine. This sync configuration is tied to main and the existing remote; review those checks before configuring a different repository.
