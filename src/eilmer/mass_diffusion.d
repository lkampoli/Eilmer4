/**
 * mass_diffusion.d
 *
 * This module houses the models for mass diffusion
 * that can be coupled to the flow solver.
 *
 * Authors: Rowan G. and Peter J.
 * Version: 2017-06-06, first cut
 *
 */
module mass_diffusion;

import std.math;
import std.stdio;
import std.conv;
import std.string;

import nm.complex;
import nm.number;
import util.lua;
import gas;

import globalconfig;
import flowstate;
import flowgradients;
import fvcore;

private immutable double SMALL_DIFFUSION_COEFFICIENT = 1.0e-20;

enum MassDiffusionModel { none, ficks_first_law }

@nogc
string massDiffusionModelName(MassDiffusionModel i)
{
    final switch (i) {
    case MassDiffusionModel.none: return "none";
    case MassDiffusionModel.ficks_first_law: return "ficks_first_law";
    }
}

@nogc
MassDiffusionModel massDiffusionModelFromName(string name)
{
    switch (name) {
    case "none": return MassDiffusionModel.none;
    case "ficks_first_law": return MassDiffusionModel.ficks_first_law;
    default: return MassDiffusionModel.none;
    }
}

interface MassDiffusion {
    @nogc
    void update_mass_fluxes(FlowState fs, const FlowGradients grad,
                            number[] jx, number[] jy, number[] jz);
}

MassDiffusion initMassDiffusion(GasModel gmodel,
                                bool sticky_electrons,
                                MassDiffusionModel mass_diffusion_model,
                                bool withConstantLewisNumber,
                                double Lewis,
                                bool withSpeciesSpecificLewisNumbers)
{
    switch (mass_diffusion_model) {
    case MassDiffusionModel.ficks_first_law:
        return new FicksFirstLaw(gmodel, sticky_electrons, true, withConstantLewisNumber,
                                 Lewis, withSpeciesSpecificLewisNumbers);
    default:
        throw new FlowSolverException("Selected mass diffusion model is not available.");
    }
}

class FicksFirstLaw : MassDiffusion {
    this(GasModel gmodel,
         bool sticky_electrons,
         bool withMassFluxCorrection=true,
         bool withConstantLewisNumber=false,
         double Lewis=1.0,
         bool withSpeciesSpecificLewisNumbers=false)
    {
        _withMassFluxCorrection = withMassFluxCorrection;
        _withConstantLewisNumber = withConstantLewisNumber;
        _withSpeciesSpecificLewisNumbers = withSpeciesSpecificLewisNumbers;
        _Le = Lewis;
        
        _gmodel = gmodel;
        _nsp = (sticky_electrons) ? gmodel.n_heavy : gmodel.n_species;
        
        _sigma.length = _nsp;
        _eps.length = _nsp;
        _LeS.length = _nsp;
        _D.length = _nsp;
        _M.length = _nsp;
        foreach (isp; 0 .. _nsp) {
            _sigma[isp].length = _nsp;
            _eps[isp].length = _nsp;
            _D[isp].length = _nsp;
            _M[isp].length = _nsp;
        }
        _D_avg.length = _nsp;
        _molef.length = _nsp;

        // Compute M_ij terms
        foreach (isp; 0 .. _nsp) {
            foreach (jsp; 0 .. _nsp) {
                if (isp == jsp) continue;
                _M[isp][jsp] = 1.0/gmodel.mol_masses[isp] + 1.0/gmodel.mol_masses[jsp];
                _M[isp][jsp] = 2.0/_M[isp][jsp];
                _M[isp][jsp] *= 1.0e3; // from kg/mol to g/mol
            }
        }
        if (!withConstantLewisNumber) { 
            if (withSpeciesSpecificLewisNumbers) {
                foreach (isp; 0 .. _nsp) {
                    _LeS[isp] = gmodel.Le[isp];
                }
            }
            else {
                // Compute sigma_ij terms
                foreach (isp; 0 .. _nsp) {
                    foreach (jsp; 0 .. _nsp) {
                        if (isp == jsp) continue;
                        _sigma[isp][jsp] = 0.5*(gmodel.LJ_sigmas[isp] + gmodel.LJ_sigmas[jsp]);
                    }
                }
                // Compute eps_ij terms
                foreach (isp; 0 .. _nsp) {
                    foreach (jsp; 0 .. _nsp) {
                        if (isp == jsp) continue;
                        _eps[isp][jsp] = sqrt(gmodel.LJ_epsilons[isp] * gmodel.LJ_epsilons[jsp]);
                    }
                }
            }
        }
    }

    @nogc
    void update_mass_fluxes(FlowState fs, const FlowGradients grad,
                            number[] jx, number[] jy, number[] jz)
    {
        version(multi_species_gas) {
            _gmodel.massf2molef(fs.gas, _molef);
            if (_withConstantLewisNumber) {
                number Cp = _gmodel.Cp(fs.gas);
                number alpha = fs.gas.k/(fs.gas.rho*Cp);
                foreach (isp; 0 .. _nsp) _D_avg[isp] = alpha/_Le;
            }
            else {
                if (!_withSpeciesSpecificLewisNumbers)
                    computeBinaryDiffCoeffs(fs.gas.T, fs.gas.p);
                computeAvgDiffCoeffs(fs.gas);
            }
            foreach (isp; 0 .. _nsp) {
                jx[isp] = -fs.gas.rho * _D_avg[isp] * grad.massf[isp][0];
                jy[isp] = -fs.gas.rho * _D_avg[isp] * grad.massf[isp][1];
                jz[isp] = -fs.gas.rho * _D_avg[isp] * grad.massf[isp][2];
            }
            if (_withMassFluxCorrection) {
                // Correction as suggested by Sutton and Gnoffo, 1998  
                number sum_x = 0.0;
                number sum_y = 0.0;
                number sum_z = 0.0;
                foreach (isp; 0 .. _nsp) {
                    sum_x += jx[isp];
                    sum_y += jy[isp];
                    sum_z += jz[isp];
                }
                foreach (isp; 0 .. _nsp) {
                    jx[isp] = jx[isp] - fs.gas.massf[isp] * sum_x;
                    jy[isp] = jy[isp] - fs.gas.massf[isp] * sum_y;
                    jz[isp] = jz[isp] - fs.gas.massf[isp] * sum_z;
                }
            }
        } else {
            // this function is gitless for single-species gas
        }
    } // end update_mass_fluxes()

private:
    GasModel _gmodel;
    size_t _nsp;
    bool _withMassFluxCorrection;
    bool _withConstantLewisNumber;
    bool _withSpeciesSpecificLewisNumbers;
    double _Le = 1.0;
    number[][] _sigma;
    number[][] _eps;
    number[][] _D;
    number[][] _M;
    double[] _LeS;
    number[] _D_avg;
    number[] _molef;
    // coefficients for diffusion collision integral calculation
    double _a = 1.06036;
    double _b = 0.15610;
    double _c = 0.19300;
    double _d = 0.47635;
    double _e = 1.03587;
    double _f = 1.52996;
    double _g = 1.76474;
    double _h = 3.89411;

    @nogc
    void computeBinaryDiffCoeffs(number T, number p)
    {
        // Expression from:
        // Reid et al.
        // The Properties of Gases and Liquids
        
        // This loop is inefficient. We only need to go up to
        // from jsp = isp+1...
        // Needs some thought. We're doing redundant work.
        // RJG, 2018-09-11

        foreach (isp; 0 .. _nsp) {
            foreach (jsp; 0 .. _nsp) {
                if (isp == jsp) continue;
                number T_star = T/_eps[isp][jsp];
                number omega = _a/(pow(T_star, _b));
                omega += _c/(exp(_d*T_star));
                omega += _e/(exp(_f*T_star));
                omega += _g/(exp(_h*T_star));

                // PJ 2018-08-18 write the calculation differently
                number denom = p/P_atm;
                denom *= sqrt(_M[isp][jsp]);
                denom *= _sigma[isp][jsp]*_sigma[isp][jsp];
                denom *= omega;
                number numer = 0.00266*sqrt(T*T*T);
                numer *= 1.0e-4; // cm^2/s --> m^2/s
                _D[isp][jsp] = numer/denom;
            }
        }
    }

    @nogc
    void computeAvgDiffCoeffs(GasState Q)
    {
        if(_withSpeciesSpecificLewisNumbers) {
            _gmodel.update_trans_coeffs(Q);
            number Prandtl = _gmodel.Prandtl(Q);
            foreach (isp; 0 .. _nsp) {
                _D_avg[isp] = Q.mu / (Q.rho * Prandtl * _LeS[isp]); 
            }
        }
        else {
            foreach (isp; 0 .. _nsp) {
                number sum = 0.0;
                foreach (jsp; 0 .. _nsp) {
                    if (isp == jsp) continue;
                    // The following two if-statements should generally catch the
                    // same flow condition, namely, a zero or very small presence of
                    // a certain species.  In this case the diffusion is effectively
                    // zero and its contribution to the mixture diffusion coefficient
                    // may be ignored.
                    //
                    // The two statements are used for extra security in detecting the
                    // condition.
                    if (_D[isp][jsp] < SMALL_DIFFUSION_COEFFICIENT ) continue;  // there is effectively nothing to diffuse
                    if (_molef[jsp] < SMALL_MOLE_FRACTION ) continue; // there is effectively nothing to diffuse
                    sum += _molef[jsp] / _D[isp][jsp];
                }
                if (sum <= 0.0) {
                    _D_avg[isp] = 0.0;
                }
                else {
                    _D_avg[isp] = (1.0 - _molef[isp])/sum;
                }
            }
        }
    }
}

// This lua wrapper is somewhat fragile.
// It works presently (2018-09-11) because there
// is only one type of mass diffusion model available.
// This will need a re-work if it has wider utility.

extern(C) int luafn_computeBinaryDiffCoeffs(lua_State *L)
{
    auto gmodel = GlobalConfig.gmodel_master;
    auto n_species = (GlobalConfig.sticky_electrons) ? gmodel.n_heavy : gmodel.n_species;
    // Expect temperature, pressure, and a table to push values into.
    auto T = to!number(luaL_checknumber(L, 1));
    auto p = to!number(luaL_checknumber(L, 2));

    auto mdmodel = cast(FicksFirstLaw) GlobalConfig.massDiffusion;
    mdmodel.computeBinaryDiffCoeffs(T, p);

    foreach (isp; 0 .. n_species) {
        lua_rawgeti(L, 3, isp);
        foreach (jsp; 0 .. n_species) {
            if (isp != jsp) {
                lua_pushnumber(L, mdmodel._D[isp][jsp]);
            }
            else {
                lua_pushnumber(L, 0.0);
            }
            lua_rawseti(L, -2, jsp);
        }
        lua_pop(L, 1);
    }
    return 0;
}


