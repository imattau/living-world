# Food-aid intervention evaluation

**Run date:** 2026-09-26  
**Engine:** Godot 4.7.2  
**Simulation version:** 4  
**Sample:** 20 paired seeds, 250 annual ticks per world

Each pair used one of the seeds from the [year-250 baseline](year-250-baseline.md). Both worlds advanced to year 100. In the control, no command was issued. In the treated world, food aid was queued for the active settlement with the lowest food coverage; ties were broken by more consecutive food-stress years, then lower settlement ID. Both worlds then advanced to year 250. The script is reproducible from the project root:

```sh
godot4.7 --headless --path . --script res://scripts/evaluation/evaluate_food_aid.gd
```

## Results

| Measure | Result |
|---|---:|
| Commands queued / applied / failed | 20 / 20 / 0 |
| Year-250 target population difference, treated minus control, min / median / max | +1 / +4 / +36 |
| Targets with higher / lower / equal population | 20 / 0 / 0 |
| Target survival, control / treated | 20 / 20 |
| Consecutive food-stress streak difference at year 250, min / median / max | −100 / −100 / 0 years |
| Target famine-onset events, control / treated | 100 / 100, all in one seed per arm |

## Findings

- The action was accepted and applied in all 20 treated worlds. No target was abandoned or at full store capacity at the time of application.
- The treated target finished with a higher population in every pair, but the median gain was only four people after 150 years. The largest gain was 36.
- All targets survived in both arms, so this sample cannot show a survival benefit.
- The year-250 food-stress value is a **consecutive streak**, not cumulative years of stress. A single aid action reset that streak in most worlds; that is why the endpoint difference is close to the 100 years elapsed since the intervention. It does not mean food stress was avoided for a century.
- Famine-onset counts did not differ. They count transitions into famine, not famine duration or severity, and all 100 target onsets came from one seed in each arm. This measure is too coarse to establish that aid prevents famine.

Simulation version advanced from 3 to 4 for the intervention-capable rule set so that saves and replays identify the rules used.

## Design decision

Keep food aid as a working prototype action, but do not infer that it is balanced or sufficiently consequential from this sample. Before adding more interventions, improve the evaluation signals to capture short-term food coverage, famine duration, and the target's population trajectory around the action. Then repeat the paired evaluation over more seeds and intervention timings. Causal links were added in the following milestone; see the updated [year-250 baseline](year-250-baseline.md) for current coverage.
