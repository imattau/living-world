# Living World — Technical Design Brief

**Status:** Initial implementation brief  
**Audience:** Engineering and design  
**Engine:** Godot 4.x / GDScript  
**Target:** Desktop prototype; single player; offline simulation

## 1. Purpose

Build a deterministic world simulation that can generate a seeded setting, advance it through 250 years, and let a player inspect what changed and why. Geography should constrain resources and settlement; population and political rules should produce events; event records should preserve enough evidence to explain those outcomes.

The first deliverable is a simulation with an inspection UI, not a complete strategy game. Player intervention, story notifications, rich character simulation, and AI narration are later milestones.

## 2. Product requirements

The prototype must:

1. Generate the same initial world for the same seed and generator version.
2. Advance a year at a time or in batches, with no dependency on render frame rate.
3. Produce settlements, population change, migration, simple states, and a small set of political events.
4. Store structured events and causes, and provide queries by year, location, and entity.
5. Display the map, current year, event chronicle, and selected entity details.
6. Let the player browse historical state at selected years.
7. Save and load a world with its seed, current state, event history, and generator/simulation versions.

### Initial scale

| Item | Target |
|---|---:|
| Map | 48 × 48 cells |
| Regions | About 20 |
| Settlements | 8–20 at founding |
| Cultures | 3 at founding |
| States | Up to 5 at founding |
| Resources | Food, wood, stone, iron |
| Simulation duration | 250 annual ticks |

These are tuning targets rather than hard-coded limits.

## 3. Non-goals for this milestone

Defer individual simulation of ordinary people, tactical combat, detailed market clearing, procedural 3D cities, fully simulated language, genetics, inventories, multiplayer, modding, and LLM integration. Detailed people may be added later for a small set of influential historical figures. The first version does not give the player direct control over settlements or states.

## 4. Runtime architecture

Use three layers with explicit data flow:

```text
Presentation (Godot scenes and controls)
        │ commands / read models
        ▼
Simulation (generation, annual phases, rules, queries)
        │ mutates
        ▼
World state (plain data objects and event records)
```

### World state

Owns the current authoritative values for geography, regions, settlements, cultures, states, and event history. It should not know about nodes, controls, rendering, or UI selection.

### Simulation

Owns world generation, deterministic random streams, phase scheduling, rules, and event creation. It accepts a world state and explicit commands, then advances it. It must be runnable headlessly.

### Presentation

Renders read-only world data and sends explicit commands such as `advance_years(count)` or (in a later milestone) `apply_intervention(command)`. It must not implement simulation rules.

Use typed GDScript classes in `scripts/world/` for model records and `RefCounted` services in `scripts/simulation/`. Use `Node` only for application lifecycle and presentation. Avoid using `.tscn` resources as the authoritative storage for generated world entities.

## 5. Proposed model

All entities use stable integer IDs scoped to one world. IDs are assigned by deterministic generation order. Save files store IDs rather than object references; runtime indexes resolve IDs to records.

### `WorldState`

- `seed: int`
- `generator_version: int`
- `simulation_version: int`
- `year: int`
- `map_width`, `map_height: int`
- `cells: Array[CellData]`
- dictionaries keyed by ID: `regions`, `settlements`, `cultures`, `states`
- `events: Array[HistoryEvent]`
- `next_entity_id`, `next_event_id: int`

### `CellData`

Static or slowly changing map attributes: elevation, temperature band, rainfall, biome ID, river flag, fertility, resource potential, and region ID. Store cells in row-major order (`y * width + x`). Political ownership is resolved through the region/state data rather than duplicated on every tile unless rendering profiling later justifies a cached array.

### `RegionData`

- ID, name key, and member cell indices
- neighboring region IDs
- fertility and resource yields
- settlement IDs
- controlling state ID or none

Regions are the primary spatial unit for simulation. Tiles are primarily for generation and display.

### `SettlementData`

- ID, name key, region ID, founding year, status
- population total and occupational shares/counts
- food store and resource stores
- culture ID and state ID (either may be none)
- prosperity/pressure indicators needed by rules

Settlement status initially supports hamlet, village, town, city, and abandoned. Status transitions follow population and local capacity rules, not experience points.

### `CultureData`

- ID, name key, origin/parent IDs
- language/religion/value labels for display
- diffusion strengths or similarity values used by later rules

Only identity and a small number of rule-relevant numeric attributes are needed in the first pass. Culture is not yet a full agent or a detailed customs simulation.

### `StateData`

- ID, name key, government type
- leader label or optional notable-person ID
- settlement/region membership derived from control data
- treasury proxy, stability, and bilateral relationship records

Initial government types: tribe, chiefdom, city-state, kingdom, and republic. Borders are derived from controlled regions.

### Population representation

Most people exist only in aggregate. Track total population per settlement and a small set of occupational shares or counts sufficient for food production, administration, and defense. Do not model a record per inhabitant. Use bounded growth and explicit capacity/food-pressure rules to prevent runaway population.

## 6. Deterministic simulation

### Randomness

Use an explicit seed and Godot's seeded RNG facilities. Separate streams by subsystem (generation, weather, migration, politics, conflict) so adding a random draw in one subsystem does not silently change unrelated outcomes. Derive stream seeds from the world seed, subsystem key, and simulation version using a documented stable integer-mixing function. Never seed from wall-clock time in reproducible runs.

Rules should process entities in sorted stable-ID order. Do not rely on dictionary iteration order. For each phase, collect proposed changes before applying them where one entity's iteration position could otherwise confer an advantage.

Same seed, generator version, simulation version, and command sequence must produce the same event IDs and state. A simulation version change may intentionally change outcomes and must be recorded in saves.

### Tick contract

`advance_year()` performs exactly one complete year and increments `WorldState.year` once after all phases have committed. `advance_years(n)` calls that same operation repeatedly. UI speed changes how many ticks are requested per frame; it never changes rule behavior.

### Annual phase order

1. **Environment:** sample deterministic annual local variation around the generated climate baseline; determine rainfall and hazards.
2. **Harvest and resources:** calculate yields from fertility, climate, population, and resource potential; apply stores and consumption.
3. **Population:** apply births/deaths as bounded rates; evaluate food pressure; propose migration from pressured settlements toward viable neighbors.
4. **Settlement:** apply migration; update settlement population, stores, status, and abandonment/founding outcomes.
5. **Economy and exchange:** resolve only coarse local surpluses, shortages, and neighboring trade. Avoid per-item markets.
6. **Politics:** update state stability, relationships, leadership transitions, and control claims.
7. **Conflict:** evaluate disputes and possible war/battle outcomes with coarse deterministic resolution. This is not tactical combat.
8. **Event commit:** assign IDs, attach cause links, append events, update indexes/checkpoints, and close the year.

If a phase emits a change that another phase needs immediately, define that explicitly in the phase contract. Otherwise apply it at the phase boundary. The order is part of the simulation version.

## 7. Events and causality

Events are the durable record used by the chronicle, timeline, and causal inspector. Do not reconstruct historical explanations from UI text.

### Event record

Each event contains:

- `id`, `year`, `type`
- optional `location_region_id` and `location_cell_index`
- `subject_ids` and `participant_ids`
- structured `facts` dictionary (for example population delta, winner, or resource shortage)
- `cause_links: Array[CauseLink]`
- optional `template_key` for localized display text

A cause link contains a source event ID when a prior event exists, a cause category, and a contribution value or strength. It may also contain a short structured fact when the cause is a condition rather than a discrete prior event (for example consecutive poor harvests). Links point backward in time; reject self-links and cycles. Contribution strengths are explanatory signals, not scientific probabilities, and do not need to sum to 100 unless a presentation explicitly normalizes them.

For the initial version, capture the main direct causes and relevant conditions. Avoid adding narrative cause links that the rule did not actually use. If the system cannot support a strong causal claim, record the observed condition and label it as contributing evidence.

### Example

```json
{
  "id": 82,
  "year": 219,
  "type": "war_declared",
  "location_region_id": 4,
  "subject_ids": [12],
  "participant_ids": [12, 17],
  "facts": {"dispute_score": 0.74},
  "cause_links": [
    {"event_id": 77, "category": "territorial_dispute", "strength": 0.8},
    {"event_id": 79, "category": "resource_competition", "strength": 0.5}
  ]
}
```

Event queries should support year range, region, entity participation, event type, and incoming/outgoing cause links. Build simple in-memory indexes only when profiling or UI query volume requires them; first keep query code centralized so indexes can be added without changing consumers.

## 8. World generation

Generation is a deterministic pipeline:

1. Initialize named RNG streams from the world seed.
2. Generate a 48×48 elevation field and classify land/water.
3. Derive temperature and rainfall from latitude/elevation plus seeded variation.
4. Trace rivers from high elevation toward low elevation and mark navigable/river-adjacent cells for settlement scoring.
5. Derive biome, fertility, and resource potential.
6. Cluster habitable cells into approximately 20 contiguous regions; retain neighbor adjacency.
7. Score candidate settlement locations using water access, fertility, resources, transport, and defensibility.
8. Place 8–20 initial settlements with minimum spacing and assign populations.
9. Create initial cultures and optional small states based on region and settlement layout.
10. Validate map connectivity, IDs, ownership references, and that generated settlements occupy habitable cells.

Generation algorithms should favor explainable inputs over artistic perfection. Keep map generation functions independent so each stage can be replaced without changing simulation entity interfaces.

## 9. Historical browsing and persistence

Current world state alone cannot provide rewind. Use periodic serialized checkpoints plus deterministic event/state deltas between them. For the first prototype, checkpoint every 25 years and at year 0; historical browsing loads the nearest prior checkpoint and replays the same versioned simulation to the requested year. Keep a separate view-state object so scrubbing does not mutate the live head state. If replay cost proves excessive, shorten checkpoint intervals.

Save format should be versioned JSON or Godot's supported variant serialization for the first pass. Store the seed, world/simulation versions, current year, entity state, events, and checkpoint metadata. Validate IDs and references on load, and provide a clear error for unsupported versions. Do not adopt SQLite until save size or event-query performance demonstrates a need.

## 10. Presentation and user flow

Initial main view:

- central map with biome colors, region borders, state borders, and settlement markers
- year label and pause/advance speed controls
- chronicle panel ordered newest first or oldest first consistently
- selected entity panel with population, culture, state, and recent events
- timeline scrubber for historical inspection

The map and panels consume a read model assembled by query services. Selection is an ID, not a direct mutable model reference. Historical view selection uses the inspected snapshot and should be visually distinguished from the live simulation head.

## 11. Error handling and observability

Fail early on invalid model references in development builds. Log the world seed, year, phase, and stable entity ID when a rule produces invalid values. Clamp only values with explicit domain bounds; do not silently swallow NaN or broken references. Provide a compact simulation summary for debugging: settlement/state counts, total population, event counts by type, and phase duration.

## 12. Performance budget

At this scale, annual simulation over a few dozen regions and settlements should be inexpensive. Keep algorithms proportional to cells for generation/rendering and proportional to settlements/regions for annual simulation. Avoid per-person loops and all-pairs tile comparisons. Batch headless ticks and update the map/UI only after a batch or when the selected year changes.

## 13. Validation scenarios

These are acceptance scenarios for implementation; they do not prescribe a testing framework:

- Two runs with the same seed and versions produce the same initial entities and map values.
- Two runs with the same seed and command sequence produce the same year-250 event stream and state summary.
- Changing the rendering frame rate does not change simulation output.
- Every event reference points to an existing entity or prior event; causal links are acyclic.
- Population and resource values stay within documented bounds; abandoned settlements stop producing yields.
- A save/load round trip preserves state and event history.
- Browsing an earlier year leaves the live head year and state unchanged.
- A war or state collapse can be inspected through structured cause records, not just a prose summary.

## 14. Delivery sequence

1. **Model and generator:** typed data records, seeded map, regions, candidate settlement placement.
2. **Annual loop:** harvest, population, settlement growth/decline, and compact summary.
3. **Migration and exchange:** movement between adjacent viable settlements and coarse trade.
4. **Politics:** cultures, state control, relationships, disputes, coarse conflict.
5. **History UI:** map, year controls, event chronicle, entity inspection, causes.
6. **Persistence and rewind:** save/load, checkpoints, historical browsing.
7. **Evaluation:** inspect multiple 250-year runs; tune for legible, explainable outcomes.

Only after the prototype produces histories worth inspecting should intervention, story detection, richer notable people, or optional narrative generation enter scope.

## 15. Open decisions

Resolve these during implementation, record the choice, and increment the appropriate version if it changes generated outcomes:

- Exact Godot minor version and any target export platforms.
- Whether map cells use typed arrays or `CellData` records after initial profiling.
- Exact region clustering and river-routing algorithms.
- Population capacity and food-consumption tuning.
- Whether historical checkpoints store full snapshots or compressed serialized variants.
- Final migration and conflict equations after observing early generated worlds.
