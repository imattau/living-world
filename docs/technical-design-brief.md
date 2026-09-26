# Living World — Technical Design Brief

**Status:** Active prototype implementation
**Audience:** Engineering and design  
**Engine:** Godot 4.7.x stable / GDScript
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

## 5. Data model

All entities use stable integer IDs scoped to one world. IDs are assigned by deterministic generation order. Save files store IDs rather than object references; runtime indexes resolve IDs to records.

### `WorldState`

- `seed: int`
- `generator_version: int`
- `simulation_version: int`
- `year: int`
- `map_width`, `map_height: int`
- `map: MapData`
- dictionaries keyed by ID: `regions`, `settlements`, `cultures`, `states`
- `events: Array[HistoryEvent]`
- `next_entity_id`, `next_event_id: int`

### `MapData`

Store dense map fields as parallel packed arrays in row-major order (`index = y * width + x`): `PackedFloat32Array` for elevation, temperature, rainfall, fertility, and four resource potentials; `PackedInt32Array` for biome and region ID; `PackedByteArray` for land and river flags. This keeps generation and rendering contiguous and avoids thousands of small objects. Put accessors and index conversion in `MapData`; callers should not calculate offsets independently. Political ownership is resolved through regions/states rather than duplicated on every cell.

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
- treasury proxy, stability, bilateral relationship/dispute records, and sorted IDs of states currently at war

Initial government types: tribe, chiefdom, city-state, kingdom, and republic. Borders are derived from controlled regions.

### Population representation

Most people exist only in aggregate. Track total population per settlement and a small set of occupational shares or counts sufficient for food production, administration, and defense. Do not model a record per inhabitant. Use bounded growth and explicit capacity/food-pressure rules to prevent runaway population. Per-settlement initial carrying capacity is `500 + 1,500 × site_fertility + 300` for a freshwater-adjacent site (otherwise no freshwater bonus).

## 6. Deterministic simulation

### Randomness

Use a project-owned Park–Miller PRNG (modulus 2,147,483,647; multiplier 48,271) rather than engine RNG, so replay does not depend on Godot RNG implementation changes. World seeds are integers in `[1, 2,147,483,646]`. Derive a nonzero stream seed as `1 + ((world_seed + subsystem_id × 104729 + version × 13007) mod 2,147,483,646)`, with fixed subsystem IDs documented in code. Maintain independent streams for generation, weather, migration, politics, and conflict. Document this algorithm in code and treat a change as a version change. Never seed from wall-clock time in reproducible runs.

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
6. **Politics:** update state stability from food pressure, store bilateral border disputes, and declare wars when the documented dispute and stability thresholds are met.
7. **Conflict:** resolve one coarse engagement per active neighboring state pair per year from strength plus seeded variance; apply casualties and stability changes, and agree peace when the losing state falls below the stability threshold. This is not tactical combat.
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
2. Generate elevation with three octaves of project-owned smooth value noise on a 48×48 grid. Use fixed lattice sizes 6, 12, and 24, weights 0.55, 0.30, and 0.15, plus a mild latitude term. Interpolate with smoothstep; normalize the result to 0–1. Cells below the 0.38 elevation threshold are sea. If land is disconnected into multiple components, retain all components but only seed settlements on components with at least 8% of total habitable area.
3. Derive temperature from latitude and elevation: normalized temperature = clamp(1 − 0.85 × absolute latitude − 0.35 × elevation, 0, 1). Generate rainfall from two-octave smooth value noise (weights 0.7/0.3) plus a broad wetness band; clamp to 0–1.
4. Route each land cell to its steepest lower D8 neighbor; break equal-height ties by lowest cell index. Cells with no lower neighbor are local basins and are marked as lakes. Accumulate upstream land-cell counts in descending elevation order. Mark rivers where accumulation reaches 12 cells; river cells and their immediate land neighbors get freshwater access.
5. Derive biome from temperature and rainfall bands. Fertility = clamp(0.55 × rainfall + 0.30 × soil potential + 0.15 × river access, 0, 1), where soil potential is a third seeded smooth-noise field. Four resource potentials come from separate deterministic noise fields modulated by biome suitability.
6. Select 20 region seeds by farthest-point sampling over habitable cells, first seed chosen from the highest-fertility valid cell and subsequent seeds maximizing minimum Manhattan distance. Assign each land cell to the nearest seed by multi-source breadth-first expansion across D8 land neighbors; ties go to the lower region ID. Preserve region adjacency. If fewer than 20 valid seeds exist, use the available count.
7. Score settlement candidates: `3 × fertility + 2 × freshwater + resource_potential + 0.5 × coast_access − 2 × local_slope`, all normalized 0–1 except the final score. Greedily pick 12 sites, requiring a Manhattan distance of at least 4 between sites; relax to 2 if fewer than 8 sites can be placed.
8. Assign starting populations using a seeded integer range of 300–1,200 and assign each settlement to the nearest of three culture origins.
9. Create three cultures. Seed three proto-states by clustering settlements around three seeded anchor sites; assign remaining settlements to the nearest anchor if land-connected, leaving remote settlements independent. States are limited to five; later state formation/splitting follows political rules.
10. Validate IDs, references, nonempty regions, land connectivity within each region, and that settlements occupy habitable cells.

Generation algorithms should favor explainable inputs over artistic perfection. Keep map generation functions independent so each stage can be replaced without changing simulation entity interfaces.

## 9. Historical browsing and persistence

Current world state alone cannot provide rewind. Store a full serialized state snapshot at year 0 and every 25 years. Each snapshot includes all mutable entity/map values plus the event-log cursor and command-log cursor. For an inspected year, load the nearest earlier snapshot into a separate world instance and replay at most 24 annual ticks. The live simulation head is never mutated by timeline scrubbing. Once interventions exist, store commands ordered by `(year, sequence_number)` and replay them at the start of their recorded year.

Use a single versioned JSON save at `user://saves/living-world.json` for the prototype. Store the current state, append-only event log, snapshots, seed, and generator/simulation versions. Entity tables are arrays sorted by ID; map fields use JSON arrays. This favors inspectability over compactness at 48×48 scale. The command log is deferred until interventions exist. Do not adopt SQLite until measured save size or event query latency requires it. Reject unsupported save versions with a clear message; do not silently migrate or drop data.

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
2. **Annual loop:** deterministic weather, harvest, food stores, population pressure, settlement growth/decline, and chronicle events.
3. **Migration and exchange:** movement between adjacent viable settlements and coarse trade.
4. **Politics:** cultures, state control, relationships, disputes, coarse conflict.
5. **History UI:** map, year controls, event chronicle, entity inspection, causes.
6. **Persistence and rewind:** save/load, checkpoints, historical browsing.
7. **Evaluation:** inspect multiple 250-year runs; tune for legible, explainable outcomes.

Only after the prototype produces histories worth inspecting should intervention, story detection, richer notable people, or optional narrative generation enter scope.

## 15. Settled prototype defaults

These choices are fixed for the first implementation. Tune numerical balance after observing generated histories, but preserve the formulas and bump `simulation_version` whenever a change alters outcomes.

- **Engine/platform:** Godot 4.7.x stable (current maintenance release at the time of this brief); GDScript; desktop Linux first. No plugins or external runtime dependencies. No Godot executable is installed in the current workspace, so editor/runtime validation begins after one is available.
- **Map storage:** parallel packed arrays in `MapData`, row-major indexing.
- **Height/climate:** custom smooth value noise on fixed lattice scales, not engine noise classes. Sea threshold 0.38; three elevation octaves; two rainfall octaves.
- **Rivers:** steepest-lower-neighbor D8 routing with deterministic tie-break; flow accumulation threshold 12. Closed basins are lakes.
- **Regions:** 20 farthest-sampled seeds and multi-source D8 breadth-first expansion on land. Actual count can be lower if valid land area is insufficient.
- **Settlements:** 12 seeded starting sites, minimum Manhattan spacing 4, relax to 2 to place at least 8. Starting population 300–1,200.
- **Starting society:** exactly three cultures and three proto-state anchors when at least three sites exist; remote sites may remain independent. Cap at five concurrent states until later tuning.
- **Settlement status:** hamlet below 500 people, village from 500 to 1,999, town from 2,000 to 7,999, and city from 8,000. A settlement below 25 people for five consecutive years becomes abandoned.
- **Randomness:** project-owned Park–Miller PRNG with independent subsystem streams and stable sorted entity iteration.
- **Population model:** persons as integer totals. Use the settlement capacity formula above for each settlement. Annual natural growth starts at 1% when food coverage is at least 1.0 and decreases linearly to 0% at 0.5 coverage. Below 0.5 coverage, mortality rises linearly up to 3% at zero coverage. Multiply natural growth by `max(0, 1 − population / carrying_capacity)` and cap net natural growth at 1.5% per year. Food coverage is food available before consumption divided by annual need; annual need is 1 food unit per person.
- **Food production:** annual yield is `population × fertility × 1.2 × weather_factor`, where weather factor is `clamp(0.75 + 0.50 × local_baseline_rainfall + deterministic_variation, 0.75, 1.25)` and deterministic variation is in `[-0.05, 0.05]`. Subtract the current year's population need after harvest; stores cap at two years of updated need. Record harvest failure and famine only when crossing their food-coverage thresholds, plus recovery when coverage rises back above the stress threshold.
- **Migration:** only settlements below 0.6 food coverage propose migration. Move up to 5% of population per year to an adjacent or same-region destination if its projected food coverage exceeds the origin by at least 0.25 and it has capacity. Split among eligible destinations by coverage gap; resolve capacity conflicts and apply moves simultaneously.
- **Trade:** settlements controlled by the same state in the same or neighboring region may transfer surplus food above one year of reserve to a neighbor below 0.75 coverage, up to 10% of surplus per donor per year. Resolve storage capacity simultaneously. No money or market-clearing model in this milestone.
- **Politics:** state food pressure is the population-weighted share of unmet coverage below 0.75. Stability drifts by `(0.35 − pressure) × 0.01` per year, clamped to 0–1. Border pairs record dispute score, claim status, and resource pressure in symmetric relationship records. A contested claim exists when a settlement belonging to one state sits in a region controlled by the other. Resource pressure is three times the higher of the two states' food-pressure values, capped at 1. The score is 0.25 for border adjacency, plus 0.35 for a contested claim, plus up to 0.40 for pressure. Declare war at 0.70 when both states have stability at least 0.25.
- **Conflict:** dispute score starts from border adjacency (0.25), a contested-region claim (0.35), and resource pressure (up to 0.40). War can be declared at score ≥0.70 when both states have stability ≥0.25. Resolve one coarse engagement per neighboring pair per year from population weighted by food coverage, with seeded opposing strength factors in the 0.85–1.15 range. The lower-scoring state loses 0.2% of its population, distributed proportionally; the winner gains 0.015 stability and loser loses 0.04. Record score inputs, strengths, variance, and casualties in event facts. Agree peace if the losing state falls below 0.10 stability. This model does not transfer territory.
- **Historical state:** the UI rebuilds an inspection-only world from the latest year-0 or 25-year checkpoint not later than the selected year, then replays at most 24 ticks. It keeps the live world untouched.
- **Save format:** one versioned JSON file at `user://saves/living-world.json`, with sorted entity arrays, map arrays, event history, and snapshots. Command-log persistence is deferred until interventions exist. No SQLite for the prototype.
- **Presentation target:** desktop at 1280×720, mouse and keyboard; renderer stays on the current compatibility setting until visuals require another choice.

Values above are starting balance parameters, not claims of realism. The first 20-seed, 250-year baseline has been run; results, limitations, and reproduction steps are in [the year-250 evaluation report](evaluation/year-250-baseline.md). Change values based on future observations and increment the simulation version whenever rules change outcomes. Godot 4.7.2 is the current stable maintenance release in the official release archive; track the latest stable 4.7 patch while avoiding development builds. [Godot release archive](https://godotengine.org/download/archive/).
