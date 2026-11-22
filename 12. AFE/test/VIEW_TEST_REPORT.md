# BQ76952EVM rendered-view report

Both images below were exported from the actual Simulink block using `export_BQ76952EVM_views.m` after building the library, then visually inspected.

- [PCB View](BQ76952EVM_PCB_View.png)
- [Schematic View](BQ76952EVM_Schematic_View.png)

## PCB image handling

The renderer uses a **cropped image over a white block background**, not a true transparent PNG. The original source image is retained as `../assets/bq76952evm_top.png`. The reproducible preparation script removes only near-black pixels connected to the image perimeter, preserves enclosed dark PCB details, and crops to the detected board-content bounding box with a small edge allowance. The crop is 1413 × 1075 pixels (aspect ratio 1.3144); mask extents follow that aspect ratio and do not independently stretch width and height.

The final export shows the board centered in the landscape block with the black rectangular surround removed. Its connector details remain visible. Port names are placed in side gutters, and the earlier bottom software-signal banner is absent. The schematic export remains a separate programmatically drawn icon under the same Display Mode toggle.

## Interface checks

The built block reports these 20 conserving ports: left side `CELL1`–`CELL16`, `BAT+`, `BAT-`; right side `PACK+`, `PACK-`. It also exposes 4 Simulink inputs and 4 outputs. The PCB view uses only board terminal names for conserving ports. `CELLn` maps internally to IC `VCn`, while `BAT-` is the `VC0` reference; that distinction is explained inside the Schematic View and in the mask documentation.

MATLAB port-side inspection for 4S, 13S and 16S confirmed the same visible 20-port list in all three cases. The series-cell mask setting changes the emulator VCell Mode but **does not dynamically remove conserving ports**. The independent 4S and 13S harnesses explicitly tie unused cell inputs to adjacent cell nodes. Changing the count does not reorder or reassign any physical terminal. Dynamic port removal is not implemented.

Display-mode testing toggled the setting repeatedly and compared port names/counts, configuration and nominal outputs. An attempt to move PACK conserving ports to the top edge was rejected by the Simscape Connection Port block's supported `Side` options (left/right only), so PACK stays on the right edge even though its EVM screw connector is top-centre in the photo. The PCB silkscreen identifies the real connector location.

The image contains physical EVM terminal labels `CELL1`–`CELL16`, `BAT+/-`, `PACK+/-`, `J17 EXT_I2C` and `J22 EXT_SPI/HDQ`. The software ports are explicitly identified in the PCB labels or schematic legend: `hostWr`, `tempPinsK`, `tDieK`, `snapshot`, `chgFet`, and `dsgFet` are simulation/diagnostic signals; `i2cTxn`/`i2cResp` are a transaction-level software abstraction of J17. There are no electrical SDA/SCL pins, and J22 SPI/HDQ has no implemented transaction interface.

The Schematic View identifies board terminal names separately from IC VC channels and distinguishes `i2cTxn`/`i2cResp` and diagnostic signals from physical connector pins. J17 and J22 labels describe the documented EVM headers; only the transaction-level J17 software interface is functional in this model. See `README_BQ76952EVM.md` and `TEST_REPORT.md` for test scope and remaining limitations.
