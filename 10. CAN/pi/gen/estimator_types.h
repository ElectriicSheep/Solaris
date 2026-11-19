/*
 * Academic License - for use in teaching, academic research, and meeting
 * course requirements at degree granting institutions only.  Not for
 * government, commercial, or other organizational use.
 *
 * File: estimator_types.h
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

#ifndef estimator_types_h_
#define estimator_types_h_
#include "rtwtypes.h"
#ifndef DEFINED_TYPEDEF_FOR_BMS_nvmRecord_
#define DEFINED_TYPEDEF_FOR_BMS_nvmRecord_

/* Record kept in non-volatile memory over a power cycle (contract) */
typedef struct {
  /* Group SOC when the record was saved, 0-1 */
  real_T socGroup[13];

  /* Real-time-clock time of the save */
  real_T tSave;

  /* Record intact (in hardware: checksum correct; false if never written) */
  boolean_T valid;
} BMS_nvmRecord;

#endif

#ifndef DEFINED_TYPEDEF_FOR_BMS_seData_
#define DEFINED_TYPEDEF_FOR_BMS_seData_

/* SE -> output: state estimates */
typedef struct {
  /* Estimated group SOC, 0-1 */
  real_T socGroup[13];

  /* Resistance SOH per group (1 = new) */
  real_T sohR[13];

  /* Capacity SOH per group (1 = new) */
  real_T sohQ[13];

  /* Pack SOC (minimum group SOC) */
  real_T socPack;

  /* Pack SOH (worst group) */
  real_T sohPack;

  /* How SOC was initialised: 0 not yet, 1 stored, 3 OCV (2 not used) */
  uint8_T socInitMethod;

  /* Stored SOC disagreed with OCV beyond BMS_socMismatchTol (OCV used) */
  boolean_T socInitMismatch;

  /* Largest |stored - OCV| SOC difference over the groups at initialisation */
  real_T socInitDiff;

  /* Group (1-13) with that largest difference; 0 = not evaluated */
  uint8_T socInitDiffIdx;

  /* Rest time since the stored record was saved (rtcNow - tSave); -1 = no stored record used (none valid, or reset) */
  real_T socInitRest;

  /* SOC being recalibrated from OCV: pack at rest (|iPack| < BMS_iRest) for BMS_tRestRecal */
  boolean_T socRecal;

  /* Record to save (current SOC, time, valid once SOC is initialised) */
  BMS_nvmRecord nvm;
} BMS_seData;

#endif

/* Forward declaration for rtModel */
typedef struct tag_RTM_estimator_T RT_MODEL_estimator_T;

#endif                                 /* estimator_types_h_ */

/*
 * File trailer for generated code.
 *
 * [EOF]
 */
