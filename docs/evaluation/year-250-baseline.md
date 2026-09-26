# Year-250 baseline evaluation

**Run date:** 2026-09-26  
**Engine:** Godot 4.7.2  
**Simulation version:** 3  
**Sample:** 20 seeds, 250 annual ticks per seed

Seeds were `26,092,600 + (sample_index × 1,009)`, for sample indices 0 through 19. Reproduce the run from the project root with:

```sh
godot4.7 --headless --path . --script res://scripts/evaluation/evaluate_worlds.gd
```

## Results

| Measure | Result |
|---|---:|
| Starting population, min / median / max | 7,215 / 9,100 / 10,912 |
| Year-250 population, min / median / max | 13,315 / 16,885 / 20,272 |
| Surviving settlements, min / median (of 12) | 11 / 12 |
| Active states, median | 3 |
| Worlds with famine events | 1 of 20 |
| Famine events | 99, all in one world |
| Worlds with migration events | 4 of 20 |
| Migration events | 179 |
| Worlds with food trade | 1 of 20 |
| Food trade events | 71 |
| Worlds with declared wars | 3 of 20 |
| Wars / battles / peace events | 5 / 84 / 5 |
| Events with structured facts | 100% (2,812 events) |
| Events with cause links | 0 |

## Findings and tuning

- Population grew in every sampled world, with a median year-250 total about 1.85 times the initial total. Settlement survival was high; one world ended with 11 of 12 settlements active.
- Famine was concentrated in one seed, which recorded 99 famine onsets. The other 19 worlds recorded none. This warrants inspecting that seed's food and migration chronicle before changing the general food model.
- Trade and migration occur only when local shortage and adjacency conditions align. They remain sparse in this sample, so their current thresholds need broader scenario coverage before changing them.
- The first conflict pass produced no wars because its resource-pressure mapping could not reach the declaration threshold. The final mapping uses three times the higher state food-pressure value, capped at 1, while retaining the 0.70 dispute threshold. This produced wars in 3 of 20 worlds, with 84 battles and 5 peace events. Conflict remains uncommon and clustered in food-stressed worlds.
- Every event has structured facts, but no event has a `cause_links` entry. The chronicle can show observed facts, but it cannot yet trace an event chain. Cause-link authoring remains a clear history-quality gap.

This is a baseline rather than a balance target. The sample is small and generated outcomes are sensitive to seed and simulation version.
