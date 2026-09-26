# Culture drift & splitting — detailed design

Status: proposal, scoped for review before implementation. Third roadmap
item from `docs/complexity-roadmap.md`, following succession and state
formation/dissolution/annexation.

## The problem this must solve first

Before designing drift, there's a precondition check: `CultureData.values`
(a `PackedFloat32Array` of 3 floats, set once at generation in
`_create_cultures`) is **never read anywhere** — confirmed by grep across
`simulation_engine.gd` and `main.gd`. It's exactly the same situation as
the `wood`/`stone`/`iron` resource potentials flagged earlier: generated,
displayed nowhere, used by nothing. `parent_ids` is likewise write-only —
set to `[]` at generation and never populated or read.

This matters because I flagged this item earlier as risking becoming
"flavour text" unless it's tied to a real mechanic. Making values drift
that nothing reads would be exactly that risk realized. So this design
gives `values` a causal role first, then makes drift and splitting matter
because of it.

## 1. Give `values` a mechanical role: cultural distance drives war

The natural hook is `_update_politics_and_conflict`'s `dispute_score`
formula (`simulation_engine.gd`), which already combines a base rate,
a contested-claim bonus, and a resource-pressure term. I'd add a
cultural-distance term: two states whose dominant cultures have diverged
further are more likely to go to war, and — for the drift half of this to
matter — two states that stay at peace with adjacent, culturally similar
populations should drift *closer* over time (see §2), making long-lasting
peace self-reinforcing and old grudges between diverged cultures more
likely to reignite.

```
cultural_distance(a, b) = mean(|a.values[i] - b.values[i]| for i in 0..2)   # already 0..1 per dimension
dispute_score = 0.20
              + (0.30 if contested else 0.0)
              + 0.30 * resource_pressure
              + 0.20 * cultural_distance(dominant_culture(first), dominant_culture(second))
```

This rebalances the existing weights (was `0.25 + 0.35 + 0.40`, max 1.0)
to make room for the new term while keeping the max at 1.0 — a real
balance change, so `simulation_version` bumps again (5 → 6) and this
needs a pass through `evaluate_worlds.gd` afterward the same way
succession's numbers would.

`_state_dominant_culture(world, state_id)`: majority-population culture
among the state's settlements (same pattern as `_worst_food_settlement`).

`war_declared`'s `cause_links` gains a `"cultural_tension"` category
alongside the existing `"resource_pressure"` one when
`cultural_distance > 0.3`, pointing at... nothing yet (there's no single
event that "caused" a slow cultural divergence) — so this one is a
`cause_link` with no `event_id`, or more consistently, we skip a
cause_link for it and just leave `cultural_distance` in the event facts,
the same way `dispute_score`/`contested_claim` already appear in facts
without a cause_link today. I'd go with the latter (facts, not
cause_links) — simpler and consistent with how the existing dispute
factors are already surfaced.

## 2. Drift — migration-driven convergence, not random walk

Rather than an undirected random walk (which would drift values with no
explanation, undercutting the causality principle this project has been
built around), drift is a direct consequence of `population_migrated`,
which already exists and already knows both settlements' cultures:

When migration moves population from a settlement of culture A into a
settlement of culture B (`_apply_migration`), pull culture B's `values`
slightly toward culture A's, weighted by the migrated fraction of B's
post-migration population:

```
weight = clampf(float(population_moved) / float(destination.population after arrival), 0.0, 0.15)
culture_b.values[i] += (culture_a.values[i] - culture_b.values[i]) * weight
```

capped per-year per-culture (a culture absorbing several migrations in
one year shouldn't swing wildly — accumulate the pulls but clamp total
yearly movement per dimension to e.g. 0.05).

This is fully deterministic (a function of migration amounts already
computed that year, no new RNG needed) and directly explains *why* a
culture's values moved: because people from culture A settled among
culture B. That "why" is inspectable the same way everything else in this
project is meant to be, even without a formal cause_link — the chronicle
already shows `population_migrated` events, and a culture's values
history could later be plotted against them.

A culture with no incoming migration in a given year simply doesn't
drift. Over 250+ years, cultures embedded in high-migration regions
(coasts, river valleys — already the more attractive migration
destinations per `_apply_migration`'s existing 0.6 coverage-gap logic)
diverge into hybrids faster than isolated ones, which is exactly the
"geography drives culture" property the design brief asks for.

## 3. Splitting — a culture fractures along state lines

**Trigger:** mirror the state-dissolution pattern. Add
`years_states_diverged: int = 0` to `CultureData`. Each year, check
whether the culture's settlements are split across 2+ *different* states
(not just "more than one state" transiently — require the same split
state pairing to persist, or simplify: any split state persisted 10+
consecutive years, since re-checking the *same* pairing is extra
bookkeeping for marginal benefit at this stage). If population is split
across states for 10+ consecutive years, fork:

- The culture's settlements are grouped by their current `state_id`.
- The largest group keeps the original `CultureData` (same id, name,
  values).
- Each other group gets a new `CultureData` with `parent_ids = [original.id]`,
  a derived name/language/religion label (e.g. `"%s (Northern)"` using a
  cardinal-direction heuristic from the group's average position relative
  to the parent's, or simpler: an ordinal like state succession's roman
  numerals — `"%s II"`), and `values` copied from the parent (a split is
  a labeling event at the moment it happens, not an instant value jump —
  the two branches then drift apart independently afterward via §2).

New event: `culture_split` (facts: `parent_culture_id`,
`child_culture_ids`, `state_ids_involved`). No cause_links (same reasoning
as `state_founded` — organic, not a discrete trigger event) but the
`state_ids_involved` fact makes the "why" (political separation) legible
without one.

## Ordering within `advance_year`

```
_apply_migration                 (existing — now also nudges culture values)
...
_update_politics_and_conflict    (existing — now also reads cultural_distance)
_update_leadership               (existing)
_update_state_cohesion           (existing — dissolution)
_update_territorial_growth       (existing — formation)
_update_culture_divergence       (new — splitting, checked after territory is settled for the year)
```

Splitting goes last since it depends on `settlement.state_id`, which
dissolution/formation/annexation may have just changed this same year.

## Determinism

No new RNG stream needed anywhere in this design — cultural distance is
a pure function of existing `values`, drift is a deterministic function
of this year's already-computed migration amounts, and splitting is a
deterministic threshold check. Same "replay-safe by construction" argument
as everything implemented so far.

## Save/serialization

`CultureData` gains `years_states_diverged: int = 0` (already has
`parent_ids`, which starts actually being populated by this work).
`world_serializer.gd`'s culture (de)serialization needs the one new field
added with a default for old saves.

## Interactions with existing systems

- `_worst_food_settlement`/`_state_food_pressure`/`_state_military_strength`:
  untouched, they don't look at culture.
- Settlement `culture_id` never changes for existing settlements (only
  new forked `CultureData` entries and existing settlements'
  `culture_id` get reassigned when their state's cultural group forks —
  that reassignment is the only place `settlement.culture_id` changes
  after generation).
- State formation (`_update_territorial_growth`): a newly founded state's
  settlements keep their existing culture_id — no new culture is created
  just because a new state formed on the same population.
- UI: `main.gd`'s settlement panel already shows `culture.name`, so a
  `culture_split` immediately becomes visible there with no UI change
  needed. Showing `culture.values` or the parent/child ancestry tree
  (`docs/design-brief.md`'s "Proto-Neran → Hadran/Valic/Marethi" idea) is
  a nice-to-have, not required to ship this.

## Open questions before implementation

1. Is folding `cultural_distance` into `dispute_score` (rebalancing the
   existing weights, bumping `simulation_version` to 6) the right first
   mechanical hook, or would you rather see it drive something else first
   (e.g., a migration-destination preference bonus for shared culture,
   which would touch `_apply_migration` instead of conflict)? I lean
   toward the war hook since it's the smallest, most legible change and
   reuses a formula that already has this exact "weighted factors →
   score" shape.
2. Splitting threshold (10 consecutive years of the same state-split) —
   fine as a first guess to tune via `evaluate_worlds.gd`, same as every
   other threshold introduced so far?
3. Naming forked cultures — cardinal-direction heuristic vs. simple
   ordinal suffix (like the succession roman-numeral pattern)? I lean
   ordinal for consistency and because it needs no extra geometry code,
   but cardinal directions read better in the chronicle.
