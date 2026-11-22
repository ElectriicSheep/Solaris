# BQ76952EVM standalone component test report

Executed in the connected MATLAB R2025b session. Production Solaris `PLANT` and `AFE` were not edited by the component work.

## Results

| Check | Result |
|---|---|
| MEX build and standalone library build | Pass |
| 4S independent Simscape nominal harness | Pass: 3.700 V/cell, 14.800 V stack, −2.960 A, FETs on |
| 13S independent Simscape nominal harness | Pass: 3.700 V sampled cells, 48.100 V stack, −2.400 A |
| 16S independent Simscape nominal harness | Pass: 3.700 V sampled cells, 59.200 V stack, −1.970 A |
| Mask cell-count and VCell Mode configuration for 3S, 4S, 13S, 16S | Pass for mask values and per-instance settings; physical conserving-port count is fixed |
| Transaction-level I2C C-controller tests | Pass: device ID, voltage/current reads, data-memory write/readback, supported subcommand, wrong-address NACK, two-instance state isolation |
| Transaction-level I2C through Simulink S-function | Pass: ID, cell voltage, current, DA_CONFIG write/readback and ALL_FETS_OFF |
| PCB/Schematic view toggle | Pass: four toggles each in 4S and 13S harnesses; names/counts and output/configuration snapshots unchanged |
| Existing unchanged `07. Tests/checkAfe.m` | Pass: nominal, COV, OCD1, OTC and CUV scenarios |
| Existing unchanged `07. Tests/checkAfeMeasurements.m` | Pass: cell, stack, current and temperature measurements |
| Exported PCB and schematic view artifacts | Pass: rendered from Simulink and visually inspected; see `BQ76952EVM_PCB_View.png` and `BQ76952EVM_Schematic_View.png` |

## Limits and interpretation

Cell-count tests configure 3S/4S/13S/16S modes and verify mask-instance values. They do not change the count of external conserving ports: CELL1–CELL16 remain fixed and stable. Users must explicitly wire unused inputs to the required adjacent node; the harnesses cover 4S and 13S. Dynamic structural port removal and a simultaneous physical simulation of two differently configured cell-count instances were not verified and are not claimed.

The communication tests exercise a software transaction interface at the 10 ms emulator sample boundary. They do not test bit-level SDA/SCL electrical behavior. J22 SPI/HDQ is annotated from the board documentation but is not implemented. The standalone harness suite covers nominal measurement/current behavior; it does not constitute standalone OV/UV delay/recovery or charge/discharge interruption coverage. The unchanged Solaris baseline protection tests passed but exercise the pre-existing AFE path, not this new component’s protection path.

`checkAfeMeasurements.m` emits its existing undefined `Wh` bus-unit warning; the test still passes and the warning was not suppressed.
