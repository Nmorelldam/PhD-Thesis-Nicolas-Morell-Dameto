function t_opf_dc_clp(quiet)
%T_OPF_DC_CLP  Tests for DC optimal power flow using CLP solver.

%   MATPOWER
%   Copyright (c) 2004-2016, Power Systems Engineering Research Center (PSERC)
%   by Ray Zimmerman, PSERC Cornell
%
%   This file is part of MATPOWER.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See https://matpower.org for more info.

if nargin < 1
    quiet = 0;
end

if have_fcn('opti_clp')
    algs = [0; 1; 2; 3; 4; 5];
    alg_names = {
        'dual simplex',
        'primal simplex',
        'pr splx/sprint',
        'barrier',
        'bar, no cross',
        'automatic'
    };
else
    algs = [1; 2];
    alg_names = {
        'primal simplex',
        'dual simplex'
    };
end
num_tests = 24 * length(algs);

t_begin(num_tests, quiet);

[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, ...
    VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST, ...
    ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;

casefile = 't_case9_opf';
if quiet
    verbose = 0;
else
    verbose = 0;
end
if have_fcn('octave')
    if have_fcn('octave', 'vnum') >= 4
        file_in_path_warn_id = 'Octave:data-file-in-path';
    else
        file_in_path_warn_id = 'Octave:load-file-in-path';
    end
    s1 = warning('query', file_in_path_warn_id);
    warning('off', file_in_path_warn_id);
end

mpopt = mpoption('out.all', 0, 'verbose', verbose);
mpopt = mpoption(mpopt, 'opf.dc.solver', 'CLP');

%% run DC OPF
if have_fcn('clp')
    for k = 1:length(algs)
        if have_fcn('opti_clp')
            mpopt = mpoption(mpopt, 'clp.opts.algorithm', algs(k));
        else
            mpopt = mpoption(mpopt, 'clp.opts.solver', algs(k));
        end
    t0 = sprintf('DC OPF (CLP %s): ', alg_names{k});

    %% set up indices
    ib_data     = [1:BUS_AREA BASE_KV:VMIN];
    ib_voltage  = [VM VA];
    ib_lam      = [LAM_P LAM_Q];
    ib_mu       = [MU_VMAX MU_VMIN];
    ig_data     = [GEN_BUS QMAX QMIN MBASE:APF];
    ig_disp     = [PG QG VG];
    ig_mu       = (MU_PMAX:MU_QMIN);
    ibr_data    = (1:ANGMAX);
    ibr_flow    = (PF:QT);
    ibr_mu      = [MU_SF MU_ST];
    ibr_angmu   = [MU_ANGMIN MU_ANGMAX];

    %% get solved DC power flow case from MAT-file
    load soln9_dcopf;       %% defines bus_soln, gen_soln, branch_soln, f_soln

    %% run OPF
    t = t0;
    [baseMVA, bus, gen, gencost, branch, f, success, et] = rundcopf(casefile, mpopt);
    t_ok(success, [t 'success']);
    t_is(f, f_soln, 3, [t 'f']);
    t_is(   bus(:,ib_data   ),    bus_soln(:,ib_data   ), 10, [t 'bus data']);
    t_is(   bus(:,ib_voltage),    bus_soln(:,ib_voltage),  3, [t 'bus voltage']);
    t_is(   bus(:,ib_lam    ),    bus_soln(:,ib_lam    ),  3, [t 'bus lambda']);
    if have_fcn('opti_clp')
        t_is(   bus(:,ib_mu     ),    bus_soln(:,ib_mu     ),  2, [t 'bus mu']);
    else
        t_skip(1, [t 'bus mu - MEXCLP does not return multipliers on var bounds']);
    end
    t_is(   gen(:,ig_data   ),    gen_soln(:,ig_data   ), 10, [t 'gen data']);
    t_is(   gen(:,ig_disp   ),    gen_soln(:,ig_disp   ),  3, [t 'gen dispatch']);
    if have_fcn('opti_clp')
        t_is(   gen(:,ig_mu     ),    gen_soln(:,ig_mu     ),  3, [t 'gen mu']);
    else
        t_skip(1, [t 'gen mu - MEXCLP does not return multipliers on var bounds']);
    end
    t_is(branch(:,ibr_data  ), branch_soln(:,ibr_data  ), 10, [t 'branch data']);
    t_is(branch(:,ibr_flow  ), branch_soln(:,ibr_flow  ),  3, [t 'branch flow']);
    if have_fcn('opti_clp')
        t_is(branch(:,ibr_mu    ), branch_soln(:,ibr_mu    ),  2, [t 'branch mu']);
    else
        t_skip(1, [t 'branch mu - MEXCLP does not return multipliers on var bounds']);
    end

    %%-----  run OPF with extra linear user constraints & costs  -----
    %% two new z variables
    %%      0 <= z1, P3 - P1 <= z1
    %%      0 <= z2, P3 - P2 <= z2
    %% with A and N sized for DC opf
    mpc = loadcase(casefile);
    mpc.A = sparse([1;1;1;2;2;2],[10;12;13;12;11;14],[-1;1;-1;1;-1;-1],2,14);
    mpc.u = [0; 0];
    mpc.l = [-Inf; -Inf];
    mpc.zl = [0; 0];

    mpc.N = sparse([1;2], [13;14], [1;1], 2, 14);   %% new z variables only
    mpc.fparm = ones(2,1) * [1 0 0 1];              %% w = r = z
    mpc.H = sparse(2,2);                            %% no quadratic term
    mpc.Cw = [1000;1];

    t = [t0 'w/extra constraints & costs 1 : '];
    [r, success] = rundcopf(mpc, mpopt);
    t_ok(success, [t 'success']);
    t_is(r.gen(1, PG), 116.15974, 4, [t 'Pg1 = 116.15974']);
    t_is(r.gen(3, PG), 116.15974, 4, [t 'Pg3 = 116.15974']);
    t_is(r.var.val.z, [0; 0.3348], 4, [t 'user vars']);
    t_is(r.cost.usr, 0.3348, 3, [t 'user costs']);

    %% with A and N sized for AC opf
    mpc = loadcase(casefile);
    mpc.A = sparse([1;1;1;2;2;2],[19;21;25;21;20;26],[-1;1;-1;1;-1;-1],2,26);
    mpc.u = [0; 0];
    mpc.l = [-Inf; -Inf];
    mpc.zl = [0; 0];

    mpc.N = sparse([1;2], [25;26], [1;1], 2, 26);   %% new z variables only
    mpc.fparm = ones(2,1) * [1 0 0 1];              %% w = r = z
    mpc.H = sparse(2,2);                            %% no quadratic term
    mpc.Cw = [1000;1];

    t = [t0 'w/extra constraints & costs 2 : '];
    [r, success] = rundcopf(mpc, mpopt);
    t_ok(success, [t 'success']);
    t_is(r.gen(1, PG), 116.15974, 4, [t 'Pg1 = 116.15974']);
    t_is(r.gen(3, PG), 116.15974, 4, [t 'Pg3 = 116.15974']);
    t_is(r.var.val.z, [0; 0.3348], 4, [t 'user vars']);
    t_is(r.cost.usr, 0.3348, 3, [t 'user costs']);

    t = [t0 'infeasible : '];
    %% with A and N sized for DC opf
    mpc = loadcase(casefile);
    mpc.A = sparse([1;1], [10;11], [1;1], 1, 14);   %% Pg1 + Pg2
    mpc.u = Inf;
    mpc.l = 600;
    [r, success] = rundcopf(mpc, mpopt);
    t_ok(~success, [t 'no success']);

    %% OPF with all buses isolated
    t = [t0 'all buses isolated : '];
    mpc = loadcase(casefile);
    mpc.bus(:, BUS_TYPE) = NONE;
    try
        r = rundcopf(mpc, mpopt);
        t_is(r.success, 0, 12, [t 'success = 0']);
    catch
        t_ok(0, [t 'unexpected fatal error']);
    end

    end
else
    t_skip(num_tests, 'CLP not available');
end

if have_fcn('octave')
    warning(s1.state, file_in_path_warn_id);
end

t_end;