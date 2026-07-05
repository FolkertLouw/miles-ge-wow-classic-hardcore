# Items Index

This is the top-level item database for the WoW Classic Hardcore field guide.

Item pages should be created when an item is personally observed as:

- a quest reward
- a quest required item
- a mob drop
- a vendor item
- a vendored/sold item
- a crafted item
- a crafting material
- a meaningful gear upgrade
- an AH sale/purchase item

## Categories

### Gear

Use for equippable armor, weapons, bags/quivers/ammo pouches, trinkets, rings, necklaces, and other equipment.

Gear is split by armor/type and then by slot where useful.

- [Gear Index](gear/index.md)

Current pattern:

```text
gear/<armor-type>/<slot>/<item>.md
```

Examples:

```text
gear/leather/hands/nomadic-gloves.md
gear/mail/legs/painted-chain-leggings.md
```

### Quest Items

Use for items that exist primarily as quest objectives or quest turn-ins.

- [Quest Items Index](quest-items/index.md)

### Trade Items

Use for stackable or economy/crafting-relevant items such as leather, hides, cloth, meat, fish, herbs, ore, thread, and similar materials.

- [Trade Items Index](trade-items/index.md)

Current pattern:

```text
trade-items/<type>/<item>.md
```

### Consumables

Use for food, drink, potions, bandages, scrolls, elixirs, and other consumed items.

- [Consumables Index](consumables/index.md)

Current pattern:

```text
consumables/<type>/<item>.md
```

### Trash

Use for items that currently appear to be mainly useful for vendoring unless later field data shows another use.

- [Trash Items Index](trash/index.md)

Current pattern:

```text
trash/<item>.md
```

## Current Personally Verified Items

### Gear

- [Painted Chain Leggings](gear/mail/legs/painted-chain-leggings.md) — quest reward option from [Break Sharptusk!](../quests/break-sharptusk.md)
- [Nomadic Gloves](gear/leather/hands/nomadic-gloves.md) — quest reward option from [Break Sharptusk!](../quests/break-sharptusk.md)

### Quest Items

- [Chief Sharptusk Thornmantle's Head](quest-items/chief-sharptusk-thornmantles-head.md) — required item for [Break Sharptusk!](../quests/break-sharptusk.md)

## Data Rules

Do not prefill item data from memory. External data must be marked as external reference data.

If an item appears in a quest reward table, link it to its item page.

If an item page references a quest, link back to the quest page.

Store money values as copper.
