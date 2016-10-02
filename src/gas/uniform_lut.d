/**
 * uniform_lut.d
 * Gas model for a uniformly spaced look-up-table 
 *
 * Based on look-up-table.cxx and look-up-table.hh 
 * for Eilmer3, 
 * Author: Rowan J. Gollan, 07-Nov-2008
 * 
 * Converted to D for use in Eilmer4,
 * Author: James M. Burgess, 11-Jan-2016
 */
module gas.uniform_lut;

import std.stdio;
import std.math;
import std.algorithm;
import std.string;
import std.conv;

import gas.gas_model;
import gas.physical_constants;
import util.lua;
import util.lua_service;

/* Output from the CEA lookuptable is : 
   {cv_hat, cv, R_hat, cp_hat, gamma_hat, mu, k }  */

class UniformLUT: GasModel{
public:
    // Default implementation
    this()
    {
	_n_species = 1;
	_n_modes = 1; 
	_species_names ~= "LUT";
	assert(_species_names.length == 1);
	create_species_reverse_lookup();
        // _mol_masses is defined at the end of the constructor  
    }

    this(lua_State *L) {
	this();    // Call the default constructor
	try {
	    with_entropy = getInt(L, LUA_GLOBALSINDEX, "with_entropy");
	    assert(with_entropy == 1);   
	    _p1 = getDouble(L, LUA_GLOBALSINDEX, "p1");
	    _T1 = getDouble(L, LUA_GLOBALSINDEX, "T1");
	    _s1 = getDouble(L, LUA_GLOBALSINDEX, "s1");
	}
	catch (Exception e) {       
	    writeln(e.msg);
	    with_entropy = 0;
	    writeln("Look_up_table(): No entropy data available");
	}
	
	_iesteps = getInt(L, LUA_GLOBALSINDEX, "iesteps");
	_irsteps = getInt(L, LUA_GLOBALSINDEX, "irsteps");
	_emin = getDouble(L, LUA_GLOBALSINDEX, "emin");
	_de = getDouble(L, LUA_GLOBALSINDEX, "de");
	_lrmin = getDouble(L, LUA_GLOBALSINDEX, "lrmin");
	_dlr = getDouble(L, LUA_GLOBALSINDEX, "dlr");
  
	_emax = _emin + _de * _iesteps;
	_lrmax = _lrmin + _dlr * _irsteps;

	lua_getglobal(L, "data");
	if ( !lua_istable(L, -1) ) {
	    string msg;
	    msg ~= format("Look_up_table():\n");
	    msg ~= format("   Error in look-up table input file: %s\n", __FILE__); 
	    msg ~= format("   A table of 'data' is expected, but not found.\n");
	    throw new Exception(msg);
	}

	size_t ne = lua_objlen(L, -1); 
	if ( ne != _iesteps + 1) {
	    string msg;
	    msg ~= format("Look_up_table():\n");
	    msg ~= format("    Error in look-up table input file: %s\n", __FILE__);
	    msg ~= format("    Inconsistent numbers for energy steps: ");
	    msg ~= format("points = %s, steps = %s\n", ne, _iesteps);
	    throw new Exception(msg);
	}

	// set i-lengths of all 2D arrays (for varying energy)
	_Cv_hat.length = ne;
	_Cv.length = ne;
	_R_hat.length = ne;
	_g_hat.length = ne;
	_mu_hat.length = ne;
	_k_hat.length = ne;
	_Cp_hat.length = ne;
    
	// Determine the required j-length of data
	lua_rawgeti(L, -1, 1);
	size_t nr = lua_objlen(L, -1);
	lua_pop(L, 1);
    
	if ( nr != _irsteps +1) {
	    string msg;
	    msg ~= "Look_up_table():\n";
	    msg ~= format("   Error in look-up table input file: %s\n", __FILE__); 
	    msg ~= "   Inconsistent numbers for density steps:.\n";
	    msg ~= format("   points = %s, steps = %s ", nr, _irsteps);
	    throw new Exception(msg);
	}
	
	for ( _ie= 0;_ie< ne; ++_ie ) {
	    // Set j-lengths of data matrices 2D arrays
	    _Cv_hat[_ie].length = nr;
	    _Cv[_ie].length = nr;
	    _R_hat[_ie].length = nr;
	    _g_hat[_ie].length = nr;
	    _mu_hat[_ie].length = nr;
	    _k_hat[_ie].length = nr;  
	    if ( with_entropy == 1) { _Cp_hat[_ie].length = nr; }
  
	    lua_rawgeti(L, -1, _ie+1);
	    for (_ir = 0;_ir< nr; ++_ir ) {
		lua_rawgeti(L, -1, _ir+1);
		lua_rawgeti(L, -1, 1);
		_Cv_hat[_ie][_ir] = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		lua_rawgeti(L, -1, 2);
		_Cv[_ie][_ir] = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		lua_rawgeti(L, -1, 3);
		_R_hat[_ie][_ir] = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		if ( with_entropy ==1 ) {
		    lua_rawgeti(L, -1, 4);
		    _Cp_hat[_ie][_ir] = luaL_checknumber(L, -1);
		    lua_pop(L, 1);
		    lua_rawgeti(L, -1, 5);
		    _g_hat[_ie][_ir] = luaL_checknumber(L, -1);
		    lua_pop(L, 1);
		    lua_rawgeti(L, -1, 6);
		    _mu_hat[_ie][_ir] = luaL_checknumber(L, -1);
		    lua_pop(L, 1);
		    lua_rawgeti(L, -1, 7);
		    _k_hat[_ie][_ir] = luaL_checknumber(L, -1);
		    lua_pop(L, 1);
		} else {
		    // The old arrangement.
		    lua_rawgeti(L, -1, 4);
		    _g_hat[_ie][_ir] = luaL_checknumber(L, -1);
		    lua_pop(L, 1);
		    lua_rawgeti(L, -1, 5);
		    _mu_hat[_ie][_ir] = luaL_checknumber(L, -1);
		    lua_pop(L, 1);
		    lua_rawgeti(L, -1, 6);
		    _k_hat[_ie][_ir] = luaL_checknumber(L, -1);
		    lua_pop(L, 1);
		}
		lua_pop(L, 1); // pop data[_ie][_ir] off.
	    }
	    lua_pop(L, 1); // pop data[_ie] off.
	}
	lua_pop(L, 1); // pop data table off.
	
	_mol_masses ~= s_molecular_weight(0); 
  
    } // End constructor  

  
    override string toString() const 
    {
	char[] repr;
	repr ~= "UniformLUT =(";
	repr ~= "with_entropy = " ~ to!string(with_entropy);
	if ( with_entropy == 1) {
	    repr ~= ": entropy reference properties ={";
	    repr ~= "p1 = " ~ to!string(_p1);
	    repr ~= ", T1 = " ~ to!string(_T1);
	    repr ~= ", s1 = " ~ to!string(_s1);
	    repr ~= "}, ";
	}
	repr ~= ", iesteps = " ~ to!string(_iesteps);
	repr ~= ", irsteps = " ~ to!string(_irsteps);
	repr ~= ", emin = " ~ to!string(_emin);
	repr ~= ", de = " ~ to!string(_de);
	repr ~= ", lrmin = " ~ to!string(_lrmin);
	repr ~= ", dlr = " ~ to!string(_dlr);
	repr ~= ")";
	return to!string(repr);
    } 
    
    void determine_interpolants(const GasState Q, ref int ir, ref int ie,
				ref double lrfrac, ref double efrac) const
    {
	if ( Q.rho <= 0.0) {
	    string msg;
	    msg ~= format("Error in function  %s \n", __FUNCTION__);
	    msg ~= format("density = %.5s is zero or negaive\n", Q.rho);
	    msg ~= format("  Supplied Q: %s", Q);
	    throw new Exception(msg);
	}

	// Find the enclosing cell
	double logrho = log10(Q.rho);
	ir = cast(int)((logrho - _lrmin) / _dlr);
	ie = cast (int)((Q.e[0] - _emin) / _de);

	// Make sure that we don't try to access data outside the
	// actual arrays.
	if (ir< 0 )ir= 0;
	if (ir> (_irsteps - 1) )ir= _irsteps - 1;
	if (ie< 0 )ie= 0;
	if (ie> (_iesteps - 1) )ie= _iesteps - 1;

	// Calculate bilinear interpolation(/extrapolation) fractions.
	lrfrac = (logrho - (_lrmin +ir* _dlr)) / _dlr;
	efrac  = (Q.e[0] - (_emin +ie* _de)) / _de;
    
	// Limit the extrapolation to small distances.
	const double EXTRAP_MARGIN = 0.2;
	lrfrac = max(lrfrac, -EXTRAP_MARGIN);
	lrfrac = min(lrfrac, 1.0+EXTRAP_MARGIN);
	efrac = max(efrac, -EXTRAP_MARGIN);
	efrac = min(efrac, 1.0+EXTRAP_MARGIN);
    }

    override void update_thermo_from_rhoe(GasState Q) const
    {
	assert(Q.e.length == 1, "incorrect length of energy array");
	double efrac, lrfrac, Cv_eff, R_eff, g_eff;
	int    ir, ie;
   
	try { determine_interpolants(Q, ir, ie, lrfrac, efrac); }
	catch (Exception caughtException) {
	    string msg;
	    msg ~= format("Error in function %s \n", __FUNCTION__);
	    msg ~= format("Excpetion message from determine_interpolants() was:\n\n");
	    msg ~= to!string(caughtException);
	    throw new Exception(msg);
	}
	Cv_eff = (1.0 - efrac) * (1.0 - lrfrac) * _Cv_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _Cv_hat[ie+1][ir] +
	    efrac         * lrfrac         * _Cv_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _Cv_hat[ie][ir+1];
   
	R_eff  = (1.0 - efrac) * (1.0 - lrfrac) * _R_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _R_hat[ie+1][ir] +
	    efrac         * lrfrac         * _R_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _R_hat[ie][ir+1];
	   
	g_eff  = (1.0 - efrac) * (1.0 - lrfrac) * _g_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _g_hat[ie+1][ir] +
	    efrac         * lrfrac         * _g_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _g_hat[ie][ir+1];
   
	// Reconstruct the thermodynamic properties.
	Q.T[0] = Q.e[0] / Cv_eff;
	Q.p = Q.rho*R_eff*Q.T[0];
	Q.a = sqrt(g_eff*R_eff*Q.T[0]);
	if ( Q.T[0] < T_MIN ) {
	    string msg;
	    msg ~= format("Error in function  %s\n", __FUNCTION__);
	    msg ~= format("Low temperature, rho = %.5s ", Q.rho);
	    msg ~= format("e= %.8s  T= %.5s \n", Q.e[0], Q.T[0]);
	    msg ~= format(    "Supplied Q: %s ", Q);
	    throw new Exception(msg);
	}

	// Fix meaningless values if they arise
	if ( Q.p < 0.0 ) Q.p = 0.0;
	if ( Q.T[0] < 0.0 ) Q.T[0] = 0.0;
	if ( Q.a < 0.0 ) Q.a = 0.0;
    }  

    override void update_trans_coeffs(GasState Q) const
    {
	double efrac, lrfrac;
	double mu_eff, k_eff;
	int ir, ie;

	try { determine_interpolants(Q, ir, ie, lrfrac, efrac); }
	catch (Exception caughtException) {
	    string msg;
	    msg ~= format("Error in function %s \n", __FUNCTION__);
	    msg ~= format("Excpetion message from determine_interpolants() was:\n\n");
	    msg ~= to!string(caughtException);
	    throw new Exception(msg);
	}
	mu_eff = (1.0 - efrac) * (1.0 - lrfrac) * _mu_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _mu_hat[ie+1][ir] +
	    efrac         * lrfrac         * _mu_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _mu_hat[ie][ir+1];

	k_eff = (1.0 - efrac) * (1.0 - lrfrac) * _k_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _k_hat[ie+1][ir] +
	    efrac         * lrfrac         * _k_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _k_hat[ie][ir+1];
   
	Q.mu = mu_eff;
	Q.k[0] = k_eff;

    }
    /* 
       override void eval_diffusion_coefficients(ref GasState Q)
       {   // These have no meaning for an equilibrium gas.
       Q.D_AB[0][0] = 0.0;
       }
    */

    override double dedT_const_v(in GasState Q) const
    { 
	double efrac, lrfrac;
	int    ir, ie;
	double Cv_actual;

	try { determine_interpolants(Q, ir, ie, lrfrac, efrac); }
	catch (Exception caughtException) {
	    string msg;
	    msg ~= format("Error in function %s\n", __FUNCTION__);
	    msg ~= format("Excpetion message from determine_interpolants() was:\n\n");
	    msg ~= to!string(caughtException);
	    throw new Exception(msg);
	}
	Cv_actual = (1.0 - efrac) * (1.0 - lrfrac) * _Cv[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _Cv[ie+1][ir] +
	    efrac         * lrfrac         * _Cv[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _Cv[ie][ir+1];

	return Cv_actual;
    }

    override double dhdT_const_p(in GasState Q) const
    {
	double efrac, lrfrac;
	int ir, ie;
	double Cv_actual, R_eff;

	try { determine_interpolants(Q, ir, ie, lrfrac, efrac); }
	catch (Exception caughtException) {
	    string msg;
	    msg ~= format("Error in function %s \n", __FUNCTION__);
	    msg ~= format("Excpetion message from determine_interpolants() was:\n\n");
	    msg ~= to!string(caughtException);
	    throw new Exception(msg);
	}
	Cv_actual = (1.0 - efrac) * (1.0 - lrfrac) * _Cv[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _Cv[ie+1][ir] +
	    efrac         * lrfrac         * _Cv[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _Cv[ie][ir+1];

	R_eff  = (1.0 - efrac) * (1.0 - lrfrac) * _R_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _R_hat[ie+1][ir] +
	    efrac         * lrfrac         * _R_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _R_hat[ie][ir+1];

	return (Cv_actual + R_eff);
    }

    override double gas_constant(in GasState Q) const
    {
	double efrac, lrfrac;
	int    ir, ie;
	double R_eff;

	try { determine_interpolants(Q, ir, ie, lrfrac, efrac); }
	catch (Exception caughtException) {
	    string msg;
	    msg ~= format("Error in function %s \n", __FUNCTION__);
	    msg ~= format("Excpetion message from determine_interpolants() was:\n\n");
	    msg ~= to!string(caughtException);
	    throw new Exception(msg);
	}
	R_eff  = (1.0 - efrac) * (1.0 - lrfrac) * _R_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _R_hat[ie+1][ir] +
	    efrac         * lrfrac         * _R_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _R_hat[ie][ir+1];
   
	return R_eff;
    }

    override double internal_energy(in GasState Q) const
    {
	// This method should never be called expecting quality data
	// because the LUT gas doesn not keep the species information.
	// This implementation is here to keep D happy that
	// all of the methods are implemented as required,
	// and there may be times when having this function
	// return something reasonable may make other code
	// simpler because it doesn't have to treat the
	// LUT gas specially.
	// This is the one-species implementation

	return Q.e[0];
    }


    override double enthalpy(in GasState Q) const
    {
	// This method assumes that the internal energy,
	// pressure and density are up-to-date in the
	// GasData object. Then enthalpy is computed
	// from definition.

	double h = Q.e[0] + Q.p/Q.rho;
	return h;
    }

    override double entropy(in GasState Q) const
    {
	double s;

	if ( with_entropy ==1 ) {
	    int ir, ie;
	    double lrfrac, efrac;

	    try { determine_interpolants(Q, ir, ie, lrfrac, efrac); }
	    catch (Exception caughtException) {
		string msg;
		msg ~= format("Error in function %s \n", __FUNCTION__);
		msg ~= format("Excpetion message from determine_interpolants() was:\n\n");
		msg ~= to!string(caughtException);
		throw new Exception(msg);
	    }
	    double Cv_eff = (1.0 - efrac) * (1.0 - lrfrac) * _Cv_hat[ie][ir] +
		efrac         * (1.0 - lrfrac) * _Cv_hat[ie+1][ir] +
		efrac         * lrfrac         * _Cv_hat[ie+1][ir+1] +
		(1.0 - efrac) * lrfrac         * _Cv_hat[ie][ir+1];
	    double R_eff  = (1.0 - efrac) * (1.0 - lrfrac) * _R_hat[ie][ir] +
		efrac         * (1.0 - lrfrac) * _R_hat[ie+1][ir] +
		efrac         * lrfrac         * _R_hat[ie+1][ir+1] +
		(1.0 - efrac) * lrfrac         * _R_hat[ie][ir+1];
	    double Cp_eff  = (1.0 - efrac) * (1.0 - lrfrac) * _Cp_hat[ie][ir] +
		efrac         * (1.0 - lrfrac) * _Cp_hat[ie+1][ir] +
		efrac         * lrfrac         * _Cp_hat[ie+1][ir+1] +
		(1.0 - efrac) * lrfrac         * _Cp_hat[ie][ir+1];
	    double T = Q.e[0] / Cv_eff;
	    double p = Q.rho*R_eff*T;
	    s = _s1 + Cp_eff*log(T/_T1) - R_eff*log(p/_p1); 
	}
	else {
	    // Without having the entropy recorded as part of the original table,
	    // the next best is to use a model of an ideal gas.
	    writeln( "Caution: calling s_entropy for LUT species without tabular data.");
	    writeln( "Using an ideal gas model" );
	    int ie = 0; // coldest
	    int ir = _irsteps - 1; // quite dense 
	    double R = _R_hat[ie][ir]; // J/kg/deg-K
	    double Cp = R + _Cv_hat[ie][ir];
	    const double T1 = 300.0; // degrees K: This value and the next was type constexpr
	    const double p1 = 100.0e3; // Pa
	    s = Cp * log(Q.T[0]/T1) - R * log(Q.p/p1);
	} 
	return s;
    }

    double s_molecular_weight(int isp) const
    { 
	// This method is not very meaningful for an equilibrium
	// gas.  The molecular weight is best obtained from
	// the mixture molecular weight methods which IS a function
	// of gas composition and thermodynamic state, however,
	// there are times when a value from this function makes
	// other code simpler, in that the doesn't have to treat
	// the look-up gas specially.
	if ( isp != 0 ) {
	    throw new Exception("LUT gas: should not be looking up isp != 0");
	}
    
	int ie = 0; // coldest
	int ir = _irsteps -1; // quite dense    
	double Rgas = _R_hat[ie][ir]; // J/kg/deg-K

	/* Eilmer3 converts these values to kg/kmol - I am keeping in SI units
	 * immutable R_universal_kmol = R_universal * 1000;
	 * double M = R_universal_kmol / Rgas; */

	double M = R_universal / Rgas;    
	return M;
    }

    override void update_sound_speed(GasState Q) const
    {
	double efrac, lrfrac, Cv_eff, R_eff, g_eff;
	int    ir, ie;
   
	try { determine_interpolants(Q, ir, ie, lrfrac, efrac); }
	catch (Exception caughtException) {
	    string msg;
	    msg ~= format("Error in function %s \n", __FUNCTION__);
	    msg ~= format("Excpetion message from determine_interpolants() was:\n\n");
	    msg ~= to!string(caughtException);
	    throw new Exception(msg);
	}
	if (isNaN(Q.rho) || isNaN(Q.e[0])) {
	    string err;
	    err ~= format("update_sound_speed() method for LUT requires e and rho of ");
	    err ~= format("GasState Q to be defined: rho = %.5s, e = .8s", Q.rho, Q.e[0]);
	    throw new Exception(err);
	}
	R_eff  = (1.0 - efrac) * (1.0 - lrfrac) * _R_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _R_hat[ie+1][ir] +
	    efrac         * lrfrac         * _R_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _R_hat[ie][ir+1];
	   
	g_eff  = (1.0 - efrac) * (1.0 - lrfrac) * _g_hat[ie][ir] +
	    efrac         * (1.0 - lrfrac) * _g_hat[ie+1][ir] +
	    efrac         * lrfrac         * _g_hat[ie+1][ir+1] +
	    (1.0 - efrac) * lrfrac         * _g_hat[ie][ir+1];
   
	// Reconstruct the thermodynamic properties.
	Q.a = sqrt(g_eff*R_eff*Q.T[0]);
    }
 

    // Remaining functions must call numerical method solution defined in gas_model.d
    override void update_thermo_from_pT(GasState Q) 
    {
	assert(Q.T.length == 1, "incorrect length of temperature array");
	update_thermo_state_pT(this, Q);
    }
    override void update_thermo_from_rhoT(GasState Q)  
    {
	assert(Q.T.length == 1, "incorrect length of temperature array");
	update_thermo_state_rhoT(this, Q);
    }
    override void update_thermo_from_rhop(GasState Q) 
    {
	update_thermo_state_rhop(this, Q);
    } 
    override void update_thermo_from_ps(GasState Q, double s) 
    {
	update_thermo_state_ps(this, Q, s);
    }
    override void update_thermo_from_hs(GasState Q, double h, double s) 
    {
	update_thermo_state_hs(this, Q, h, s);
    }



    // Factor for computing forward difference derivatives
    immutable double Epsilon = 1.0e-6;

    override double dpdrho_const_T(in GasState Q)
    {
	// Cannot be directly computed from look up table
	// Apply forward finite difference in calling update from p, rho
	// Make a copy of the GasState object, to avoid modifying Q
	auto Q_temp = new GasState(this);
	Q_temp.copy_values_from(Q);

	// Save values for derivative calculation
	double p = Q_temp.p;
	double rho = Q_temp.rho;
	double h = Epsilon * rho; // Step size for varying rho
	double rho_step = rho + h; // Define a small step size
	Q_temp.rho = rho_step; // Modify density slightly

	// Evaluate gas state due to perturbed rho, holding constant T
	this.update_thermo_from_rhoT(Q_temp);
	double p_step = Q_temp.p;
	return ( (p_step - p) / h);
     }

 
private:
    int with_entropy;
    double _s1, _p1, _T1;
    int _iesteps, _irsteps;
    double _emin, _emax, _de;
    double _lrmin, _lrmax, _dlr;
    int _ie, _ir; // used in the constructor, but not in interpolation
    
    // Data for interpolation
    double[][]  _Cv_hat;
    double[][] _Cv;
    double[][] _R_hat;
    double[][] _g_hat;
    double[][] _mu_hat;
    double[][] _k_hat;
    double[][] _Cp_hat;

} // End of uniformLUT class

version(uniform_lut_test) 
{
    import util.msg_service;
    int main() {
	GasModel gm;
	try { lua_State* L = init_lua_State("sample-data/cea-lut-air-version-test.lua");
	    gm = new UniformLUT(L);
	}
	catch (Exception e) {
	    writeln(e.msg);
	    string msg;
	    msg ~= "Test of look up table in uniform_lut.d require file:";
	    msg ~= " cea-lut-air-version-test.lua ";
	    msg ~= " in directory: gas/sample_data";
	    throw new Exception(msg);
	}

	// An arbitrary state was defined for 'Air', massf=1, in CEA2
	// using the utility cea2_gas.py
	double p_given = 1.0e6; // Pa
	double T_given = 1.0e3; // K
	double rho_given = 3.4837; // kg/m^^3
	// CEA uses a reference temperature of 298K (Eilmer uses 0K) so the
	// temperature was offset by amount e_offset 
	double e_CEA =  456600; // J/kg
	double e_offset = 303949.904; // J/kg
	double e_given = e_CEA + e_offset; // J/kg
	double h_CEA = 743650; // J/kg
	double h_given = h_CEA + e_offset; // J/kg 
	double a_given = 619.2; // m/s
	double s_given = 7475.7; // J(kg.K)
	double R_given = 287.036; // J/(kg.K)
	double gamma_given = 1.3866;
	double Cp_given = 1141; // J/(kg.K)
	double mu_given = 4.3688e-05; // Pa.s
	double k_given = 0.0662; // W/(m.K)
	double Cv_given = e_given / T_given; // J/(kg.K)
		
	auto Q = new GasState(gm, p_given, T_given);
	// Return values not stored in the GasState
	double Cv = gm.dedT_const_v(Q);
	double Cp = gm.dhdT_const_p(Q);
	double R = gm.gas_constant(Q);
	double h = gm.enthalpy(Q);
	double s = gm.entropy(Q);

	assert(gm.n_modes == 1, failedUnitTest());
	assert(gm.n_species == 1, failedUnitTest());
	assert(approxEqual(e_given, Q.e[0], 1.0e-4), failedUnitTest());
	assert(approxEqual(rho_given, Q.rho, 1.0e-4), failedUnitTest());
	assert(approxEqual(a_given, Q.a, 1.0e-4), failedUnitTest());
	assert(approxEqual(Cp_given, Cp, 1.0e-3), failedUnitTest());
	assert(approxEqual(h_given, h, 1.0e-4), failedUnitTest());
	assert(approxEqual(mu_given, Q.mu, 1.0e-4), failedUnitTest());
	assert(approxEqual(k_given, Q.k[0], 1.0e-3), failedUnitTest());
	assert(approxEqual(s_given, s, 1.0e-4), failedUnitTest());
	assert(approxEqual(R_given, R, 1.0e-4), failedUnitTest());
	
	return 0;
    }
}
