# BQ76952EVM Simulink Component — Explainer

## What this component represents

`BQ76952EVM.slx` is a reusable Simulink library containing a masked behavioral model of TI’s BQ76952EVM evaluation board. It combines Simscape Electrical terminals and sensing with the existing `bq76952_emul.c` register, measurement and protection behavior. It can be used in a model without access to the Solaris plant, plant truth buses, SOC or SOH.

This is a board-level behavioral model, not a transistor-level reproduction. The library and its test harnesses are under [`12. AFE`](.). The component build script is [`build_BQ76952EVM.m`](build_BQ76952EVM.m).

## External terminals

The block exposes 20 Simscape electrical conserving ports:

| Terminal group | Ports | Purpose |
|---|---|---|
| Cell taps | `CELL1`–`CELL16` | Physical cell-node inputs. Each terminal feeds its corresponding differential IC sense channel: CELLn → VCn. |
| Battery power/reference | `BAT+`, `BAT-` | Battery-side power connection and low reference. `BAT-` is also the IC VC0 reference. |
| Pack power | `PACK+`, `PACK-` | Load/charger-side power connection. |

The PCB face uses board terminal names. The internal `VC0`–`VC16` names describe IC sense channels, not EVM terminal names. The Schematic View and mask description explain the mapping.

### Connecting a battery

Connect each cell tap to its corresponding stack node. Connect `BAT-` to stack negative. Connect both `BAT+` and `CELL16` to the stack-positive node. This reflects the separate board power and top cell-sense connections.

Connect the external load or charger across `PACK+` and `PACK-`. The board path from `BAT+` to `PACK+` includes the configured positive-link resistance. The return path from `PACK-` to `BAT-` includes the physical shunt and the protection-controlled CHG/DSG switches.

The PACK terminals are on the right side of the Simulink block. The photographed high-current PACK connector is near the board’s top centre. Simscape Connection Port placement in this component supports left and right sides; the attempted top-side placement was rejected by MATLAB. The board photograph still shows the connector at its physical location.

## Cell count and unused taps

The **Number of Series Cells** mask setting selects the emulator’s active VCell Mode. It does **not** change the physical port count. 4S, 13S and 16S instances all expose the same stable 20 conserving ports listed above.

This fixed interface avoids silently moving a wire to a different cell input when a mask parameter changes. For reduced cell counts, explicitly connect unused `CELLx` terminals to the adjacent used stack node, as TI specifies for reduced-cell configurations. The supplied 4S and 13S harnesses demonstrate this wiring. The component does not silently short unused inputs internally.

The emulator’s selected active channels use the bottom cell inputs and the top channel:

| Series count | Active VCell Mode mask | Measured channels |
|---:|---:|---|
| 3S | `0x8003` | VC1, VC2, VC16 |
| 4S | `0x8007` | VC1–VC3, VC16 |
| 13S | `0x8FFF` | VC1–VC12, VC16 |
| 16S | `0xFFFF` | VC1–VC16 |

The mask derives the active mode from the series count. Users remain responsible for explicitly wiring unused physical taps. The harnesses use zero-volt cell sources for those ties. These reduced-cell choices follow the BQ76952’s required bottom and top cell channels and TI’s unused-input guidance; consult the [BQ76952 datasheet](https://www.ti.com/lit/ds/symlink/bq76952.pdf) when designing other configurations.

## Internal electrical behavior

- Each cell sense path uses a physical resistor/filter and voltage sensor. Cell measurements are derived from the connected conserving terminals; the component does not accept a precomputed group-voltage vector.
- A Simscape shunt and current sensor sit in the battery-to-pack return path.
- CHG and DSG protection behavior controls the pack current path through the modeled switches. Nominal harness runs confirm current measurement and nominal conduction.
- Temperature inputs are signal interfaces, not thermal conserving ports. They provide the emulator’s temperature inputs.
- The emulator retains its 10 ms update cadence and existing quantization, register protocol, protection delays and FET behavior.

## Communications and signal interfaces

The block’s Simulink signals are software or diagnostic interfaces, not physical EVM pins:

| Signal | Direction | Meaning |
|---|---|---|
| `hostWr` | Input | Existing software host-write/command interface. |
| `i2cTxn` | Input | Transaction-level software request associated with J17 EXT_I2C. |
| `tempPinsK` | Input | Simulated board temperature-pin values, in kelvin. |
| `tDieK` | Input | Simulated die temperature, in kelvin. |
| `snapshot` | Output | Register/measurement snapshot for the simulated host. |
| `chgFet` | Output | Simulated CHG FET state/status. |
| `dsgFet` | Output | Simulated DSG FET state/status. |
| `i2cResp` | Output | Transaction-level software response for `i2cTxn`. |

The I²C transaction interface supports the tested device addressing, register reads/writes, data-memory access, a supported subcommand subset and ACK/NACK status. It is processed at an emulator sample boundary. It is **not** an electrical SDA/SCL implementation: the model has no open-drain pins, pull-ups, START/STOP detection, bit timing or bus arbitration. The 10 ms emulator update is not an I²C clock.

The EVM headers are annotated in Schematic View using TI’s connector assignments:

- J17 — EXT_I2C: SDA, SCL, an unlabeled pin and PGND.
- J22 — EXT_SPI / HDQ: PACK−, SPI_CS, SPI_CLK, SPI_MISO and SPI_MOSI/HDQ.

These labels describe the real board connectors; they do not imply those pins are electrically modeled. J17’s communication behavior exists only at the transaction abstraction. J22 SPI/HDQ has no implemented interface. No decorative electrical pins have been added. Pin references: [TI BQ76952EVM User’s Guide](https://www.ti.com/lit/ug/sluuc33a/sluuc33a.pdf) and [TI MSPM0 I²C connection guide](https://www.ti.com/lit/an/slaaeb3a/slaaeb3a.pdf).

## Mask configuration and display

The mask organizes settings into tabs for battery/cell configuration, current sensing, measurement and temperature acquisition, protection, FET behavior, and communications/diagnostics. Physical component parameters (such as shunt and filter values) are separate from programmable emulator data-memory settings. Preset values can initialize the component but do not create a Solaris plant dependency.

`Display Mode` selects PCB View or Schematic View. It changes only the mask icon. Both modes use the same ports, internal network, emulator settings and signal interfaces. The PCB image uses a tightly cropped image over a white background; it preserves the board’s original aspect ratio. In PCB View, the block labels cell terminals as `CELLn` and prefixes software/diagnostic interfaces with `SIM` or identifies them as software transactions. Schematic View explains the VC mapping, connector assignments and software/electrical distinction.

The final exported images are [`BQ76952EVM_PCB_View.png`](test/BQ76952EVM_PCB_View.png) and [`BQ76952EVM_Schematic_View.png`](test/BQ76952EVM_Schematic_View.png). The rendering method and interface audit are recorded in [`VIEW_TEST_REPORT.md`](test/VIEW_TEST_REPORT.md).

## Verified behavior

The independent harnesses passed nominal 4S, 13S and 16S runs. They measured 3.700 V per sampled cell and stack voltages of 14.800 V, 48.100 V and 59.200 V respectively; the measured nominal currents were −2.960 A, −2.400 A and −1.970 A. Display-mode invariance passed repeated switching in the 4S and 13S harnesses. The unchanged Solaris `checkAfe.m` and `checkAfeMeasurements.m` tests passed; the latter prints its existing undefined `Wh` bus-unit warning.

Cell-count inspection confirmed the same 20 conserving ports at 4S, 13S and 16S. This verifies the fixed interface, not dynamic port removal. Transaction-level I²C controller tests passed for device identification, measurement reads, a data-memory write/readback, a supported subcommand, wrong-address NACK and independent C-emulator instance state. See [`TEST_REPORT.md`](test/TEST_REPORT.md) for the test scope and limits.

## Not modeled

- Dynamic addition/removal of physical conserving ports by cell count.
- Electrical-layer SDA/SCL, SPI, HDQ or ALERT pins and their timing/protocol waveforms.
- Cell balancing circuitry, secondary protector/fuse, precharge, transistor-level board details, exact PCB parasitics and realistic ADC slot scheduling.
- A physical thermal network; temperatures are supplied as Simulink signals.

The model is intended for reusable battery-interface and BQ76952 behavior studies, not detailed EVM PCB electrical sign-off.
