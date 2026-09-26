# Year-250 baseline evaluation

**Run date:** 2026-09-26 · **Engine:** Godot 4.7.2 · **Simulation version:** 4
**Sample:** 20 seeds, 250 annual ticks per seed

Seeds were `26,092,600 + (sample_index × 1,009)`, for sample indices 0 through 19. Reproduce the run from the project root with:

```sh
godot4.7 --headless --path . --script res://scripts/evaluation/evaluate_worlds.gd
```

## Results

| Measure | Result |
|---|---:|
| Starting population, min / median / max | 7,215 / 9,100 / 10,912 |
| Year-250 population, min / median / max | 13,330 / 16,992 / 20,283 |
| Surviving settlements, min / median (of 12) | 11 / 12 |
| Active states, median | 3 |
| Worlds with famine events | 1 of 20 |
| Famine events | 100, all in one world |
| Worlds with migration events | 4 of 20 |
| Migration events | 180 |
| Worlds with food trade | 1 of 20 |
| Food trade events | 73 |
| Worlds with declared wars | 3 of 20 |
| Wars / battles / peace events | 5 / 88 / 5 |
| Events with structured facts | 100% (2,809 events) |
| Events with at least one cause link | 100% (2,809 events) |
| Condition-evidence links / earlier-event references | 2,819 / 1,232 |

## Findings and tuning

- Population grew in every sampled world, with a median year-250 total about 1.87 times the initial total. Settlement survival was high; one world ended with 11 of 12 settlements active.
- Famine was concentrated in one seed, which recorded 100 famine onsets. The other 19 worlds recorded none. This warrants inspecting that seed's food and migration chronicle before changing the general food model.
- Trade and migration occur only when local shortage and adjacency conditions align. They remain sparse in this sample, so their current thresholds need broader scenario coverage before changing them.
- The first conflict pass produced no wars because its resource-pressure mapping could not reach the declaration threshold. The final mapping uses three times the higher state food-pressure value, capped at 1, while retaining the 0.70 dispute threshold. This produced wars in 3 of 20 worlds, with 88 battles and 5 peace events. Conflict remains uncommon and clustered in food-stressed worlds.
- Every event has structured facts and at least one cause link. Across the sample, links cite 2,819 recorded conditions and 1,232 earlier events, including chains such as food stress to migration and war to battle to peace. The links are explanatory evidence, not probabilities; their coverage does not establish that every historical chain is complete.

This is a baseline rather than a balance target. The sample is small and generated outcomes are sensitive to seed and simulation version.
