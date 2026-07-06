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

For skinning, `characterLevel` is context only. Skinning success and difficulty should be calculated from Skinning profession skill.

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

## Skinning skill model

Skinning events must be interpreted through profession skill, not player level.

The addon records:

```lua
skinningSkillBefore = {
  profession = "Skinning",
  known = true,
  baseSkill = 1,
  modifier = 0,
  effectiveSkill = 1,
  maxSkill = 75,
  source = "skill_lines"
}
```

and, where available:

```lua
skinningRequirementBefore = {
  mobLevel = 4,
  requiredSkill = 1,
  canSkin = true,
  skillDeltaToRequired = 0,
  requirementFormula = "Classic: level <= 10 requires 1; level 11-20 requires level*10-100; level >= 21 requires level*5.",
  difficultyColor = nil,
  difficultyColorSource = "not_captured_yet"
}
```

The importer should prefer these fields for generated skinning statistics:

```text
mob level
required Skinning skill
effective Skinning skill before
effective Skinning skill after
canSkin
skillDeltaToRequired
skinning loot
skill-up delta, if any
```

### Skinning requirement formula

```text
mob level 1-10: required Skinning = 1
mob level 11-20: required Skinning = mob level * 10 - 100
mob level 21+: required Skinning = mob level * 5
```

### Skinning events

`Skinning.lua` adds explicit skinning events so skinning is not only inferred from generic loot messages.

#### `skinning_started`

Logged when the player starts casting Skinning.

```lua
{
  eventType = "skinning_started",
  spellName = "Skinning",
  targetContext = {
    source = "current_target",
    mob = {
      name = "Battleboar",
      guid = "...",
      level = 4,
      creatureType = "Beast"
    },
    skinning = {
      mobLevel = 4,
      requiredSkill = 1,
      canSkin = true
    }
  },
  skinningSkillBefore = {},
  skinningRequirementBefore = {}
}
```

#### `skinning_succeeded`

Logged when the Skinning cast succeeds.

```lua
{
  eventType = "skinning_succeeded",
  spellName = "Skinning",
  targetContext = {},
  skinningSkillBefore = {},
  skinningSkillAfter = {},
  skinningRequirementBefore = {},
  skinningRequirementAfter = {}
}
```

#### `skinning_skill_message`

Logged when a skinning-related skill message arrives during the skinning window.

```lua
{
  eventType = "skinning_skill_message",
  rawMessage = "Your skill in Skinning has increased to 2.",
  skinningSkillBefore = {},
  skinningSkillAfter = {}
}
```

#### `skinning_loot_received`

Logged from loot chat within the skinning window.

```lua
{
  eventType = "skinning_loot_received",
  rawMessage = "You receive loot: [Light Leather].",
  items = {},
  skinnedMob = {
    name = "Battleboar",
    level = 4,
    creatureType = "Beast"
  },
  skinningSkillBefore = {},
  skinningSkillAfter = {},
  skinningRequirementBefore = {},
  skinningRequirementAfter = {},
  skinningCast = {}
}
```

#### `skinning_completed`

Primary source event for generated skinning drop tables.

```lua
{
  eventType = "skinning_completed",
  skinnedMob = {
    name = "Battleboar",
    level = 4,
    creatureType = "Beast"
  },
  skinningLoot = {
    { name = "Light Leather", quantity = 1 }
  },
  skinningSkillBefore = {
    baseSkill = 1,
    effectiveSkill = 1,
    maxSkill = 75
  },
  skinningSkillAfter = {
    baseSkill = 2,
    effectiveSkill = 2,
    maxSkill = 75
  },
  skinningRequirementBefore = {
    requiredSkill = 1,
    canSkin = true,
    skillDeltaToRequired = 0
  }
}
```

Importer behavior:

```text
Use `skinning_completed` as the primary source for skinning drop tables.
Use `skinning_loot_received` as supporting evidence.
Calculate skill-up as skinningSkillAfter.baseSkill - skinningSkillBefore.baseSkill when both are known.
Treat mob relation as high confidence only if the target/corpse context is unambiguous; otherwise mark needsReview.
Do not use characterLevel for skinning success calculations.
```

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
generated/skinning-stats/mobs/*.json
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
