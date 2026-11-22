#define S_FUNCTION_NAME bq76952evmsfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include "bq76952_emul.h"

enum { CFG_N = 42, INPUT_N = 110, OUTPUT_N = 186 };

static BqeConfig config_from_param(const mxArray *p)
{
    const double *v = mxGetPr(p);
    BqeConfig c;
    c.usedCells=(uint16_t)v[1]; c.shuntMicroOhms=(uint32_t)v[2]; c.daConfig=(uint8_t)v[3];
    c.i2cAddress=(uint8_t)v[41];
    c.protEnabledA=(uint8_t)v[4]; c.protEnabledB=(uint8_t)v[5]; c.mfgStatusInit=(uint16_t)v[6];
    c.covThreshold=(uint8_t)v[7]; c.covHyst=(uint8_t)v[8]; c.covDelay=(uint16_t)v[9];
    c.cuvThreshold=(uint8_t)v[10]; c.cuvHyst=(uint8_t)v[11]; c.cuvDelay=(uint16_t)v[12];
    c.occThreshold=(uint8_t)v[13]; c.occDelay=(uint8_t)v[14]; c.occRecoveryMilliAmps=(int16_t)v[15];
    c.ocd1Threshold=(uint8_t)v[16]; c.ocd1Delay=(uint8_t)v[17]; c.ocdRecoveryMilliAmps=(uint16_t)v[18];
    c.scdThreshold=(uint8_t)v[19]; c.scdDelay=(uint8_t)v[20]; c.scdRecoverySeconds=(uint8_t)v[21];
    c.otcThreshold=(int8_t)v[22]; c.otcRecovery=(int8_t)v[23]; c.otdThreshold=(int8_t)v[24]; c.otdRecovery=(int8_t)v[25];
    c.utcThreshold=(int8_t)v[26]; c.utcRecovery=(int8_t)v[27]; c.utdThreshold=(int8_t)v[28]; c.utdRecovery=(int8_t)v[29];
    c.otUtDelaySeconds=(uint8_t)v[30]; c.recoveryTimeSeconds=(uint8_t)v[31];
    for (int i=0; i<9; ++i) c.pinConfig[i]=(uint8_t)v[32+i];
    return c;
}

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S,1);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    if (mxGetNumberOfElements(ssGetSFcnParam(S,0)) != CFG_N) {
        ssSetErrorStatus(S,"BQ76952EVM configuration vector must contain 42 values."); return;
    }
    ssSetNumContStates(S,0); ssSetNumDiscStates(S,0);
    if (!ssSetNumInputPorts(S,1)) return;
    ssSetInputPortWidth(S,0,INPUT_N); ssSetInputPortDirectFeedThrough(S,0,1);
    ssSetInputPortRequiredContiguous(S,0,1); ssSetInputPortDataType(S,0,SS_DOUBLE);
    if (!ssSetNumOutputPorts(S,1)) return;
    ssSetOutputPortWidth(S,0,OUTPUT_N); ssSetOutputPortDataType(S,0,SS_DOUBLE);
    ssSetNumSampleTimes(S,1); ssSetNumPWork(S,1); ssSetNumRWork(S,0); ssSetNumIWork(S,0);
    ssSetOptions(S,SS_OPTION_EXCEPTION_FREE_CODE);
}

static void mdlInitializeSampleTimes(SimStruct *S)
{
    const double *v=mxGetPr(ssGetSFcnParam(S,0));
    ssSetSampleTime(S,0,v[0]); ssSetOffsetTime(S,0,0.0);
}

#define MDL_START
static void mdlStart(SimStruct *S)
{
    BqeState *state=bqe_create();
    if (!state) { ssSetErrorStatus(S,"BQ76952EVM state allocation failed."); return; }
    BqeConfig c=config_from_param(ssGetSFcnParam(S,0));
    bqe_configure_instance(state,&c);
    ssSetPWorkValue(S,0,state);
}

static void mdlOutputs(SimStruct *S,int_T tid)
{
    (void)tid;
    BqeState *state=(BqeState *)ssGetPWorkValue(S,0);
    const real_T *u=(const real_T *)ssGetInputPortSignal(S,0);
    real_T *y=(real_T *)ssGetOutputPortSignal(S,0);
    double v[16],t[9]; uint8_t wr[BQE_WRITE_BYTES],snap[BQE_SNAP_BYTES],f[2];
    for(int k=0;k<16;++k) v[k]=u[k];
    for(int k=0;k<9;++k) t[k]=u[17+k];
    for(int k=0;k<BQE_WRITE_BYTES;++k) wr[k]=(uint8_t)u[30+k];
    uint8_t txn[BQE_I2C_REQ_BYTES],resp[BQE_I2C_RESP_BYTES];
    for(int k=0;k<BQE_I2C_REQ_BYTES;++k) txn[k]=(uint8_t)u[70+k];
    bqe_i2c_transaction_instance(state,txn,resp);
    const double dt=mxGetPr(ssGetSFcnParam(S,0))[0];
    bqe_step_instance(state,dt,v,u[16],t,u[26],u[27],u[28],u[29],wr,snap,f);
    for(int k=0;k<BQE_SNAP_BYTES;++k) y[k]=(real_T)snap[k];
    y[BQE_SNAP_BYTES]=(real_T)f[0]; y[BQE_SNAP_BYTES+1]=(real_T)f[1];
    for(int k=0;k<BQE_I2C_RESP_BYTES;++k) y[BQE_SNAP_BYTES+2+k]=(real_T)resp[k];
}

#define MDL_TERMINATE
static void mdlTerminate(SimStruct *S)
{
    BqeState *state=(BqeState *)ssGetPWorkValue(S,0);
    if (state) bqe_destroy(state);
}

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
