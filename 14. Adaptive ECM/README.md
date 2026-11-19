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

## Spreading learning to unvisited table points (2026-11-20)

Learning itself (the stored tables) is unchanged. When a table is read, each point's correction ratio (stored value ÷ starting value) is blended with its neighbours' ratios:
- the blend is weighted by distance, using kernels of 1.5 points over SOC and over temperature;
- each point's own data counts in proportion to count/(count + c), with c = 2000 for R0 and c = 200 for R1 and τ1;
- a point with no updates takes its neighbours' ratio, and a point with plenty of its own data keeps its own.

This is the `fill_*` blocks in `adaptiveEcm.slx`, switched by `ecmParams(Spread=…)`. Starting errors can now vary over the table (`ErrShape`):
- `group`: one error per parameter per group, as before;
- `smooth`: a smooth surface with |d| of 2–5 % and one sign per group, like a table measured on a different cell;
- `node`: an independent error at every point. This is the hard case.

The test was CYCLE A for 48 h, error seed 1. For `smooth` it was also run with seeds 2 and 3, which give the same picture. For example, the R0 95th-percentile error in the first discharge was 0.61 / 0.71 / 0.66 % with spreading and 3.08 / 3.17 / 3.12 % without; the R1 whole-table median was 1.51 / 1.54 / 1.79 % with spreading and 3.42 / 3.47 / 3.37 % without.

| Starting errors | Spreading | R0 first discharge, 95th pct | R0 last 24 h, 95th pct | R0 at SOC 0 and 100 % (never visited) | R0 whole table, median | R1 whole table, median | τ1 whole table, median |
|---|---|---|---|---|---|---|---|
| group | off | 2.56 % | 1.17 % | 3.04 % | 2.61 % | 2.95 % | 3.24 % |
| group | on | **0.41 %** | **0.61 %** | **0.23 %** | **0.32 %** | 1.70 % | 2.28 % |
| smooth | off | 3.08 % | 1.46 % | 3.73 % | 3.08 % | 3.42 % | 3.56 % |
| smooth | on | **0.61 %** | **0.73 %** | **0.43 %** | **0.67 %** | 1.51 % | 2.30 % |
| node | off | 2.48 % | 1.59 % | 2.58 % | 3.21 % | 3.48 % | 3.61 % |
| node | on | 2.66 % | 1.38 % | 2.93 % | 3.10 % | 3.52 % | 3.70 % |

Errors at the operating point use the table values the EKF actually uses. The "SOC 0 and 100 %" and "whole table" columns cover every point, including those never updated.

- **Smooth or group starting errors:** spreading removes most of the R0 sawtooth (worst-case error in the first discharge falls from about 3 % to about 0.6 %). Groups whose R0 error later left the band fall from 13 of 13 to 9–10 of 13. The never-visited ends of the table end up within 0.5 %.
- **R1 and τ1:** spreading halves the whole-table error, but the operating-point error over the last 24 h is unchanged (95th percentile 7.5 % for R1, 9.8 % for τ1). Those remain limited by the 1 mV resolution.
- **Independent starting errors:** spreading does nothing useful, and is slightly worse at the never-visited ends (2.9 % against 2.6 %). Neighbours carry no information about a point whose error is independent of theirs. The benefit therefore depends on the real table errors being smooth, which is plausible for a table from another cell or an older characterisation, but is an assumption.
- **Convergence times with independent errors:** these look fast (about 0.3 h) only because randomly signed point errors partly cancel at points between table points. That is not real convergence.

## Bench extensions (2026-11-20)

All plant additions are **placeholders**.

- **Temperature dependence.** R0, R1 and τ1 follow Arrhenius (Ea 15, 30 and 10 kJ/mol, reference 25 °C) on a 10 °C grid. OCV and capacity do not depend on temperature. `ecmParams(TempDep=false)` switches it off.
- **Degradation.** Equivalent full cycles are counted as EFC = Ah throughput / (2 Q_new).
  - Capacity loss: 0.3/600 per EFC from cycling, plus 2 %/year calendar.
  - Resistance growth: 0.6/600 per EFC from cycling, plus 3 %/year calendar.
  - Both are Arrhenius in temperature (Ea 20 kJ/mol cycling, 50 kJ/mol calendar).
  - SOHq = Q/Q_new and SOHr = R_new/R. End of life is SOHq = 70 %, about 600 EFC at 25 °C.
  - `AgeingScale` fast-forwards ageing; `Degradation=false` switches it off.
  - `checkFastPlant` switches both temperature dependence and degradation off, and still passes (0.012 mV).
- **Initial conditions per group** (`IC`, and the app's Initial conditions tab): SOC, SOHr, SOHq, temperature, cycles, and ambient temperature. `ecmSohFromCycles` converts a cycle count to SOH. `ErrBase` sets whether the estimator's starting error is relative to the aged true values or to new-cell values.
- **Ideal-excitation load** (`Profile="ideal"`, `ecmIdealProfile`):
  - a multisine with 37 log-spaced harmonics up to 2 Hz, plus random steps held 0.3–60 s;
  - the same average as CYCLE A (2.78 A) and nearly the same peak (15.06 A against 15.16 A);
  - short charge pulses down to −3 A.
- **Engine, batch and replay.**
  - `EcmEngine` runs in chunks, keeps a decimated history, and saves and loads results, so a run can be continued.
  - `ecmBatch` runs N cycles flat out at about 1100× real time, including the build.
  - `ecmBatchMany` runs several batches in parallel on process workers.
  - The app's "Open results…" and replay slider step through a saved run.
- **Dual EKF** (`Method="dekf"`). This is the parameter filter of a dual EKF after Plett 2004:
  - parameters are ln R0, ln R1, ln τ1 and an OCV offset;
  - it uses an output-error formulation with recursive sensitivities;
  - updates happen only while the current varies;
  - the state EKF uses the filter's previous estimates.

  It feeds the same tables, spreading and capacity estimator as the FFRLS path.

### Method and load comparison (48 h, smooth starting errors 2–5 %, seed 1, ageing and temperature dependence on)

Error at the operating point over the last 24 h, median / 95th percentile, %:

| Method | Load | R0 | R1 | τ1 | Table points, median R1 / τ1 |
|---|---|---|---|---|---|
| FFRLS + EKF | CYCLE A | 0.15 / 0.75 | 2.6 / 7.6 | 2.9 / 8.4 | 2.9 / 3.3 |
| FFRLS + EKF | ideal | 0.15 / 0.75 | **1.0 / 3.9** | **2.0 / 5.8** | **1.7 / 2.3** |
| dual EKF | CYCLE A | 0.36 / 2.3 | 16 / 146 | 9.7 / 176 | 7.8 / 7.5 |
| dual EKF | ideal | 0.60 / 6.3 | 9.0 / 108 | 8.2 / 185 | 5.5 / 6.3 |

- **Ideal excitation** clearly helps R1 and τ1 with FFRLS: R1 is at 1 % median, but its 95th percentile is still 3.9 %. It changes nothing for R0 and capacity.
- **The dual EKF, as implemented here, is worse than FFRLS on every measure,** with occasional large excursions (the 95th percentiles above 100 %).
  - It has not been tuned beyond first choices (Q, R, the gating, the offset term). Until it has, this comparison says nothing about dual EKFs in general.
  - A first version without the OCV offset was biased in proportion to each group's capacity error, through the SOC estimate. The offset fixed that.
- A first version of the ideal profile (steps held 2–60 s, multisine up to 0.2 Hz) had too few fast current steps. R0 never passed its information threshold, and R1 and τ1 were then biased by the unlearned R0. The fast content was added for that reason. CYCLE A changes by more than 1 A in about 13 % of 0.1 s steps.

## Limits

- **Best-case model match.** The plant and the estimator have the same 1-RC structure, the plant has no temperature dependence, and there is no hysteresis or diffusion.
- **Placeholder cells.** None of these numbers describes a real INR18650-35E.
- **Capacity needs long rests.** It relies on two rests of at least 20 min with at least 20 % SOC between them. A vehicle that never rests would never update it.
- **One load.** The excitation comes from one cycle at low C-rate. A higher C-rate or a richer profile, more resolution, or longer averaging are the levers for R1 and τ1. With CYCLE A doubled (24 h), the final operating-point errors narrowed (R1 at most 4.3 %, τ1 at most 6.1 %), but the table-node errors did not (median 4.2 % / 4.6 %).
- **Offline only.** Nothing here has run on the Pi. The blocks use only code-generation-compatible primitives, but no code has been generated yet.
