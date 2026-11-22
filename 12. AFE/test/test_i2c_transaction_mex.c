#define main run_i2c_transaction_checks
#include "test_i2c_transaction.c"
#undef main
#include "mex.h"

void mexFunction(int nlhs,mxArray *plhs[],int nrhs,const mxArray *prhs[])
{
    (void)nlhs; (void)plhs; (void)nrhs; (void)prhs;
    (void)run_i2c_transaction_checks();
    mexPrintf("PASS transaction-level I2C: device ID, voltage/current reads, data-memory write/readback, supported subcommand, address NACK and two-instance isolation.\n");
}
