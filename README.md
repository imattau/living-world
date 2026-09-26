# Living World

A simulation-first worldbuilding game about geography, societies, and emergent history. The player observes a world, investigates why events happened, and later may influence history in limited ways.

## First milestone

Generate a seeded world, simulate 200–250 years, and make its history interesting to inspect.

## Project status

The project includes seeded world generation, an interactive map, annual food and population simulation, food-pressure migration, same-state food exchange, and a recent-history chronicle. Enter a seed, generate a world, then advance it one or ten years at a time. See [the design brief](docs/design-brief.md), [technical design overview](docs/technical-design.md), and [implementation-ready technical design brief](docs/technical-design-brief.md).

## Getting started

Open this folder in Godot 4.7.x stable and run the project (Linux desktop is the first target). The current scene supports seeded generation and annual stepping; migration, trade, and historical browsing are next.

## Project layout

- `scenes/` — Godot scenes and presentation composition
- `scripts/simulation/` — engine, time, rules, and event generation
- `scripts/world/` — simulation data models
- `scripts/presentation/` — map, timeline, and chronicle UI
- `data/` — authored definitions and tuning data
- `assets/` — project art and audio
- `docs/` — design and technical notes
