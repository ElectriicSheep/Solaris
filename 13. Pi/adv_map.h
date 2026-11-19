#ifndef ADV_MAP_H
#define ADV_MAP_H
#include "solaris_can.h"
/* ADV_GroupSoc: sets mux and its 4 group SOCs (percent); not available -> raw all-ones */
void map_group_soc(struct solaris_can_adv_group_soc_t *m, int mux, const double pct[16], const int avail[16]);
#endif
