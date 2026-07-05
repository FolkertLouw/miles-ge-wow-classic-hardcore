# MILES GE — WoW Classic Hardcore Field Guide

A structured field-data project for **World of Warcraft Classic Hardcore**.

This repository is not meant to recreate Wowhead. Wowhead already has the encyclopedia.

This project is meant to become a **personally verified, state-aware field guide** built from real Hardcore exploration: mobs, drops, vendors, trainers, routes, risks, crafting, economy, and survival decisions.

The first field character is:

- **Name:** DaddyStitch
- **Realm type:** Official Classic Hardcore
- **Faction:** Horde
- **Race:** Tauren
- **Class:** Hunter
- **Core fantasy:** hunter, skinner, leatherworker, trader, explorer
- **Primary profession plan:** Skinning + Leatherworking
- **Secondary profession plan:** First Aid, Cooking, Fishing

## Core Idea

The value of this repository is not a play diary.

The value is reusable field data:

- where mobs are found
- what level they are
- what they drop
- whether they are safe or dangerous
- what vendors sell
- what items vendor for
- what trainers teach
- what recipes require
- what materials are useful
- what routes are safe
- what early mistakes should be avoided

DaddyStitch is the first field researcher. The data should eventually be useful for other Classic Hardcore players as well.

## How To Use This With ChatGPT

In a new chat, use this prompt:

> I’m doing a new session. Familiarize yourself with the GitHub project `miles-ge-wow-classic-hardcore`, especially the README and CHAT_BRIEFING. This is the WoW Classic Hardcore field-data project. Use the existing structure and continue from the current DaddyStitch state. I will give you field observations, and you should convert them into structured repo updates.

After that, you can report observations naturally.

Examples:

```text
log: Mulgore 45,76 killed lvl 1 Plainstrider, dropped Tough Jerky
```

```text
vendor: sold Ruined Pelt x1 for 3c at Camp Narache
```

```text
observe: around 47,75 there are many lvl 1-2 Plainstriders, open field, low danger
```

```text
trainer: learned Apprentice Skinning from Yonn Deepcut for 10c
```

```text
near death: pulled two wolves near 48,62, survived at 12 percent health, lesson is avoid fighting near roaming mobs before pet
```

The assistant should parse those notes into structured field events and update the repository.

## Data Philosophy

Raw observations are the source of truth.

Do not invent exact coordinates, prices, drops, vendors, trainer details, quest details, or item values. If something is uncertain, store it as uncertain.

External data from Wowhead or other sources may be useful, but it must be clearly separated from personally verified DaddyStitch field data.

## Main Data Layers

### Field Data

Personally verified observations from play.

Examples:

- mob location observations
- mob kills
- drops
- skinning results
- vendor sales
- vendor inventories
- trainer purchases
- repair bills
- crafting events
- skill-ups
- near-death events
- route notes

### Character State

The current state of DaddyStitch.

Examples:

- level
- zone
- gold
- professions
- known recipes
- current goal
- known risks
- pet status

### Knowledge Pages

Human-readable summaries generated from the raw field data.

Examples:

- Mulgore field guide
- Plainstrider page
- Skinning starter route
- early Leatherworking workbench
- vendor and trainer summaries

### Generated Outputs

Optional summaries, website pages, guides, and route advice generated from the structured data.

## Money Format

Always store money as copper.

Examples:

```json
{
  "priceCopper": 82,
  "receivedCopper": 3,
  "repairCostCopper": 14
}
```

Display conversion:

```text
82 copper = 82c
137 copper = 1s 37c
12345 copper = 1g 23s 45c
```

## Product Vision

This may eventually become a small public website.

Working concept:

# The Stitchbook

*A Classic Hardcore field guide stitched together from verified exploration.*

Possible rooms:

- Field Guide
- Treasury
- Workbench
- Trophy Room
- Sales Room
- Risk Map

The central question:

**Can a Hardcore Tauren leatherworker map, craft, trade, and survive long enough to build something useful?**
