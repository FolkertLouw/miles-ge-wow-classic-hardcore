# Prairie Wolf

## Status

Personally verified by DaddyStitch through StitchLogger addon import.

## Classification

- Creature type: Beast
- Observed level: 6
- Classification: normal
- Zone: Mulgore
- Observed coordinates: 50.03, 63.88

## Observed combat

- Source event: `sl-000008`
- DaddyStitch level: 5
- XP awarded: 148
- Credited source: player

## Observed normal loot

| Item | Observed count | Notes |
|---|---:|---|
| Rabbit's Foot | 1 | Looted after the Prairie Wolf kill. Tooltip captured by StitchLogger. |

## Observed skinning

- Source events: `sl-000014` to `sl-000020`
- Skinning skill before: 1 / 75
- Skinning skill after: 2 / 75
- Required Skinning skill for observed mob level: 1
- Can skin: true
- Skill-up observed: yes

| Item | Observed count | Notes |
|---|---:|---|
| Ruined Leather Scraps | 1 | Loot message occurred immediately after the Prairie Wolf skinning flow. `skinning_completed` fired before the loot message, so attribution is medium confidence until the addon ordering is patched. |

## Open questions

- Confirm whether Prairie Wolf can drop other normal loot.
- Confirm more skinning outcomes at Skinning skill 2+.
- Patch StitchLogger so skinning loot is attached directly to `skinning_completed` instead of only same-timestamp loot messages.
