/**
 * gas_model.d
 * 
 * Contents: The gas model file has a number of parts.
 *   1. The GasModel base class for specifying how 
 *      specific gas models should behave.
 *   2. The GasState class which specifies the storage arrangement
 *      for the data defining a gas state.
 *   3. Utility functions to transform mass-fraction and mole-fraction
 *      data arrays.
 *   4. Fill-in functions for gas model classes that don't implement
 *      some of the functions declared in the base class.
 *   5. Utility functions to create GasModel objects.
 *   6. Unit tests for the module.
 *
 * Authors: Peter J. and Rowan G.
 * Version: 2014-06-22, first cut, exploring the options.
 *          2015--2016, lots of experiments
 *          2017-01-06, introduce ChemicalReactor base class
 *          2017-11-10, move ThermochemicalReactor to its own module in kinetics package
 *          2018-06-02, adapted to complex numbers for Kyle
 */

module gas.gas_model;

import std.conv;
import std.math;
import std.stdio;
import std.string;
import nm.complex;
import nm.number;

import util.lua;
import util.lua_service;
import util.msg_service;
import gas.gas_state;
import gas.physical_constants;

immutable double SMALL_MOLE_FRACTION = 1.0e-15;
immutable double MIN_MASS_FRACTION = 1.0e-30;
immutable double MIN_MOLES = 1.0e-30;
immutable double T_MIN = 20.0; 
immutable double MASSF_ERROR_TOL = 1.0e-6;

class GasModelException : Exception {
    this(string message, string file=__FILE__, size_t line=__LINE__,
         Throwable next=null)
    {
        super(message, file, line, next);
    }
}

class GasModel {
public:
    @nogc @property uint n_species() const { return _n_species; }
    @nogc @property uint n_modes() const { return _n_modes; }
    @property ref double[] mol_masses() { return _mol_masses; }
    @property ref double[] LJ_sigmas() { return _LJ_sigmas; }
    @property ref double[] LJ_epsilons() { return _LJ_epsilons; }
    final string species_name(int i) const { return _species_names[i]; }
    final int species_index(string spName) const { return _species_indices.get(spName, -1); }

    void create_species_reverse_lookup()
    {
        _species_indices.clear;
        foreach ( int isp; 0 .. _n_species ) {
            _species_indices[_species_names[isp]] = isp;
        }
    }
    // Methods to be overridden.
    //
    // Although the following methods are not intended to alter their
    // GasModel object in a formal sense, they are not marked const.
    // The reason for this non-const-ness is that some GasModel classes
    // have private workspace that needs to be alterable.
    abstract void update_thermo_from_pT(GasState Q);
    abstract void update_thermo_from_rhou(GasState Q);
    abstract void update_thermo_from_rhoT(GasState Q);
    abstract void update_thermo_from_rhop(GasState Q);
    abstract void update_thermo_from_ps(GasState Q, number s);
    abstract void update_thermo_from_hs(GasState Q, number h, number s);
    abstract void update_sound_speed(GasState Q);
    abstract void update_trans_coeffs(GasState Q);
    // const void update_diff_coeffs(ref GasState Q) {}

    // Methods to be overridden.
    abstract number dudT_const_v(in GasState Q); 
    abstract number dhdT_const_p(in GasState Q); 
    abstract number dpdrho_const_T(in GasState Q); 
    abstract number gas_constant(in GasState Q);
    abstract number internal_energy(in GasState Q);
    abstract number enthalpy(in GasState Q);
    number enthalpy(in GasState Q, int isp)
    {
        // For the single-species gases, provide a default implementation
        // but we need to be careful to override this for multi-component gases.
        return enthalpy(Q);
    }
    abstract number entropy(in GasState Q);
    number entropy(in GasState Q, int isp)
    {
        // For the single-species gases, provide a default implementation
        // but we need to be carefule to override this for multi-component gases.
        return entropy(Q);
    }

    number gibbs_free_energy(GasState Q, int isp)
    {
        number h = enthalpy(Q, isp);
        number s = entropy(Q, isp);
        number g = h - Q.T*s;
        return g;
    }
    
    final number Cv(in GasState Q) { return dudT_const_v(Q); }
    final number Cp(in GasState Q) { return dhdT_const_p(Q); }
    final number R(in GasState Q)  { return gas_constant(Q); }
    final number gamma(in GasState Q) { return Cp(Q)/Cv(Q); }
    final number molecular_mass(in GasState Q) 
    in {
        assert(Q.massf.length == _mol_masses.length, brokenPreCondition("Inconsistent array lengths."));
    }
    body {
        return mixture_molecular_mass(Q.massf, _mol_masses);
    }
    final void massf2molef(in GasState Q, number[] molef) 
    in {
        assert(Q.massf.length == molef.length, brokenPreCondition("Inconsistent array lengths."));
    }
    body {
        gas.gas_model.massf2molef(Q.massf, _mol_masses, molef);
    }
    final void molef2massf(in number[] molef, GasState Q) 
    in {
        assert(Q.massf.length == molef.length, brokenPreCondition("Inconsistent array lengths."));
    }
    body {
        gas.gas_model.molef2massf(molef, _mol_masses, Q.massf);
    }
    final void massf2conc(in GasState Q, number[] conc) 
    in {
        assert(Q.massf.length == conc.length, brokenPreCondition("Inconsistent array lengths."));
    }
    body {
        foreach ( i; 0.._n_species ) {
            conc[i] = Q.massf[i]*Q.rho / _mol_masses[i];
            if ( conc[i] < MIN_MOLES ) conc[i] = 0.0;
        }
    }
    final void conc2massf(in number[] conc, GasState Q) 
    in {
        assert(Q.massf.length == conc.length, brokenPreCondition("Inconsisten array lengths."));
    }
    body {
        foreach ( i; 0.._n_species ) {
            Q.massf[i] = conc[i]*_mol_masses[i] / Q.rho;
            if ( Q.massf[i] < MIN_MASS_FRACTION ) Q.massf[i] = 0.0;
        }
    }

protected:
    // These data need to be properly initialized by the derived class.
    uint _n_species;
    uint _n_modes;
    string[] _species_names;
    int[string] _species_indices;
    double[] _mol_masses;
    double[] _LJ_sigmas;
    double[] _LJ_epsilons;
} // end class GasModel

@nogc void scale_mass_fractions(ref number[] massf, double tolerance=0.0,
                                double assert_error_tolerance=0.1)
{
    auto my_nsp = massf.length;
    if (my_nsp == 1) {
        // Single species, always expect massf[0]==1.0, so we can take a short-cut.
        assert(fabs(massf[0] - 1.0) < assert_error_tolerance,
               "Single species mass fraction far from 1.0");
        massf[0] = 1.0;
    } else {
        // Multiple species, do the full job.
        number massf_sum = 0.0;
        foreach(isp; 0 .. my_nsp) {
            massf[isp] = massf[isp] >= 0.0 ? massf[isp] : to!number(0.0);
            massf_sum += massf[isp];
        }
        assert(fabs(massf_sum - 1.0) < assert_error_tolerance,
               "Sum of species mass fractions far from 1.0");
        if ( fabs(massf_sum - 1.0) > tolerance ) {
            foreach(isp; 0 .. my_nsp) massf[isp] /= massf_sum;
        }
    }
    return;
} // end scale_mass_fractions()

@nogc pure number mass_average(in GasState Q, in number[] phi)
in {
    assert(Q.massf.length == phi.length, "Inconsistent array lengths.");
}
body {
    number result = 0.0;
    foreach ( i; 0..Q.massf.length ) result += Q.massf[i] * phi[i];
    return result;
}

@nogc pure number mole_average(in number[] molef, in number[] phi)
in {
    assert(molef.length == phi.length, "Inconsistent array lengths.");
}
body {
    number result = 0.0;
    foreach ( i; 0..molef.length ) result += molef[i] * phi[i];
    return result;
}
version(complex_numbers) {
    // We want to retain the flavour with double numbers.
    @nogc pure number mole_average(in number[] molef, in double[] phi)
        in {
            assert(molef.length == phi.length, "Inconsistent array lengths.");
        }
    body {
        number result = 0.0;
        foreach ( i; 0..molef.length ) result += molef[i] * phi[i];
        return result;
    }
}

@nogc pure number mixture_molecular_mass(in number[] massf, in double[] mol_masses)
in {
    assert(massf.length == mol_masses.length, "Inconsistent array lengths.");
}
body {
    number M_inv = 0.0;
    foreach (i; 0 .. massf.length) M_inv += massf[i] / mol_masses[i];
    return 1.0/M_inv;
}

@nogc void massf2molef(in number[] massf, in double[] mol_masses, number[] molef)
in {
    assert(massf.length == mol_masses.length, "Inconsistent array lengths.");
    assert(massf.length == molef.length, "Inconsistent array lengths.");
}
body {
    number mixMolMass = mixture_molecular_mass(massf, mol_masses);
    foreach ( i; 0..massf.length ) molef[i] = massf[i] * mixMolMass / mol_masses[i];
}

@nogc void molef2massf(in number[] molef, in double[] mol_masses, number[] massf)
in {
    assert(massf.length == mol_masses.length, "Inconsistent array lengths.");
    assert(massf.length == molef.length, "Inconsistent array lengths.");
}
body {
    number mixMolMass = mole_average(molef, mol_masses);
    foreach ( i; 0..massf.length ) massf[i] = molef[i] * mol_masses[i] / mixMolMass;
}


//----------------------------------------------------------------------------------------
// PART 4. Fill-in functions for gas models that don't define all functions
//         specified in the base class GasModel
//----------------------------------------------------------------------------------------

/* The following functions:
   update_thermo_state_pT(), update_thermo_state_rhoT(), update_thermo_state_rhop() 
   are for updating the thermo state from when  the gas model does not  have a method
   for doing so with those variables, but does have a defined method for
   update_thermo_from_rhou(). (e.g. in the UniformLUT class)
   A guess is made for rho & e and that guess is iterated using the  Newton-Raphson 
   method.
   A GasModel object is a function parameter so that the update method from rho,e for
   that gas model can be called.
   The funcions:
   update_thermo_state_ps(), and update_thermo_state_hs() actually iterate on the update
   update_thermo_from_pT(), as  called from the gas model (though the p,T update can be
   defined as the function defined here that itself iterates on the update method for
   rho,e)
*/

immutable MAX_RELATIVE_STEP = 0.1;
immutable MAX_STEPS = 30;

void update_thermo_state_pT(GasModel gmodel, GasState Q)
{
    number drho, rho_old, rho_new, e_old, e_new, de;
    number drho_sign, de_sign;
    number Cv_eff, R_eff, T_old;
    number fp_old, fT_old, fp_new, fT_new;
    number dfp_drho, dfT_drho, dfp_de, dfT_de, det;
    int converged, count;

    number p_given = Q.p;
    number T_given = Q.T;
    // When using single-sided finite-differences on the
    // curve-fit EOS functions, we really cannot expect 
    // much more than 0.1% tolerance here.
    // However, we want a tighter tolerance so that the starting values
    // don't get shifted noticeably.
 
    number fT_tol = 1.0e-6 * T_given;
    number fp_tol = 1.0e-6 * p_given;
    number fp_tol_fail = 0.02 * p_given;
    number fT_tol_fail = 0.02 * T_given;

    Q.rho = 1.0; // kg/m**3
    Q.u = 2.0e5; // J/kg
    // Get an idea of the gas properties by calling the original
    // equation of state with some starting values for density
    // and internal energy.
    gmodel.update_thermo_from_rhou(Q);
    
    T_old = Q.T;
    R_eff = Q.p / (Q.rho * T_old);
    de = 0.01 * Q.u;
    Q.u += de;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 1 failed in %s\n", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }

    Cv_eff = de / (Q.T - T_old);
    // Now, get a better guess for the appropriate density and
    // internal energy.
    e_old = Q.u + (T_given - Q.T) * Cv_eff;
    rho_old = p_given / (R_eff * T_given);

    // Evaluate state variables using this guess.
    Q.rho = rho_old;
    Q.u = e_old;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 2 failed in %s\n", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }

    fp_old = p_given - Q.p;
    fT_old = T_given - Q.T;
    // Update the guess using Newton iterations
    // with the partial derivatives being estimated
    // via finite differences.
    converged = (fabs(fp_old) < fp_tol) && (fabs(fT_old) < fT_tol);
    count = 0;
    while ( !converged && count < MAX_STEPS ) {
        // Perturb first dimension to get derivatives.
        rho_new = rho_old * 1.001;
        e_new = e_old;
        Q.rho = rho_new;
        Q.u = e_new;
        try { gmodel.update_thermo_from_rhou(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s failed at call A in %s\n", count, __FUNCTION__); 
            msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }
        fp_new = p_given - Q.p;
        fT_new = T_given - Q.T;
        dfp_drho = (fp_new - fp_old) / (rho_new - rho_old);
        dfT_drho = (fT_new - fT_old) / (rho_new - rho_old);
        // Perturb other dimension to get derivatives.
        rho_new = rho_old;
        e_new = e_old * 1.001;
        Q.rho = rho_new;
        Q.u = e_new;

        try { gmodel.update_thermo_from_rhou(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s failed at call B in %", count, __FUNCTION__);
            msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }

        fp_new = p_given - Q.p;
        fT_new = T_given - Q.T;
        dfp_de = (fp_new - fp_old) / (e_new - e_old);
        dfT_de = (fT_new - fT_old) / (e_new - e_old);
        det = dfp_drho * dfT_de - dfT_drho * dfp_de;
        if( fabs(det) < 1.0e-12 ) {
            string msg;
            msg ~= format("Error in function %s\n", __FUNCTION__);
            msg ~= format("    Nearly zero determinant, det = ", det);
            throw new GasModelException(msg);
        }
        drho = (-dfT_de * fp_old + dfp_de * fT_old) / det;
        de = (dfT_drho * fp_old - dfp_drho * fT_old) / det;
        if( fabs(drho) > MAX_RELATIVE_STEP * rho_old ) {
            // move a little toward the goal 
            drho_sign = (drho > 0.0 ? 1.0 : -1.0);
            drho = drho_sign * MAX_RELATIVE_STEP * rho_old;
        } 
        if( fabs(de) > MAX_RELATIVE_STEP * e_old ) {
            // move a little toward the goal
            de_sign = (de > 0.0 ? 1.0 : -1.0);
            de = de_sign * MAX_RELATIVE_STEP * e_old;
        } 
        rho_old += drho;
        e_old += de;
        // Make sure of consistent thermo state.
        Q.rho = rho_old;
        Q.u = e_old;
        try { gmodel.update_thermo_from_rhou(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s failed in %s\n", count, __FUNCTION__);
            msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }
        // Prepare for next iteration.
        fp_old = p_given - Q.p;
        fT_old = T_given - Q.T;
        converged = (fabs(fp_old) < fp_tol) && (fabs(fT_old) < fT_tol);
        ++count;
    } // end while 

    if ( count >= MAX_STEPS ) {
        string msg;
        msg ~= format("Warning in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations did not converge.\n");
        msg ~= format("    fp_old = %g, fT_old = %g\n", fp_old, fT_old);
        msg ~= format("    p_given = %.10s, T_given, %.5s\n", p_given, T_given); 
        msg ~= "  Supplied Q:" ~ Q.toString();
        writeln(msg);

    }

    if( (fabs(fp_old) > fp_tol_fail) || (fabs(fT_old) > fT_tol_fail) ) {
        string msg;
        msg ~= format("Error in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations failed badly.\n");
        msg ~= format("    p_given = %.10s, T_given, %.5s\n", p_given, T_given); 
        msg ~= format("    fp_old = %g, fT_old = %g\n", fp_old, fT_old);
        msg ~= "  Supplied Q:" ~ Q.toString();
        throw new GasModelException(msg);
    }
}

void update_thermo_state_rhoT(GasModel gmodel, GasState Q)  
{
    // This method can be applied to single-species models only
    number e_old, e_new, de, tmp, de_sign;
    number Cv_eff, T_old;
    number dfT_de, fT_old, fT_new;
    int converged, count;

    number rho_given = Q.rho;
    number T_given = Q.T;
    // When using single-sided finite-differences on the
    // curve-fit EOS functions, we really cannot expect 
    // much more than 0.1% tolerance here.
    // However, we want a tighter tolerance so that the starting values
    // don't get shifted noticeably.
    number fT_tol = 1.0e-6 * T_given;
    number fT_tol_fail = 0.02 * T_given;

    // Get an idea of the gas properties by calling the original
    // equation of state with some dummy values for density
    // and internal energy.
       
    Q.rho = rho_given; // kg/m**3 
    Q.u = 2.0e5; // J/kg 
    gmodel.update_thermo_from_rhou(Q);

    T_old = Q.T;
    de = 0.01 * Q.u;
    Q.u += de;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 0 failed in %s", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }
   
   
    Cv_eff = de / (Q.T - T_old);
    // Now, get a better guess for the appropriate density and internal energy.
    e_old = Q.u + (T_given - Q.T) * Cv_eff;
    // Evaluate state variables using this guess.
    Q.rho = rho_given;
    Q.u = e_old;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 1 failed in %s", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }
   
    fT_old = T_given - Q.T;
    // Perturb to get derivative.
    e_new = e_old * 1.001;
    Q.rho = rho_given;
    Q.u = e_new;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 2 failed in %s", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }

    fT_new = T_given - Q.T;
    dfT_de = (fT_new - fT_old) / (e_new - e_old);

    // At the start of iteration, we want *_old to be the best guess.
    if ( fabs(fT_new) < fabs(fT_old) ) {
        tmp = fT_new; fT_new = fT_old; fT_old = tmp;
        tmp = e_new; e_new = e_old; e_old = tmp;
    }
    // Update the guess using Newton iterations
    // with the partial derivatives being estimated
    // via finite differences.
    converged = (fabs(fT_old) < fT_tol);
    count = 0;
    while ( !converged && count < MAX_STEPS ) {
        de = -fT_old / dfT_de;
        if ( fabs(de) > MAX_RELATIVE_STEP * e_old ) {
            // move a little toward the goal 
            de_sign = (de > 0.0 ? 1.0 : -1.0);
            de = de_sign * MAX_RELATIVE_STEP * fabs(e_old);
        } 
        e_new = e_old + de;
        Q.rho = rho_given;
        Q.u = e_new;
        try { gmodel.update_thermo_from_rhou(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s failed in %", count, __FUNCTION__);
            msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }
        fT_new = T_given - Q.T;
        dfT_de = (fT_new - fT_old) / (e_new - e_old);
        // Prepare for the next iteration.
        ++count;
        fT_old = fT_new;
        e_old = e_new;
        converged = fabs(fT_old) < fT_tol;
    }   // end while 
    // Ensure that we have the current data for all EOS variables.
    Q.rho = rho_given;
    Q.u = e_old;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Function %s failed after finishing iterations", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }

     if ( count >= MAX_STEPS ) {
        string msg;
        msg ~= format("Warning in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations did not converge.\n");
        msg ~= format("    fT_old = %g\n", fT_old);
        msg ~= format("    rho_given = %.5s, T_given, %.5s\n", rho_given, T_given); 
        msg ~= "  Supplied Q:" ~ Q.toString;
        writeln(msg);

    }
    if ( fabs(fT_old) > fT_tol_fail ) {
        string msg;
        msg ~= format("Error in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations failed badly.\n");
        msg ~= format("    rho_given = %.5s, T_given, %.5s\n", rho_given, T_given); 
        msg ~= "  Supplied Q:" ~ Q.toString();
        throw new GasModelException(msg);
    }  
}

void update_thermo_state_rhop(GasModel gmodel, GasState Q)
{
    number e_old, e_new, de, dedp, tmp, de_sign;
    number p_old;
    number dfp_de, fp_old, fp_new;
    int converged, count;

    number rho_given = Q.rho;
    number p_given = Q.p;
    // When using single-sided finite-differences on the
    // curve-fit EOS functions, we really cannot expect 
    // much more than 0.1% tolerance here.
    // However, we want a tighter tolerance so that the starting values
    // don't get shifted noticeably.
    number fp_tol = 1.0e-6 * p_given;
    number fp_tol_fail = 0.02 * p_given;

    // Get an idea of the gas properties by calling the original
    // equation of state with some dummy values for density
    // and internal energy.
    Q.rho = rho_given; // kg/m**3
    Q.u = 2.0e5; // J/kg 
    gmodel.update_thermo_from_rhou(Q);
    p_old = Q.p;
    de = 0.01 * Q.u;
    Q.u += de;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 0 failed in %s\n", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }

    dedp = de / (Q.p - p_old);
    // Now, get a better guess for the appropriate internal energy.
    e_old = Q.u + (p_given - Q.p) * dedp;
    //     printf( "Initial guess e_old= %g dedp= %g\n", e_old, dedp );
    // Evaluate state variables using this guess.
    Q.rho = rho_given;
    Q.u = e_old;


    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 1 failed in %s\n", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }

    fp_old = p_given - Q.p;
    // Perturb to get derivative.
    e_new = e_old * 1.001;
    Q.rho = rho_given;
    Q.u = e_new;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 2 failed in %s\n", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }

    fp_new = p_given - Q.p;
    dfp_de = (fp_new - fp_old) / (e_new - e_old);

    // At the start of iteration, we want *_old to be the best guess.
    if ( fabs(fp_new) < fabs(fp_old) ) {
        tmp = fp_new; fp_new = fp_old; fp_old = tmp;
        tmp = e_new; e_new = e_old; e_old = tmp;
    }
    // Update the guess using Newton iterations
    // with the partial derivatives being estimated
    // via finite differences.
    converged = (fabs(fp_old) < fp_tol);
    count = 0;
    while ( !converged && count < MAX_STEPS ) {
        de = -fp_old / dfp_de;
        if ( fabs(de) > MAX_RELATIVE_STEP * e_old ) {
            // move a little toward the goal
            de_sign = (de > 0.0 ? 1.0 : -1.0);
            de = de_sign * MAX_RELATIVE_STEP * fabs(e_old);
        } 
        e_new = e_old + de;
        Q.rho = rho_given;
        Q.u = e_new;

        try { gmodel.update_thermo_from_rhou(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s failed in %", count, __FUNCTION__);
            msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }

        fp_new = p_given - Q.p;
        dfp_de = (fp_new - fp_old) / (e_new - e_old);
        // Prepare for next iteration.
        ++count;
        fp_old = fp_new;
        e_old = e_new;
        converged = fabs(fp_old) < fp_tol;
    }   // end while 
    // Ensure that we have the current data for all EOS variables.
    Q.rho = rho_given;
    Q.u = e_old;

    try { gmodel.update_thermo_from_rhou(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Function %s failed after finishing iterations", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_rhou() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }

      if ( count >= MAX_STEPS ) {
        string msg;
        msg ~= format("Error in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations did not converge.\n");
        msg ~= format("    fp_old = %g, e_old = %g\n", fp_old, e_old);
        msg ~= format("    rho_given = %.5s, p_given, %.8s\n", rho_given, p_given); 
        msg ~= "  Supplied Q:" ~ Q.toString;
        writeln(msg);
    }

    if ( fabs(fp_old) > fp_tol_fail ) {
        string msg;
        msg ~= format("Error in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations failed badly.\n");
        msg ~= format("    rho_given = %.5s, T_given, %.8s\n", rho_given, p_given); 
        msg ~= "  Supplied Q:" ~ Q.toString();
        throw new GasModelException(msg);
    }
}

void update_thermo_state_ps(GasModel gmodel, GasState Q, number s) 
{
    number T_old, T_new, dT, tmp, dT_sign;
    number dfs_dT, fs_old, fs_new;
    int converged, count;

    number s_given = s;
    number p_given = Q.p;
   
    // When using single-sided finite-differences on the
    // curve-fit EOS functions, we really cannot expect 
    // much more than 0.1% tolerance here.
    // However, we want a tighter tolerance so that the starting values
    // don't get shifted noticeably.
    number fs_tol = 1.0e-6 * s_given;
    number fs_tol_fail = 0.02 * s_given;

    // Guess the thermo state assuming that T is a good guess.
    T_old = Q.T;
    try { gmodel.update_thermo_from_pT(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 0 failed in %s\n", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_pT() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }
    ////**** Need to check this is the correct method - is called 2 more times*****/////
    number s_old = gmodel.entropy(Q);   
    fs_old = s_given - s_old;
    // Perturb T to get a derivative estimate
    T_new = T_old * 1.001;
    Q.T = T_new;

    try { gmodel.update_thermo_from_pT(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Starting guess at iteration 1 failed in %s\n", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_pT() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }
    number s_new = gmodel.entropy(Q);
    fs_new = s_given - s_new;
    dfs_dT = (fs_new - fs_old)/(T_new - T_old);
    // At the start of iteration, we want *_old to be the best guess.
    if ( fabs(fs_new) < fabs(fs_old) ) {
        tmp = fs_new; fs_new = fs_old; fs_old = tmp;
        tmp = s_new; s_new = s_old; s_old = tmp;
    }
    // Update the guess using Newton iterations
    // with the partial derivatives being estimated
    // via finite differences.
    converged = (fabs(fs_old) < fs_tol);
    count = 0;
    while ( !converged && count < MAX_STEPS ) {
        dT = -fs_old / dfs_dT;
        if ( fabs(dT) > MAX_RELATIVE_STEP * T_old ) {
            // move a little toward the goal
            dT_sign = (dT > 0.0 ? 1.0 : -1.0);
            dT = dT_sign * MAX_RELATIVE_STEP * fabs(T_old);
        } 
        T_new = T_old + dT;
        Q.T = T_new;
        try { gmodel.update_thermo_from_pT(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s failed in %", count, __FUNCTION__);
            msg ~= format("Exception message from update_thermo_from_pT() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }
        s_new = gmodel.entropy(Q);
        fs_new = s_given - s_new;
        dfs_dT = (fs_new - fs_old) / (T_new - T_old);
        // Prepare for next iteration.
        ++count;
        fs_old = fs_new;
        T_old = T_new;
        converged = (fabs(fs_old) < fs_tol);
    }   // end while 
    // Ensure that we have the current data for all EOS variables.
    Q.T = T_old;

    try { gmodel.update_thermo_from_pT(Q); }
    catch (Exception caughtException) {
        string msg;
        msg ~= format("Function %s failed after finishing iterations", __FUNCTION__);
        msg ~= format("Exception message from update_thermo_from_pT() was:\n\n");
        msg ~= to!string(caughtException);
        throw new GasModelException(msg);
    }
    if ( count >= MAX_STEPS ) {
        string msg;
        msg ~= format("Error in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations did not converge.\n");
        msg ~= format("    fs_old = %g\n", fs_old);
        msg ~= format("    p_given = %.8s, s_given, %.5s\n", p_given, s_given); 
        msg ~= "  Supplied Q:" ~ Q.toString;
        writeln(msg);
    }

    if ( fabs(fs_old) > fs_tol_fail ) {
        string msg;
        msg ~= format("Error in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations failed badly.\n");
        msg ~= format("    p_given = %.8s, s_given, %.5s\n", p_given, s_given); 
        msg ~= "  Supplied Q:" ~ Q.toString();
        throw new GasModelException(msg);
    }
}

void update_thermo_state_hs(GasModel gmodel, GasState Q, number h, number s)
{
    number dp, p_old, p_new, T_old, T_new, dT;
    number dp_sign, dT_sign;
    number fh_old, fs_old, fh_new, fs_new;
    number dfh_dp, dfs_dp, dfh_dT, dfs_dT, det;
    int converged, count;

    number h_given = h;
    number s_given = s;
    // When using single-sided finite-differences on the
    // curve-fit EOS functions, we really cannot expect 
    // much more than 0.1% tolerance here.
    // However, we want a tighter tolerance so that the starting values
    // don't get shifted noticeably.
    number fh_tol = 1.0e-6 * h_given;
    number fs_tol = 1.0e-6 * s_given;
    number fh_tol_fail = 0.02 * h_given;
    number fs_tol_fail = 0.02 * s_given;

    // Use current gas state as guess
    p_old = Q.p;
    T_old = Q.T;
    number h_new = gmodel.enthalpy(Q);
    number s_new = gmodel.entropy(Q);
    fh_old = h_given - h_new;
    fs_old = s_given - s_new;

    // Update the guess using Newton iterations
    // with the partial derivatives being estimated
    // via finite differences.
    converged = (fabs(fh_old) < fh_tol) && (fabs(fs_old) < fs_tol);
    count = 0;
    while ( !converged && count < MAX_STEPS ) {
        // Perturb first dimension to get derivatives.
        p_new = p_old * 1.001;
        T_new = T_old;
        Q.p = p_new;
        Q.T = T_new;
        try { gmodel.update_thermo_from_pT(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s at call A failed in %", count, __FUNCTION__);
            msg ~= format("Exception message from update_thermo_from_pT() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }
        h_new = gmodel.enthalpy(Q);
        s_new = gmodel.entropy(Q);
        fh_new = h_given - h_new;
        fs_new = s_given - s_new;
        dfh_dp = (fh_new - fh_old) / (p_new - p_old);
        dfs_dp = (fs_new - fs_old) / (p_new - p_old);
        // Perturb other dimension to get derivatives.
        p_new = p_old;
        T_new = T_old * 1.001;
        Q.p = p_new;
        Q.T = T_new;
        try { gmodel.update_thermo_from_pT(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s at call B failed in %", count, __FUNCTION__);
            msg ~= format("Exception message from update_thermo_from_pT() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }
        h_new = gmodel.enthalpy(Q);
        s_new = gmodel.entropy(Q);
        fh_new = h_given - h_new;
        fs_new = s_given - s_new;
        dfh_dT = (fh_new - fh_old) / (T_new - T_old);
        dfs_dT = (fs_new - fs_old) / (T_new - T_old);

        det = dfh_dp * dfs_dT - dfs_dp * dfh_dT;
      
        if( fabs(det) < 1.0e-12 ) {
            string msg;
            msg ~= format("Error in function %s\n", __FUNCTION__);
            msg ~= format("    Nearly zero determinant, det = ", det);
            throw new GasModelException(msg);
        }
        dp = (-dfs_dT * fh_old + dfh_dT * fs_old) / det;
        dT = (dfs_dp * fh_old - dfh_dp * fs_old) / det;
        if( fabs(dp) > MAX_RELATIVE_STEP * p_old ) {
            // move a little toward the goal 
            dp_sign = (dp > 0.0 ? 1.0 : -1.0);
            dp = dp_sign * MAX_RELATIVE_STEP * p_old;
        } 
        if( fabs(dT) > MAX_RELATIVE_STEP * T_old ) {
            // move a little toward the goal
            dT_sign = (dT > 0.0 ? 1.0 : -1.0);
            dT = dT_sign * MAX_RELATIVE_STEP * T_old;
        } 
        p_old += dp;
        T_old += dT;
        // Make sure of consistent thermo state.
        Q.p = p_old;
        Q.T = T_old;
        try { gmodel.update_thermo_from_pT(Q); }
        catch (Exception caughtException) {
            string msg;
            msg ~= format("Iteration %s at call C failed in %", count, __FUNCTION__);
            msg ~= format("Exception message from update_thermo_from_pT() was:\n\n");
            msg ~= to!string(caughtException);
            throw new GasModelException(msg);
        }
        h_new = gmodel.enthalpy(Q);
        s_new = gmodel.entropy(Q);
        // Prepare for next iteration.
        fh_old = h_given - h_new;
        fs_old = s_given - s_new;
        converged = (fabs(fh_old) < fh_tol) && (fabs(fs_old) < fs_tol);
        ++count;
    } // end while 

    if ( count >= MAX_STEPS ) {
        string msg;
        msg ~= format("Error in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations did not converge.\n");
        msg ~= format("    fh_old = %g, fs_old = %g\n", fh_old, fs_old);
        msg ~= format("    h_given = %.10s, h_given, %.5s\n", h_given, s_given); 
        msg ~= "  Supplied Q:" ~ Q.toString();
        writeln(msg);
    }

    if( (fabs(fh_old) > fh_tol_fail) || (fabs(fs_old) > fs_tol_fail) ) {
        string msg;
        msg ~= format("Error in function: %s:\n", __FUNCTION__);
        msg ~= format("    Iterations failed badly.\n");
        msg ~= format("    h_given = %.10s, h_given, %.5s\n", h_given, s_given);        
        msg ~= "  Supplied Q:" ~ Q.toString();
        throw new GasModelException(msg);
    }
} // end update_thermo_state_hs()


//----------------------------------------------------------------------------------------
// PART 5. Utility functions to make GasModel and ChemicalReactor objects
//----------------------------------------------------------------------------------------

// Utility function to construct specific gas models needs to know about
// all of the gas-model modules that are in play.
version(complex_numbers) {
    import gas.ideal_gas;
} else {
    import gas.ideal_gas;
    import gas.cea_gas;
    import gas.therm_perf_gas;
    import gas.very_viscous_air;
    import gas.co2gas;
    import gas.co2gas_sw;
    import gas.sf6virial;
    import gas.uniform_lut;
    import gas.adaptive_lut_CEA;
    import gas.ideal_air_proxy;
    import gas.powers_aslam_gas;
    import gas.two_temperature_reacting_argon;
    import gas.ideal_dissociating_gas;
    import gas.two_temperature_air;
    import gas.two_temperature_nitrogen;
    import gas.vib_specific_nitrogen;
    import gas.fuel_air_mix;
    import gas.equilibrium_gas;
    import gas.steam : Steam;
}
import core.stdc.stdlib : exit;


GasModel init_gas_model(string file_name="gas-model.lua")
/**
 * Get the instructions for setting up the GasModel object from a Lua file.
 * The first item in the file should be a model name which we use to select 
 * the specific GasModel class.
 * The constructor for each specific gas model will know how to pick out the
 * specific parameters of interest.
 * As new GasModel classes are added to the collection, just 
 * add a new case to the switch statement below.
 */
{
    lua_State* L;
   
    try { 
        L = init_lua_State();
        doLuaFile(L, file_name);
    } catch (Exception e) {
        string msg = "In function init_gas_model() in gas_model.d";
        msg ~= format("there was a problem parsing the input file: ", file_name);
        msg ~= " There could be a Lua syntax error OR the file might not exist.";
        throw new GasModelException(msg);
    }
    string gas_model_name;
    try {
        gas_model_name = getString(L, LUA_GLOBALSINDEX, "model");
    } catch (Exception e) {
        string msg = "In function init_gas_model() in gas_model.d, ";
        msg ~= "there was a problem reading the 'model' name";
        msg ~= " from the gas model input Lua file.";
        throw new GasModelException(msg);
    }
    GasModel gm;
    version(complex_numbers) {
        // Limited number of options.
        switch (gas_model_name) {
        case "IdealGas":
            gm = new IdealGas(L);
            break;
        default:
            string errMsg = format("The gas model '%s' is not available.", gas_model_name);
            throw new Error(errMsg);
        }
    } else {
        // All options for double_numbers.
        switch (gas_model_name) {
        case "IdealGas":
            gm = new IdealGas(L);
            break;
        case "CEAGas":
            gm = new CEAGas(L);
            break;
        case "ThermallyPerfectGas":
            gm = new ThermallyPerfectGas(L);
            break;
        case "VeryViscousAir":
            gm = new VeryViscousAir(L);
            break;
        case "CO2Gas":
            gm = new CO2Gas(L);
            break;
        case "CO2GasSW":
            gm = new CO2GasSW(L);
            break;
        case "SF6Virial":
            gm = new SF6Virial(L);
            break;
        case "look-up table":  
            gm = new  UniformLUT(L);
            break;
        case "CEA adaptive look-up table":
            gm = new AdaptiveLUT(L);
            break;
        case "IdealAirProxy":
            gm = new IdealAirProxy(); // no further config in the Lua file
            break;
        case "PowersAslamGas":
            gm = new PowersAslamGas(L);
            break;
        case "TwoTemperatureReactingArgon":
            gm = new TwoTemperatureReactingArgon(L);
            break;
        case "IdealDissociatingGas":
            gm = new IdealDissociatingGas(L);
            break;
        case "TwoTemperatureAir":
            gm = new TwoTemperatureAir(L);
            break;
        case "TwoTemperatureNitrogen":
            gm = new TwoTemperatureNitrogen();
            break;
        case "VibSpecificNitrogen":
            gm = new VibSpecificNitrogen();
            break;
        case "FuelAirMix":
            gm = new FuelAirMix(L);
            break;
        case "EquilibriumGas":
            gm = new EquilibriumGas(L);
            break;
        case "Steam":
            gm = new Steam();
            break;
        default:
            string errMsg = format("The gas model '%s' is not available.", gas_model_name);
            throw new Error(errMsg);
        }
    } // end version double_numbers
    lua_close(L);
    return gm;
} // end init_gas_model()


//----------------------------------------------------------------------------------------
// PART 6. Unit tests for the module
//----------------------------------------------------------------------------------------

version(gas_model_test) {
    int main() {
        // Methods for testing gas state class
        auto gd = new GasState(2, 1);
        gd.massf[0] = 0.8;
        gd.massf[1] = 0.2;
        number[] phi = [to!number(9.0), to!number(16.0)];
        assert(approxEqualNumbers(to!number(10.4), mass_average(gd, phi), 1.0e-6));
        
        // Iterative methods test using idealgas single species model
        // These assume IdealGas class is working properly
        GasModel gm;
        try {
            gm = init_gas_model("sample-data/ideal-air-gas-model.lua");
        }
        catch (Exception e) {
            writeln(e.msg);
            string msg;
            msg ~= "Test of iterative methods in gas_model.d require file:";
            msg ~= " ideal-air-gas-model.lua in directory: gas/sample_data";
            throw new Exception(msg);
        }

        gd = new GasState(gm, 100.0e3, 300.0);
        assert(approxEqualNumbers(gm.R(gd), to!number(287.086), 1.0e-4), "gas constant");
        assert(gm.n_modes == 0, "number of energy modes");
        assert(gm.n_species == 1, "number of species");
        assert(approxEqualNumbers(gd.p, to!number(1.0e5)), "pressure");
        assert(approxEqualNumbers(gd.T, to!number(300.0), 1.0e-6), "static temperature");
        assert(approxEqualNumbers(gd.massf[0], to!number(1.0), 1.0e-6), "massf[0]");

        gm.update_thermo_from_pT(gd);
        gm.update_sound_speed(gd);
        assert(approxEqualNumbers(gd.rho, to!number(1.16109), 1.0e-4), "density");
        assert(approxEqualNumbers(gd.u, to!number(215314.0), 1.0e-4), "internal energy");
        assert(approxEqualNumbers(gd.a, to!number(347.241), 1.0e-4), "sound speed");
        gm.update_trans_coeffs(gd);
        assert(approxEqualNumbers(gd.mu, to!number(1.84691e-05), 1.0e-6), "viscosity");
        assert(approxEqualNumbers(gd.k, to!number(0.0262449), 1.0e-6), "conductivity");

        // Select arbitrary energy and density and establish a set of 
        // variables that are thermodynamically consistent
        number e_given = 1.0e7;
        number rho_given = 2.0;
        auto Q = new GasState(gm);
        Q.u = e_given;
        Q.rho = rho_given;
        gm.update_thermo_from_rhou(Q);
        number p_given = Q.p;
        number T_given = Q.T;
        
        // Initialise the same state from the different property combinations
        // Test pT iterative update
        Q.p = p_given;
        Q.T = T_given;
        update_thermo_state_pT(gm, Q); 
        // Determine correct entropy/enthalpy for updates that use them
        number s_given = gm.entropy(Q); 
        number h_given = gm.enthalpy(Q);
        assert(approxEqualNumbers(Q.rho, rho_given, 1.0e-6),  failedUnitTest());
        assert(approxEqualNumbers(Q.u, e_given, 1.0e-6), failedUnitTest());
        // Test rhoT iterative update
        Q.rho = rho_given;
        Q.T = T_given;
        update_thermo_state_rhoT(gm, Q);
        assert(approxEqualNumbers(Q.u, e_given, 1.0e-6), failedUnitTest());
        assert(approxEqualNumbers(Q.p, p_given, 1.0e-6),  failedUnitTest());
        // Test rhop iterative update
        Q.rho = rho_given;
        Q.p = p_given;
        assert(approxEqualNumbers(Q.T, T_given, 1.0e-6), failedUnitTest());
        assert(approxEqualNumbers(Q.u, e_given, 1.0e-6), failedUnitTest());
        // Test  ps iterative update
        Q.p = p_given;
        update_thermo_state_ps(gm, Q, s_given); 
        assert(approxEqualNumbers(Q.T, T_given, 1.0e-6), failedUnitTest());
        assert(approxEqualNumbers(Q.u, e_given, 1.0e-6), failedUnitTest());
        assert(approxEqualNumbers(Q.rho, rho_given, 1.0e-6), failedUnitTest());
        // Test hs iterative update
        assert(approxEqualNumbers(Q.T, T_given, 1.0e-6), failedUnitTest());
        assert(approxEqualNumbers(Q.u, e_given, 1.0e-6), failedUnitTest());
        assert(approxEqualNumbers(Q.rho, rho_given, 1.0e-6), failedUnitTest());
        assert(approxEqualNumbers(Q.p, p_given, 1.0e-6), failedUnitTest());

        version(complex_numbers) {
            // Check du/dT = Cv
            number u0 = Q.u;
            double h = 1.0e-20;
            Q.T += complex(0.0,h);
            update_thermo_state_rhoT(gm, Q);
            double myCv = Q.u.im/h;
            assert(approxEqual(myCv, gm.dudT_const_v(Q).re), failedUnitTest());
        }
        return 0;
    }
}

