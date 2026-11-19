/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 *
 * File: SE_Step.c
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

#include "SE_Step.h"
#include <math.h>
#include <string.h>
#include "estimator.h"
#include "rtwtypes.h"
#include "estimator_private.h"

/* Output and update for atomic system: '<Root>/SE' */
void SE_Step(void)
{
  real_T rtb_idxIfMax[13];
  real_T rtb_socOcv[13];
  real_T rtb_restTime;
  real_T rtb_socOcv_0;
  real_T rtb_toAhPerS;
  int32_T i;
  boolean_T rtb_Compare_g;
  boolean_T rtb_Compare_k;
  boolean_T rtb_count;
  boolean_T rtb_everLast;
  boolean_T rtb_initNow;
  boolean_T rtb_useOcv;
  boolean_T rtb_useOcv_tmp;

  /* Logic: '<S5>/notBoot' incorporates:
   *  Inport: '<Root>/boot'
   *
   * Block description for '<Root>/boot':
   *  One step: first measurement set after the BMS came on
   */
  rtb_Compare_k = !estimator_U.boot;

  /* Logic: '<S5>/initNowAnd' incorporates:
   *  Inport: '<Root>/awake'
   *  Logic: '<S5>/notDone'
   *  UnitDelay: '<S5>/doneLast'
   *
   * Block description for '<Root>/awake':
   *  BMS frames arriving (BMS on)
   */
  rtb_initNow = (estimator_U.awake && estimator_B.recal &&
                 (!estimator_DW.doneLast_DSTATE));

  /* Logic: '<S5>/doneAnd' incorporates:
   *  Logic: '<S5>/doneOr'
   *  UnitDelay: '<S5>/doneLast'
   */
  estimator_DW.doneLast_DSTATE = ((estimator_DW.doneLast_DSTATE || rtb_initNow) &&
    rtb_Compare_k);

  /* Logic: '<S1>/countWhen' incorporates:
   *  Inport: '<Root>/awake'
   *  UnitDelay: '<S5>/doneLast'
   *
   * Block description for '<Root>/awake':
   *  BMS frames arriving (BMS on)
   */
  rtb_count = (estimator_U.awake && estimator_DW.doneLast_DSTATE);

  /* Logic: '<S7>/quiet' incorporates:
   *  Abs: '<S7>/absI'
   *  Constant: '<S9>/Constant'
   *  Inport: '<Root>/iPack'
   *  RelationalOperator: '<S9>/Compare'
   *
   * Block description for '<Root>/iPack':
   *  Pack current from f_PackValuesP0 (A, discharge positive)
   */
  rtb_everLast = ((fabs(estimator_U.iPack) < 0.2) && rtb_count &&
                  estimator_B.recal);

  /* Switch: '<S7>/timerSel' */
  if (rtb_everLast) {
    /* Switch: '<S7>/timerSel' incorporates:
     *  Constant: '<S7>/step'
     *  Constant: '<S7>/tLimit'
     *  MinMax: '<S7>/capAtLimit'
     *  Sum: '<S7>/addStep'
     *  UnitDelay: '<S7>/timerLast'
     */
    estimator_DW.timerLast_DSTATE = fmin(estimator_DW.timerLast_DSTATE + 0.1,
      600.0);
  } else {
    /* Switch: '<S7>/timerSel' incorporates:
     *  Constant: '<S7>/zeroT'
     */
    estimator_DW.timerLast_DSTATE = 0.0;
  }

  /* End of Switch: '<S7>/timerSel' */

  /* Logic: '<S7>/recalAnd' incorporates:
   *  Constant: '<S7>/tLimit'
   *  RelationalOperator: '<S7>/elapsed'
   */
  estimator_B.recal = (rtb_everLast && (estimator_DW.timerLast_DSTATE >= 600.0));

  /* Logic: '<S5>/forceOr' incorporates:
   *  Inport: '<Root>/reset'
   *  Logic: '<S5>/keepForce'
   *  UnitDelay: '<S5>/forceLast'
   *
   * Block description for '<Root>/reset':
   *  One step: SOC to be re-initialised from OCV
   */
  estimator_DW.forceLast_DSTATE = (estimator_U.reset ||
    (estimator_DW.forceLast_DSTATE && rtb_Compare_k));

  /* Logic: '<S8>/noRecord' incorporates:
   *  Inport: '<Root>/nvmValid'
   *
   * Block description for '<Root>/nvmValid':
   *  SOC record file present and intact
   */
  rtb_everLast = !estimator_U.nvmValid;

  /* Sum: '<S8>/restTime' incorporates:
   *  Inport: '<Root>/nvmTSave'
   *  Inport: '<Root>/rtcNow'
   *
   * Block description for '<Root>/nvmTSave':
   *  SOC record file: save time (s)
   *
   * Block description for '<Root>/rtcNow':
   *  Pi clock (s, same epoch as nvmTSave)
   */
  rtb_restTime = estimator_U.rtcNow - estimator_U.nvmTSave;

  /* RelationalOperator: '<S11>/Compare' incorporates:
   *  Constant: '<S11>/Constant'
   */
  rtb_Compare_k = (rtb_restTime < 0.0);
  for (i = 0; i < 13; i++) {
    /* Lookup_n-D: '<S6>/ocvTable' incorporates:
     *  Inport: '<Root>/vGroup'
     *
     * Block description for '<Root>/vGroup':
     *  Group voltages from f_CellVoltages (V)
     */
    rtb_socOcv_0 = look1_binlcpw(estimator_U.vGroup[i],
      estimator_ConstP.ocvTable_bp01Data, estimator_ConstP.ocvTable_tableData,
      10U);
    rtb_socOcv[i] = rtb_socOcv_0;

    /* Abs: '<S8>/absDiff' incorporates:
     *  Inport: '<Root>/nvmSoc'
     *  Sum: '<S8>/diff'
     *
     * Block description for '<Root>/nvmSoc':
     *  SOC record file: group SOC
     */
    rtb_idxIfMax[i] = fabs(estimator_U.nvmSoc[i] - rtb_socOcv_0);
  }

  /* MinMax: '<S8>/diffMaxBlk' */
  rtb_socOcv_0 = rtb_idxIfMax[0];
  for (i = 0; i < 12; i++) {
    rtb_socOcv_0 = fmax(rtb_socOcv_0, rtb_idxIfMax[i + 1]);
  }

  /* RelationalOperator: '<S10>/Compare' incorporates:
   *  Constant: '<S10>/Constant'
   *  MinMax: '<S8>/diffMaxBlk'
   */
  rtb_Compare_g = (rtb_socOcv_0 > 0.1);

  /* Logic: '<S8>/useOcv' incorporates:
   *  Constant: '<S12>/Constant'
   *  Logic: '<S8>/noRecordUsed'
   *  RelationalOperator: '<S12>/Compare'
   */
  rtb_useOcv_tmp = (estimator_DW.forceLast_DSTATE || rtb_everLast);
  rtb_useOcv = (rtb_useOcv_tmp || rtb_Compare_k || rtb_Compare_g ||
                (rtb_restTime >= 7200.0));

  /* Switch: '<S4>/resetSel' incorporates:
   *  Logic: '<S4>/notYet'
   *  Logic: '<S4>/resetOr'
   *  Switch: '<S4>/countGate'
   *  UnitDelay: '<S4>/everLast'
   */
  if (rtb_initNow || estimator_B.recal || (!estimator_DW.everLast_DSTATE)) {
    for (i = 0; i < 13; i++) {
      /* Switch: '<S4>/icSel' incorporates:
       *  Inport: '<Root>/nvmValid'
       *  Switch: '<S4>/preInit'
       *  Switch: '<S4>/recalSel'
       *
       * Block description for '<Root>/nvmValid':
       *  SOC record file present and intact
       */
      if (rtb_initNow) {
        /* Switch: '<S8>/socSel' */
        if (rtb_useOcv) {
          /* UnitDelay: '<S4>/socLast' */
          estimator_DW.socLast_DSTATE[i] = rtb_socOcv[i];
        } else {
          /* UnitDelay: '<S4>/socLast' incorporates:
           *  Inport: '<Root>/nvmSoc'
           *
           * Block description for '<Root>/nvmSoc':
           *  SOC record file: group SOC
           */
          estimator_DW.socLast_DSTATE[i] = estimator_U.nvmSoc[i];
        }

        /* End of Switch: '<S8>/socSel' */
      } else if (estimator_B.recal) {
        /* UnitDelay: '<S4>/socLast' incorporates:
         *  Switch: '<S4>/recalSel'
         */
        estimator_DW.socLast_DSTATE[i] = rtb_socOcv[i];
      } else if (estimator_U.nvmValid) {
        /* Switch: '<S4>/preInit' incorporates:
         *  Inport: '<Root>/nvmSoc'
         *  Switch: '<S4>/recalSel'
         *  UnitDelay: '<S4>/socLast'
         *
         * Block description for '<Root>/nvmSoc':
         *  SOC record file: group SOC
         */
        estimator_DW.socLast_DSTATE[i] = estimator_U.nvmSoc[i];
      } else {
        /* UnitDelay: '<S4>/socLast' incorporates:
         *  Switch: '<S4>/recalSel'
         */
        estimator_DW.socLast_DSTATE[i] = 0.0;
      }

      /* End of Switch: '<S4>/icSel' */
    }
  } else {
    if (rtb_count) {
      /* Gain: '<S4>/toAhPerS' incorporates:
       *  Inport: '<Root>/iPack'
       *  Switch: '<S4>/countGate'
       *
       * Block description for '<Root>/iPack':
       *  Pack current from f_PackValuesP0 (A, discharge positive)
       */
      rtb_toAhPerS = -0.00027777777777777778 * estimator_U.iPack;

      /* Switch: '<S4>/countGate' incorporates:
       *  Product: '<S4>/socRate'
       */
      for (i = 0; i < 13; i++) {
        rtb_socOcv[i] = rtb_toAhPerS / estimator_ConstB.qAct[i];
      }
    } else {
      /* Switch: '<S4>/countGate' */
      memset(&rtb_socOcv[0], 0, 13U * sizeof(real_T));
    }

    for (i = 0; i < 13; i++) {
      /* Saturate: '<S4>/sat01' incorporates:
       *  Gain: '<S4>/perStep'
       *  Sum: '<S4>/addStep'
       *  UnitDelay: '<S4>/socLast'
       */
      rtb_toAhPerS = 0.1 * rtb_socOcv[i] + estimator_DW.socLast_DSTATE[i];
      if (rtb_toAhPerS > 1.0) {
        estimator_DW.socLast_DSTATE[i] = 1.0;
      } else if (rtb_toAhPerS < 0.0) {
        estimator_DW.socLast_DSTATE[i] = 0.0;
      } else {
        estimator_DW.socLast_DSTATE[i] = rtb_toAhPerS;
      }

      /* End of Saturate: '<S4>/sat01' */
    }
  }

  /* End of Switch: '<S4>/resetSel' */

  /* Switch: '<S8>/idxIfMax' incorporates:
   *  Constant: '<S8>/groupNo'
   *  Constant: '<S8>/noGroup'
   *  MinMax: '<S8>/diffMaxBlk'
   *  RelationalOperator: '<S8>/isMax'
   */
  for (i = 0; i < 13; i++) {
    if (rtb_idxIfMax[i] == rtb_socOcv_0) {
      rtb_idxIfMax[i] = estimator_ConstP.groupNo_Value[i];
    } else {
      rtb_idxIfMax[i] = 99.0;
    }
  }

  /* End of Switch: '<S8>/idxIfMax' */

  /* MinMax: '<S8>/firstMax' */
  rtb_toAhPerS = rtb_idxIfMax[0];
  for (i = 0; i < 12; i++) {
    rtb_toAhPerS = fmin(rtb_toAhPerS, rtb_idxIfMax[i + 1]);
  }

  /* Outputs for Enabled SubSystem: '<S1>/captureInit' incorporates:
   *  EnablePort: '<S3>/initNow'
   */
  if (rtb_initNow) {
    /* Switch: '<S8>/methodSel' */
    if (rtb_useOcv) {
      /* SignalConversion generated from: '<S3>/method' incorporates:
       *  Constant: '<S8>/mOcv'
       */
      estimator_B.method = 3U;
    } else {
      /* SignalConversion generated from: '<S3>/method' incorporates:
       *  Constant: '<S8>/mStored'
       */
      estimator_B.method = 1U;
    }

    /* End of Switch: '<S8>/methodSel' */

    /* SignalConversion generated from: '<S3>/mismatch' incorporates:
     *  Logic: '<S8>/mismatchAnd'
     *  Logic: '<S8>/notForced'
     */
    estimator_B.mismatch = (rtb_Compare_g && ((!estimator_DW.forceLast_DSTATE) &&
      (!rtb_everLast) && (!rtb_Compare_k)));

    /* SignalConversion generated from: '<S3>/diffMax' incorporates:
     *  MinMax: '<S8>/diffMaxBlk'
     */
    estimator_B.diffMax = rtb_socOcv_0;

    /* DataTypeConversion: '<S8>/toUint8' incorporates:
     *  MinMax: '<S8>/firstMax'
     */
    if (rtb_toAhPerS < 256.0) {
      if (rtb_toAhPerS >= 0.0) {
        /* SignalConversion generated from: '<S3>/diffIdx' */
        estimator_B.diffIdx = (uint8_T)rtb_toAhPerS;
      } else {
        /* SignalConversion generated from: '<S3>/diffIdx' */
        estimator_B.diffIdx = 0U;
      }
    } else {
      /* SignalConversion generated from: '<S3>/diffIdx' */
      estimator_B.diffIdx = MAX_uint8_T;
    }

    /* End of DataTypeConversion: '<S8>/toUint8' */

    /* Switch: '<S8>/restOut' */
    if (rtb_useOcv_tmp) {
      /* SignalConversion generated from: '<S3>/rest' incorporates:
       *  Constant: '<S8>/minusOne'
       */
      estimator_B.rest = -1.0;
    } else {
      /* SignalConversion generated from: '<S3>/rest' */
      estimator_B.rest = rtb_restTime;
    }

    /* End of Switch: '<S8>/restOut' */
  }

  /* End of Outputs for SubSystem: '<S1>/captureInit' */

  /* Switch: '<S1>/methodOut' incorporates:
   *  Constant: '<S1>/notYet'
   *  UnitDelay: '<S5>/doneLast'
   */
  if (estimator_DW.doneLast_DSTATE) {
    estimator_Y.seData.socInitMethod = estimator_B.method;
  } else {
    estimator_Y.seData.socInitMethod = 0U;
  }

  /* End of Switch: '<S1>/methodOut' */

  /* Logic: '<S1>/mismatchOut' incorporates:
   *  UnitDelay: '<S5>/doneLast'
   */
  estimator_Y.seData.socInitMismatch = (estimator_B.mismatch &&
    estimator_DW.doneLast_DSTATE);

  /* MinMax: '<S1>/socPackMin' */
  rtb_toAhPerS = estimator_DW.socLast_DSTATE[0];
  for (i = 0; i < 12; i++) {
    rtb_toAhPerS = fmin(rtb_toAhPerS, estimator_DW.socLast_DSTATE[i + 1]);
  }

  estimator_Y.seData.socPack = rtb_toAhPerS;

  /* End of MinMax: '<S1>/socPackMin' */

  /* SignalConversion generated from: '<S1>/saveTime' incorporates:
   *  Inport: '<Root>/rtcNow'
   *
   * Block description for '<Root>/rtcNow':
   *  Pi clock (s, same epoch as nvmTSave)
   */
  estimator_B.rtcNow = estimator_U.rtcNow;

  /* Update for UnitDelay: '<S4>/everLast' incorporates:
   *  Logic: '<S4>/everOr'
   */
  estimator_DW.everLast_DSTATE = (estimator_DW.everLast_DSTATE || rtb_initNow);
}

/*
 * File trailer for generated code.
 *
 * [EOF]
 */
