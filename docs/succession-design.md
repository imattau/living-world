# State succession — detailed design

Status: proposal, scoped for review before implementation. First item from
`docs/complexity-roadmap.md`'s build order.

## Goal

Right now `StateData.leader_label` is set once at generation ("Founder")
and never changes for the life of the world. A state can exist for 250+
years under the same nominal ruler. This adds a yearly succession check so
leadership turns over, sometimes cleanly and sometimes with consequences,
giving long-run histories a political "generation" texture instead of a
single frozen leader per state.

## Data model changes

`StateData` gains:

```gdscript
var leader_id: int = -1          # allocated entity id, for event participant_ids
var leader_since_year: int = 0
var leader_age: int = 0          # years old, advances +1/year
var succession_rule: String = "hereditary"  # only value for now; future government_types can vary this
```

`leader_label` stays as the display name (e.g. "Aran III"); `leader_id` is
what events reference so the UI/serializer treat leaders consistently with
every other participant type already in `HistoryEvent.participant_ids`.

At generation, `world_generator.gd:_create_initial_states` sets
`leader_since_year = 0`, `leader_age` to a seeded random 25–45, and
`leader_id = world.allocate_entity_id()`.

## Yearly algorithm (new `_update_leadership` step in `simulation_engine.gd`)

Runs once per year, after `_update_politics_and_conflict` (so a leader who
just lost a war can plausibly be the one deposed), for every state in
`_sorted_integer_keys(world.states)`:

1. `leader_age += 1`.
2. Death check: mortality probability rises with age past 60 (simple
   curve, e.g. `clampf((leader_age - 60) * 0.02, 0.0, 0.35)` per year),
   rolled from a dedicated `LEADERSHIP_STREAM_ID` `SeededRandom` derived
   the same way `CONFLICT_STREAM_ID` already is
   (`derive_seed(world.seed, LEADERSHIP_STREAM_ID, world.simulation_version * 65_537 + year)`)
   — keeps this deterministic and replay-safe like the existing conflict
   roll.
3. Instability check (independent of age): if `stability < 0.15`, roll a
   coup chance (e.g. 15%/year while stability stays that low). A
   successful coup is a forced succession even if the leader is alive.
4. If neither death nor coup fires, nothing happens (majority of state-years).
5. On a triggered succession, resolve the new leader:
   - **Peaceful (death, stability ≥ 0.35):** hereditary — new leader is a
     freshly allocated id, age reset to a seeded 20–35, `leader_since_year
     = year`. Small stability bump (+0.02, continuity).
   - **Contested (death with stability 0.15–0.35, or any coup):** roll a
     seeded outcome between "smooth transition" and "succession crisis".
     A crisis applies a stability penalty (-0.08 to -0.15) and has a
     chance to trigger the state-fragmentation hook once
     formation/dissolution (item 2 in the roadmap) exists; until then it's
     just a worse stability hit and a distinct event type.
6. Emit exactly one event per triggered succession:
   - `ruler_died` (facts: `previous_leader_id`, `age`, `cause: "old_age"`)
     — only when death (not coup) triggers it, always paired with a
     `ruler_succeeded` or `succession_crisis` event on the same year.
   - `ruler_succeeded` (facts: `previous_leader_id`, `new_leader_id`,
     `method: "hereditary"|"coup"`, `stability_before`, `stability_after`)
   - `succession_crisis` (facts: as above, plus `outcome: "crisis"`) in
     place of `ruler_succeeded` when the contested roll goes badly.
   - `cause_links`: if the triggering state's `_state_food_pressure` was
     elevated or it lost a recent `battle_resolved`, link back to that
     event the same way `war_declared`/`settlement_abandoned` already do
     (reuse the existing `_find_causal_event` pattern, searching for the
     state's most recent `battle_resolved` where it was `loser_state_id`,
     or a `war_declared`/instability driver) — this is what makes "a
     losing war destabilized the throne" inspectable rather than a bare
     coincidence.

## Interactions with existing systems

- **War/battle:** a coup mid-war doesn't change `at_war_with` — the state
  continues the war under new leadership. No special-casing needed.
- **Casualties/abandonment:** leaders aren't tied to a settlement, so
  settlement abandonment doesn't affect leadership directly.
- **`_state_military_strength`/`_state_food_pressure`:** unaffected;
  leadership is cosmetic to those formulas for now (a later pass could let
  a low-stability succession temporarily reduce military strength, but
  that's scope creep for this item).
- **Single-state edge case:** with only 1 state in the world (or 0, after
  a hypothetical future collapse), `_update_leadership` still runs per
  state independently — it doesn't require the 2+ states that
  `_update_politics_and_conflict` needs, so no guard changes there.

## Determinism & replay

Uses its own RNG stream id (next unused constant after `CONFLICT_STREAM_ID
= 7`, so `LEADERSHIP_STREAM_ID = 9` to leave room), derived the same
per-year way as conflict rolls, so it's replay-safe by the same argument
already established for `war_declared`/`battle_resolved`. `cause_links`
lookups reuse `_find_causal_event`, which already searches
`world.events + _pending_events` rather than engine-instance state, so
this doesn't introduce a new source of live-vs-replay divergence.

## Save/serialization

`world_serializer.gd`'s state (de)serialization needs the four new
`StateData` fields added to its dictionary round-trip
(`to_dictionary`/`from_dictionary` equivalents for states) with sane
defaults for old saves (`leader_id: -1`, `leader_age: 30`,
`leader_since_year: 0`, `succession_rule: "hereditary"`) so existing saves
still load.

## UI

No new UI required to ship this — `ruler_succeeded`/`succession_crisis`/
`ruler_died` events render through the existing chronicle and cause_links
display in `main.gd`. A "current leader" line in the state summary panel
(`main.gd`'s selected-state view) would be a nice small addition but isn't
required for the mechanic to be inspectable.

## Open questions before implementation

1. Death-by-age curve and coup-chance-at-low-stability numbers above are
   first guesses for tuning — fine to implement and tune via
   `scripts/evaluation/evaluate_worlds.gd` after the fact, or do you want
   to fix different numbers up front?
2. Should a `succession_crisis` do anything mechanical yet (e.g. a bigger
   stability hit, temporary military weakness) or stay a flavour/severity
   distinction until state fragmentation (roadmap item 2) exists to give
   it real teeth?
3. OK to add the leadership step unconditionally to `advance_year`, or
   should it be gated behind a world-generation flag/version bump so
   existing saves' histories aren't retroactively "different" if replayed
   from an early checkpoint under new engine code? (Note: replaying old
   saves under updated simulation code is already implicitly assumed
   elsewhere, e.g. `simulation_version` exists precisely to isolate RNG
   streams across such changes — this would just be another bump.)
