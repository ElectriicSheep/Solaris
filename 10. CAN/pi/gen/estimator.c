/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 *
 * File: estimator.c
 *
 * Code generated for Simulink model 'estimator'.
 *
 * Model version                  : 1.1
 * Simulink Coder version         : 25.2 (R2025b) 28-Jul-2025
 * C/C++ source code generated on : Thu Nov 19 12:28:30 2026
 *
 * Target selection: ert.tlc
 * Embedded hardware selection: ARM Compatible->ARM 64-bit (LP64)
 * Code generation objectives: Unspecified
 * Validation result: Not run
 */

#include "estimator.h"
#include "SE_Step.h"
#include <string.h>
#include "rtwtypes.h"
#include "estimator_private.h"

/* Block signals (default storage) */
B_estimator_T estimator_B;

/* Block states (default storage) */
DW_estimator_T estimator_DW;

/* External inputs (root inport signals with default storage) */
ExtU_estimator_T estimator_U;

/* External outputs (root outports fed by signals with default storage) */
ExtY_estimator_T estimator_Y;

/* Real-time model */
static RT_MODEL_estimator_T estimator_M_;
RT_MODEL_estimator_T *const estimator_M = &estimator_M_;
real_T look1_binlcpw(real_T u0, const real_T bp0[], const real_T table[],
                     uint32_T maxIndex)
{
  real_T frac;
  real_T yL_0d0;
  uint32_T iLeft;

  /* Column-major Lookup 1-D
     Search method: 'binary'
     Use previous index: 'off'
     Interpolation method: 'Linear point-slope'
     Extrapolation method: 'Clip'
     Use last breakpoint for index at or above upper limit: 'off'
     Remove protection against out-of-range input in generated code: 'off'
   */
  /* Prelookup - Index and Fraction
     Index Search method: 'binary'
     Extrapolation method: 'Clip'
     Use previous index: 'off'
     Use last breakpoint for index at or above upper limit: 'off'
     Remove protection against out-of-range input in generated code: 'off'
   */
  if (u0 <= bp0[0U]) {
    iLeft = 0U;
    frac = 0.0;
  } else if (u0 < bp0[maxIndex]) {
    uint32_T bpIdx;
    uint32_T iRght;

    /* Binary Search */
    bpIdx = maxIndex >> 1U;
    iLeft = 0U;
    iRght = maxIndex;
    while (iRght - iLeft > 1U) {
      if (u0 < bp0[bpIdx]) {
        iRght = bpIdx;
      } else {
        iLeft = bpIdx;
      }

      bpIdx = (iRght + iLeft) >> 1U;
    }

    frac = (u0 - bp0[iLeft]) / (bp0[iLeft + 1U] - bp0[iLeft]);
  } else {
    iLeft = maxIndex - 1U;
    frac = 1.0;
  }

  /* Column-major Interpolation 1-D
     Interpolation method: 'Linear point-slope'
     Use last breakpoint for index at or above upper limit: 'off'
     Overflow mode: 'portable wrapping'
   */
  yL_0d0 = table[iLeft];
  return (table[iLeft + 1U] - yL_0d0) * frac + yL_0d0;
}

/* Model step function */
void estimator_step(void)
{
  int32_T i;
  boolean_T tmp;
  boolean_T tmp_0;

  /* Logic: '<S2>/allV' incorporates:
   *  Inport: '<Root>/vValid'
   *
   * Block description for '<Root>/vValid':
   *  Not f_CellVoltages invalid flag
   */
  tmp = estimator_U.vValid[0];
  for (i = 0; i < 12; i++) {
    tmp = (tmp && estimator_U.vValid[i + 1]);
  }

  /* Logic: '<S2>/allT' incorporates:
   *  Inport: '<Root>/tValid'
   *
   * Block description for '<Root>/tValid':
   *  Not f_CellTemperatures invalid flag
   */
  tmp_0 = estimator_U.tValid[0];
  for (i = 0; i < 25; i++) {
    tmp_0 = (tmp_0 && estimator_U.tValid[i + 1]);
  }

  /* Logic: '<S2>/allValid' incorporates:
   *  Inport: '<Root>/iValid'
   *  Logic: '<S2>/allT'
   *  Logic: '<S2>/allV'
   *
   * Block description for '<Root>/iValid':
   *  Current received and plausible
   */
  estimator_B.recal = (tmp && estimator_U.iValid && tmp_0);

  /* Outputs for Atomic SubSystem: '<Root>/SE' */
  SE_Step();

  /* End of Outputs for SubSystem: '<Root>/SE' */

  /* BusCreator generated from: '<Root>/seData' incorporates:
   *  UnitDelay: '<S4>/socLast'
   *  UnitDelay: '<S5>/doneLast'
   */
  estimator_Y.seData.nvm.tSave = estimator_B.rtcNow;
  estimator_Y.seData.nvm.valid = estimator_DW.doneLast_DSTATE;
  memcpy(&estimator_Y.seData.nvm.socGroup[0], &estimator_DW.socLast_DSTATE[0],
         13U * sizeof(real_T));

  /* BusCreator generated from: '<Root>/seData' incorporates:
   *  Constant: '<S1>/sohQ'
   *  Constant: '<S1>/sohR'
   *  Outport: '<Root>/seData'
   *  UnitDelay: '<S4>/socLast'
   */
  memcpy(&estimator_Y.seData.socGroup[0], &estimator_DW.socLast_DSTATE[0], 13U *
         sizeof(real_T));
  memcpy(&estimator_Y.seData.sohR[0], &estimator_ConstB.sohR[0], 13U * sizeof
         (real_T));
  memcpy(&estimator_Y.seData.sohQ[0], &estimator_ConstB.sohQ[0], 13U * sizeof
         (real_T));
  estimator_Y.seData.sohPack = estimator_ConstB.sohPack;
  estimator_Y.seData.socInitDiff = estimator_B.diffMax;
  estimator_Y.seData.socInitDiffIdx = estimator_B.diffIdx;
  estimator_Y.seData.socInitRest = estimator_B.rest;
  estimator_Y.seData.socRecal = estimator_B.recal;
}

/* Model initialize function */
void estimator_initialize(void)
{
  /* (no initialization code required) */
}

/* Model terminate function */
void estimator_terminate(void)
{
  /* (no terminate code required) */
}

/*
 * File trailer for generated code.
 *
 * [EOF]
 */
