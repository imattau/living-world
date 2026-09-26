# Living World

A simulation-first worldbuilding game about geography, societies, and emergent history. The player observes a world, investigates why events happened, and can spend regenerating Influence to send food aid to a settlement. Aid is scheduled for the next year and its uncertain downstream effects are simulated rather than directly controlled.

## First milestone

Generate a seeded world, simulate 200–250 years, and make its history interesting to inspect.

## Project status

The project includes seeded world generation, an interactive map, annual food and population simulation, food-pressure migration, same-state food exchange, state stability and disputes, coarse deterministic wars and battles, historical year inspection, a replayable food-aid intervention, structured condition evidence and event-cause links, and versioned JSON save/load with periodic checkpoints. Reproducible reports cover the [20-seed, 250-year baseline](docs/evaluation/year-250-baseline.md) and [paired food-aid evaluation](docs/evaluation/food-aid-intervention.md). Enter a seed, generate a world, advance it, then inspect earlier years or save and reload the world. See [the design brief](docs/design-brief.md), [technical design overview](docs/technical-design.md), and [implementation-ready technical design brief](docs/technical-design-brief.md).

## Getting started

Open this folder in Godot 4.7.x stable and run the project (Linux desktop is the first target). The current scene supports seeded generation, annual stepping, timeline inspection, settlement details, event-fact and cause browsing, and Save/Load controls. Saves are written to `user://saves/living-world.json`.

## Project layout

- `scenes/` — Godot scenes and presentation composition
- `scripts/simulation/` — engine, time, rules, and event generation
- `scripts/world/` — simulation data models
- `scripts/presentation/` — map, timeline, and chronicle UI
- `data/` — authored definitions and tuning data
- `assets/` — project art and audio
- `docs/` — design and technical notes
