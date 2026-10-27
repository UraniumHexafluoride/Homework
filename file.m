fn  = @MLE_compute_cpa_2D_PVA_analytic;
th0 = [Rpos(1:2)'; Rvel(1:2)'; Racc(1:2)'];   % [px py vx vy ax ay]'
Jn  = zeros(2,6);
for k = 1:6
    h = 1e-5*max(abs(th0(k)), 1e-3);
    d = zeros(6,1); d(k) = h;
    tp = th0 + d;  tm = th0 - d;
    [t_p,b_p] = fn(tp(1:2),tp(3:4),tp(5:6),Phat);
    [t_m,b_m] = fn(tm(1:2),tm(3:4),tm(5:6),Phat);
    Jn(:,k) = [t_p - t_m; b_p - b_m]/(2*h);
end
S = Jn*Phat*Jn';
fprintf('FD of my function: time std %g, brg std %g\n', sqrt(S(1,1)), sqrt(S(2,2)));