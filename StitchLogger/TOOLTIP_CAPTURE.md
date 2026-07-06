# Tooltip Capture

`Tooltip.lua` captures item tooltip text from hidden in-game tooltips when an item link is available.

This is designed to preserve the information the player can visually see in-game, including details that `GetItemInfo` does not expose in structured fields.

## Events

### `item_tooltips_from_loot`

Logged when loot chat contains item links.

```lua
{
  eventType = "item_tooltips_from_loot",
  rawMessage = "You receive loot: [Light Leather].",
  items = {
    {
      name = "Light Leather",
      itemId = 2318,
      quality = 1,
      itemType = "Trade Goods",
      itemSubType = "Leather",
      vendorValueCopper = 15,
      tooltip = {
        captured = true,
        source = "hidden_game_tooltip",
        lines = {
          { index = 1, left = "Light Leather", right = nil },
          { index = 2, left = "Crafting Reagent", right = nil }
        }
      }
    }
  }
}
```

### `merchant_inventory_tooltips`

Logged when a merchant window opens. Captures merchant inventory plus tooltip lines for linked items.

### `quest_item_tooltips`

Logged when quest detail or quest complete panels are visible. Captures reward-choice and fixed-reward item tooltip lines.

## What tooltip lines may include

Depending on the item and what WoW exposes in the tooltip, lines may include:

- item name
- quality color through tooltip text color
- bind text
- unique/equipped restrictions
- item type
- armor value
- weapon damage
- weapon speed
- damage per second
- stats
- durability
- required level
- required profession/skill
- use text
- equip text
- quest item text
- sell price, when shown

## Data shape

Tooltip lines are stored as ordered line records:

```lua
{
  index = 3,
  left = "2 - 5 Damage",
  right = "Speed 1.60",
  leftColor = { r = 1, g = 1, b = 1 },
  rightColor = { r = 1, g = 1, b = 1 }
}
```

The importer should preserve raw tooltip lines and may later parse them into structured fields such as `damageMin`, `damageMax`, `speed`, `armor`, `durability`, `requiredLevel`, or `useEffect`.

## Important limitations

- Tooltip capture requires an item link. Plain item names from chat without links cannot be scanned reliably.
- Tooltip text is locale-dependent. If the WoW client is not English, the importer should keep raw lines and parse cautiously.
- Some tooltip data may not be available immediately until the client has cached item info.
- Tooltip capture is raw evidence, not final normalized item knowledge.
