/**
 * ideal_gas.d
 * Ideal gas model for use in the CFD codes.
 *
 * Author: Peter J. and Rowan G.
 * Version: 2014-06-22: initial cut, to explore options.
 */

module gas.ideal_gas;

import gas.gas_model;
import gas.physical_constants;
import gas.diffusion.viscosity;
import gas.diffusion.therm_cond;
import std.math;
import std.stdio;
import std.string;
import std.file;
import std.json;
import std.conv;
import util.lua;
import util.lua_service;
import core.stdc.stdlib : exit;

class IdealGas: GasModel {
public:

    this(lua_State *L) {
	_n_species = 1;
	_n_modes = 0;
	// Bring table to TOS
	lua_getglobal(L, "IdealGas");
	// There's just one species name to be read from the gas-model file.
	_species_names.length = 1;
	_species_names[0] = getString(L, -1, "speciesName");
	// Now, pull out the remaining numeric value parameters.
	_mol_masses.length = 1;
	_mol_masses[0] = getDouble(L, -1, "mMass");
	_gamma = getDouble(L, -1, "gamma");
	// Reference values for entropy
	lua_getfield(L, -1, "entropyRefValues");
	_s1 = getDouble(L, -1, "s1");
	_T1 = getDouble(L, -1, "T1");
	_p1 = getDouble(L, -1, "p1");
	lua_pop(L, 1);
	// Molecular transport coefficent models.
	lua_getfield(L, -1, "viscosity");
	_viscModel = createViscosityModel(L);
	lua_pop(L, 1);
	
	lua_getfield(L, -1, "thermCondModel");
	auto model = getString(L, -1, "model");
	if ( model == "constPrandtl" ) {
	    _Prandtl = getDouble(L, -1, "Prandtl");
	    _constPrandtl = true;
	}
	else {
	    _thermCondModel = createThermalConductivityModel(L);
	    _constPrandtl = false;
	}
	lua_pop(L, 1);
	// Compute derived parameters
	_Rgas = R_universal/_mol_masses[0];
	_Cv = _Rgas / (_gamma - 1.0);
	_Cp = _Rgas*_gamma/(_gamma - 1.0);
	create_species_reverse_lookup();
    }

    override string toString() const
    {
	char[] repr;
	repr ~= "IdealGas =(";
	repr ~= "name=\"" ~ _species_names[0] ~"\"";
	repr ~= ", Mmass=" ~ to!string(_mol_masses[0]);
	repr ~= ", gamma=" ~ to!string(_gamma);
	repr ~= ", s1=" ~ to!string(_s1);
	repr ~= ", T1=" ~ to!string(_T1);
	repr ~= ", p1=" ~ to!string(_p1);
	repr ~= ", constPrandtl=" ~ to!string(_constPrandtl);
	repr ~= ", Prandtl=" ~ to!string(_Prandtl);
	repr ~= ")";
	return to!string(repr);
    }

    override void update_thermo_from_pT(GasState Q) const 
    {
	Q.rho = Q.p/(Q.Ttr*_Rgas);
	Q.u = _Cv*Q.Ttr;
    }
    override void update_thermo_from_rhou(GasState Q) const
    {
	Q.Ttr = Q.u/_Cv;
	Q.p = Q.rho*_Rgas*Q.Ttr;
	if (Q.Ttr <= 0.0 || Q.p <= 0.0) {
	    string msg = "Temperature and/or pressure went negative in IdealGas update."; 
	    throw new GasModelException(msg);
	}
    }
    override void update_thermo_from_rhoT(GasState Q) const
    {
	Q.p = Q.rho*_Rgas*Q.Ttr;
	Q.u = _Cv*Q.Ttr;
    }
    override void update_thermo_from_rhop(GasState Q) const
    {
	Q.Ttr = Q.p/(Q.rho*_Rgas);
	Q.u = _Cv*Q.Ttr;
    }
    
    override void update_thermo_from_ps(GasState Q, double s) const
    {
	Q.Ttr = _T1 * exp((1.0/_Cp)*((s - _s1) + _Rgas * log(Q.p/_p1)));
	update_thermo_from_pT(Q);
    }
    override void update_thermo_from_hs(GasState Q, double h, double s) const
    {
	Q.Ttr = h / _Cp;
	Q.p = _p1 * exp((1.0/_Rgas)*(_s1 - s + _Cp*log(Q.Ttr/_T1)));
	update_thermo_from_pT(Q);
    }
    override void update_sound_speed(GasState Q) const
    {
	Q.a = sqrt(_gamma*_Rgas*Q.Ttr);
    }
    override void update_trans_coeffs(GasState Q)
    {
	_viscModel.update_viscosity(Q);
	if ( _constPrandtl ) {
	    Q.k = _Cp*Q.mu/_Prandtl;
	}
	else {
	    _thermCondModel.update_thermal_conductivity(Q);
	}
    }
    /*
    override void eval_diffusion_coefficients(ref GasState Q) {
	throw new Exception("not implemented");
    }
    */
    override double dudT_const_v(in GasState Q) const
    {
	return _Cv;
    }
    override double dhdT_const_p(in GasState Q) const
    {
	return _Cp;
    }
    override double dpdrho_const_T(in GasState Q) const
    {
	double R = gas_constant(Q);
	return R*Q.Ttr;
    }
    override double gas_constant(in GasState Q) const
    {
	return R_universal/_mol_masses[0];
    }
    override double internal_energy(in GasState Q) const
    {
	return Q.u;
    }
    override double enthalpy(in GasState Q) const
    {
	return Q.u + Q.p/Q.rho;
    }
    override double entropy(in GasState Q) const
    {
	return _s1 + _Cp * log(Q.Ttr/_T1) - _Rgas * log(Q.p/_p1);
    }

private:
    // Thermodynamic constants
    double _Rgas; // J/kg/K
    double _gamma;   // ratio of specific heats
    double _Cv; // J/kg/K
    double _Cp; // J/kg/K
    // Reference values for entropy
    double _s1;  // J/kg/K
    double _T1;  // K
    double _p1;  // Pa
    // Molecular transport coefficent constants.
    Viscosity _viscModel;
    // We compute thermal conductivity in one of two ways:
    // 1. based on constant Prandtl number; OR
    // 2. ThermalConductivity model
    // therefore we have places for both data
    bool _constPrandtl = false;
    double _Prandtl;
    ThermalConductivity _thermCondModel;

} // end class Ideal_gas

version(ideal_gas_test) {
    import std.stdio;
    import util.msg_service;

    int main() {
	lua_State* L = init_lua_State();
	doLuaFile(L, "sample-data/ideal-air-gas-model.lua");
	auto gm = new IdealGas(L);
	lua_close(L);
	auto gd = new GasState(1, 0);
	gd.p = 1.0e5;
	gd.Ttr = 300.0;
	gd.massf[0] = 1.0;
	assert(approxEqual(gm.R(gd), 287.086, 1.0e-4), failedUnitTest());
	assert(gm.n_modes == 0, failedUnitTest());
	assert(gm.n_species == 1, failedUnitTest());
	assert(approxEqual(gd.p, 1.0e5, 1.0e-6), failedUnitTest());
	assert(approxEqual(gd.Ttr, 300.0, 1.0e-6), failedUnitTest());
	assert(approxEqual(gd.massf[0], 1.0, 1.0e-6), failedUnitTest());

	gm.update_thermo_from_pT(gd);
	gm.update_sound_speed(gd);
	assert(approxEqual(gd.rho, 1.16109, 1.0e-4), failedUnitTest());
	assert(approxEqual(gd.u, 215314.0, 1.0e-4), failedUnitTest());
	assert(approxEqual(gd.a, 347.241, 1.0e-4), failedUnitTest());
	gm.update_trans_coeffs(gd);
	assert(approxEqual(gd.mu, 1.84691e-05, 1.0e-6), failedUnitTest());
	assert(approxEqual(gd.k, 0.0262449, 1.0e-6), failedUnitTest());

	return 0;
    }
}
