# Complexity roadmap beyond the 250-year milestone

Status: proposal, not yet implemented. The 200–250yr window in AGENTS.md was
a test milestone, not a permanent ceiling — this document sketches where to
add depth next, in an order that keeps each stage independently interesting
to inspect (per `docs/design-brief.md` §19's "don't move to the next stage
until watching the current stage is interesting" rule).

## Where we are against the design brief's 8 stages

| Stage | State |
|---|---|
| 1. World | Done |
| 2. Settlement | Done (growth/decline/abandonment) |
| 3. Population | Done (food, migration, trade) |
| 4. Politics | Partial — states, war/peace, stability exist; no succession, no formation/dissolution, no culture drift |
| 5. People | Not started — no significant-individual layer |
| 6. History | Partial — chronicle + causality (`cause_links`) now wired; no event-chain/story detection |
| 7. Intervention | Partial — one command (`food_relief`) |
| 8. Narrative | Not started |

## Why politics/culture is the next lever, not economy or combat

AGENTS.md still defers "complex economics" and "detailed combat" for this
milestone, and I'd keep respecting that: a market simulator or multi-unit
battle model is a lot of new surface area for something that doesn't yet
pay off in story terms. Political and cultural stasis is the opposite —
it's cheap to fix relative to its payoff, because the substrate
(`StateData`, `CultureData`, the event/cause_links system) already exists;
it's just never mutated after generation. A run at 500+ years currently
would show the same handful of founding states fighting the same wars
forever, which undercuts the entire "watch a living history" premise more
than any missing mechanic would.

### Proposed additions (roughly in build order)

1. **State succession & leadership** — `StateData.leader_label` /
   `government_type` currently never change. Add a leader lifespan/death
   check per year; on death, resolve succession (heir, election, coup —
   weighted by government_type and stability) and emit a `ruler_succeeded`
   or `succession_crisis` event, with `cause_links` back to whatever drove
   instability if relevant.
2. **State formation & dissolution** — allow a state below a stability/
   population floor to fragment into successor states (civil war), and
   allow a settlement to secede or be annexed by a neighbour after
   repeated conquest. This is what makes 500+ year runs politically
   varied instead of a fixed 5-state chessboard.
3. **Culture drift & splitting** — `CultureData.parent_ids` exists but
   nothing populates it after generation. Model slow drift of culture
   values with isolation, and a split event when a culture's settlements
   fragment across long-unconnected regions (mirrors the design brief's
   §8 "Proto-Neran → Hadran/Valic/Marethi" tree).
4. **Settlement founding post-generation** — currently all settlements
   are placed at year 0. Once a region has food/population headroom and
   no settlement, allow colonization to found a new one, closing the loop
   with population growth that currently just caps out at carrying
   capacity.
5. **Event-chain / story detection (stage 6 completion)** — now that
   individual events carry `cause_links`, a lightweight pass that walks
   chains (famine → migration → war → succession) and flags them as
   named "stories" for the chronicle UI is a natural, low-cost next step
   before touching stage 5 or 8.

### Deliberately still deferred

Detailed combat (unit composition, terrain, sieges), full market/pricing
economics, individual inventories, and the significant-individuals layer
(stage 5) all stay out of scope for this pass — they're each a large
enough surface that they deserve their own design pass once the political/
cultural substrate above is in place for them to attach to.

### Non-mechanical follow-up already flagged in the earlier review

Independent of new mechanics, the UI gaps identified in the code review
(chronicle only shows the last 12 events, no population/food/war trend
graph, no state/territory colour-coding on the map) become more pressing
as history gets longer and more eventful — worth doing alongside stage 4/6
work rather than after, since new event types are meaningless if nobody
can browse them.

## What I'd want confirmed before implementing

- Order of the five additions above, or a different priority.
- Whether "state formation/dissolution" should allow a *new* state to form
  from an uncontrolled region, or stay limited to existing states
  splitting/merging.
- Whether to touch `wood`/`stone`/`iron` at all in this pass (they're
  generated but completely unused) or leave that for the economy pass.
