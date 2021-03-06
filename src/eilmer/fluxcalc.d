/**
 * fluxcalc.d
 * Convective-Flux calculators, for use in the CFD codes.
 *
 * Author: Peter J. and Rowan G.
 * Version: 2014-07-23: initial cut, to explore options.
 */

module fluxcalc;

import std.math;
import std.stdio;
import std.conv;
import nm.complex;
import nm.number;

import geom;
import gas;
import flowstate;
import conservedquantities;
import fvcore;
import fvinterface;
import globalconfig;

@nogc
void compute_interface_flux(ref FlowState Lft, ref FlowState Rght, ref FVInterface IFace,
                            ref LocalConfig myConfig, double omegaz=0.0)
/** Compute the inviscid fluxes (in 1D) across the cell interfaces.
 *
 * This is the top-level function that calls the previously selected
 * flux calculator for open cell faces. i.e. those with cells either side.
 * Much of the detailed work is delegated.
 *
 * Lft : reference to the LEFT FlowState
 * Rght : reference to the RIGHT FlowState
 * IFace : reference to the interface where the fluxes are to be stored
 * myConfig : a block-local configuration object
 * omegaz : angular speed of the block
 *
 * Note that the FlowState objects, Lft and Rght, are tampered with.
 * Be sure that you use copies if you care about their content.
 */
{
    // Transform to interface frame of reference.
    // Firstly, subtract interface velocity, in the case where the grid is moving
    // we want the velocity of the flow relative to the interface.
    Lft.vel.refx -= IFace.gvel.x; Lft.vel.refy -= IFace.gvel.y; Lft.vel.refz -= IFace.gvel.z;
    Rght.vel.refx -= IFace.gvel.x; Rght.vel.refy -= IFace.gvel.y; Rght.vel.refz -= IFace.gvel.z;
   
    IFace.gvel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    Lft.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    Rght.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    version(MHD) {
        // Also transform the magnetic field
        if (myConfig.MHD) {
            Lft.B.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
            Rght.B.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
        }
    }
    // Compute the fluxes in the local frame of the interface.
    final switch (myConfig.flux_calculator) {
    case FluxCalculator.efm:
        efmflx(Lft, Rght, IFace, myConfig);
        break;
    case FluxCalculator.ausmdv:
        ausmdv(Lft, Rght, IFace, myConfig);
        break;
    case FluxCalculator.hanel:
        hanel(Lft, Rght, IFace, myConfig);
        break;
    case FluxCalculator.adaptive_efm_ausmdv:
        adaptive_efm_ausmdv(Lft, Rght, IFace, myConfig);
        break;
    case FluxCalculator.adaptive_hanel_ausmdv:
        adaptive_hanel_ausmdv(Lft, Rght, IFace, myConfig);
        break;
    case FluxCalculator.adaptive_hlle_roe:
        adaptive_hlle_roe(Lft, Rght, IFace, myConfig);
        break;
    case FluxCalculator.ausm_plus_up:
        ausm_plus_up(Lft, Rght, IFace, myConfig.M_inf, myConfig);
        break;
    case FluxCalculator.hlle:
        hlle(Lft, Rght, IFace, myConfig);
        break;
    case FluxCalculator.roe:
        roe(Lft, Rght, IFace, myConfig);
        break;
    } // end switch
    ConservedQuantities F = IFace.F;
    version(MHD) {
        // Adjustment of the magnetic field flux and associated parameter psi as per Dedner et al.
        if (myConfig.MHD) {
            F.divB = 0.5 * (Rght.B.x - Lft.B.x);
            if (myConfig.divergence_cleaning) {
                F.B.refx += Lft.psi + 0.5 * (Rght.psi - Lft.psi) - (myConfig.c_h / 2.0) * (Rght.B.x - Lft.B.x);
                F.psi += (Lft.B.x + 0.5 * (Rght.B.x - Lft.B.x) - (1.0 / (2.0 * myConfig.c_h)) *
                          (Rght.psi - Lft.psi)) * myConfig.c_h * myConfig.c_h;
            }
        }
    }
    if (omegaz != 0.0) {
        // Rotating frame.
        number x = IFace.pos.x;
        number y = IFace.pos.y;
        number rsq = x*x + y*y;
        // The conserved quantity is rothalpy,
        // so we need to take -(u**2)/2 off the total energy flux.
        // Note that rotating frame velocity u = omegaz * r.
        F.total_energy -= F.mass * 0.5*omegaz*omegaz*rsq;
    }
    // Transform fluxes back from interface frame of reference to local frame of reference.
    // Flux of Total Energy
    number v_sqr = IFace.gvel.x*IFace.gvel.x + IFace.gvel.y*IFace.gvel.y + IFace.gvel.z*IFace.gvel.z; 
    F.total_energy += 0.5 * F.mass * v_sqr + F.momentum.dot(IFace.gvel);
    // Flux of momentum: Add component for interface velocity then
    // rotate back to the global frame of reference.
    Vector3 momentum_increment;
    momentum_increment.set(IFace.gvel); momentum_increment *= F.mass;
    F.momentum += momentum_increment;
    F.momentum.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    // Also, transform the interface (grid) velocity and magnetic field.
    IFace.gvel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    version(MHD) {
        if (myConfig.MHD) { F.B.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2); }
    }
    return;
} // end compute_interface_flux()

@nogc
void compute_flux_at_left_wall(ref FlowState Rght, ref FVInterface IFace,
                               ref LocalConfig myConfig, double omegaz=0.0)
{
    // Transform to interface frame of reference.
    IFace.gvel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    Rght.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    version(MHD) {
        // Also transform the magnetic field
        if (myConfig.MHD) { Rght.B.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2); }
    }
    // Compute the fluxes in the local frame of the interface,
    // presuming that there is a right-running wave which processes the gas
    // from the initial right-flow-state to that at the wall.
    // See PJ workbook notes 2018-06-09.
    // Source of this calculation is the 1998 report on L1d, Report 13/98.
    number vstar = IFace.gvel.x;
    number aR = Rght.gas.a;
    number vR = Rght.vel.x;
    number g = myConfig.gmodel.gamma(Rght.gas);
    // Riemann invariant across left-running wave.
    number UbarR = vR - 2.0*aR/(g-1.0);
    // Set up to compute pressure at wall, pstar.
    number rhoR = Rght.gas.rho;
    number pR = Rght.gas.p;
    number tmp = (vstar - UbarR)*(g-1.0)/(2.0*sqrt(g))*sqrt(rhoR/pow(pR,1.0/g));
    number ptiny = myConfig.flowstate_limits.min_pressure;
    number pstar = (tmp > 0.0) ? pow(tmp, 2.0*g/(g-1.0)) : ptiny;
    if (pstar > 1.1*pR) {
        // Shock wave processing. See PJ workbook notes 2010-05-22.
        number f(number ps)
        {
            number xi = ps/pR;
            number M1sq = 1.0 + (g+1.0)/2.0/g*(xi-1.0);
            number u1 = sqrt(M1sq)*aR;
            number u2 = u1*((g-1.0)*M1sq+2.0)/((g+1.0)*M1sq);
            return vstar - u1 + u2 - vR;
        }
        int count = 0;
        number incr_pstar;
        do {
            number f0 = f(pstar);
            number dp = 0.001 * pstar;
            number f1 = f(pstar+dp);
            incr_pstar = -f0*dp/(f1-f0);
            pstar += incr_pstar;
            count += 1;
        } while (fabs(incr_pstar)/pstar > 0.01 && count < 10);
    }
    // Limit the post-wave pressure to handle extreme boundary situations
    // where there is a large velocity difference between the cell centre and the wall.
    pstar = fmin(pstar, pR*10.0);
    //
    // Fill in the fluxes.
    ConservedQuantities F = IFace.F;
    F.mass = 0.0;
    F.momentum.set(pstar, to!number(0.0), to!number(0.0));
    F.total_energy = pstar * vstar;
    version(multi_species_gas) {
        uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
        foreach (i; 0 .. nsp) { F.massf[i] = 0.0; }
    }
    version(multi_T_gas) {
        foreach (i; 0 .. F.energies.length) { F.energies[i] = 0.0; }
    }
    version(komega) {
        foreach (i; 0 .. F.rhoturb.length) { F.rhoturb[i] = 0.0; }
    }
    version(MHD) {
        // [TODO] magnetic field.
        F.B.set(0.0, 0.0, 0.0);
        F.psi = 0.0;
        F.divB = 0.0;
    }
    // Rotate back to the global frame of reference.
    F.momentum.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    // Also, transform the interface (grid) velocity
    IFace.gvel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    version(MHD) {
        // and transform the magnetic field
        if (myConfig.MHD) { F.B.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2); }
    }
    return;
} // end compute_flux_at_left_wall()

@nogc
void compute_flux_at_right_wall(ref FlowState Lft, ref FVInterface IFace,
                                ref LocalConfig myConfig, double omegaz=0.0)
{
    // Transform to interface frame of reference.
    IFace.gvel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    Lft.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    version(MHD) {
        // Also transform the magnetic field
        if (myConfig.MHD) { Lft.B.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2); }
    }
    // Compute the fluxes in the local frame of the interface,
    // presuming that there is a right-running wave which processes the gas
    // from the initial right-flow-state to that at the wall.
    // See PJ workbook notes 2018-06-09.
    // Source of this calculation is the 1998 report on L1d, Report 13/98.
    number vstar = IFace.gvel.x;
    number aL = Lft.gas.a;
    number vL = Lft.vel.x;
    number g = myConfig.gmodel.gamma(Lft.gas);
    // Riemann invariant across left-running wave.
    number UbarL = vL + 2.0*aL/(g-1.0);
    // Set up to compute pressure at wall, pstar.
    number rhoL = Lft.gas.rho;
    number pL = Lft.gas.p;
    number tmp = (UbarL - vstar)*(g-1.0)/(2.0*sqrt(g))*sqrt(rhoL/pow(pL,1.0/g));
    number ptiny = myConfig.flowstate_limits.min_pressure;
    number pstar = (tmp > 0.0) ? pow(tmp, 2.0*g/(g-1.0)) : ptiny;
    if (pstar > 1.1*pL) {
        // Shock wave processing. See PJ workbook notes 2010-05-22.
        number f(number ps)
        {
            number xi = ps/pL;
            number M1sq = 1.0 + (g+1.0)/2.0/g*(xi-1.0);
            number u1 = sqrt(M1sq)*aL;
            number u2 = u1*((g-1.0)*M1sq+2.0)/((g+1.0)*M1sq);
            return vstar + u1 - u2 - vL;
        }
        int count = 0;
        number incr_pstar;
        do {
            number f0 = f(pstar);
            number dp = 0.001 * pstar;
            number f1 = f(pstar+dp);
            incr_pstar = -f0*dp/(f1-f0);
            pstar += incr_pstar;
            count += 1;
        } while (fabs(incr_pstar)/pstar > 0.01 && count < 10);
    }
    // Limit the post-wave pressure to handle extreme boundary situations
    // where there is a large velocity difference between the cell centre and the wall.
    pstar = fmin(pstar, pL*10.0);
    //
    // Fill in the fluxes.
    ConservedQuantities F = IFace.F;
    F.mass = 0.0;
    F.momentum.set(pstar, to!number(0.0), to!number(0.0));
    F.total_energy = pstar * vstar;
    version(multi_species_gas) {
        uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
        foreach (i; 0 .. nsp) { F.massf[i] = 0.0; }
    }
    version(multi_T_gas) {
        foreach (i; 0 .. F.energies.length) { F.energies[i] = 0.0; }
    }
    version(komega) {
        foreach (i; 0 .. F.rhoturb.length) { F.rhoturb[i] = 0.0; }
    }
    version(MHD) {
        // [TODO] magnetic field.
        F.B.set(0.0, 0.0, 0.0);
        F.psi = 0.0;
        F.divB = 0.0;
    }
    // Rotate back to the global frame of reference.
    F.momentum.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    // Also, transform the interface (grid) velocity
    IFace.gvel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    version(MHD) {
        // and transform the magnetic field
        if (myConfig.MHD) { F.B.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2); }
    }
    return;
} // end  compute_flux_at_right_wall()

@nogc
void set_flux_vector_in_local_frame(ref ConservedQuantities F, ref FlowState fs, 
                                    ref LocalConfig myConfig)
{
    number rho = fs.gas.rho;
    number vn = fs.vel.x;
    number vt1 = fs.vel.y;
    number vt2 = fs.vel.z;
    number p = fs.gas.p;
    number u = myConfig.gmodel.internal_energy(fs.gas);
    number ke = 0.5 * (vn*vn + vt1*vt1 + vt2*vt2); // Kinetic energy per unit volume.
    //
    // Fluxes (quantity / unit time / unit area)
    F.mass = rho * vn; // The mass flux is relative to the moving interface.
    F.momentum.set(F.mass*vn + p, F.mass*vt1, F.mass*vt2);
    F.total_energy = F.mass*(u+ke) + p*vn;
    version(komega) {
        F.total_energy += fs.turb[0]; // TODO: Generalise to tke function (NNG)
        foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = F.mass * fs.turb[i]; }
    }
    version(multi_species_gas) {
        uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
        foreach (isp; 0 .. nsp) { F.massf[isp] = F.mass*fs.gas.massf[isp]; }
    }
    version(multi_T_gas) {
        foreach (imode; 0 .. F.energies.length) { F.energies[imode] = F.mass*fs.gas.u_modes[imode]; }
    }
} // end set_flux_vector_in_local_frame()

@nogc
void set_flux_vector_in_global_frame(ref FVInterface IFace, ref FlowState fs, 
                                     ref LocalConfig myConfig, double omegaz=0.0)
{
    ConservedQuantities F = IFace.F;
    // Record velocity to restore fs at end.
    number vx = fs.vel.x; number vy = fs.vel.y; number vz = fs.vel.z; 
    // Transform to interface frame of reference.
    // Beware: fs.vel is changed here and restored below.
    fs.vel.refx -= IFace.gvel.x; fs.vel.refy -= IFace.gvel.y; fs.vel.refz -= IFace.gvel.z; 
    IFace.gvel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    version(MHD) {
        // also transform the magnetic field
        if (myConfig.MHD) { fs.B.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2); }
    }
    set_flux_vector_in_local_frame(IFace.F, fs, myConfig);
    if (omegaz != 0.0) {
        // Rotating frame.
        number x = IFace.pos.x;
        number y = IFace.pos.y;
        number rsq = x*x + y*y;
        // The conserved quantity is rothalpy,
        // so we need to take -(u**2)/2 off the total energy flux.
        // Note that rotating frame velocity u = omegaz * r.
        F.total_energy -= F.mass * 0.5*omegaz*omegaz*rsq;
    }
    //
    // Transform fluxes back from interface frame of reference to local frame of reference.
    number v_sqr = IFace.gvel.x*IFace.gvel.x + IFace.gvel.y*IFace.gvel.y + IFace.gvel.z*IFace.gvel.z;
    F.total_energy += 0.5 * F.mass * v_sqr + F.momentum.dot(IFace.gvel);
    Vector3 momentum_increment;
    momentum_increment.set(IFace.gvel); momentum_increment *= F.mass; 
    F.momentum += momentum_increment;
    //
    // Rotate momentum fluxes back to the global frame of reference.
    F.momentum.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    // also transform the interface (grid) velocity
    IFace.gvel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    version(MHD) {
        // also transform the magnetic field
        if (myConfig.MHD) { F.B.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2); }
    }
    fs.vel.set(vx, vy, vz); // restore fs.vel
} // end set_flux_vector_in_global_frame()

@nogc
void ausmdv(in FlowState Lft, in FlowState Rght, ref FVInterface IFace, ref LocalConfig myConfig)
// Wada and Liou's flux calculator.
// 
// Implemented from details in their AIAA paper 
// with hints from Ian Johnston.
// Y. Wada and M. -S. Liou (1994)
// A flux splitting scheme with high-resolution and robustness for discontinuities.
// AIAA-94-0083.
{
    auto gmodel = myConfig.gmodel;
    // Unpack the flow-state vectors for either side of the interface.
    // Store in work vectors, those quantities that will be neede later.
    number rL = Lft.gas.rho;
    number pL = Lft.gas.p;
    number pLrL = pL / rL;
    number uL = Lft.vel.x;
    number vL = Lft.vel.y;
    number wL = Lft.vel.z;
    number eL = gmodel.internal_energy(Lft.gas);
    number aL = Lft.gas.a;
    number keL = 0.5*(uL*uL + vL*vL + wL*wL);
    number HL = eL + pLrL + keL;
    version(komega) { HL += Lft.turb[0]; } // Generalise to TKE function (NNG)
    //
    number rR = Rght.gas.rho;
    number pR = Rght.gas.p;
    number pRrR = pR / rR;
    number uR = Rght.vel.x;
    number vR = Rght.vel.y;
    number wR = Rght.vel.z;
    number eR = gmodel.internal_energy(Rght.gas);
    number aR = Rght.gas.a;
    number keR = 0.5*(uR*uR + vR*vR + wR*wR);
    number HR = eR + pRrR + keR;
    version(komega) { HR += Rght.turb[0]; } // Generalise to tke function (NNG)
    //
    // This is the main part of the flux calculator.
    // Weighting parameters (eqn 32) for velocity splitting.
    number alphaL = 2.0 * pLrL / (pLrL + pRrR);
    number alphaR = 2.0 * pRrR / (pLrL + pRrR);
    // Common sound speed (eqn 33) and Mach numbers.
    number am = fmax(aL, aR);
    number ML = uL / am;
    number MR = uR / am;
    // Left state: 
    // pressure splitting (eqn 34) 
    // and velocity splitting (eqn 30)
    number pLplus, uLplus;
    number duL = 0.5 * (uL + fabs(uL));
    if (fabs(ML) <= 1.0) {
        pLplus = pL * (ML + 1.0) * (ML + 1.0) * (2.0 - ML) * 0.25;
        uLplus = alphaL * ((uL + am) * (uL + am) / (4.0 * am) - duL) + duL;
    } else {
        pLplus = pL * duL / uL;
        uLplus = duL;
    }
    // Right state: 
    // pressure splitting (eqn 34) 
    // and velocity splitting (eqn 31)
    number pRminus, uRminus;
    number duR = 0.5 * (uR - fabs(uR));
    if (fabs(MR) <= 1.0) {
        pRminus = pR * (MR - 1.0) * (MR - 1.0) * (2.0 + MR) * 0.25;
        uRminus = alphaR * (-(uR - am) * (uR - am) / (4.0 * am) - duR) + duR;
    } else {
        pRminus = pR * duR / uR;
        uRminus = duR;
    }
    // Mass Flux (eqn 29)
    // The mass flux is relative to the moving interface.
    number ru_half = uLplus * rL + uRminus * rR;
    // Pressure flux (eqn 34)
    number p_half = pLplus + pRminus;
    // Momentum flux: normal direction
    // Compute blending parameter s (eqn 37),
    // the momentum flux for AUSMV (eqn 21) and AUSMD (eqn 21)
    // and blend (eqn 36).
    number dp = pL - pR;
    const double K_SWITCH = 10.0;
    dp = K_SWITCH * fabs(dp) / fmin(pL, pR);
    number s = 0.5 * fmin(1.0, dp);
    number ru2_AUSMV = uLplus * rL * uL + uRminus * rR * uR;
    number ru2_AUSMD = 0.5 * (ru_half * (uL + uR) - fabs(ru_half) * (uR - uL));
    number ru2_half = (0.5 + s) * ru2_AUSMV + (0.5 - s) * ru2_AUSMD;
    //
    // Assemble components of the flux vector.
    ConservedQuantities F = IFace.F;
    F.mass = ru_half;
    if (ru_half >= 0.0) {
        // Wind is blowing from the left.
        F.momentum.set(ru2_half+p_half, ru_half*vL, ru_half*wL);
        F.total_energy = ru_half*HL;
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = ru_half*Lft.turb[i]; }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) { F.massf[i] = ru_half*Lft.gas.massf[i]; }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) { F.energies[i] = ru_half*Lft.gas.u_modes[i]; }
        }
        // NOTE: - the following relies on the free-electron mode being the last mode
        //       - for single temp models F_renergies isn't used
        //       - for multitemp modes with no free-electrons p_e is zero
        // Add electron pressure work term onto final energy mode
        // FIX-ME F.energies[nmodes-1] += ru_half * Lft.gas.p_e / Lft.gas.rho;
    } else {
        // Wind is blowing from the right.
        F.momentum.set(ru2_half+p_half, ru_half*vR, ru_half*wR);
        F.total_energy = ru_half*HR;
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = ru_half*Rght.turb[i]; }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) { F.massf[i] = ru_half*Rght.gas.massf[i]; }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) { F.energies[i] = ru_half*Rght.gas.u_modes[i]; }
        }
    }
    //
    // Apply entropy fix (section 3.5 in Wada and Liou's paper)
    const double C_EFIX = 0.125;
    bool caseA = ((uL - aL) < 0.0) && ((uR - aR) > 0.0);
    bool caseB = ((uL + aL) < 0.0) && ((uR + aR) > 0.0);
    //
    number d_ua = 0.0;
    if (caseA && !caseB) { d_ua = C_EFIX * ((uR - aR) - (uL - aL)); }
    if (caseB && !caseA) { d_ua = C_EFIX * ((uR + aR) - (uL + aL)); }
    //
    if (d_ua != 0.0) {
        F.mass -= d_ua*(rR - rL);
        F.momentum.refx -= d_ua*(rR*uR - rL*uL);
        F.momentum.refy -= d_ua*(rR*vR - rL*vL);
        F.momentum.refz -= d_ua*(rR*wR - rL*wL);
        F.total_energy -= d_ua*(rR*HR - rL*HL);
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] -= d_ua*(rR*Rght.turb[i] - rL*Lft.turb[i]); }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) {
                F.massf[i] -= d_ua*(rR*Rght.gas.massf[i] - rL*Lft.gas.massf[i]);
            }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) {
                F.energies[i] -= d_ua*(rR*Rght.gas.u_modes[i] - rL*Lft.gas.u_modes[i]);
            }
        }
    } // end of entropy fix (d_ua != 0)
} // end ausmdv()

@nogc
void hanel(in FlowState Lft, in FlowState Rght, ref FVInterface IFace, ref LocalConfig myConfig)
// Hanel's flux calculator.
// 
// Implemented from Y. Wada and M. S. Liou details in their AIAA paper 
// Y. Wada and M. -S. Liou (1997)
// An accurate and robust flux splitting scheme for shock and contact discontinuities.
// with reference to....
// Hanel, Schwane, & Seider's 1987 paper
// On the accuracy of upwind schemes for the solution of the Navier-Stokes equations

{
    auto gmodel = myConfig.gmodel;
    // Unpack the flow-state vectors for either side of the interface.
    // Store in work vectors, those quantities that will be neede later.
    number rL = Lft.gas.rho;
    number pL = Lft.gas.p;
    number pLrL = pL / rL;
    number uL = Lft.vel.x;
    number vL = Lft.vel.y;
    number wL = Lft.vel.z;
    number eL = gmodel.internal_energy(Lft.gas);
    number aL = Lft.gas.a;
    number keL = 0.5*(uL*uL + vL*vL + wL*wL);
    number HL = eL + pLrL + keL;
    version(komega) { HL += Lft.turb[0]; } // Generalise to tke function (NNG)
    //
    number rR = Rght.gas.rho;
    number pR = Rght.gas.p;
    number pRrR = pR / rR;
    number uR = Rght.vel.x;
    number vR = Rght.vel.y;
    number wR = Rght.vel.z;
    number eR = gmodel.internal_energy(Rght.gas);
    number aR = Rght.gas.a;
    number keR = 0.5*(uR*uR + vR*vR + wR*wR);
    number HR = eR + pRrR + keR;
    version(komega) { HR += Rght.turb[0]; } // Generalise to tke function (NNG)
    //
    number am = fmax(aL, aR);
    number ML = uL / am;
    number MR = uR / am;
    // Left state: 
    // pressure splitting (eqn 7) 
    // and velocity splitting (eqn 9)
    number pLplus, uLplus;
    if (fabs(uL) <= aL) {
        uLplus = 1.0/(4.0*aL) * (uL+aL)*(uL+aL);
        pLplus = pL*uLplus * (1.0/aL * (2.0-uL/aL));
    } else {
        uLplus = 0.5*(uL+fabs(uL));
        pLplus = pL*uLplus * (1.0/uL);
    }
    // Right state: 
    // pressure splitting (eqn 7) 
    // and velocity splitting (eqn 9)
    number pRminus, uRminus;
    if (fabs(uR) <= aR) {
        uRminus = -1.0/(4.0*aR) * (uR-aR)*(uR-aR);  
        pRminus = pR*uRminus * (1.0/aR * (-2.0-uR/aR));
    } else {
        uRminus = 0.5*(uR-fabs(uR)); 
        pRminus = pR*uRminus * (1.0/uR);
    }
    // The mass flux is relative to the moving interface.
    number ru_half = uLplus * rL + uRminus * rR;
    number ru2_half = uLplus * rL * uL + uRminus * rR * uR;
    // Pressure flux (eqn 8)
    number p_half = pLplus + pRminus;
    // Assemble components of the flux vector (eqn 36).
    ConservedQuantities F = IFace.F;
    F.mass = uLplus * rL + uRminus * rR;
    F.momentum.set(uLplus * rL * uL + uRminus * rR * uR + p_half,
                   uLplus * rL * vL + uRminus * rR * vR,
                   uLplus * rL * wL + uRminus * rR * wR);
    F.total_energy = uLplus * rL * HL + uRminus * rR * HR;
    version(komega) {
        foreach(i; 0 .. F.rhoturb.length) {
            F.rhoturb[i] = uLplus * rL * Lft.turb[i] + uRminus * rR * Rght.turb[i];
        }
    }
    version(multi_species_gas) {
        uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
        foreach (i; 0 .. nsp) {
            F.massf[i] = uLplus*rL*Lft.gas.massf[i] + uRminus*rR*Rght.gas.massf[i];
        }
    }
    version(multi_T_gas) {
        foreach (i; 0 .. F.energies.length) {
            F.energies[i] = uLplus*rL*Lft.gas.u_modes[i] + uRminus*rR*Rght.gas.u_modes[i];
        }
    }
} // end hanel()

@nogc
void efmflx(in FlowState Lft, in FlowState Rght, ref FVInterface IFace, ref LocalConfig myConfig)
/** \brief Compute the fluxes across an interface using
 * the Equilibrium Flux Method of Macrossan & Pullin
 *
 * \param Lft    : IN     : array of Left flow states
 *     (with velocities in local frame of reference)
 * \param Rght   : IN     : array of Right flow state
 * \param IF     : IN/OUT : array of interface flux data structures
 *
 * \verbatim
 * interface data -- contains...
 *     flux of mass across the interface (kg/s/m**2)
 *     flux of normal momentum
 *     flux of tangential momentum
 *     flux of energy
 *     array of species fluxes 
 *     vibrational energies
 *     free-electron energy
 * \endverbatim 
 */
{
    auto gmodel = myConfig.gmodel;
    // Local variable names reflect the names used in the original FORTRAN code by MNM.
    const double PHI = 1.0;
    number vnL, vpL, vnR, vpR, vqL, vqR;
    number rtL, cmpL, rtR, cmpR;
    number hvsqL, hvsqR;
    number wL, wR, dL, dR;
    number rhoL, rhoR, presL, presR, tR, tL;
    number eL, eR, hL, hR;
    number snL, snR, exL, exR, efL, efR;
    number fmsL, fmsR;
    number cv, cp, con, gam, Rgas;
    number cvL, cvR, RgasL, RgasR;
    number rLsqrt, rRsqrt, alpha;
    int statusf;
    //
    // Calculate Constants
    // dtwspi = 1.0 / (2.0 * sqrt ( 3.14159265359 ));
    const double dtwspi = 0.282094792;
    // Unpack Left flow state.
    rhoL = Lft.gas.rho;
    presL = Lft.gas.p;
    eL = gmodel.internal_energy(Lft.gas);
    hL = eL + presL/rhoL;
    version(komega) { hL += Lft.turb[0]; } // bundle turbulent energy, PJ 2017-06-17
    tL = Lft.gas.T;
    vnL = Lft.vel.x;
    vpL = Lft.vel.y;
    vqL = Lft.vel.z;
    // Unpack Right flow state.
    rhoR = Rght.gas.rho;
    presR = Rght.gas.p;
    eR = gmodel.internal_energy(Rght.gas);
    hR = eR + presR/rhoR;
    version(komega) { hR += Rght.turb[0]; }
    tR = Rght.gas.T;
    vnR = Rght.vel.x;
    vpR = Rght.vel.y;
    vqR = Rght.vel.z;
    // Derive the gas "constants" from the local conditions.
    cvL = gmodel.Cv(Lft.gas);
    RgasL = presL / (rhoL * tL);
    cvR = gmodel.Cv(Rght.gas);
    RgasR = presR / (rhoR * tR);
    rLsqrt = sqrt(rhoL);
    rRsqrt = sqrt(rhoR);
    alpha = rLsqrt / (rLsqrt + rRsqrt);
    cv = alpha * cvL + (1.0 - alpha) * cvR;
    Rgas = alpha * RgasL + (1.0 - alpha) * RgasR;
    cp = cv + Rgas;
    gam = cp / cv;
    //
    // Start EFM calculation proper.
    con = 0.5 * (gam + 1.0) / (gam - 1.0);
    //
    rtL = Rgas * tL;
    cmpL = sqrt(2.0 * rtL);
    hvsqL = 0.5 * (vnL * vnL + vpL * vpL + vqL * vqL);
    snL = vnL / (PHI * cmpL);
    exxef(snL, exL, efL);
    wL = 0.5 * (1.0 + efL);
    dL = exL * dtwspi;
    //
    rtR = presR / rhoR;
    cmpR = sqrt(2.0 * rtR);
    hvsqR = 0.5 * (vnR * vnR + vpR * vpR + vqR * vqR);
    snR = vnR / (PHI * cmpR);
    exxef(snR, exR, efR);
    wR = 0.5 * (1.0 - efR);
    dR = -exR * dtwspi;
    //
    // Combine the fluxes.
    fmsL = (wL * rhoL * vnL) + (dL * cmpL * rhoL);
    fmsR = (wR * rhoR * vnR) + (dR * cmpR * rhoR);
    ConservedQuantities F = IFace.F;
    F.mass = fmsL + fmsR;
    F.momentum.set(fmsL*vnL + fmsR*vnR + wL*presL + wR*presR,
                   fmsL*vpL + fmsR*vpR,
                   fmsL*vqL + fmsR*vqR);
    F.total_energy = (wL * rhoL * vnL) * (hvsqL + hL) +
        (wR * rhoR * vnR) * (hvsqR + hR) +
        (dL * cmpL * rhoL) * (hvsqL + con * rtL) +
        (dR * cmpR * rhoR) * (hvsqR + con * rtR);
    // Species mass flux and individual energies.
    // Presently, this is implemented by assuming that
    // the wind is blowing one way or the other and then
    // picking the appropriate side for the species fractions.
    // Such an approach may not be fully compatible with the
    // EFM approach where there can be fluxes from both sides.
    if (F.mass > 0.0) {
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = F.mass * Lft.turb[i]; }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) { F.massf[i] = F.mass * Lft.gas.massf[i]; }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) { F.energies[i] = F.mass * Lft.gas.u_modes[i]; }
        }
        // NOTE: - the following relies on the free-electron mode being the last mode
        //       - for single temp models F_renergies isn't used
        //       - for multitemp modes with no free-electrons p_e is zero
        // Add electron pressure work term onto final energy mode
        // F.energies[$-1] += (F.mass) * Lft.gas.p_e / Lft.gas.rho; [TODO]
    } else {
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = F.mass * Rght.turb[i]; }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) { F.massf[i] = F.mass * Rght.gas.massf[i]; }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) { F.energies[i] = F.mass * Rght.gas.u_modes[i]; }
        }
    }
} // end efmflx()

@nogc
void exxef(number sn, ref number exx, ref number ef)
/** \brief Compute exp(-x**2) and erf(x) with a polynomial approximation.
 *
 * \param sn   : IN  : x
 * \param &exx : OUT : exp(x**2)
 * \param &ef  : OUT : erf(x)  error function
 */
{
    number snsq, ef1, y;
    //
    const double P = 0.327591100;
    const double A1 = 0.254829592;
    const double A2 = -0.284496736;
    const double A3 = 1.421413741;
    const double A4 = -1.453152027;
    const double A5 = 1.061405429;
    const double LIMIT = 5.0;
    const double EXLIM = 0.138879e-10;
    const double EFLIM = 1.0;
    //
    //#   define DSIGN(val,sgn) ( (sgn >= 0.0)? fabs(val): -fabs(val) )
    //
    if (fabs(sn) > LIMIT) {
        exx = EXLIM;
        ef1 = EFLIM;
    } else {
        snsq = sn * sn;
        exx = exp(-snsq);
        y = 1.0 / (1.0 + P * fabs(sn));
        ef1 = 1.0 - y * (A1 + y * (A2 + y * (A3 + y * (A4 + A5 * y)))) * exx;
    }
    ef = copysign(ef1, sn);
} // end exxef

@nogc
void adaptive_efm_ausmdv(in FlowState Lft, in FlowState Rght, ref FVInterface IFace, ref LocalConfig myConfig)
// This adaptive flux calculator uses uses the Equilibrium Flux Method
// near shocks and AUSMDV away from shocks, however, we really don't want
// EFM to be used across interfaces with strong shear.
// EFM should still be able to do it's work as we really needed it for the
// situations where the shock is closely aligned with the grid.
// In that situation, we don't expect a stong shear at the interface.
//
// The actual work is passed off to the original flux calculation functions.
{
    number sound_speed = 0.5 * (Lft.gas.a + Rght.gas.a);
    number shear_y = fabs(Lft.vel.y - Rght.vel.y) / sound_speed;
    number shear_z = fabs(Lft.vel.z - Rght.vel.z) / sound_speed;
    bool shear_is_small = fmax(shear_y, shear_z) <= myConfig.shear_tolerance;
    if ((Lft.S == 1 || Rght.S == 1) && shear_is_small) {
        efmflx(Lft, Rght, IFace, myConfig);
    } else {
        ausmdv(Lft, Rght, IFace, myConfig);
    }
} // end adaptive_flux()

@nogc
void adaptive_hanel_ausmdv(in FlowState Lft, in FlowState Rght, ref FVInterface IFace, ref LocalConfig myConfig)
// This adaptive flux calculator uses uses the Hanel flux calculator
// near shocks and AUSMDV away from shocks.
//
// The actual work is passed off to the original flux calculation functions.
{
    number sound_speed = 0.5 * (Lft.gas.a + Rght.gas.a);
    number shear_y = fabs(Lft.vel.y - Rght.vel.y) / sound_speed;
    number shear_z = fabs(Lft.vel.z - Rght.vel.z) / sound_speed;
    bool shear_is_small = fmax(shear_y, shear_z) <= myConfig.shear_tolerance;
    if ((Lft.S == 1 || Rght.S == 1) && shear_is_small) {
        hanel(Lft, Rght, IFace, myConfig);
    } else {
        ausmdv(Lft, Rght, IFace, myConfig);
    }
} // end adaptive_flux()

@nogc
void adaptive_hlle_roe(in FlowState Lft, in FlowState Rght, ref FVInterface IFace, ref LocalConfig myConfig)
// This adaptive flux calculator uses uses the HLLE flux calculator
// near shocks and Roe away from shocks.
//
// The actual work is passed off to the original flux calculation functions.
{
    number sound_speed = 0.5 * (Lft.gas.a + Rght.gas.a);
    number shear_y = fabs(Lft.vel.y - Rght.vel.y) / sound_speed;
    number shear_z = fabs(Lft.vel.z - Rght.vel.z) / sound_speed;
    bool shear_is_small = fmax(shear_y, shear_z) <= myConfig.shear_tolerance;
    if ((Lft.S == 1 || Rght.S == 1) && shear_is_small) {
        hlle(Lft, Rght, IFace, myConfig);
    } else {
        roe(Lft, Rght, IFace, myConfig);
    }
} // end adaptive_flux()

@nogc
void ausm_plus_up(in FlowState Lft, in FlowState Rght, ref FVInterface IFace,
                  double M_inf, ref LocalConfig myConfig)
// Liou's 2006 AUSM+up flux calculator
//
// A new version of the AUSM-family schemes, based 
// on the low Mach number asymptotic analysis.
// Ironically, this flux calculator causes simulations
// initialised with 0.0 m/s velocities to crash.
//
// RJG -- 26-Apr-2013
// Added a (+ EPSILON) to help with any divide by zero problems.
// That being said, I'm not sure this helps with the 
// crashes at zero velocity because it would seem that the flow
// of control would pass through a different branch for these cases.
//
// M. -S. Liou (2006)
// A sequel to AUSM, Part II: AUSM+-up for all speeds
// Journal of Computational Physics, Vol 214, pp 137-170
//
// This code: W. Y. K. Chan & P. A. Jacobs
{
    auto gmodel = myConfig.gmodel;
    // Some helper functions
    @nogc number M1plus(number M) { return 0.5*(M + fabs(M)); }
    @nogc number M1minus(number M) { return 0.5*(M - fabs(M)); }
    @nogc number M2plus(number M) { return 0.25*(M + 1.0)*(M + 1.0); }
    @nogc number M2minus(number M) { return -0.25*(M - 1.0)*(M - 1.0); } 
    @nogc number M4plus(number M, number beta) {
        if ( fabs(M) >= 1.0 ) {
            return M1plus(M);
        } else {
            number M2p = M2plus(M);
            number M2m = M2minus(M);
            return M2p*(1.0 - 16.0*beta*M2m);
        }
    }
    @nogc number M4minus(number M, number beta) {
        if ( fabs(M) >= 1.0 ) {
            return M1minus(M);
        } else {
            number M2p = M2plus(M);
            number M2m = M2minus(M);
            return M2m*(1.0 + 16.0*beta*M2p);
        }
    }
    @nogc number P5plus(number M, number alpha) {
        if ( fabs(M) >= 1.0 ) {
            return (1.0/M)*M1plus(M);
        } else {
            number M2p = M2plus(M);
            number M2m = M2minus(M);
            return M2p*((2.0 - M) - 16.0*alpha*M*M2m);
        }
    }
    @nogc number P5minus(number M, number alpha) {
        if ( fabs(M) >= 1.0 ) {
            return (1.0/M)*M1minus(M);
        } else {
            number M2p = M2plus(M);
            number M2m = M2minus(M);
            return M2m*((-2.0 - M) + 16.0*alpha*M*M2p);
        }
    }
    // Unpack the flow-state vectors for either side of the interface.
    // Store in work vectors, those quantities that will be neede later.
    number rL = Lft.gas.rho;
    number pL = Lft.gas.p;
    number uL = Lft.vel.x;
    number vL = Lft.vel.y;
    number wL = Lft.vel.z;
    number eL = gmodel.internal_energy(Lft.gas);
    number aL = Lft.gas.a;
    number keL = 0.5 * (uL * uL + vL * vL + wL * wL);
    number HL = eL + pL/rL + keL;
    version(komega) { HL += Lft.turb[0]; }
    //
    number rR = Rght.gas.rho;
    number pR = Rght.gas.p;
    number uR = Rght.vel.x;
    number vR = Rght.vel.y;
    number wR = Rght.vel.z;
    number eR = gmodel.internal_energy(Rght.gas);
    number aR = Rght.gas.a;
    number keR = 0.5 * (uR * uR + vR * vR + wR * wR);
    number HR = eR + pR/rR + keR;
    version(komega) { HR += Rght.turb[0]; }
    //
    // This is the main part of the flux calculator.
    //
    // Interface sound speed (eqns 28 & 30). 
    // An approximation is used instead of these equations as
    // suggested by Liou in his paper (see line below eqn 69).
    number a_half = 0.5 * (aR + aL);
    // Left and right state Mach numbers (eqn 69).
    number ML = uL / a_half;
    number MR = uR / a_half;
    // Mean local Mach number (eqn 70).
    number MbarSq = (uL*uL + uR*uR) / (2.0 * a_half *a_half);
    // Reference Mach number (eqn 71).
    number M0Sq = fmin(1.0, fmax(MbarSq, M_inf));
     // Some additional parameters.
    number fa = sqrt(M0Sq) * (2.0 - sqrt(M0Sq));   // eqn 72
    number alpha = 0.1875 * (-4.0 + 5 * fa * fa);  // eqn 76
    number beta = 0.125;                           // eqn 76
    // Left state: 
    // M4plus(ML)
    // P5plus(ML)
    number M4plus_ML = M4plus(ML, beta);
    number P5plus_ML = P5plus(ML, alpha);
    // Right state: 
    // M4minus(MR)
    // P5minus(MR)
    number M4minus_MR = M4minus(MR, beta);
    number P5minus_MR = P5minus(MR, alpha);
    // Pressure diffusion modification for 
    // mass flux (eqn 73) and pressure flux (eqn 75).
    const double KP = 0.25;
    const double KU = 0.75;
    const double SIGMA = 1.0;
    number r_half = 0.5*(rL + rR);
    number Mp = -KP / fa * fmax((1.0 - SIGMA * MbarSq), 0.0) * (pR - pL) / (r_half*a_half*a_half);
    number Pu = -KU * P5plus_ML * P5minus_MR * (rL + rR) * fa * a_half * (uR - uL);
    // Mass Flux (eqns 73 & 74).
    number M_half = M4plus_ML + M4minus_MR + Mp;
    number ru_half = a_half * M_half;
    if ( M_half > 0.0 ) {
       ru_half *= rL;
    } else {
       ru_half *= rR;
    }
    // Pressure flux (eqn 75).
    number p_half = P5plus_ML*pL + P5minus_MR*pR + Pu;
    // Momentum flux: normal direction
    number ru2_half;
    if (ru_half >= 0.0) {
        ru2_half = ru_half * uL;
    } else {
        ru2_half = ru_half * uR;
    }
    // Assemble components of the flux vector.
    ConservedQuantities F = IFace.F;
    F.mass = ru_half;
    if (ru_half >= 0.0) {
        // Wind is blowing from the left.
        F.momentum.set(ru2_half+p_half, ru_half*vL, ru_half*wL);
        F.total_energy = ru_half * HL;
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = ru_half * Lft.turb[i]; }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) { F.massf[i] = ru_half * Lft.gas.massf[i]; }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) { F.energies[i] = ru_half * Lft.gas.u_modes[i]; }
        }
        // NOTE: - the following relies on the free-electron mode being the last mode
        //       - for single temp models F_renergies isn't used
        //       - for multitemp modes with no free-electrons p_e is zero
        // Add electron pressure work term onto final energy mode
        // F.energies[nmodes-1] += ru_half * Lft.gas.p_e / Lft.gas.rho;
    } else {
        // Wind is blowing from the right.
        F.momentum.set(ru2_half+p_half, ru_half*vR, ru_half*wR);
        F.total_energy = ru_half * HR;
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = ru_half * Rght.turb[i]; }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) { F.massf[i] = ru_half * Rght.gas.massf[i]; }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) { F.energies[i] = ru_half * Rght.gas.u_modes[i]; }
        }
    }
} // end ausm_plus_up()

@nogc
void hlle(in FlowState Lft, in FlowState Rght, ref FVInterface IFace, ref LocalConfig myConfig)
// HLLE fluxes for MHD.
// From V. Wheatley Matlab implementation
// Author D. M. Bond
// Port to D by PJ, 2014-07-24
{
    auto gmodel = myConfig.gmodel;
    @nogc number SAFESQRT(number x) { return (fabs(x)>1.0e-14) ? sqrt(x) : to!number(0.0); }
    // Unpack the flow-state vectors for either side of the interface.
    // Store in work vectors, those quantities that will be neede later.
    number rL = Lft.gas.rho;
    number pL = Lft.gas.p;
    number uL = Lft.vel.x;
    number vL = Lft.vel.y;
    number wL = Lft.vel.z;
    version(MHD) {
        number BxL = Lft.B.x;
        number ByL = Lft.B.y;
        number BzL = Lft.B.z;
    }
    number rR = Rght.gas.rho;
    number pR = Rght.gas.p;
    number uR = Rght.vel.x;
    number vR = Rght.vel.y;
    number wR = Rght.vel.z;
    version(MHD) {
        number BxR = Rght.B.x;
        number ByR = Rght.B.y;
        number BzR = Rght.B.z;
    }
    //
    // Derive the gas "constants" from the local conditions.
    number cvL = gmodel.Cv(Lft.gas);
    number RgasL = gmodel.R(Lft.gas);
    number cvR = gmodel.Cv(Rght.gas);
    number RgasR = gmodel.R(Rght.gas);
    number rLsqrt = sqrt(rL);
    number rRsqrt = sqrt(rR);
    number alpha = rLsqrt / (rLsqrt + rRsqrt);
    number cv = alpha * cvL + (1.0 - alpha) * cvR;
    number Rgas = alpha * RgasL + (1.0 - alpha) * RgasR;
    number cp = cv + Rgas;
    number gam = cp / cv;
    //
    // Compute Roe Average State (currently simple average)
    number rho = 0.5*(rL+rR);
    number p   = 0.5*(pL+pR);
    number u   = 0.5*(uL+uR);
    //v   = 0.5*(vL+vR);
    //w   = 0.5*(wL+wR);
    version(MHD) {
        number Bx  = 0.5*(BxL+BxR);
        number By  = 0.5*(ByL+ByR);
        number Bz  = 0.5*(BzL+BzR);
    }
    //
    // Compute Eigenvalues of Roe Matrix
    //u2=u*u;
    //v2=v*v;
    //w2=w*w;
    //uu=u2+v2+w2;
    version(MHD) {
        number a2 = gam*p/rho;
        number Bx2 = Bx*Bx;
        number Bt2 = By*By + Bz*Bz;
        number BB = Bx2 + Bt2;
        number ca2 = Bx2/rho;
        number alf = a2+BB/rho;
        number als = SAFESQRT(alf*alf-4.0*a2*ca2);
        number cf2 = 0.5*(alf+als);
        number cf = sqrt(cf2);
        number wp = u+cf;
        number wm = u-cf;
        //
        // Compute the Jump in Conserved Variables between L and R
        number BxL2 = BxL*BxL;
        number BtL2 = ByL*ByL + BzL*BzL;
        number BBL = BxL2 + BtL2;
        number ptL = pL + 0.5*BBL;
        number uL2 = uL*uL;
        number uuL = uL2 + vL*vL + wL*wL;
        number aL2 = gam*pL/rL;
        number caL2 = BxL2/rL;
        number alfL = aL2+BBL/rL;
        number alsL = SAFESQRT(alfL*alfL-4.0*aL2*caL2);
        number cfL2 = 0.5*(alfL+alsL);
        number cfL = sqrt(cfL2);
        //wpL = uL+cfL;
        number wmL = uL-cfL;
        number BxR2 = BxR*BxR;
        number BtR2 = ByR*ByR + BzR*BzR;
        number BBR = BxR2 + BtR2;
        number ptR = pR + 0.5*BBR;
        number uR2 = uR*uR;
        number uuR = uR2 + vR*vR + wR*wR;
        number aR2 = gam*pR/rR;
        number caR2 = BxR2/rR;
        number alfR = aR2+BBR/rR;
        number alsR = SAFESQRT(alfR*alfR-4.0*aR2*caR2);
        number cfR2 = 0.5*(alfR+alsR);
        number cfR = sqrt(cfR2);
        number wpR = uR+cfR;
        //wmR = uR-cfR;

        number[8] dU;
        dU[0] = rR - rL;
        dU[1] = rR*uR - rL*uL;
        dU[2] = rR*vR - rL*vL;
        dU[3] = rR*wR - rL*wL;
        dU[4] = BxR - BxL;
        dU[5] = ByR - ByL;
        dU[6] = BzR - BzL;
        dU[7] = (pR - pL)/(gam-1.0) + 0.5*(rR*uuR+BBR) - 0.5*(rL*uuL+BBL);
        //
        number bl = fmin(wmL, wm);
        number br = fmax(wpR, wp);
        number blm = fmin(bl, 0.0);
        number brp = fmax(br, 0.0);
        number fmassL = rL*uL;
        number fmassR = rR*uR;
        number fmomxL = rL*uL2 - BxL2 + ptL;
        number fmomxR = rR*uR2 - BxR2 + ptR;
        number fmomyL = rL*uL*vL - BxL*ByL;
        number fmomyR = rR*uR*vR - BxR*ByR;
        number fmomzL = rL*uL*wL - BxL*BzL;
        number fmomzR = rR*uR*wR - BxR*BzR;
        number fBxL = 0.0;
        number fBxR = 0.0;
        number fByL = uL*ByL - vL*BxL;
        number fByR = uR*ByR - vR*BxR;
        number fBzL = uL*BzL - wL*BxL;
        number fBzR = uR*BzR - wR*BxR;
        number fenergyL = (pL/(gam-1.0)+0.5*(rL*uuL+BBL)+ptL)*uL - (uL*BxL+vL*ByL+wL*BzL)*BxL;
        number fenergyR = (pR/(gam-1.0)+0.5*(rR*uuR+BBR)+ptR)*uR - (uR*BxR+vR*ByR+wR*BzR)*BxR;
        number iden = 1.0/(brp - blm);
        number fac1 = brp*blm;
        //
        ConservedQuantities F = IFace.F;
        F.mass = (brp*fmassL - blm*fmassR + fac1*dU[0])*iden;
        F.momentum.set((brp*fmomxL - blm*fmomxR + fac1*dU[1])*iden,
                       (brp*fmomyL - blm*fmomyR + fac1*dU[2])*iden,
                       (brp*fmomzL - blm*fmomzR + fac1*dU[3])*iden);
        F.B.set((brp*fBxL - blm*fBxR + fac1*dU[4])*iden,
                (brp*fByL - blm*fByR + fac1*dU[5])*iden,
                (brp*fBzL - blm*fBzR + fac1*dU[6])*iden);
        F.total_energy = (brp*fenergyL - blm*fenergyR + fac1*dU[7])*iden;
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) {
                F.massf[i] = F.mass * ((F.mass >= 0.0) ? Lft.gas.massf[i]: Rght.gas.massf[i]);
            }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) {
                F.energies[i] = F.mass * ((F.mass >= 0.0) ? Lft.gas.u_modes[i]: Rght.gas.u_modes[i]);
            }
        }
    } else {
        assert(0, "HLLE not implemented for normal gas dynamics");
    }
} // end hlle()

@nogc
void roe(in FlowState Lft, in FlowState Rght, ref FVInterface IFace, ref LocalConfig myConfig)
// Philip Roe's flux calculator with entropy fix.
// 
// Particular implementation is the Roe-Pike Method from
// E. F. Toro (2009)
// Riemann Solvers and Numerical Methods for Fluid Dynamics, pg. 366.
// with entropy fix from
// M. J. Kermani & E. G. Plett (2001)
// Modified Entropy Correction Formula for the Roe Scheme
{
    auto gmodel = myConfig.gmodel;
    // Unpack the flow-state vectors for either side of the interface.
    // Store in work vectors, those quantities that will be neede later.
    number rL = Lft.gas.rho;
    number pL = Lft.gas.p;
    number pLrL = pL / rL;
    number uL = Lft.vel.x;
    number vL = Lft.vel.y;
    number wL = Lft.vel.z;
    number eL = gmodel.internal_energy(Lft.gas);
    number aL = Lft.gas.a;
    number keL = 0.5*(uL*uL + vL*vL + wL*wL);
    number HL = eL + pLrL + keL;
    version(komega) { HL += Lft.turb[0]; }
    //
    number rR = Rght.gas.rho;
    number pR = Rght.gas.p;
    number pRrR = pR / rR;
    number uR = Rght.vel.x;
    number vR = Rght.vel.y;
    number wR = Rght.vel.z;
    number eR = gmodel.internal_energy(Rght.gas);
    number aR = Rght.gas.a;
    number keR = 0.5*(uR*uR + vR*vR + wR*wR);
    number HR = eR + pRrR + keR;
    version(komega) { HR += Rght.turb[0]; }

    // averaged gamma
    number gL = gmodel.gamma(Lft.gas);
    number gR = gmodel.gamma(Rght.gas);
    number ghat = (gR+gL)/2.0;
    
    // intermediate state (eq. 11.118)
    number rhat = sqrt(rL*rR);
    number uhat = (sqrt(rL)*uL+sqrt(rR)*uR) / (sqrt(rL) + sqrt(rR));
    number vhat = (sqrt(rL)*vL+sqrt(rR)*vR) / (sqrt(rL) + sqrt(rR));
    number what = (sqrt(rL)*wL+sqrt(rR)*wR) / (sqrt(rL) + sqrt(rR));
    number Hhat = (sqrt(rL)*HL+sqrt(rR)*HR) / (sqrt(rL) + sqrt(rR));
    number ahat2 = (ghat-1.0)*(Hhat-0.5*(uhat*uhat+vhat*vhat+what*what));
    number ahat = sqrt(ahat2);
    
    // eigenvalues at intermediate state (eq. 11.107)
    number[5] lambda;
    lambda[0] = uhat - ahat;
    lambda[1] = uhat;
    lambda[2] = uhat;
    lambda[3] = uhat;
    lambda[4] = uhat + ahat;

    // Apply entropy fix to eigenvalues (eq. 11 with EPS2 from the Kermani & Plett paper)
    number lambdaL = uL-aL;
    number lambdaR = uR-aR;
    double eps = 1.0e-12;
    number EPS = 4.0*fmax(0.0, (lambdaR - lambdaL));
    // only change lambda[0] & lambda[4] (as per bottom of pg. 367)
    if (fabs(lambda[0]) < EPS) lambda[0] = (lambda[0]*lambda[0]+EPS*EPS)/(2.0*EPS + eps);
    if (fabs(lambda[4]) < EPS) lambda[4] = (lambda[4]*lambda[4]+EPS*EPS)/(2.0*EPS + eps); 
      
    // eigenvectors at intermediate state (eq. 11.108)
    number[5][5] K;
    K[0][0] = 1.0;
    K[0][1] = uhat-ahat;
    K[0][2] = vhat;
    K[0][3] = what;
    K[0][4] = Hhat-uhat*ahat;

    K[1][0] = 1.0;
    K[1][1] = uhat;
    K[1][2] = vhat;
    K[1][3] = what;
    K[1][4] = 0.5*(uhat*uhat+vhat*vhat+what*what);

    K[2][0] = 0.0;
    K[2][1] = 0.0;
    K[2][2] = 1.0;
    K[2][3] = 0.0;
    K[2][4] = vhat;
    
    K[3][0] = 0.0;
    K[3][1] = 0.0;
    K[3][2] = 0.0;
    K[3][3] = 1.0;
    K[3][4] = what;

    K[4][0] = 1.0;
    K[4][1] = uhat+ahat;
    K[4][2] = vhat;
    K[4][3] = what;
    K[4][4] = Hhat+uhat*ahat;

    // wave strengths at intermediate state (eq. 11.113)
    number[5] alpha;
    alpha[0] = 1.0/(2.0 * ahat2) * ( (pR-pL) - rhat*ahat*(uR-uL) );
    alpha[1] = (rR-rL) - (pR-pL)/ahat2;
    alpha[2] = rhat*(vR-vL);
    alpha[3] = rhat*(wR-wL);
    alpha[4] = 1.0/(2.0 * ahat2) * ( (pR-pL) + rhat*ahat*(uR-uL) );
    
    // compute fluxes (eq. 11.29)
    ConservedQuantities F = IFace.F;

    number FL; number FR;

    // mass flux
    FL = rL*uL;
    FR = rR*uR;
    F.mass = 0.5*(FL+FR);
    foreach ( i; 0..5 ) F.mass -= 0.5*alpha[i]*fabs(lambda[i])*K[i][0];

    // x-momentum flux;
    FL = pL+rL*uL*uL;
    FR = pR+rR*uR*uR;
    F.momentum.refx = 0.5*(FL+FR);
    foreach ( i; 0..5) F.momentum.refx -= 0.5*alpha[i]*fabs(lambda[i])*K[i][1];

    // y-momentum flux;
    FL = rL*uL*vL;
    FR = rR*uR*vR;
    F.momentum.refy = 0.5*(FL+FR);
    foreach ( i; 0..5) F.momentum.refy -= 0.5*alpha[i]*fabs(lambda[i])*K[i][2];

    // z-momentum flux;
    FL = rL*uL*wL;
    FR = rR*uR*wR;
    F.momentum.refz = 0.5*(FL+FR);
    foreach ( i; 0..5) F.momentum.refz -= 0.5*alpha[i]*fabs(lambda[i])*K[i][3];

    // total energy flux
    FL = (rL*eL + rL*(uL*uL+vL*vL+wL*wL)/2.0 + pL)*uL;
    FR = (rR*eR + rR*(uR*uR+vR*vR+wR*wR)/2.0 + pR)*uR;
    F.total_energy = 0.5*(FL+FR);
    foreach ( i; 0..5) F.total_energy -= 0.5*alpha[i]*fabs(lambda[i])*K[i][4];

    // remaining fluxes
    if (F.mass >= 0.0) {
        /* Wind is blowing from the left */
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = F.mass*Lft.turb[i]; }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) { F.massf[i] = F.mass*Lft.gas.massf[i]; }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) { F.energies[i] = F.mass*Lft.gas.u_modes[i]; }
        }
    } else {
        /* Wind is blowing from the right */
        version(komega) {
            foreach(i; 0 .. F.rhoturb.length) { F.rhoturb[i] = F.mass*Rght.turb[i]; }
        }
        version(multi_species_gas) {
            uint nsp = (myConfig.sticky_electrons) ? myConfig.n_heavy : myConfig.n_species;
            foreach (i; 0 .. nsp) { F.massf[i] = F.mass*Rght.gas.massf[i]; }
        }
        version(multi_T_gas) {
            foreach (i; 0 .. F.energies.length) { F.energies[i] = F.mass*Rght.gas.u_modes[i]; }
        }
    }
} // end roe()

@nogc
void ASF_242(FlowState[] stencil, ref FVInterface IFace, ref LocalConfig myConfig) {
    // Start by substracting interface velocities and transforming to local frame; it is unlikely we will be using moving grids with this solver, but harm in including this.

    auto gmodel = myConfig.gmodel;
    ConservedQuantities F = IFace.F;
    foreach (cell; stencil) {

        cell.vel.refx -= IFace.gvel.x;
        cell.vel.refy -= IFace.gvel.y;
        cell.vel.refz -= IFace.gvel.z;

        cell.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
    }

    // Define the v,w functions as prescribed by White et al. 2012 for the simple convective fluxes

    number[4][10] v, w; 

    foreach (i, cell; stencil) {
        v[0][i] = cell.gas.rho;
        w[0][i] = cell.vel.x;
        v[1][i] = cell.vel.x * cell.gas.rho;
        w[1][i] = cell.vel.x;
        v[2][i] = cell.vel.y * cell.gas.rho;
        w[2][i] = cell.vel.x;
        v[3][i] = cell.vel.z * cell.gas.rho;
        w[3][i] = cell.vel.x;
        v[4][i] = gmodel.internal_energy(cell.gas) * cell.gas.rho;
        w[4][i] = cell.vel.x;
        v[5][i] = cell.vel.x * cell.vel.x * cell.gas.rho;
        w[5][i] = cell.vel.x;
        v[6][i] = cell.vel.y * cell.vel.y * cell.gas.rho;
        w[6][i] = cell.vel.x;
        v[7][i] = cell.vel.z * cell.vel.z * cell.gas.rho;
        w[7][i] = cell.vel.x;
        v[8][i] = cell.gas.p;
        w[8][i] = cell.vel.x;
        v[9][i] = cell.gas.p;
        w[9][i] = 1;
    }

    // Prepare the conservative and product rule fluxes arrays
    number[10] f_c, f_e;

    // Calculate conservative and product rule fluxes
    foreach (i ; 0 .. 10) {
        f_c[i] = (1.0 / 12.0) * (-v[i][0] * w[i][0] + 7.0 * v[i][1] * w[i][1] + 7.0 * v[i][2] * w[i][2] - v[i][3] * w[i][3]);

        f_e[i] = (1.0 / 12.0) * (-v[i][0] * w[i][2] - v[i][2] * w[i][0] + 8 * v[i][1] * w[i][2] + 8 * v[i][2] * w[i][1] - v[i][1] * w[i][3] - v[i][3] * w[i][1]);
    }

    // Define the splitting values as per White et al, in the conservative skew-symmetric form of Honein and Moin.
    number alpha_mass = 1.0, alpha_mom = 0.5, alpha_ie = 0.5, alpha_ke = 0.0, alpha_p = 0.0;

    // Calculate the final flux values of the simple quantities mass, momentum and energy
    F.mass = (alpha_mass * f_c[0] + (1.0 - alpha_mass) * f_e[0]);
    F.momentum.set((alpha_mom * f_c[1] + (1.0 - alpha_mom) * f_e[1]) + (alpha_p * f_c[9] + (1.0 - alpha_p) * f_e[9]),
           (alpha_mom * f_c[2] + (1.0 - alpha_mom) * f_e[2]), (alpha_mom * f_c[3] + (1.0 - alpha_mom) * f_e[3]));

    F.total_energy = (alpha_ie * f_c[4] + (1.0 - alpha_ie) * f_e[4] + (1.0 / 2.0) * (alpha_ke * f_c[5] + (1.0 - alpha_ke) * f_e[5] + alpha_ke * f_c[6] +
           (1.0 - alpha_ke) * f_e[6] + alpha_ke * f_c[7] + (1.0 - alpha_ke) * f_e[7]) + alpha_p * f_c[8] + (1.0 - alpha_p) * f_e[8]);

    // Bit of a placeholder for multi_species_gas
    F.massf[0] = F.mass;

    // Account for interface movement- probably shouldn't happen in this but check it anyway
    // Total energy flux due to interface movement
    number v_sqr = IFace.gvel.x*IFace.gvel.x + IFace.gvel.y*IFace.gvel.y + IFace.gvel.z*IFace.gvel.z; 
    F.total_energy += 0.5 * F.mass * v_sqr + F.momentum.dot(IFace.gvel);
    // Flux of momentum: Add component for interface velocity then
    // rotate back to the global frame of reference.
    Vector3 momentum_increment;
    momentum_increment.set(IFace.gvel); momentum_increment *= F.mass;
    F.momentum += momentum_increment;
    F.momentum.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    // Also, transform the interface (grid) velocity and magnetic field.
    IFace.gvel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);

    // Transform back to the global frame
    foreach (cell; stencil) {
        cell.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
    }
}
