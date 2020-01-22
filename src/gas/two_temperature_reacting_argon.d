/**
 * two_temperature_reacting_argon.d
 *
 * Two-temperature reacting argon based model of:
 * Martin I. Hoffert and Hwachii Lien
 * "Quasi-One-Dimensional, Nonequilibrium Gas Dynamics of Partially Ionised Two-Temperature Argon"
 * The Physics of Fluids 10, 1769 (1967); doi 10.1063/1.1762356
 *
 * Authors: Daniel Smith, Rory Kelly and Peter J.
 * Version: 19-July-2017: initial cut.
 *          12-Feb-2019: code clean up and viscous transport coefficients
 */

module gas.two_temperature_reacting_argon;

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

// First, the basic gas model.
enum Species {Ar=0, Ar_plus, e_minus}

class TwoTemperatureReactingArgon: GasModel {
public:

    this(lua_State *L) {
        // Some parameters are fixed and some come from the gas model file.
        _is_plasma = true;
        _n_species = 3;
        _n_modes = 1;
        _species_names.length = 3;
        _species_names[Species.Ar] = "Ar";
        _species_names[Species.Ar_plus] = "Ar+";
        _species_names[Species.e_minus] = "e-";
        _mol_masses.length = 3;
        _mol_masses[Species.Ar] = 39.948e-3; // Units are kg/mol
        _mol_masses[Species.e_minus] = 5.485799e-7; // Units are kg/mol
        _mol_masses[Species.Ar_plus] = _mol_masses[Species.Ar] - _mol_masses[Species.e_minus];
        _e_mass_over_ion_mass = _mol_masses[Species.e_minus] / _mol_masses[Species.Ar_plus];
        lua_getglobal(L, "TwoTemperatureReactingArgon");
        // [TODO] test that we actually have the table as item -1
        // Now, pull out the remaining numeric value parameters.
        _ion_tol = getDoubleWithDefault(L, -1, "ion_tol", 0.0);
        lua_pop(L, 1); // dispose of the table
        // Compute derived parameters
        create_species_reverse_lookup();
    } // end constructor

    override string toString() const
    {
        char[] repr;
        repr ~= "TwoTemperatureReactingArgon =(";
        repr ~= "species=[\"Ar\", \"Ar+\", \"e-\"]";
        repr ~= ", Mmass=[" ~ to!string(_mol_masses[Species.Ar]);
        repr ~= "," ~ to!string(_mol_masses[Species.Ar_plus]);
        repr ~= "," ~ to!string(_mol_masses[Species.e_minus]) ~ "]";
        repr ~= ")";
        return to!string(repr);
    }

    override void update_thermo_from_pT(GasState Q) const 
    {
        number alpha = ionisation_fraction_from_mass_fractions(Q);
        if (Q.T <= 0.0 || Q.p <= 0.0) {
            string msg = "Temperature and/or pressure was negative for update_thermo_from_pT."; 
            debug { msg ~= format("\nQ=%s\n", Q); }
            throw new GasModelException(msg);
        }
        number Te = Q.T; // Assume electron temperature is the same as heavy-particle T.
        Q.rho = Q.p/(_Rgas*(Q.T + alpha*Te));
        Q.u = 3.0/2.0*_Rgas*Q.T;
        Q.T_modes[0] = Te;
        Q.u_modes[0] = 3.0/2.0*_Rgas*alpha*Te + alpha*_Rgas*_theta_ion;
    }
    override void update_thermo_from_rhou(GasState Q) const
    {
        number alpha = ionisation_fraction_from_mass_fractions(Q);
        if (Q.u <= 0.0 || Q.rho <= 0.0) {
            string msg = "Internal energy and/or density was negative for update_thermo_from_rhou.";
            debug { msg ~= format("\nQ=%s\n", Q); }
            throw new GasModelException(msg);
        }
        Q.T = 2.0/3.0*Q.u/_Rgas;
        number Te;
        if (alpha > 0.0) {
            Te = (Q.u_modes[0]/alpha-_Rgas*_theta_ion)*2.0/3.0/_Rgas;
            if (Te > 500.0e3) { Te = 500.0e3; }
            if (Te < 20.0) { Te = 20.0; }
        } else {
            Te = Q.T;
        }
        Q.p = Q.rho*_Rgas*(Q.T+alpha*Te);
        Q.T_modes[0] = Te;
    }
    override void update_thermo_from_rhoT(GasState Q) const
    {
        number alpha = ionisation_fraction_from_mass_fractions(Q);
        if (Q.T <= 0.0 || Q.rho <= 0.0) {
            string msg = "Temperature and/or density was negative for update_thermo_from_rhoT."; 
            debug { msg ~= format("\nQ=%s\n", Q); }
            throw new GasModelException(msg);
        }
        number Te = Q.T_modes[0];
        Q.p = Q.rho*_Rgas*(Q.T+alpha*Te);
        Q.u = 3.0/2.0*_Rgas*Q.T;
        Q.u_modes[0] = 3.0/2.0*_Rgas*alpha*Te + alpha*_Rgas*_theta_ion;
    }
    override void update_thermo_from_rhop(GasState Q) const
    {
        // Assume Q.T_modes[0] is set independently, and is correct.
        number alpha = ionisation_fraction_from_mass_fractions(Q);
        if (Q.p <= 0.0 || Q.rho <= 0.0) {
            string msg = "Pressure and/or density was negative for update_thermo_from_rhop."; 
            debug { msg ~= format("\nQ=%s\n", Q); }
            throw new GasModelException(msg);
        }
        Q.T = Q.p/Q.rho/_Rgas - alpha*Q.T_modes[0];
        Q.u = 3.0/2.0*_Rgas*Q.T;
        Q.u_modes[0] = 3.0/2.0*_Rgas*alpha*Q.T_modes[0] + alpha*_Rgas*_theta_ion;
    }
    override void update_thermo_from_ps(GasState Q, number s) const
    {
        throw new GasModelException("update_thermo_from_ps not implemented.");
    }
    override void update_thermo_from_hs(GasState Q, number h, number s) const
    {
        throw new GasModelException("update_thermo_from_hs not implemented.");
    }
    override void update_sound_speed(GasState Q) const
    {
        if (Q.T <= 0.0) {
            string msg = "Temperature was negative for update_sound_speed."; 
            debug { msg ~= format("\nQ=%s\n", Q); }
            throw new GasModelException(msg);
        }
        // Assume that the properties for argon atoms, ignoring dissociation.
        number _gamma = dhdT_const_p(Q)/dudT_const_v(Q);
        Q.a = sqrt(_gamma*_Rgas*Q.T);
    }
    override void update_trans_coeffs(GasState Q)
    {
        // Assume the properties of argon atoms, ignoring the ionisation.
        // Use power-law from
        // Michael Macrossan and Charles Lilley (2003)
        // Viscosity of aegon at temperatures >2000K from measured shock thickness.
        // Physics of Fluids Vol 15 No 11 pp 3452-3457
        double mu_ref = 73.0e-6; // Pa.s
        double T_ref = 1500.0; // degree K
        Q.mu = mu_ref * pow(Q.T/T_ref, 0.72);
        Q.k = Q.mu * _Cp / 0.667; // fixed Prandtl number
        Q.k_modes[0] = 0.0;
    }
    override number dudT_const_v(in GasState Q) const
    {
        // Assume frozen dissociation, 3/2*_Rgas
        return to!number(_Cv);
    }
    override number dhdT_const_p(in GasState Q) const
    {
        // Assume frozen dissociation, 5/2*_Rgas
        return to!number(_Cp);
    }
    override number dpdrho_const_T(in GasState Q) const
    {
        return _Rgas*Q.T;
    }
    override number gas_constant(in GasState Q) const
    {
        return to!number(_Rgas);
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
        throw new GasModelException("entropy not implemented in TwoTemperatureReactingArgon.");
    }

    override void balance_charge(GasState Q) const
    {
        Q.massf[Species.e_minus] = Q.massf[Species.Ar_plus] * _e_mass_over_ion_mass;
    }

    @nogc number ionisation_fraction_from_mass_fractions(const(GasState) Q) const
    {
        number ions = Q.massf[Species.Ar_plus] / _mol_masses[Species.Ar_plus];
        number atoms = Q.massf[Species.Ar] / _mol_masses[Species.Ar];
        return ions/(ions+atoms);
    }
    
private:
    // Thermodynamic constants
    double _Rgas = 208.0; // J/kg/K
    double _Cp = 520.0;
    double _Cv = 312.0;
    double _theta_ion = 183100.0;
    double _theta_A1star = 135300.0;
    double _ion_tol; // set from value in Lua file
    double _e_mass_over_ion_mass; // set once mol masses are set in constructor
} // end class

//// Unit test of the basic gas model...

version(two_temperature_reacting_argon_test) {
    import std.stdio;
    import util.msg_service;
    import std.math : approxEqual;
    int main() {
        lua_State* L = init_lua_State();
        doLuaFile(L, "sample-data/two-temperature-reacting-argon-model.lua");
        auto gm = new TwoTemperatureReactingArgon(L);
        lua_close(L);
        auto gd = new GasState(3, 1);
        gd.p = 1.0e5;
        gd.T = 300.0;
        gd.T_modes[0] = 300;
        gd.massf[Species.Ar] = 1.0;
        gd.massf[Species.Ar_plus] = 0.0;
        gd.massf[Species.e_minus] = 0.0;

        assert(approxEqual(gm.R(gd), 208.0, 1.0e-4), failedUnitTest());
        assert(gm.n_modes == 1, failedUnitTest());
        assert(gm.n_species == 3, failedUnitTest());
        assert(approxEqual(gd.p, 1.0e5, 1.0e-6), failedUnitTest());
        assert(approxEqual(gd.T, 300.0, 1.0e-6), failedUnitTest());
        assert(approxEqual(gd.massf[Species.Ar], 1.0, 1.0e-6), failedUnitTest());
        assert(approxEqual(gd.massf[Species.Ar_plus], 0.0, 1.0e-6), failedUnitTest());
        assert(approxEqual(gd.massf[Species.e_minus], 0.0, 1.0e-6), failedUnitTest());

        gm.update_thermo_from_pT(gd);
        gm.update_sound_speed(gd);
        number my_rho = 1.0e5 / (208.0 * 300.0);
        assert(approxEqual(gd.rho, my_rho, 1.0e-4), failedUnitTest());

        number my_Cv = gm.dudT_const_v(gd);
        number my_u = my_Cv*300.0; 
        assert(approxEqual(gd.u, my_u, 1.0e-3), failedUnitTest());

        number my_Cp = gm.dhdT_const_p(gd);
        number my_a = sqrt(my_Cp/my_Cv*208.0*300.0);
        assert(approxEqual(gd.a, my_a, 1.0e-3), failedUnitTest());

        gm.update_trans_coeffs(gd);
        assert(approxEqual(gd.mu, 22.912e-6, 1.0e-6), failedUnitTest());
        assert(approxEqual(gd.k, 0.0178625, 1.0e-6), failedUnitTest());

        return 0;
    }
}
