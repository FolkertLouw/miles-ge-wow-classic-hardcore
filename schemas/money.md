# Money Format

World of Warcraft money should be stored as **copper** in structured data.

Do not store separate gold, silver, and copper fields in raw data unless it is purely for display.

## Conversion

```text
1 silver = 100 copper
1 gold = 10,000 copper
```

Examples:

```text
82 copper = 82c
137 copper = 1s 37c
12345 copper = 1g 23s 45c
```

## Raw Data Examples

```json
{
  "priceCopper": 82,
  "receivedCopper": 3,
  "repairCostCopper": 14,
  "goldOnHandCopper": 137
}
```

## Rule

If the value is unknown, use `null`.

Never invent prices, vendor values, repair bills, training costs, AH sale prices, or auction deposits.
