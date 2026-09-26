# Technical Design — Overview

This page summarizes the initial architecture and prototype scope. For implementation details, see the [Technical Design Brief](technical-design-brief.md).

## Product target

Build a deterministic, simulation-first worldbuilding game. The first meaningful prototype generates a seeded world, simulates roughly 200–250 years, and lets a player inspect the resulting history and its causes.

## Architecture boundaries

Keep three layers separate:

1. **World model** — plain data for geography, regions, settlements, population aggregates, cultures, political entities, people, and events.
2. **Simulation engine** — seeded world generation, annual tick scheduling, rules, decisions, event creation, and cause propagation. It must not depend on scene nodes.
3. **Presentation** — Godot scenes for the map, timeline, event chronicle, and selection panels. Presentation reads simulation state and issues explicit player actions.

The initial implementation should use GDScript and Godot 4. Simulation data should be plain `RefCounted`/`Resource` classes or simple typed data structures, selected based on serialization needs. Avoid making simulation entities Node subclasses.

## First prototype scope

- 48×48 world map with elevation, climate, rainfall, biome, rivers, fertility, and resources.
- Approximately 20 simulation regions derived from map cells.
- 8–20 settlements, 3 cultures, and up to 5 political states.
- Four resources: food, wood, stone, and iron.
- Annual simulation ticks for 250 years.
- Basic UI: colored map, settlement markers, borders, year/speed controls, event list, selection details, and a timeline scrubber.
- Event records include stable IDs, year, type, location, participants, and structured causes.

## Simulation cadence

Use one simulation tick per year initially. Each year runs named phases in a stable order: environment and harvest; population and migration; settlement growth/decline; economy and trade; politics and diplomacy; conflict; event finalization. Use an explicit seeded RNG and avoid dependence on frame timing so the same seed and action sequence can be replayed.

Keep phase boundaries explicit, and collect effects/events before applying cross-entity changes where order could otherwise bias outcomes. Fast-forward should execute ticks in batches without requiring one rendered frame per simulated year.

## Population and people

Represent most inhabitants as aggregate settlement populations and broad occupational groups. Create detailed person records only for historically significant individuals such as rulers, generals, leaders, rebels, and inventors. Do not create or update one entity per inhabitant.

## Events and causality

Events are the durable historical record and the source for the chronicle. Each event should carry a type, year, location, subject/participants, and zero or more cause links with contribution weights or explanatory facts. Keep causal records structured and authoritative; prose summaries are a presentation concern.

Initial event types can include settlement founded, migration, harvest failure, ruler change, dispute, war, battle, treaty, and state collapse. Build a query path to browse events by year, location, entity, and causal link.

## Persistence and replay

Start with in-memory state and a versioned save format once the model stabilizes. Keep the world seed and player interventions in the save so deterministic replay is possible. Revisit SQLite if historical queries or save size make flat serialization awkward; avoid committing to a database before the prototype proves the data shape.

## Development sequence

1. Seeded terrain and region generation.
2. Settlement placement and annual growth/decline.
3. Aggregate population, food pressure, and migration.
4. Cultures and simple states/borders.
5. Political events and conflict.
6. Timeline, chronicle, and cause inspection.
7. Evaluate generated histories across many seeds; only then add player intervention and story detection.

## Success check

Run multiple generated worlds for 250 years. The prototype succeeds when the player can ask why a state collapsed, where a population moved from, or why a conflict began and inspect concrete event/cause records that answer the question.
