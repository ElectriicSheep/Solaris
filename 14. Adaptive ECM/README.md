# 14. Adaptive ECM: offline proof of concept

The estimator starts from equivalent-circuit parameters that are deliberately wrong by 2 to 5 %. It adapts them online from the group voltages, the pack current and the temperatures (the same signals the BQ76952 gives the Pi), and the results are compared against the true plant values. This runs **offline only**: there is no chip emulator and no Pi link, so it is fast.

## Quick start

```matlab
app = EcmConvergenceApp;        % press Run (or app.run(24))
```

or, as a script:

```matlab
ECM = ecmParams;                % Seed=, ErrRange=, Noise=, InitTables=
set_param("ecmOffline", "StopTime", string(24*3600));
L = ecmGetLog(sim("ecmOffline"));
R = ecmEvaluate(L, ECM);        % convergence clocks, Wh, table errors
S = ecmSaveTables(L);           % work/ecmTables.mat, for ecmParams(InitTables=S)
```

Speed in accelerator mode: 24 h simulated in about 30 s. The app runs more slowly than this, because it updates its plots after each chunk of simulated time.

## Files

| File | What it is |
|---|---|
| `ecmParams.m` | All parameters: group tables built from the cells, thermal model, sensors, load schedule, starting errors, estimator tuning |
| `ecmOffline.slx` (built by `buildEcmOffline.m`) | LOAD schedule (Stateflow) → PLANT (13 group 1-RC models, continuous, variable step) → SENSOR (resolution, optional noise) → EST |
| `adaptiveEcm.slx` (built by `buildAdaptiveEcm.m`) | The estimator, as Simulink blocks: one For Each iteration per group |
| `EcmConvergenceApp.m` | The app: live error plots, time and Wh to convergence, lookup-table maps, signals |
| `ecmConvergence.m` | Convergence clocks (the pass rule below) |
| `ecmGetLog.m`, `ecmEvaluate.m`, `ecmSaveTables.m` | Read logs, summarise a run, save tables for a restart |
| `checkFastPlant.m` | Fast plant vs the detailed 91-cell Simscape plant |
| `dev/ecmPrototype.m` | Reference MATLAB implementation, used to check the blocks; not the deliverable |

## Plant (truth)

There are 13 parallel groups (7P each). Each group has one table per parameter, built from its 7 cells:
- OCV and τ1 are the mean of the cells;
- R0 and R1 are the cells in parallel;
- capacity and thermal mass are the sum;
- the cells' resistances to ambient combine in parallel.

The cells come from `bat_35E_13S7P_placeholder_params_hetero.m`. Those are **synthetic placeholder values**: the spread is per module, and nothing in them is measured.

The tables have **no temperature dependence**. Heat comes from I²R0 + v1²/R1 per group and is lost to a fixed 15 °C ambient, with no conduction between groups.

The load repeats this cycle: 10 min rest, then marine CYCLE A until the lowest group reaches 10 % SOC, 30 min rest, a 7 A charge until 95 % or 4.20 V, then 30 min rest.

`checkFastPlant` (600 s of CYCLE A, same current into both plants) gives a maximum group-voltage difference of **0.012 mV** and a maximum SOC difference of **0.00017 percentage points**: PASS. Temperatures matched to 0.002 K over that run, but the fast plant has no conduction between cells, so longer runs will differ.

## Estimator (per group, `adaptiveEcm.slx`)

| Block | Rate | What it does |
|---|---|---|
| `ekf` | 0.1 s | SOC and RC voltage. A 2-state EKF using R0, R1 and τ1 from the group's tables and the current capacity estimate. The OCV curve is the nominal cell curve, so the per-module OCV offsets (±3 mV) are not known to it. |
| `r0Ident` | 0.1 s | R0 by forgetting-factor RLS on Δv = −R0·Δi (λ = 0.999). |
| `rcIdent` | 1 s | R1 and τ1 by **instrumental-variable** FFRLS (λ = 0.995) on y = OCV(SOC) − v − R0·i, with y_n = a·y_{n−1} + c·i + d, R1 = c/(1−a) and τ1 = −1/ln(a). |
| tables | (with the identification blocks) | R0, R1 and τ1 over SOC (0:0.1:1) × temperature (0:10:50 °C), plus capacity. |
| `capacity` | at each rest | charge between two rested OCV readings ÷ the SOC change between them. |

Design choices in `rcIdent`:
- The instrument is the output of an auxiliary model driven by the table values. Plain RLS was biased by 40 % with the chip's 1 mV resolution.
- The update rate is 1 s, not 0.1 s. At 0.1 s, a sits so close to 1 that R1 and τ1 cannot be resolved (the a₁ → 1 problem).
- Updates happen only when the current varies. During rest and constant-current charge the parameters cannot be identified, and updating there corrupted the tables.

Table updates:
- A node moves towards the estimate by a fixed step in the direction of the error (a median-type update), at the SOC and temperature the estimate represents. That is the average of SOC and temperature over the RLS memory.
- Only the SOC node within ±0.02 of that point is moved. Moving both neighbours left a zig-zag in the table, because discharge always sweeps SOC the same way.
- The step shrinks as a node collects updates, down to 5 % of its starting size.

Every update is counted, and the app shows the counts.

The blocks were checked against `dev/ecmPrototype.m` over 1 h with the sensor resolution removed. The table values at the operating point differ by:

| Parameter | Median difference | 95th percentile |
|---|---|---|
| R0 | 0.005 % | 0.009 % |
| R1 | 0.007 % | 0.19 % |
| τ1 | 0.06 % | 0.8 % |

With 1 mV resolution the R0 path still agrees (median 0.005 %). The R1 and τ1 paths diverge, because single 1 mV flips push the noise-dominated RC identification onto a different path.

## Convergence rule (fixed before the runs)

A parameter has converged when its error stays within **±1 % for 10 min** of simulated time. The time and Wh reported are those at the **start** of that window. If the error later leaves the band, the time it left is reported too.

- For R0, R1 and τ1, the error compares the table values the EKF is using now (at the estimated SOC and the measured temperature) with the true values (at the true SOC and temperature).
- For capacity, it is the estimate against the true capacity.
- Wh is the energy through each group, counting charge and discharge.

## Results (seed 1, plant seed 1, placeholder cells, no sensor noise unless stated)

**Capacity.** All 13 groups converged at **10.96 h / 148 Wh**. That is the rest after the first charge, which gives the first usable pair of rested readings. Final error ≤ 0.19 %. It also converged with noise and a 20 mA current offset (final median 0.06 %).

**R0.** All 13 groups entered the band about 20 min after the load started (0.5 h, 3–4 Wh). During the first discharge the error saw-tooths between SOC nodes, because each node is corrected only when SOC reaches it. Final error ≤ 0.35 %. After 72 h, the table read at the operating temperature is within **0.07–0.66 %** at SOC 0.1–0.9. The 0 % and 100 % nodes are never reached, so they keep their starting error.

**R1 and τ1.** These do **not** hold ±1 %.

| Run | R1 final error at the operating point | τ1 final error at the operating point | Updated nodes, median error (R1 / τ1) |
|---|---|---|---|
| 24 h | −5.6 … +5.2 % | −18 … +12 % | 3.1 % / 4.9 % |
| 72 h | — | — | 2.6 % / 3.5 % |
| 24 h, sensor resolution removed | median 0.9 %, max 3.6 % | median 0.9 %, max 3.6 % | — |
| 24 h, sensor noise added | — | — | 7.7 % / 10 % |

With the resolution removed, all four parameters met the ±1 % rule in every group. **The 1 mV voltage resolution is the main limit.** The RC voltage is small: about 10 mV at this cycle's 2.8 A average (0.12C).

**Restart from saved tables** (24 h run, then 12 h from its tables), compared with the first 7 h of a fresh start:

| Parameter | 95th-percentile error at the operating point, fresh start | From saved tables |
|---|---|---|
| R0 | 2.9 % | 0.8 % |
| R1 | 12.9 % | 7.2 % |
| τ1 | 13.2 % | 10.2 % |

Capacity started within 0.1 % of the true value.

**Temperature axis.** Temperatures stayed between 15 and 21 °C. Only the 10 °C and 20 °C columns were updated, and the data fixes only a weighted combination of the two. So each column can be wrong while the value at the operating temperature is right.

## Limits

- **Best-case model match.** The plant and the estimator have the same 1-RC structure, the plant has no temperature dependence, and there is no hysteresis or diffusion.
- **Placeholder cells.** None of these numbers describes a real INR18650-35E.
- **Capacity needs long rests.** It relies on two rests of at least 20 min with at least 20 % SOC between them. A vehicle that never rests would never update it.
- **One load.** The excitation comes from one cycle at low C-rate. A higher C-rate or a richer profile, more resolution, or longer averaging are the levers for R1 and τ1. With CYCLE A doubled (24 h), the final operating-point errors narrowed (R1 at most 4.3 %, τ1 at most 6.1 %), but the table-node errors did not (median 4.2 % / 4.6 %).
- **Offline only.** Nothing here has run on the Pi. The blocks use only code-generation-compatible primitives, but no code has been generated yet.
