# Living World

A simulation-first worldbuilding game about geography, societies, and emergent history. The player observes a world, investigates why events happened, and later may influence history in limited ways.

## First milestone

Generate a seeded world, simulate 200–250 years, and make its history interesting to inspect.

## Project status

Initial project scaffold. See [the design brief](docs/design-brief.md), [technical design overview](docs/technical-design.md), and [implementation-ready technical design brief](docs/technical-design-brief.md).

## Getting started

Open this folder in Godot 4.3 or newer and run the project. The current scene is a minimal placeholder while the simulation model is designed.

## Project layout

- `scenes/` — Godot scenes and presentation composition
- `scripts/simulation/` — engine, time, rules, and event generation
- `scripts/world/` — simulation data models
- `scripts/presentation/` — map, timeline, and chronicle UI
- `data/` — authored definitions and tuning data
- `assets/` — project art and audio
- `docs/` — design and technical notes
