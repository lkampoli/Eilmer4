/**
 * vib_specific_nitrogen.d
 * Authors: Rowan G., Katrina Sklavos and Peter J.
 *
 * This is a 10-level vibrationally-specific model for nitrogen
 * as descrbied in:
 *
 * Giordano, et al. (1997)
 * Vibrationally Relaxing Flow of N2 past an Infinite Cylinder
 * Journal of Thermophysics and Heat Transfer, vol 11, no 1, pp 27 - 35
 *
 */

module gas.vib_specific_nitrogen;

import std.algorithm.iteration;
import std.math;
import std.stdio;
import std.string;
import std.file;
import std.json;
import std.conv;
import util.lua;
import util.lua_service;
import core.stdc.stdlib : exit;

import nm.complex;
import nm.number;

import gas.gas_model;
import gas.gas_state;
import gas.physical_constants;
import gas.diffusion.viscosity;
import gas.diffusion.therm_cond;

immutable int numVibLevels = 10;

class VibSpecificNitrogen: GasModel {
public:
    double _R_N2 = 296.805; // gas constant for N2
    double _M_N2 = 0.0280134; // kg/mole
    double _gamma = 7./5.; // ratio of specific heats for vibrationally-frozen gas.
    double kB = Boltzmann_constant;
    double[numVibLevels] _vib_energy;
    double[numVibLevels] _vib_energy_perkg;

    this()
    {
        // In this model the nitrogen molecules with differing vibrational levels
        // are considered pseudo-chemical-species.
        _n_species = numVibLevels;
        _n_modes = 0;
        _species_names.length = _n_species;
        foreach (isp; 0 .. _n_species) {
            _species_names[isp] = format("N2-vib-%d", isp);
        }
        create_species_reverse_lookup();
        // The energy levels of the individual vibration modes
        // are constant, once computed.
        foreach (i; 0 .. numVibLevels) {
            _vib_energy[i] = vib_energy(i);
            _vib_energy_perkg[i]= (Avogadro_number/_M_N2) * _vib_energy[i];
        }
    } // end constructor

    override string toString() const
    {
        char[] repr;
        repr ~= "VibSpecificNitrogen=()";
        return to!string(repr);
    }

    override void update_thermo_from_pT(GasState Q) const 
    {
        Q.rho = Q.p / (_R_N2*Q.T);
        // For full internal energy, start with trans-rotational mode
        // and then add vibrational modes.
        Q.u = 2.5 * _R_N2 * Q.T;
        foreach (i; 0 .. numVibLevels) { Q.u += Q.massf[i]*_vib_energy_perkg[i]; }
    }
    override void update_thermo_from_rhou(GasState Q) const
    {
        // Separate out vibrational energy before computing trans-rotational temperature.
        number u = Q.u;
        foreach (i; 0 .. numVibLevels) { u -= Q.massf[i]*_vib_energy_perkg[i]; }
        Q.T = (0.4/_R_N2) * u;
        Q.p = Q.rho * _R_N2 * Q.T;
    }
    override void update_thermo_from_rhoT(GasState Q) const
    {
        Q.p = Q.rho * _R_N2 * Q.T;
        Q.u = 2.5 * _R_N2 * Q.T; // trans-rotational component
        foreach (i; 0 .. numVibLevels) { Q.u += Q.massf[i]*_vib_energy_perkg[i]; }
    }
    override void update_thermo_from_rhop(GasState Q) const
    {
        Q.T = Q.p / (Q.rho * _R_N2);
        Q.u = 2.5 * _R_N2 * Q.T;
        foreach (i; 0 .. numVibLevels) { Q.u += Q.massf[i]*_vib_energy_perkg[i]; }
    }
    override void update_thermo_from_ps(GasState Q, number s) const
    {
        throw new Error("ERROR: VibSpecificNitrogen:update_thermo_from_ps NOT IMPLEMENTED.");
    }
    override void update_thermo_from_hs(GasState Q, number h, number s) const
    {
        throw new Error("ERROR: VibSpecificNitrogen:update_thermo_from_hs NOT IMPLEMENTED.");
    }
    override void update_sound_speed(GasState Q) const
    {
        Q.a = sqrt(_gamma * _R_N2 * Q.T); 
    }
    override void update_trans_coeffs(GasState Q)
    {
        // The gas is inviscid.
        // [TODO] Add nitrogen model.
        Q.mu = 0.0;
        Q.k = 0.0;
    }
    override number dudT_const_v(in GasState Q) const
    {
        return to!number(_R_N2/(_gamma - 1.0));
    }
    override number dhdT_const_p(in GasState Q) const
    {
        throw new Error("ERROR: VibSpecificNitrogen:dhdT_const_p NOT IMPLEMENTED.");
    }
    override number dpdrho_const_T(in GasState Q) const
    {
        throw new Error("ERROR: VibSpecificNitrogen:dpdrho_const_T NOT IMPLEMENTED.");
    }
    override number gas_constant(in GasState Q) const
    {
        return to!number(_R_N2);
    }
    override number internal_energy(in GasState Q) const
    {
        return Q.u;
    }
    override number enthalpy(in GasState Q) const
    {
        return Q.u + Q.p/Q.rho;
    }
    override number entropy(in GasState Q) const
    {
        throw new Error("ERROR: VibSpecificNitrogen:entropy NOT IMPLEMENTED.");
    }

    // Keep the following function as public
    // because the postprocessor will use it.
    number compute_Tvib(GasState Q, number x0, number x1, double tol) const
    {
        // Use secant method to compute Tf1
        number init_x0 = x0;
        number init_x1 = x1;
        number fx0 = boltzmann_eq(x0) - Q.massf[0];
        number fx1 = boltzmann_eq(x1) - Q.massf[0];
        int max_it = 100; 
        foreach(n; 0 .. max_it) {
            if (abs(fx1) < tol) {return x1;}
            number x2 = ((x0*fx1) - (x1*fx0)) / (fx1 - fx0);
            x0 = x1;
            x1 = x2;
            fx0 = fx1;
            fx1 = boltzmann_eq(x2) - Q.massf[0];
        } //end foreach
        return x1;
    } // end compute_Tvib()
    
    double vib_energy(int i) const 
    {
        int I = i+1;
        double w_e = 235857;
        double we_xe = 1432.4;
        double we_ye = -0.226;
        double h = 6.626e-34;
        double c = 2.998e8;
        double e = h*c * (w_e*(I-0.5) - we_xe*(I-0.5)^^2 + we_ye*(I-0.5)^^3);
        return e;
    }
     
    number boltzmann_eq(number Tf1) const
    {
        number summ = 0;
        foreach(ej; 0 .. numVibLevels) { summ += exp(-_vib_energy[ej] / (kB*Tf1)); }        
        number ei = _vib_energy[0];
        number temp_func = (exp(-ei/(kB*Tf1)) / summ);
        return temp_func;   
    }
} // end class VibSpecificNitrogen

version(vib_specific_nitrogen_test) {
    import std.stdio;
    import util.msg_service;

    int main() {
        auto gm = new VibSpecificNitrogen();
        auto Q = new GasState(numVibLevels, 0);
        Q.p = 1.0e5;
        Q.T = 300.0;
        Q.massf[] = 1.0/10;

        double R_N2 = 296.805; // gas constant for N2
        double M_N2 = 0.0280134; // kg/mole
        double gamma = 7./5.; // ratio of specific heats.

        gm.update_thermo_from_pT(Q);
        double my_rho = 1.0e5 / (R_N2 * 300.0);
        assert(approxEqual(Q.rho, my_rho, 1.0e-6), failedUnitTest());
        
        double my_u = 2.5 * R_N2 * 300.0;
        foreach (i; 0 .. numVibLevels) {
            my_u += (Avogadro_number/M_N2) * gm.vib_energy(i) * Q.massf[i];
        }
        assert(approxEqual(Q.u, my_u, 1.0e-6), failedUnitTest());
        
        gm.update_trans_coeffs(Q);
        assert(approxEqual(Q.mu, 0.0, 1.0e-6), failedUnitTest());
        assert(approxEqual(Q.k, 0.0, 1.0e-6), failedUnitTest());
        
        gm.update_sound_speed(Q);
        double my_a = sqrt(gamma * R_N2 * 300.0);
        assert(approxEqual(Q.a, my_a, 1.0e-6), failedUnitTest());
        
        return 0;
    }
}

