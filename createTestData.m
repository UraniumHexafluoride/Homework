% =============================================================================
% CREATE TEST MAT FILES FOR TELEMETRY QA TESTING
% =============================================================================
% Run this script once in your working folder. It creates three test .mat
% files with synthetic CEU/PDS/UPS structs, so you can test TelemetryQAAnalyze
% without needing your real data. After running this, you'll see three files:
%   LRID_24566_EntireRun.mat  (UPS data)
%   LRID_24578_EntireRun.mat  (CEU data)
%   LRID_24572_EntireRun.mat  (PDS data)
% Then run TelemetryQAAnalyze() in the same folder to test the analysis.

clear all;

% =============================================================================
% TEST FILE 1: LRID_24566_EntireRun.mat (UPS)
% =============================================================================
fprintf('Creating LRID_24566_EntireRun.mat (UPS)...\n');

ups.upsStatus_online = 1;              % 1 = online (good)
ups.upsStatus_fault = 0;               % 0 = no fault (good)
ups.upsStatus_battery_low = 0;         % 0 = battery ok (good)
ups.upsVoltage_input = [118, 119, 120, 121, 120, 119, 118, 120];  % array of readings
ups.upsVoltage_output = [240, 241, 240, 239, 240, 241, 240, 240];
ups.upsTemp_internal = [35.2, 35.4, 35.3, 35.5, 35.2, 35.1, 35.3, 35.4];  % Celsius
ups.upsBattery_soc = 85;               % state of charge, %
ups.upsTimestamp = now();              % metadata - will be ignored
ups.upsID = 'UPS-001';                 % metadata - will be ignored

save('LRID_24566_EntireRun.mat', 'ups');
fprintf('  Created LRID_24566_EntireRun.mat\n');

% =============================================================================
% TEST FILE 2: LRID_24578_EntireRun.mat (CEU)
% =============================================================================
fprintf('Creating LRID_24578_EntireRun.mat (CEU)...\n');

ceu.ceuStatus_fault = 0;               % 0 = no fault (good)
ceu.ceuStatus_enabled = 1;             % 1 = enabled (good)
ceu.ceuStatus_overtemp = 0;            % 0 = no overheat (good)
ceu.ceuTemp_coolant = [45.1, 45.3, 45.2, 45.4, 45.1, 45.0, 45.2, 45.3];  % array, Celsius
ceu.ceuTemp_external = [22.5, 22.6, 22.5, 22.7, 22.5, 22.4, 22.5, 22.6];
ceu.ceuPressure_coolant = [50.2, 50.1, 50.3, 50.2, 50.1, 50.2, 50.3, 50.1];  % PSI
ceu.ceuFlow_coolant = [12.5, 12.6, 12.5, 12.4, 12.5, 12.6, 12.5, 12.4];  % GPM
ceu.ceuVoltage_rail_3v3 = [3.28, 3.29, 3.28, 3.30, 3.28, 3.27, 3.28, 3.29];
ceu.ceuVoltage_rail_5v = [5.01, 5.02, 5.00, 5.03, 5.01, 5.00, 5.01, 5.02];
ceu.ceuTimestamp = now();              % metadata - will be ignored
ceu.ceuDeviceID = 'CEU-A';             % metadata - will be ignored

save('LRID_24578_EntireRun.mat', 'ceu');
fprintf('  Created LRID_24578_EntireRun.mat\n');

% =============================================================================
% TEST FILE 3: LRID_24572_EntireRun.mat (PDS)
% =============================================================================
fprintf('Creating LRID_24572_EntireRun.mat (PDS)...\n');

pds.pdsStatus_fault = 0;               % 0 = no fault (good)
pds.pdsStatus_relay_closed = 1;        % 1 = closed (good)
pds.pdsStatus_warning = 0;             % 0 = no warning (good)
pds.pdsVoltage_primary = [27.5, 27.6, 27.5, 27.4, 27.5, 27.6, 27.5, 27.4];  % Volts array
pds.pdsVoltage_secondary = [13.8, 13.9, 13.8, 13.7, 13.8, 13.9, 13.8, 13.7];
pds.pdsCurrent_primary = [8.2, 8.1, 8.3, 8.2, 8.1, 8.2, 8.3, 8.2];  % Amps
pds.pdsCurrent_secondary = [16.4, 16.2, 16.6, 16.4, 16.2, 16.4, 16.6, 16.4];
pds.pdsPower_primary = [225, 226, 224, 225, 226, 225, 224, 225];  % Watts
pds.pdsTemp_transformer = [38.5, 38.6, 38.5, 38.7, 38.5, 38.4, 38.5, 38.6];  % Celsius
pds.pdsEfficiency = [96.2, 96.1, 96.3, 96.2, 96.1, 96.2, 96.3, 96.2];  % percentage
pds.pdsTimestamp = now();              % metadata - will be ignored
pds.pdsSerialNumber = 'PDS-2024-001';  % metadata - will be ignored

save('LRID_24572_EntireRun.mat', 'pds');
fprintf('  Created LRID_24572_EntireRun.mat\n');

fprintf('\n==================================================\n');
fprintf('Test files created successfully!\n');
fprintf('==================================================\n');
fprintf('\nNow run TelemetryQAAnalyze() in this same folder.\n');
fprintf('Expected output:\n');
fprintf('  - Terminal summary showing PASS/FAIL/REVIEW counts\n');
fprintf('  - Excel file: Telemetry_PassFail_Report.xlsx\n');
fprintf('  - 5 sheets: UPS, CEU, PDS, All, Summary\n');
fprintf('\nNotes on the test data:\n');
fprintf('  - All fault flags are 0 (good) or 1 (good) - should PASS\n');
fprintf('  - All numeric arrays are tight clusters - should PASS 95%% CI\n');
fprintf('  - All fields have realistic names, units, and ranges\n');
fprintf('  - Metadata fields (timestamp, ID, serial) will be IGNORED\n');
fprintf('==================================================\n');
