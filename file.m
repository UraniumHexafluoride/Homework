[T1,B1,R1] = MLE_compute_cpa_acc(Rpos,Rvel,Racc);
fprintf('yours:  %g min, %g deg, %g km\n', T1/60, B1*180/pi, R1/1000);
fprintf('mine:   %g min, %g deg, %g km\n', t2/60, b2*180/pi, r2/1000);
