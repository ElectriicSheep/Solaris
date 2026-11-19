# Third-party code

These files are copied **unmodified** from Libre Solar `bms-firmware`
(https://github.com/LibreSolar/bms-firmware, commit beba3d3, 17 Nov 2026),
`drivers/bms_ic/bq769x2/`, licensed Apache-2.0 (LICENSE in this folder):

- `bq769x2_interface.c`, `bq769x2_interface.h` - BQ769x2 host protocol (direct commands,
  subcommands, data memory with checksum, CONFIG_UPDATE mode), used with real chips
- `bq769x2_priv.h` - driver configuration structure (only the read/write callbacks are used)
- `bq769x2_registers.h` - register and data-memory map

They build on Linux through the stand-ins in `../compat/` (Zephyr device, logging and sleep
APIs). The emulator (`12. AFE/bq76952_emul.c`) adapts the register/subcommand memory handling
of Libre Solar's `bq769x2_emul.c` (same licence).
