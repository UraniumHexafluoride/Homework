function [Phi_T,Phi_B,Phi_R] = MLE_compute_cpa_Phi_analytic(Rpos,Rvel,Racc,use_full_chain)
%------------------------------------------------------------------------------------------------------------------------
%   This subroutine computes the Phi sensitivity / Jacobian matrices
%   ALGEBRAICALLY (in closed form) for CPA time, bearing, and range
%   for an accelerating sensor and contact, eliminating finite difference errors.
%
%   Derivation Method:
%   At CPA time t = Tcpa, the relative position r(t) and velocity v(t) satisfy:
%       F(t, x) = r(t) . v(t) = 0
%   By the Implicit Function Theorem:
%       dTcpa / dx = - (grad_x F) / (dF / dt)
%   where:
%       dF / dt = ||v(Tcpa)||^2 + r(Tcpa) . a0   (scalar denominator > 0)
%       dF / dr0 = v(Tcpa)
%       dF / dv0 = Tcpa * v(Tcpa) + r(Tcpa)
%       dF / da0 = (1/2)*Tcpa^2 * v(Tcpa) + Tcpa * r(Tcpa)
%------------------------------------------------------------------------------------------------------------------------
% Inputs:
%   Rpos           - relative x, y, z position         (m)             [ 1 x 3 ]
%   Rvel           - relative x, y, z velocity         (m/s)           [ 1 x 3 ]
%   Racc           - relative x, y, z acceleration     (m/s^2)         [ 1 x 3 ]
%   use_full_chain - (optional, default: true) boolean
%                    true  = includes dTcpa/dx chain-rule in bearing partials
%                    false = matches Ken's simplified frozen-time bearing partials
%------------------------------------------------------------------------------------------------------------------------
% Outputs:
%   Phi_T - [ 1 x 6 ] Jacobian for CPA time
%   Phi_B - [ 1 x 6 ] Jacobian for CPA bearing
%   Phi_R - [ 1 x 6 ] Jacobian for CPA range
%------------------------------------------------------------------------------------------------------------------------

if nargin < 4
    use_full_chain = true;
end

% 1. Compute CPA time, bearing, and range
[Tcpa, ~, Rcpa] = MLE_compute_cpa_acc(Rpos, Rvel, Racc);

% 2. Relative position and velocity at CPA
rc = Rpos + Rvel*Tcpa + 0.5*Racc*Tcpa^2;
vc = Rvel + Racc*Tcpa;

% 3. Denominator: d/dt (r(t) . v(t)) = ||v(Tcpa)||^2 + r(Tcpa) . Racc
D = vc*vc' + rc*Racc';

% 4. Algebraic partial derivatives of CPA time (Implicit Function Theorem)
Phi_T = zeros(1, 6);
if abs(D) > eps
    % Partials with respect to [xpos, ypos]
    Phi_T(1, 1:2) = -vc(1:2) / D;
    % Partials with respect to [xvel, yvel]
    Phi_T(1, 3:4) = -(Tcpa*vc(1:2) + rc(1:2)) / D;
    % Partials with respect to [xacc, yacc]
    if norm(Racc) > 0
        Phi_T(1, 5:6) = -(0.5*Tcpa^2*vc(1:2) + Tcpa*rc(1:2)) / D;
    end
end

% 5. Algebraic partial derivatives of CPA Range
% Note: At CPA, dR/dt = (rc . vc) / Rcpa = 0, so the chain rule term
% (dR/dt)*(dTcpa/dx) vanishes identically.
Phi_R = zeros(1, 6);
if Rcpa > 0
    Phi_R(1, 1) = rc(1) / Rcpa;
    Phi_R(1, 2) = rc(2) / Rcpa;
    Phi_R(1, 3) = Phi_R(1, 1) * Tcpa;
    Phi_R(1, 4) = Phi_R(1, 2) * Tcpa;
    if norm(Racc) > 0
        Phi_R(1, 5) = Phi_R(1, 1) * Tcpa^2 / 2;
        Phi_R(1, 6) = Phi_R(1, 2) * Tcpa^2 / 2;
    end
end

% 6. Algebraic partial derivatives of CPA Bearing
% B = atan2(rc(1), rc(2))
Phi_B = zeros(1, 6);
if Rcpa > 0
    % Direct (explicit) partials: d(atan2(x, y))/dx = y/R^2, d/dy = -x/R^2
    dB_dx =  rc(2) / Rcpa^2;
    dB_dy = -rc(1) / Rcpa^2;
    
    if ~use_full_chain
        % Ken's original frozen-time approximation
        Phi_B(1, 1) = dB_dx;
        Phi_B(1, 2) = dB_dy;
        Phi_B(1, 3) = dB_dx * Tcpa;
        Phi_B(1, 4) = dB_dy * Tcpa;
        if norm(Racc) > 0
            Phi_B(1, 5) = dB_dx * Tcpa^2 / 2;
            Phi_B(1, 6) = dB_dy * Tcpa^2 / 2;
        end
    else
        % Full chain-rule accounting for d(rc)/dx = partial(rc)/partial(x) + vc * (dTcpa/dx)
        dB_drc = [dB_dx, dB_dy];
        drc_dx = zeros(2, 6);
        drc_dx(1:2, 1:2) = eye(2);
        drc_dx(1:2, 3:4) = Tcpa * eye(2);
        if norm(Racc) > 0
            drc_dx(1:2, 5:6) = 0.5 * Tcpa^2 * eye(2);
        end
        % Total Jacobian
        Phi_B = dB_drc * (drc_dx + vc(1:2)' * Phi_T);
    end
end

return;
