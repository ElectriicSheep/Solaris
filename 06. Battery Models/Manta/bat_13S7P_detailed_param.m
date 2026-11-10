%% Battery parameters

%% ModuleType1
ModuleType1.BatteryCapacityCell = 27; % Battery capacity, A*hr
ModuleType1.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ModuleType1.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ModuleType1.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ModuleType1.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ModuleType1.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ModuleType1.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ModuleType1.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ModuleType1.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ModuleType1.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ModuleType1.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ModuleType1.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ModuleType2
ModuleType2.BatteryCapacityCell = 27; % Battery capacity, A*hr
ModuleType2.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ModuleType2.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ModuleType2.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ModuleType2.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ModuleType2.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ModuleType2.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ModuleType2.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ModuleType2.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ModuleType2.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ModuleType2.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ModuleType2.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ModuleType3
ModuleType3.BatteryCapacityCell = 27; % Battery capacity, A*hr
ModuleType3.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ModuleType3.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ModuleType3.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ModuleType3.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ModuleType3.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ModuleType3.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ModuleType3.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ModuleType3.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ModuleType3.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ModuleType3.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ModuleType3.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ModuleType4
ModuleType4.BatteryCapacityCell = 27; % Battery capacity, A*hr
ModuleType4.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ModuleType4.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ModuleType4.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ModuleType4.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ModuleType4.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ModuleType4.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ModuleType4.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ModuleType4.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ModuleType4.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ModuleType4.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ModuleType4.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ModuleType5
ModuleType5.BatteryCapacityCell = 27; % Battery capacity, A*hr
ModuleType5.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ModuleType5.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ModuleType5.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ModuleType5.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ModuleType5.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ModuleType5.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ModuleType5.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ModuleType5.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ModuleType5.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ModuleType5.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ModuleType5.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ModuleType6
ModuleType6.BatteryCapacityCell = 27; % Battery capacity, A*hr
ModuleType6.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ModuleType6.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ModuleType6.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ModuleType6.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ModuleType6.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ModuleType6.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ModuleType6.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ModuleType6.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ModuleType6.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ModuleType6.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ModuleType6.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ModuleType7
ModuleType7.BatteryCapacityCell = 27; % Battery capacity, A*hr
ModuleType7.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ModuleType7.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ModuleType7.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ModuleType7.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ModuleType7.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ModuleType7.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ModuleType7.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ModuleType7.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ModuleType7.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ModuleType7.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ModuleType7.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ParallelAssemblyType1
ParallelAssemblyType1.BatteryCapacityCell = 27; % Battery capacity, A*hr
ParallelAssemblyType1.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ParallelAssemblyType1.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ParallelAssemblyType1.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ParallelAssemblyType1.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ParallelAssemblyType1.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ParallelAssemblyType1.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ParallelAssemblyType1.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ParallelAssemblyType1.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ParallelAssemblyType1.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ParallelAssemblyType1.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ParallelAssemblyType1.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ParallelAssemblyType2
ParallelAssemblyType2.BatteryCapacityCell = 27; % Battery capacity, A*hr
ParallelAssemblyType2.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ParallelAssemblyType2.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ParallelAssemblyType2.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ParallelAssemblyType2.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ParallelAssemblyType2.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ParallelAssemblyType2.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ParallelAssemblyType2.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ParallelAssemblyType2.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ParallelAssemblyType2.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ParallelAssemblyType2.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ParallelAssemblyType2.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ParallelAssemblyType3
ParallelAssemblyType3.BatteryCapacityCell = 27; % Battery capacity, A*hr
ParallelAssemblyType3.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ParallelAssemblyType3.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ParallelAssemblyType3.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ParallelAssemblyType3.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ParallelAssemblyType3.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ParallelAssemblyType3.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ParallelAssemblyType3.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ParallelAssemblyType3.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ParallelAssemblyType3.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ParallelAssemblyType3.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ParallelAssemblyType3.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ParallelAssemblyType4
ParallelAssemblyType4.BatteryCapacityCell = 27; % Battery capacity, A*hr
ParallelAssemblyType4.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ParallelAssemblyType4.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ParallelAssemblyType4.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ParallelAssemblyType4.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ParallelAssemblyType4.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ParallelAssemblyType4.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ParallelAssemblyType4.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ParallelAssemblyType4.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ParallelAssemblyType4.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ParallelAssemblyType4.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ParallelAssemblyType4.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ParallelAssemblyType5
ParallelAssemblyType5.BatteryCapacityCell = 27; % Battery capacity, A*hr
ParallelAssemblyType5.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ParallelAssemblyType5.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ParallelAssemblyType5.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ParallelAssemblyType5.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ParallelAssemblyType5.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ParallelAssemblyType5.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ParallelAssemblyType5.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ParallelAssemblyType5.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ParallelAssemblyType5.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ParallelAssemblyType5.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ParallelAssemblyType5.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ParallelAssemblyType6
ParallelAssemblyType6.BatteryCapacityCell = 27; % Battery capacity, A*hr
ParallelAssemblyType6.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ParallelAssemblyType6.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ParallelAssemblyType6.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ParallelAssemblyType6.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ParallelAssemblyType6.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ParallelAssemblyType6.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ParallelAssemblyType6.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ParallelAssemblyType6.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ParallelAssemblyType6.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ParallelAssemblyType6.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ParallelAssemblyType6.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W

%% ParallelAssemblyType7
ParallelAssemblyType7.BatteryCapacityCell = 27; % Battery capacity, A*hr
ParallelAssemblyType7.SOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints, SOC
ParallelAssemblyType7.TemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints, T, K
ParallelAssemblyType7.OpenCircuitVoltageThermalCell = [3.49, 3.5, 3.51; 3.55, 3.57, 3.56; 3.62, 3.63, 3.64; 3.71, 3.71, 3.72; 3.91, 3.93, 3.94; 4.07, 4.08, 4.08; 4.19, 4.19, 4.19]; % Open-circuit voltage, OCV(SOC,T), V
ParallelAssemblyType7.VoltageRangeCell = [0, inf]; % Terminal voltage operating range, [Min Max], V
ParallelAssemblyType7.ResistanceSOCBreakpointsCell = [0, .1, .25, .5, .75, .9, 1]; % State of charge breakpoints for resistance, SOC
ParallelAssemblyType7.ResistanceTemperatureBreakpointsCell = [278, 293, 313]; % Temperature breakpoints for resistance, T, K
ParallelAssemblyType7.R0ThermalCell = [.0117, .0085, .009; .011, .0085, .009; .0114, .0087, .0092; .0107, .0082, .0088; .0107, .0083, .0091; .0113, .0085, .0089; .0116, .0085, .0089]; % Instantaneous resistance, R0(SOC,T), Ohm
ParallelAssemblyType7.R1ThermalCell = [.0109, .0029, .0013; .0069, .0024, .0012; .0047, .0026, .0013; .0034, .0016, .001; .0033, .0023, .0014; .0033, .0018, .0011; .0028, .0017, .0011]; % First polarization resistance, R1(SOC,T), Ohm
ParallelAssemblyType7.Tau1ThermalCell = [20, 36, 39; 31, 45, 39; 109, 105, 61; 36, 29, 26; 59, 77, 67; 40, 33, 29; 25, 39, 33]; % First time constant, Tau1(SOC,T), s
ParallelAssemblyType7.BatteryThermalMassCell = 100; % Battery thermal mass, J/K
ParallelAssemblyType7.AmbientResistance = 25; % Cell level ambient thermal path resistance, K/W
