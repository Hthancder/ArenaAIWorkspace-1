# Movement-general prediction benchmark

Deterministic synthetic held-out seeds: 1847, 82031, 517991. Frozen solver evaluated on these seeds once; diagnostic/calibration seeds were 7301, 99173, 441019.
12 motion families × 3 seeds × 30/60/144Hz render × regular/jitter-gap 33Hz snapshots. WebSocket packet order preserved, backlog produces bunching. Quantization 16-bit/1024; fixed 35ms one-way age + 35ms estimated input transit.
Model only sees arrived samples. Weapon nominal speeds 66/85/100/182; origin/muzzle/range are explicit. No spread, body physics, obstructions or player skill. **Not live hitrate/FPS.**

Miss is future-position error at model flight time; collider miss=max(0, miss−1). Rejected/stale snapshot predictions are scored as direct/native fallback, not removed. Legacy baseline uses former render-sampled Tracker/intercept, without old controller blend (isolates estimator/solver). CV uses last arrival interval, no filtering.

| Motion | Model | n | Median miss wu | p95 miss | p95 collider miss | p95 overshoot | Recovery proxy median ms | Native fallback % | Reduced lead % | Solver p95 µs |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| stationary | no-predict | 12540 | 0.001 | 0.001 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| stationary | legacy-render | 12540 | 0.001 | 0.001 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| stationary | simple-CV | 12540 | 0.001 | 0.001 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| stationary | snapshot | 12540 | 0.001 | 0.001 | 0.000 | 0.000 | 0.000 | 2.743 | 0.000 | 8.088 |
| straight | no-predict | 12540 | 10.484 | 17.579 | 16.579 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| straight | legacy-render | 12540 | 1.455 | 9.219 | 8.219 | 2.265 | 0.000 | 0.000 | 0.000 | 0.000 |
| straight | simple-CV | 12540 | 1.079 | 12.670 | 11.670 | 12.425 | 0.000 | 0.000 | 0.000 | 0.000 |
| straight | snapshot | 12540 | 0.388 | 3.139 | 2.139 | 1.198 | 0.000 | 2.743 | 3.102 | 5.197 |
| diagonal | no-predict | 12540 | 11.854 | 21.416 | 20.416 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| diagonal | legacy-render | 12540 | 1.665 | 10.456 | 9.456 | 2.908 | 0.000 | 0.000 | 0.000 | 0.000 |
| diagonal | simple-CV | 12540 | 1.145 | 14.628 | 13.628 | 14.144 | 0.000 | 0.000 | 0.000 | 0.000 |
| diagonal | snapshot | 12540 | 0.402 | 5.594 | 4.594 | 1.431 | 0.000 | 2.743 | 7.560 | 1.928 |
| approach-retreat | no-predict | 12540 | 4.688 | 10.507 | 9.507 | 6.938 | 916.667 | 0.000 | 0.000 | 0.000 |
| approach-retreat | legacy-render | 12540 | 3.845 | 19.676 | 18.676 | 18.720 | 444.444 | 0.000 | 0.000 | 0.000 |
| approach-retreat | simple-CV | 12540 | 4.168 | 25.333 | 24.333 | 23.496 | 433.333 | 0.000 | 0.000 | 0.000 |
| approach-retreat | snapshot | 12540 | 3.659 | 20.300 | 19.300 | 18.915 | 416.667 | 2.743 | 1.451 | 1.931 |
| start-stop | no-predict | 12540 | 5.483 | 7.896 | 6.896 | 0.000 | 173.611 | 0.000 | 0.000 | 0.000 |
| start-stop | legacy-render | 12540 | 4.965 | 8.685 | 7.685 | 9.570 | 229.167 | 0.000 | 0.000 | 0.000 |
| start-stop | simple-CV | 12540 | 5.804 | 13.040 | 12.040 | 20.112 | 201.389 | 0.000 | 0.000 | 0.000 |
| start-stop | snapshot | 12540 | 6.050 | 8.317 | 7.317 | 8.800 | 194.444 | 2.743 | 2.863 | 1.754 |
| curve | no-predict | 12540 | 7.947 | 11.583 | 10.583 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| curve | legacy-render | 12540 | 2.964 | 7.770 | 6.770 | 2.146 | 0.000 | 0.000 | 0.000 | 0.000 |
| curve | simple-CV | 12540 | 2.833 | 9.338 | 8.338 | 7.673 | 0.000 | 0.000 | 0.000 | 0.000 |
| curve | snapshot | 12540 | 2.573 | 6.646 | 5.646 | 1.701 | 0.000 | 2.743 | 0.526 | 1.824 |
| turn90 | no-predict | 12540 | 7.023 | 8.836 | 7.836 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| turn90 | legacy-render | 12540 | 5.789 | 14.688 | 13.688 | 10.803 | 270.833 | 0.000 | 0.000 | 0.000 |
| turn90 | simple-CV | 12540 | 5.611 | 18.588 | 17.588 | 16.020 | 291.667 | 0.000 | 0.000 | 0.000 |
| turn90 | snapshot | 12540 | 5.481 | 14.894 | 13.894 | 11.054 | 270.833 | 2.743 | 1.077 | 1.856 |
| reverse180 | no-predict | 12540 | 3.936 | 7.829 | 6.829 | 6.285 | 583.333 | 0.000 | 0.000 | 0.000 |
| reverse180 | legacy-render | 12540 | 4.731 | 16.448 | 15.448 | 16.093 | 312.500 | 0.000 | 0.000 | 0.000 |
| reverse180 | simple-CV | 12540 | 5.112 | 18.856 | 17.856 | 18.258 | 298.611 | 0.000 | 0.000 | 0.000 |
| reverse180 | snapshot | 12540 | 4.835 | 17.043 | 16.043 | 16.515 | 284.722 | 2.743 | 0.574 | 1.517 |
| speed-change | no-predict | 12540 | 11.551 | 21.794 | 20.794 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| speed-change | legacy-render | 12540 | 4.736 | 14.533 | 13.533 | 10.043 | 416.667 | 0.000 | 0.000 | 0.000 |
| speed-change | simple-CV | 12540 | 4.713 | 16.900 | 15.900 | 16.708 | 400.000 | 0.000 | 0.000 | 0.000 |
| speed-change | snapshot | 12540 | 4.502 | 12.800 | 11.800 | 9.845 | 347.222 | 2.807 | 11.284 | 2.639 |
| zigzag-irregular | no-predict | 12540 | 8.121 | 12.927 | 11.927 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| zigzag-irregular | legacy-render | 12540 | 7.099 | 18.189 | 17.189 | 14.331 | 236.111 | 0.000 | 0.000 | 0.000 |
| zigzag-irregular | simple-CV | 12540 | 7.310 | 24.073 | 23.073 | 20.587 | 201.389 | 0.000 | 0.000 | 0.000 |
| zigzag-irregular | snapshot | 12540 | 7.098 | 17.068 | 16.068 | 12.980 | 201.389 | 2.743 | 6.220 | 1.912 |
| mixed | no-predict | 12540 | 3.636 | 10.018 | 9.018 | 1.974 | 270.833 | 0.000 | 0.000 | 0.000 |
| mixed | legacy-render | 12540 | 3.403 | 11.428 | 10.428 | 9.279 | 291.667 | 0.000 | 0.000 | 0.000 |
| mixed | simple-CV | 12540 | 3.356 | 12.627 | 11.627 | 11.299 | 266.667 | 0.000 | 0.000 | 0.000 |
| mixed | snapshot | 12540 | 3.285 | 11.389 | 10.389 | 9.123 | 266.667 | 2.743 | 1.180 | 1.386 |
| wall-stop | no-predict | 12540 | 5.048 | 9.041 | 8.041 | 0.000 | 145.833 | 0.000 | 0.000 | 0.000 |
| wall-stop | legacy-render | 12540 | 5.277 | 13.162 | 12.162 | 12.891 | 516.667 | 0.000 | 0.000 | 0.000 |
| wall-stop | simple-CV | 12540 | 5.304 | 17.486 | 16.486 | 17.049 | 423.611 | 0.000 | 0.000 | 0.000 |
| wall-stop | snapshot | 12540 | 5.230 | 13.158 | 12.158 | 12.360 | 375.000 | 2.743 | 1.746 | 1.513 |

Recovery column is the elapsed time since the most recent detected ground-truth velocity discontinuity **for frames already within radius** (not a guarantee of sustained recovery). Smooth curves have no discrete turn marker. Selection churn is not measured in this single-target solver benchmark; separate combination tests cover target ownership/lifecycle. CPU column measures only this solver call in Node, not frame work or browser FPS.

## Interpretation / limits

Fit residual (wu) and slope uncertainty (wu/s) are separate. Excess slope uncertainty uses an explicit reduced-lead fallback, recalculating physical flight time; stale age >150ms relinquishes aim. Native fallback is scored using current-position direct aim as a proxy because physical user intent is not available in this synthetic dataset.

Short weighted regression is movement-agnostic: no maneuver classifier or future-pattern fit. Turns/stops can be intrinsically unpredictable across flight time. The uncertainty guard may relinquish aim instead of claiming an accurate intercept; fallback misses remain in this table. Per-category results, including regressions, must be reviewed rather than hidden in a grand average.
