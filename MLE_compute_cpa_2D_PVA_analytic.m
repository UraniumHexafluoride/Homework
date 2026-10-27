function [t,brg,rng,sig_t,sig_b,sig_r,J] = MLE_compute_cpa_2D_PVA_analytic(Rpos,Rvel,Racc,Phat)
p = Rpos(1:2); v = Rvel(1:2); a = Racc(1:2);   % 2D only (z = 0 in your tests)
p=p(:); v=v(:); a=a(:);

% cubic: R.V = 0
c   = [0.5*(a'*a), 1.5*(v'*a), v'*v + p'*a, p'*v];
rts = roots(c);
rts = real(rts(abs(imag(rts)) < 1e-9));
best = inf; t = NaN;
for k = 1:numel(rts)
    tk = rts(k);
    Rk = p + v*tk + 0.5*a*tk^2;  Vk = v + a*tk;
    if Vk'*Vk + Rk'*a > 0 && norm(Rk) < best     % range minimum
        best = norm(Rk);  t = tk;
    end
end
% NOTE: replace the root-selection above with whatever rule your code uses

R = p + v*t + 0.5*a*t^2;
V = v + a*t;
r = norm(R);
D = V'*V + R'*a;

I2    = eye(2);
dRdth = [I2, t*I2, 0.5*t^2*I2];                    % 2x6
dfdth = [V', (t*V+R)', (0.5*t^2*V + t*R)'];        % 1x6
dtdth = -dfdth / D;
dRtot = dRdth + V*dtdth;

J = [dtdth;
     [R(2), -R(1)]/r^2 * dRtot;                    % bearing = atan2(Rx,Ry)
     (R'/r) * dRtot];                              % range
S = J*Phat*J';
sig_t = sqrt(S(1,1));  sig_b = sqrt(S(2,2));  sig_r = sqrt(S(3,3));
brg = atan2(R(1),R(2));  rng = r;
end

[t2,b2,r2,st2,sb2,sr2] = MLE_compute_cpa_2D_PVA_analytic(Rpos,Rvel,Racc,Phat);
fprintf('time std: %g vs %g\nbrg std: %g vs %g\nrng std: %g vs %g\n', ...
    CPA_time_std_CA,st2, CPA_brg_std_CA,sb2, CPA_rng_std_CA,sr2);