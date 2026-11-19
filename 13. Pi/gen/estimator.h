/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 *
 * File: estimator.h
 *
 * Code generated for Simulink model 'estimator'.
 *
 * Model version                  : 1.2
 * Simulink Coder version         : 25.2 (R2025b) 28-Jul-2025
 * C/C++ source code generated on : Thu Nov 19 17:50:00 2026
 *
 * Target selection: ert.tlc
 * Embedded hardware selection: ARM Compatible->ARM 64-bit (LP64)
 * Code generation objectives: Unspecified
 * Validation result: Not run
 */

#ifndef estimator_h_
#define estimator_h_
#ifndef estimator_COMMON_INCLUDES_
#define estimator_COMMON_INCLUDES_
#include "rtwtypes.h"
#endif                                 /* estimator_COMMON_INCLUDES_ */

#include "estimator_types.h"

/* Macros for accessing real-time model data structure */
#ifndef rtmGetErrorStatus
#define rtmGetErrorStatus(rtm)         ((rtm)->errorStatus)
#endif

#ifndef rtmSetErrorStatus
#define rtmSetErrorStatus(rtm, val)    ((rtm)->errorStatus = (val))
#endif

/* Block signals (default storage) */
typedef struct {
  real_T rtcNow;
  real_T diffMax;                      /* '<S3>/diffMax' */
  real_T rest;                         /* '<S3>/rest' */
  uint8_T method;                      /* '<S3>/method' */
  uint8_T diffIdx;                     /* '<S3>/diffIdx' */
  boolean_T mismatch;                  /* '<S3>/mismatch' */
  boolean_T recal;                     /* '<S7>/recalAnd' */
} B_estimator_T;

/* Block states (default storage) for system '<Root>' */
typedef struct {
  real_T socLast_DSTATE[13];           /* '<S4>/socLast' */
  real_T timerLast_DSTATE;             /* '<S7>/timerLast' */
  boolean_T doneLast_DSTATE;           /* '<S5>/doneLast' */
  boolean_T everLast_DSTATE;           /* '<S4>/everLast' */
  boolean_T forceLast_DSTATE;          /* '<S5>/forceLast' */
} DW_estimator_T;

/* Invariant block signals (default storage) */
typedef struct {
  const real_T sohQ[13];               /* '<S1>/sohQ' */
  const real_T qAct[13];               /* '<S4>/qAct' */
  const real_T sohPack;                /* '<S1>/sohPackMin' */
  const real_T sohR[13];               /* '<S1>/sohR' */
} ConstB_estimator_T;

/* Constant parameters (default storage) */
typedef struct {
  /* Expression: (1:13)'
   * Referenced by: '<S8>/groupNo'
   */
  real_T groupNo_Value[13];

  /* Expression: BMS_ocvSoc
   * Referenced by: '<S6>/ocvTable'
   */
  real_T ocvTable_tableData[11];

  /* Expression: BMS_ocvV
   * Referenced by: '<S6>/ocvTable'
   */
  real_T ocvTable_bp01Data[11];
} ConstP_estimator_T;

/* External inputs (root inport signals with default storage) */
typedef struct {
  real_T vGroup[13];                   /* '<Root>/vGroup' */
  boolean_T vValid[13];                /* '<Root>/vValid' */
  real_T iPack;                        /* '<Root>/iPack' */
  boolean_T iValid;                    /* '<Root>/iValid' */
  real_T tSensor[7];                   /* '<Root>/tSensor' */
  boolean_T tValid[7];                 /* '<Root>/tValid' */
  real_T rtcNow;                       /* '<Root>/rtcNow' */
  real_T nvmSoc[13];                   /* '<Root>/nvmSoc' */
  real_T nvmTSave;                     /* '<Root>/nvmTSave' */
  boolean_T nvmValid;                  /* '<Root>/nvmValid' */
  boolean_T awake;                     /* '<Root>/awake' */
  boolean_T boot;                      /* '<Root>/boot' */
  boolean_T reset;                     /* '<Root>/reset' */
} ExtU_estimator_T;

/* External outputs (root outports fed by signals with default storage) */
typedef struct {
  BMS_seData seData;                   /* '<Root>/seData' */
} ExtY_estimator_T;

/* Real-time Model Data Structure */
struct tag_RTM_estimator_T {
  const char_T * volatile errorStatus;
};

/* Block signals (default storage) */
extern B_estimator_T estimator_B;

/* Block states (default storage) */
extern DW_estimator_T estimator_DW;

/* External inputs (root inport signals with default storage) */
extern ExtU_estimator_T estimator_U;

/* External outputs (root outports fed by signals with default storage) */
extern ExtY_estimator_T estimator_Y;
extern const ConstB_estimator_T estimator_ConstB;/* constant block i/o */

/* Constant parameters (default storage) */
extern const ConstP_estimator_T estimator_ConstP;

/* Model entry point functions */
extern void estimator_initialize(void);
extern void estimator_step(void);
extern void estimator_terminate(void);

/* Real-time Model object */
extern RT_MODEL_estimator_T *const estimator_M;

/*-
 * These blocks were eliminated from the model due to optimizations:
 *
 * Block '<S2>/hwBus_powerBtn' : Unused code path elimination
 * Block '<S2>/hwBus_resetBtn' : Unused code path elimination
 * Block '<S2>/noBtn' : Unused code path elimination
 * Block '<S2>/noFb' : Unused code path elimination
 * Block '<S2>/noIdx' : Unused code path elimination
 * Block '<S2>/pwrBus_powerOff' : Unused code path elimination
 * Block '<S2>/pwrBus_powerOn' : Unused code path elimination
 * Block '<S2>/tMax' : Unused code path elimination
 * Block '<S2>/tMin' : Unused code path elimination
 * Block '<S2>/vMax' : Unused code path elimination
 * Block '<S2>/vMin' : Unused code path elimination
 * Block '<S2>/validBus_contactorFb' : Unused code path elimination
 * Block '<S2>/validBus_tMax' : Unused code path elimination
 * Block '<S2>/validBus_tMaxIdx' : Unused code path elimination
 * Block '<S2>/validBus_tMin' : Unused code path elimination
 * Block '<S2>/validBus_tMinIdx' : Unused code path elimination
 * Block '<S2>/validBus_tSensor' : Unused code path elimination
 * Block '<S2>/validBus_vMax' : Unused code path elimination
 * Block '<S2>/validBus_vMaxIdx' : Unused code path elimination
 * Block '<S2>/validBus_vMin' : Unused code path elimination
 * Block '<S2>/validBus_vMinIdx' : Unused code path elimination
 * Block '<S1>/recordOk' : Eliminate redundant signal conversion block
 * Block '<S1>/saveTime' : Eliminate redundant signal conversion block
 * Block '<S2>/hwBus_rtcNow' : Eliminate redundant signal conversion block
 * Block '<S2>/nvmBus_socGroup' : Eliminate redundant signal conversion block
 * Block '<S2>/nvmBus_tSave' : Eliminate redundant signal conversion block
 * Block '<S2>/nvmBus_valid' : Eliminate redundant signal conversion block
 * Block '<S2>/pwrBus_awake' : Eliminate redundant signal conversion block
 * Block '<S2>/pwrBus_boot' : Eliminate redundant signal conversion block
 * Block '<S2>/pwrBus_reset' : Eliminate redundant signal conversion block
 * Block '<S2>/validBus_allValid' : Eliminate redundant signal conversion block
 * Block '<S2>/validBus_iPack' : Eliminate redundant signal conversion block
 * Block '<S2>/validBus_measReady' : Eliminate redundant signal conversion block
 * Block '<S2>/validBus_vGroup' : Eliminate redundant signal conversion block
 */

/*-
 * The generated code includes comments that allow you to trace directly
 * back to the appropriate location in the model.  The basic format
 * is <system>/block_name, where system is the system number (uniquely
 * assigned by Simulink) and block_name is the name of the block.
 *
 * Use the MATLAB hilite_system command to trace the generated code back
 * to the model.  For example,
 *
 * hilite_system('<S3>')    - opens system 3
 * hilite_system('<S3>/Kp') - opens and selects block Kp which resides in S3
 *
 * Here is the system hierarchy for this model
 *
 * '<Root>' : 'estimator'
 * '<S1>'   : 'estimator/SE'
 * '<S2>'   : 'estimator/adapt'
 * '<S3>'   : 'estimator/SE/captureInit'
 * '<S4>'   : 'estimator/SE/coulombCounter'
 * '<S5>'   : 'estimator/SE/initControl'
 * '<S6>'   : 'estimator/SE/ocvToSoc'
 * '<S7>'   : 'estimator/SE/restRecal'
 * '<S8>'   : 'estimator/SE/startupSoc'
 * '<S9>'   : 'estimator/SE/restRecal/lowI'
 * '<S10>'  : 'estimator/SE/startupSoc/beyondTol'
 * '<S11>'  : 'estimator/SE/startupSoc/clockBack'
 * '<S12>'  : 'estimator/SE/startupSoc/longRest'
 */
#endif                                 /* estimator_h_ */

/*
 * File trailer for generated code.
 *
 * [EOF]
 */
