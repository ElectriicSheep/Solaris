/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 *
 * File: estimator_data.c
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

#include "estimator.h"

/* Invariant block signals (default storage) */
const ConstB_estimator_T estimator_ConstB = {
  { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },/* '<S1>/sohQ' */

  { 23.45, 23.45, 23.45, 23.45, 23.45, 23.45, 23.45, 23.45, 23.45, 23.45, 23.45,
    23.45, 23.45 },                    /* '<S4>/qAct' */
  1.0,                                 /* '<S1>/sohPackMin' */

  { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 }/* '<S1>/sohR' */
};

/* Constant parameters (default storage) */
const ConstP_estimator_T estimator_ConstP = {
  /* Expression: (1:13)'
   * Referenced by: '<S8>/groupNo'
   */
  { 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0 },

  /* Expression: BMS_ocvSoc
   * Referenced by: '<S6>/ocvTable'
   */
  { 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 },

  /* Expression: BMS_ocvV
   * Referenced by: '<S6>/ocvTable'
   */
  { 2.65, 3.38, 3.51, 3.59, 3.655, 3.725, 3.795, 3.875, 3.97, 4.075, 4.2 }
};

/*
 * File trailer for generated code.
 *
 * [EOF]
 */
