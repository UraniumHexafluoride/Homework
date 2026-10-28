% compare_numeric_vs_analytic.m
% Compares numerical finite-difference partials (Ken's MLE_compute_cpa_Phi)
% against closed-form algebraic partials (MLE_compute_cpa_Phi_analytic).

clearvars;
close all;

define_constants;
define_colors;

% Accelerating test scenario from Test_MLE_compute_CPA
Spos = [     0        0      0 ];
Svel = [ 3.000   -1.000      0 ];
Tpos = [ 10000    -5000      0 ];
Tvel = [ 3.000    4.000      0 ];
Sacc = [ +0.002 +0.003     0 ];
Tacc = [ -0.005  0.005     0 ];

Rpos = Tpos - Spos;
Rvel = Tvel - Svel;
Racc = Tacc - Sacc;

Phat = diag([ 100.0^2 100.0^2  0.1^2  0.1^2 .001^2 .001^2 ]);

% 1. Numerical partials (finite differences)
[Phi_T_num, Phi_B_num, Phi_R_num] = MLE_compute_cpa_Phi(Rpos, Rvel, Racc);

% 2. Closed-form analytic partials
[Phi_T_ana, Phi_B_ana, Phi_R_ana] = MLE_compute_cpa_Phi_analytic(Rpos, Rvel, Racc, true);
[~, Phi_B_ken, ~]                 = MLE_compute_cpa_Phi_analytic(Rpos, Rvel, Racc, false);

% Standard deviations
std_T_num = sqrt(Phi_T_num * Phat * Phi_T_num');
std_T_ana = sqrt(Phi_T_ana * Phat * Phi_T_ana');

std_R_num = sqrt(Phi_R_num * Phat * Phi_R_num');
std_R_ana = sqrt(Phi_R_ana * Phat * Phi_R_ana');

std_B_num = sqrt(Phi_B_num * Phat * Phi_B_num');
std_B_ana = sqrt(Phi_B_ana * Phat * Phi_B_ana');
std_B_ken = sqrt(Phi_B_ken * Phat * Phi_B_ken');

fprintf('========================================================================\n');
fprintf('     COMPARISON: NUMERICAL VS. ALGEBRAIC (ANALYTIC) PARTIALS           \n');
fprintf('========================================================================\n\n');

labels = {'dxpos', 'dypos', 'dxvel', 'dyvel', 'dxacc', 'dyacc'};

fprintf('--- 1. CPA TIME PARTIALS (Phi_T) ---\n');
fprintf('%-10s %14s %14s %14s\n', 'Param', 'Numerical', 'Analytic', 'Diff');
for i = 1:6
    fprintf('%-10s %14.4f %14.4f %14.4f\n', labels{i}, Phi_T_num(i), Phi_T_ana(i), Phi_T_ana(i) - Phi_T_num(i));
end
fprintf('  --> Time Std Dev: Numerical = %6.3f min  |  Analytic = %6.3f min\n\n', std_T_num/60, std_T_ana/60);

fprintf('--- 2. CPA RANGE PARTIALS (Phi_R) ---\n');
fprintf('%-10s %14s %14s %14s\n', 'Param', 'Numerical', 'Analytic', 'Diff');
for i = 1:6
    fprintf('%-10s %14.4f %14.4f %14.4f\n', labels{i}, Phi_R_num(i), Phi_R_ana(i), Phi_R_ana(i) - Phi_R_num(i));
end
fprintf('  --> Range Std Dev: Numerical = %6.3f Km   |  Analytic = %6.3f Km\n\n', std_R_num/1000, std_R_ana/1000);

fprintf('--- 3. CPA BEARING PARTIALS (Phi_B) ---\n');
fprintf('%-10s %14s %14s %14s\n', 'Param', 'Ken Formula', 'Full Chain', 'Diff');
for i = 1:6
    fprintf('%-10s %14.5f %14.5f %14.5f\n', labels{i}, Phi_B_ken(i), Phi_B_ana(i), Phi_B_ana(i) - Phi_B_ken(i));
end
fprintf('  --> Bearing Std Dev: Ken Approx = %6.3f deg  |  Full Chain = %6.3f deg\n', std_B_ken*rtd, std_B_ana*rtd);
fprintf('========================================================================\n');
