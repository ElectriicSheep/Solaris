# Standalone BQ76952EVM Simulink component

`BQ76952EVM.slx` is a reusable Simulink library containing one masked behavioral EVM block. It uses physical Simscape Electrical cell sensing, shunt, and protection-controlled pack path and retains the instance-local `bq76952_emul.c` register/protection model. It has no Solaris workspace, plant bus, SOC/SOH or battery truth input. The initial mask preset is configurable and no longer required by the block.

## Electrical terminals

The block has conserving terminals `CELL1` through `CELL16`, `BAT+`, `BAT-`, `PACK+` and `PACK-`. External CELLx terminals connect to the corresponding IC VCx differential sense channel; the mapping is `CELLn` → `VCn` and `BAT-` → `VC0`. `BAT-` is the common low reference and battery-side current return into the shunt. `BAT+` remains a separate battery power terminal; connect it and `CELL16` to the same physical stack-positive node in the external battery model. PACK+ is linked to BAT+ through the configured board link resistance. PACK− is connected through the physical shunt and anti-series CHG/DSG switches.

The `Number of Series Cells` parameter configures VCell Mode but **does not change the conserving-port count**. Every CELL terminal remains visible and keeps its stable physical name. The current linked-library subsystem derives its conserving interface from fixed Connection Port blocks; mask initialization cannot safely add/remove those blocks at a linked instance without breaking the library link or risking external lines being rebound by port index. The safe behavior is to preserve the interface and require explicit external zero-volt ties for unused cells, as TI recommends. It never silently shorts or reassigns cell taps.

The automatic VCell Mode selection uses bottom channels `1..N-1` and top channel 16: 3S `0x8003`, 4S `0x8007`, 13S `0x8FFF`, 16S `0xFFFF`. For reduced configurations, connect each unused CELLx terminal to its adjacent used stack node using explicit external wiring. The test harnesses demonstrate 4S with CELL4–CELL15 shorted to the CELL3 potential and 13S with CELL13–CELL15 shorted to the CELL12 potential. BAT, PACK and the fixed CELL1–CELL16 interface are not rearranged when the count changes.

## Communications

The software ports `i2cTxn` and `i2cResp` implement a transaction-level J17 controller/peripheral interface. A request is a 40-byte vector: sequence number (uint32 little-endian), 7-bit device address, read flag, register address, byte count and up to 32 write bytes. The response is a 40-byte vector: echoed sequence number, status (`0` ACK / `1` NACK), byte count, and up to 32 read bytes. The default configurable device address is `0x08`. Transactions use the existing direct-command, data-memory, and implemented subcommand register logic; a supported subset is exercised by the controller tests. The legacy `hostWr`/`snapshot` interface remains available.

This is not an electrical SDA/SCL implementation. No open-drain pins, pull-ups, START/STOP edges, bit timing or line arbitration are modeled, and the 10 ms emulator cadence is not used as an I2C bit clock. The transaction request is processed at the emulator sample boundary. J22 SPI/HDQ has documented board pins but no functional interface in this model. No communications connector pin is represented as an electrical conserving port.

The signal ports `hostWr`, `tempPinsK`, `tDieK`, `snapshot`, `chgFet` and `dsgFet` are simulation/diagnostic interfaces, not EVM header pins. `i2cTxn` and `i2cResp` are the software transaction-level I2C request/response abstraction for J17 EXT_I2C. The PCB icon prefixes these with `SIM` or labels them as software transactions to distinguish them from the physical board connectors. J17's physical SDA/SCL pins and J22's SPI/HDQ pins are not implemented as electrical communication ports.

The visible conserving-port topology is fixed at 20 terminals for every series-count setting: CELL1–CELL16, BAT+, BAT−, PACK+ and PACK−. MATLAB inspection confirmed that 4S, 13S and 16S all expose the same list. The mask selects VCell Mode; for reduced stacks the unused cell terminals must be explicitly connected to adjacent used nodes as in the provided harnesses. This avoids silently changing or rebinding existing wires. Simscape Connection Port supports left/right sides in this block, so PACK remains on the right side even though its physical board connector is top-centre in the photograph.

TI EVM schematic pin assignments used in the schematic-view annotation:

| Connector | Pin | Board signal |
|---|---:|---|
| J17 EXT_I2C | 1 | SDA |
| J17 EXT_I2C | 2 | SCL |
| J17 EXT_I2C | 3 | Unlabeled in the schematic |
| J17 EXT_I2C | 4 | PGND |
| J22 EXT_SPI / HDQ | 1 | PACK− |
| J22 EXT_SPI / HDQ | 2 | SPI_CS |
| J22 EXT_SPI / HDQ | 3 | SPI_CLK |
| J22 EXT_SPI / HDQ | 4 | SPI_MISO |
| J22 EXT_SPI / HDQ | 5 | SPI_MOSI / HDQ |

The J17/J22 annotations describe the physical board connectors; the `i2cTxn`/`i2cResp` Simulink signal pair is a software transaction interface and is not electrically connected to those pins. Pin assignments follow the [TI BQ76952EVM User's Guide](https://www.ti.com/lit/ug/sluuc33a/sluuc33a.pdf) and the J17 signal numbering is cross-checked against TI's [MSPM0 I2C connection guide](https://www.ti.com/lit/an/slaaeb3a/slaaeb3a.pdf). Reduced-cell rules follow the [BQ76952 datasheet](https://www.ti.com/lit/ds/symlink/bq76952.pdf).

## Mask and views

The mask groups cell configuration, current sensing, measurement/temperature, protection, FET/shunt and communications settings. `Display Mode` selects PCB View or Schematic View without changing the model interface or emulator settings. The PCB image uses a cropped raster rendered over white; `prepare_BQ76952EVM_image.m` starts from the retained original image, removes only border-connected near-black background, and preserves enclosed PCB components. The image is scaled to the source aspect ratio and sits between the port-label gutters.

Final rendered exports are [PCB View](test/BQ76952EVM_PCB_View.png) and [Schematic View](test/BQ76952EVM_Schematic_View.png). The schematic separates physical conserving terminals from the software signal ports and marks J22 SPI/HDQ as unimplemented.

## Build and tests

Run `build_BQ76952EVM.m` to build the library and instance-aware S-function. Independent harness builders and tests are in `test/`.

- 4S nominal: 3.700 V/cell, 14.800 V stack, −2.960 A.
- 13S nominal: 3.700 V sampled cells, 48.100 V stack, −2.400 A.
- 16S nominal: 3.700 V sampled cells, 59.200 V stack, −1.970 A.
- Cell-count settings 3S, 4S, 13S and 16S: expected VCell Mode masks and per-instance settings passed; conserving-port count remains fixed by design.
- I2C transaction engine and S-function port: device ID, cell/current reads, DA_CONFIG write/readback, ALL_FETS_OFF, wrong-address NACK, and independent instance state passed.
- PCB/Schematic toggling: four transitions each in 4S and 13S harnesses preserved port names/counts, S-function configuration and nominal outputs.
- Unchanged Solaris `checkAfe.m` and `checkAfeMeasurements.m`: passed. The measurement script prints its existing undefined `Wh` bus-unit warning.

See `test/VIEW_TEST_REPORT.md` and `test/TEST_REPORT.md` for recorded results. The component is behavioral: no transistor-level reproduction, cell balancing, secondary protector/fuse, precharge, ADC slot scheduler, electrical I2C/SPI/HDQ PHY, or exact PCB parasitics are modeled. The 10 ms measurement/emulator cadence is retained.
