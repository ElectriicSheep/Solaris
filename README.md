# Solaris

Battery management test platform for the UTAS AUV battery (one tube: 13S7P Samsung INR18650-35E),
built around a **TI BQ76952** battery monitor / protector and a **Raspberry Pi 4B** advisory layer.

```
 PC (Simulink) or OPAL-RT OP5033                                Raspberry Pi 4B
 LOAD -> PLANT (Simscape 13S7P) -> AFE: BQ76952 emulator  <== I2C (real) / UDP (SITL) ==>  solaris_host
                         ^            protections, FETs                                     estimators
                         +-- FETs ----+                                                     ADV_* CAN --> vehicle
```

* **Protection: the BQ76952.** It measures, protects (cell over/under-voltage, over-current,
  short circuit, temperature) and switches the CHG / DSG FETs on its own. The pack runs without the Pi.
* **Advisory layer: the Pi.** It reads the chip (Libre Solar host driver, unmodified), runs the
  estimator set generated from Simulink (SOC now; SOH, SOP, SOE planned) and sends advisory CAN
  messages to the higher-level controller. Later: cell balancing control.
* **SITL:** in Simulink the chip is an emulator (C, `12. AFE`); the Pi's program is the same for the
  emulator and the real BQ76952EVM, only the transport changes (`--sitl` / `--i2c`).

| Folder | Content |
|---|---|
| 01. LoadProfiles | Load profiles (CONST, PULSE, CYCLE A from the ULC prototype logs) |
| 02. Platform | `bmsTestPlatform.slx`: SM_bms = LOAD, PLANT, AFE, PILINK, ARB, EVAL |
| 05. Interfaces | Dictionaries and their definition scripts (`defineInterfaces.m`, `defineParameters.m`) |
| 06. Battery Models | Simscape battery (13S7P) and its parameters |
| 07. Tests | `checkAfe` (protections in the platform), `checkCanCodec`, `checkCanRx`, `checkPiLink` (live, needs the Pi), plant checks |
| 09. RT-LAB | `prepareRTModel.m` for the OP5033 copy |
| 10. CAN | `solarisCan.dbc`: advisory messages Pi -> vehicle; MATLAB codec |
| 11. Estimator | `estimator.slx` (Simulink blocks), `defineEstimator.m`, `exportPiCode.m` |
| 12. AFE | BQ76952 emulator (C), unit test, stand-alone SITL tool |
| 13. Pi | `solaris_host` for the Raspberry Pi (build with `make` on the Pi) |
| 14. Adaptive ECM | Offline proof of concept: adaptive ECM (R0, R1, tau1 tables over SOC x T, capacity) from deliberately wrong starting values; `EcmConvergenceApp` shows convergence live |

Set-up on a new machine: open `modularBMS.prj`, run `defineInterfaces` and `defineParameters`
(custom-code paths are absolute), `defineEstimator`. A C compiler is needed (MinGW-w64 on Windows).

The previous design (foxBMS-style BMS in Simulink, CAN to the Pi) is on branch
`archive/foxbms-pi`, tag `foxbms-pi-v1`.

Third-party: Libre Solar `bms-firmware` (Apache-2.0), see `13. Pi/libresolar/NOTICE.md`.
