# State formation, dissolution & annexation — detailed design

Status: proposal, scoped for review before implementation. Second item
from `docs/complexity-roadmap.md`'s build order, building on the
succession mechanic already implemented (`docs/succession-design.md`).

## Why this is next

Region/settlement ownership (`RegionData.controlling_state_id`,
`SettlementData.state_id`) is set once in `world_generator.gd` and never
changes afterward — confirmed by grep, there are no other write sites.
Wars can now topple rulers (succession) but can never actually change
which state holds what. That's the other half of "why does the map look
the same in year 500 as year 50": borders are permanently frozen at
generation. This closes that gap with three linked mechanics: annexation
(a war actually redraws a border), dissolution (a broken state can
fragment), and formation (a new state can emerge from ungoverned land).

## 1. Annexation — wars start mattering territorially

Currently `_has_contested_claim` already detects when a settlement's
`state_id` differs from its region's `controlling_state_id` (a "pocket"
inside a rival's territory) and that feeds `dispute_score`. But nothing
ever resolves a contested claim — it just sits there indefinitely,
constantly nudging up war likelihood.

**Change:** when `battle_resolved` fires and the border region
(`pair["region"]`) was a contested claim between the two states, resolve
it in the winner's favor: reassign the border region's
`controlling_state_id` to the winner, and reassign any settlements in
that region whose `state_id` was the loser's to the winner. This is a
one-region-at-a-time land grab, not a full conquest — matches the scale
of a single `battle_resolved` roll.

New event: `territory_annexed` (facts: `region_id`, `from_state_id`,
`to_state_id`, `settlement_ids`), `cause_links` → the triggering
`battle_resolved` event (reuse `_find_causal_event`/pattern already
established for `succession_crisis`).

Guard: only annex if the loser would retain at least one settlement
afterward (states shouldn't be silently erased here — total collapse is
dissolution's job, see below, and going through the same path keeps
"a state disappeared" always explainable by one mechanic).

## 2. Dissolution — a broken state can fragment

**Trigger:** a state's `stability` stays below `0.10` for `N` consecutive
years (mirrors the existing `ABANDONMENT_POPULATION`/
`YEARS_BELOW_ABANDONMENT_THRESHOLD` pattern already used for settlements —
add `years_below_fragmentation_threshold` to `StateData`, checked in a new
`_update_state_cohesion` step).

**Resolution:** split the state's current settlements into 2–3 successor
states using the same anchor/nearest-anchor clustering
`world_generator.gd:_create_initial_states` already uses (extract that
into a shared helper both call, rather than duplicating it — this is the
one piece of this design that touches generation code, not just the
engine). Each successor gets a fresh `leader_id`/`leader_age`/
`leader_ordinal = 1`/`leader_label = "Founder"`, `stability` reset to a
moderate `0.5` (a fragment starts unstable but not doomed), and inherits
the parent's `government_type` for now (culture-linked government types
are a later pass).

New event: `state_fragmented` (facts: `parent_state_id`,
`successor_state_ids`, `stability_before`), `cause_links` → whatever
`succession_crisis`/`battle_resolved` events kept stability pinned below
threshold (same lookup pattern).

Old state record: kept in `world.states` with `settlement_ids` cleared
and a `dissolved_year` field (new) set, rather than deleted outright —
preserves it as a queryable historical entity for the chronicle ("State
07 existed from year 40 to year 118") instead of erasing it.

## 3. Formation — new states from ungoverned land

**Trigger:** a region with `controlling_state_id == -1` whose settlements'
combined population crosses a threshold (proposed: 400, roughly one
grown-past-hamlet settlement) and none of those settlements already
belong to a state.

**Resolution:** found a new chiefdom exactly as `_create_initial_states`
does for one anchor — pick the region's largest settlement as capital,
claim the region, assign `leader_id` etc. fresh.

New event: `state_founded` (facts: `region_id`, `capital_settlement_id`,
`founding_population`). No `cause_links` needed — this is organic growth,
not caused by another event, matching how `settlement_status_changed`
already has no cause_links today.

**Cap, to bound cost:** `_update_politics_and_conflict` is O(states²) for
border pairs. Formation + fragmentation could otherwise let the state
count climb indefinitely over a long run. Cap total live states at
`INITIAL_STATE_COUNT * 2` (a constant captured at generation time,
`world.max_states` or similar) — once at the cap, formation checks are
skipped (fragmentation still allowed, since it's usually reducing net
governed complexity per state even though it raises count; if it would
exceed the cap, cap it at 2 successors instead of 3).

## Ordering within `advance_year`

```
_update_politics_and_conflict   (war/battle — now also does annexation on battle_resolved)
_update_leadership              (existing)
_update_state_cohesion          (new — dissolution)
_update_territorial_growth      (new — formation)
```

Annexation is folded into the existing conflict step (it's a direct
consequence of a specific battle) rather than a separate pass. Dissolution
and formation get their own passes since they're not tied to a single
event.

## Determinism

Two more RNG needs:
- Dissolution's successor split reuses the anchor-clustering algorithm,
  which is currently deterministic-but-generation-only (no RNG inside it
  beyond what world_generator already seeded) — safe to reuse as pure
  geometry.
- Formation needs no RNG (deterministic threshold trigger + deterministic
  "largest settlement" pick).
- Annexation needs no RNG (deterministic, tied to an already-resolved
  battle).

So none of this needs a new stream id — everything here is a
deterministic function of already-established state, same argument as
`cause_links` lookups.

## Save/serialization

`StateData` gains `years_below_fragmentation_threshold: int = 0` and
`dissolved_year: int = -1`. `world` gains `max_states: int` (set at
generation to `initial state count * 2`, serialized, defaulted to a large
number like 999 for old saves so they don't suddenly get capped
mid-history). Successor/founded states are just new entries in
`world.states` — no schema change needed beyond the two new `StateData`
fields.

## Interactions with existing systems

- `_has_contested_claim`/`dispute_score`: annexation directly reduces
  future contested-claim war triggers for the region it resolves — this
  is the intended feedback loop (wars now *fix* the border tension that
  caused them, at least locally, rather than the tension persisting
  forever).
- `_shared_border_region`: unaffected — it already recomputes from live
  `controlling_state_id` each year, so it picks up annexation and
  fragmentation results for free.
- `_state_food_pressure`/`_state_military_strength`/`_worst_food_settlement`:
  all iterate live `settlement.state_id`, so they too pick up ownership
  changes automatically with no changes needed.
- Succession: a freshly fragmented/founded state's leadership starts
  clean (age reset, ordinal 1) — `_update_leadership` needs no changes,
  it just processes whatever's in `world.states` that year.
- UI (`main.gd`): the settlement panel's "Political state" line and new
  "Ruled by" line already read live `state_id`/`states` lookups, so
  annexation/fragmentation/formation show up with no UI changes required.
  A world map redraw to color regions by `controlling_state_id` (flagged
  as a separate gap in the original code review) would make this far more
  visible, but isn't required for the mechanic to be inspectable via the
  chronicle and selection panel.

## Open questions before implementation

1. Dissolution threshold/duration (`stability < 0.10` for how many years —
   proposed same `5` as settlement abandonment) — fine as a first guess to
   tune later, per the same approach taken for succession?
2. Should a losing state that annexation would reduce to zero settlements
   instead trigger full dissolution (fragmenting its *remaining*
   settlements elsewhere, i.e. it just ceases to exist with its last
   settlement going to the winner) rather than being blocked from
   happening at all? I lean toward: block annexation from zeroing a state
   in this pass, and leave "a state can be entirely conquered" for a later
   pass once dissolution's bookkeeping (dissolved_year, historical
   queryability) is proven — but it's a real gap either way (a
   1-settlement state currently becomes un-annexable, effectively
   immortal even when powerless).
3. Formation population threshold (400) and state cap multiplier (2x
   initial) are first guesses — same "implement, tune via
   evaluate_worlds.gd" approach as succession, or fix different numbers
   now?
