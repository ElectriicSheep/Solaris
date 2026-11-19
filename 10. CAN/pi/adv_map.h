#ifndef ADV_MAP_H
#define ADV_MAP_H
#include "bms_can.h"
/* f_CellVoltages (mux 0-3): fills mv[4*mux .. 4*mux+3] (mV) and invalid flags */
void map_cell_voltages(const struct bms_can_f_cell_voltages_t *m, double mv[16], int bad[16]);
/* f_CellTemperatures (mux 0-4): fills degc[6*mux .. 6*mux+5] and invalid flags */
void map_cell_temperatures(const struct bms_can_f_cell_temperatures_t *m, double degc[30], int bad[30]);
/* ADV_GroupSoc: sets mux and its 4 group SOCs (percent); not available -> raw all-ones */
void map_group_soc(struct bms_can_adv_group_soc_t *m, int mux, const double pct[16], const int avail[16]);
#endif
