# StitchLogger Import Format

StitchLogger writes a Lua SavedVariables table named `StitchLoggerDB`.

The importer should read:

```text
WTF/Account/<ACCOUNT>/SavedVariables/StitchLogger.lua
```

and convert session events into repository data.

## Top-level structure

```lua
StitchLoggerDB = {
  version = 1,
  addonVersion = "0.1.0",
  createdAt = "2026-07-05T...Z",
  settings = {},
  counters = {
    nextSession = 2,
    nextEvent = 123,
  },
  currentSessionId = nil,
  sessions = {
    {
      sessionId = "2026-07-05-001",
      startedAt = "...",
      endedAt = "...",
      character = {},
      events = {},
    }
  }
}
```

## Event base fields

Every event should contain:

```lua
{
  eventId = "sl-000001",
  eventType = "manual_note",
  timestamp = "2026-07-05T12:34:56Z",
  timeSeconds = 1780000000,
  character = "DaddyStitch",
  characterLevel = 5,
  zone = "Mulgore",
  subZone = "Bloodhoof Village",
  coords = { mapID = 1412, x = 46.15, y = 58.16 },
  source = "addon",
  confidence = "high"
}
```

## Important event types

### `manual_note`

Human context typed through `/stitch note`.

```lua
{
  eventType = "manual_note",
  text = "Palemane camp feels risky because mobs are close together.",
  target = {}
}
```

### `manual_snapshot`

Explicit snapshot from `/stitch snapshot`.

```lua
{
  eventType = "manual_snapshot",
  player = {},
  target = {},
  professions = {},
  bags = {}
}
```

### `mob_defeat`

Combat-log defeat credited to player or pet.

```lua
{
  eventType = "mob_defeat",
  mob = {
    name = "Battleboar",
    guid = "...",
    level = 4,
    creatureType = "Beast"
  },
  creditedSource = {
    sourceType = "player"
  }
}
```

### `xp_gained`

XP delta from `PLAYER_XP_UPDATE`.

```lua
{
  eventType = "xp_gained",
  xpGained = 56,
  recentDefeat = {
    eventId = "sl-000123",
    mobName = "Battleboar"
  }
}
```

### `loot_message`

Loot chat line with item links extracted when possible.

```lua
{
  eventType = "loot_message",
  rawMessage = "You receive loot: [Battleboar Flank].",
  items = {},
  recentDefeat = {}
}
```

The importer should only treat loot-to-mob attribution as high confidence when the context is unambiguous.

### `quest_accepted`

```lua
{
  eventType = "quest_accepted",
  questID = 123,
  questTitle = "Sharing the Land",
  npc = {}
}
```

### `quest_turned_in`

```lua
{
  eventType = "quest_turned_in",
  questID = 123,
  questTitle = "Rites of the Earthmother",
  xpReward = 340,
  moneyRewardCopper = 0,
  npc = {}
}
```

### `quest_detail_panel`, `quest_progress_panel`, `quest_complete_panel`

These capture visible quest text and reward options when a quest panel is open.

```lua
{
  eventType = "quest_complete_panel",
  npc = {},
  quest = {
    title = "The Battleboars",
    objectiveText = "...",
    questText = "...",
    choices = {},
    rewards = {},
    moneyCopper = 0,
    xp = 0
  }
}
```

### `merchant_opened`

```lua
{
  eventType = "merchant_opened",
  vendor = {},
  merchantInventory = {}
}
```

### `merchant_item_bought`

```lua
{
  eventType = "merchant_item_bought",
  vendor = {},
  item = {},
  estimatedTotalPriceCopper = 82
}
```

### `merchant_closed`

Contains a bag diff across the whole merchant session.

```lua
{
  eventType = "merchant_closed",
  vendor = {},
  moneyBeforeCopper = 100,
  moneyAfterCopper = 200,
  moneyDeltaCopper = 100,
  itemsAdded = {},
  itemsRemoved = {}
}
```

This event is raw evidence. If the session included both buying and selling, the importer should reconcile it with `merchant_item_bought` events before generating final sale records.

### `trainer_opened`

```lua
{
  eventType = "trainer_opened",
  trainer = {},
  services = {}
}
```

### `trainer_service_bought`

```lua
{
  eventType = "trainer_service_bought",
  trainer = {},
  service = {
    name = "Apprentice Skinning",
    costCopper = 10
  }
}
```

### `skills_changed`

```lua
{
  eventType = "skills_changed",
  professions = {
    { name = "Skinning", rank = 1, maxRank = 75 }
  }
}
```

## Import targets

A future importer should create or update:

```text
field-data/daddystitch/events/<date>-addon-import.jsonl
field-data/daddystitch/state/current-character-state.json
field-data/daddystitch/treasury/ledger.jsonl
generated/drop-stats/mobs/*.json
knowledge/mobs/*.md
knowledge/items/**/*.md
knowledge/quests/*.md
knowledge/vendors/*.md
knowledge/trainers/*.md
```

## Confidence rules

Use the addon data as raw evidence, but still distinguish:

```text
high confidence: direct event or exact screen data
medium confidence: inferred relation such as recent loot after recent mob defeat
low confidence: chat text without item link or unclear context
```
