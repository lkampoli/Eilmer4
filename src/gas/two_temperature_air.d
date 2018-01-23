/**
 * Authors: Rowan G.
 * Date: 2017-12-05
 *
 */

module gas.two_temperature_air;

import std.math : fabs, sqrt, log, pow, exp, PI;
import std.conv;
import std.stdio;
import std.string;
import std.algorithm : canFind;

import gas.gas_model;
import gas.gas_state;
import gas.physical_constants;
import gas.thermo.perf_gas_mix_eos;


immutable double T_REF = 298.15; // K
static string[] molecularSpeciesNames = ["N2", "O2", "NO", "N2+", "O2+", "NO+"];

// For table parameters see end of file.
// They are declared in the static this() function.

class TwoTemperatureAir : GasModel {
public:
    int[] molecularSpecies;
    this(string model, string[] species)
    {
        // For each of the cases, 5-, 7- and 11-species, we know which species
        // must be supplied, however, we don't know what order the user will
        // hand them to us. So we do a little dance below in which we check
        // that the species handed to us are correct and then set the 
        // appropriate properties.
        switch (model) {
        case "5-species":
            if (species.length != 5) {
                string errMsg = "You have selected the 5-species 2-T air model but have not supplied 5 species.\n";
                errMsg ~= format("Instead, you have supplied %d species.\n", species.length);
                errMsg ~= "The valid species for the 5-species 2-T air model are:\n";
                errMsg ~= "   'N', 'O', 'N2', 'O2', 'NO'\n";
                throw new Error(errMsg);
            }
            _n_species = 5;
            _n_modes = 1;
            _species_names.length = 5;
            _mol_masses.length = 5;
            bool[string] validSpecies = ["N":true, "O":true, "N2":true, "O2":true, "NO":true];
            foreach (isp, sp; species) {
                if (sp in validSpecies) {
                    _species_names[isp] = sp;
                    _mol_masses[isp] = __mol_masses[sp];
                }
                else {
                    string errMsg = "The species you supplied is not part of the 5-species 2-T air model,\n";
                    errMsg ~= "or you have supplied a duplicate species.\n";
                    errMsg ~= format("The error occurred for supplied species: %s\n", sp);
                    errMsg ~= "The valid species for the 5-species 2-T air model are:\n";
                    errMsg ~= "   'N', 'O', 'N2', 'O2', 'NO'\n";
                    throw new Error(errMsg);
                }
            }
            create_species_reverse_lookup();
            break;
        case "7-species":
            throw new Error("Two temperature air not available presently with 7 species.");
            /*
            _n_species = 7;
            _n_modes = 1;
            _species_names.length = 7;
            _mol_masses.length = 7;
            _species_names[0] = "N"; _mol_masses[0] = 14.0067e-3;
            _species_names[1] = "O"; _mol_masses[1] = 0.01599940; 
            _species_names[2] = "N2"; _mol_masses[2] = 28.0134e-3; 
            _species_names[3] = "O2"; _mol_masses[3] = 0.03199880;
            _species_names[4] = "NO"; _mol_masses[4] = 0.03000610;
            _species_names[5] = "NO+"; _mol_masses[5] = 30.0055514e-3;
            _species_names[6] = "e-"; _mol_masses[6] = 0.000548579903e-3;
            create_species_reverse_lookup();
            break;
            */
        case "11-species":
            throw new Error("Two temperature air not available presently with 11 species.");
            /*
            _n_species = 11;
            _n_modes = 1;
            _species_names.length = 11;
            _mol_masses.length = 11;
            _species_names[0] = "N"; _mol_masses[0] = 14.0067e-3;
            _species_names[1] = "O"; _mol_masses[1] = 0.01599940; 
            _species_names[2] = "N2"; _mol_masses[2] = 28.0134e-3;
            _species_names[3] = "O2"; _mol_masses[3] = 0.03199880;
            _species_names[4] = "NO"; _mol_masses[4] = 0.03000610;
            _species_names[5] = "N+"; _mol_masses[5] = 14.0061514e-3;
            _species_names[6] = "O+"; _mol_masses[6] = 15.9988514e-3;
            _species_names[7] = "N2+"; _mol_masses[7] = 28.0128514e-3;
            _species_names[8] = "O2+"; _mol_masses[8] = 31.9982514e-3;
            _species_names[9] = "NO+"; _mol_masses[9] = 30.0055514e-3;
            _species_names[10] = "e-"; _mol_masses[10] = 0.000548579903e-3;
            create_species_reverse_lookup();
            break;
            */
        default:
            string errMsg = format("The model name '%s' is not a valid selection for the two-temperature air model.", model);
            throw new Error(errMsg);
        }
        
        _molef.length = _n_species;
        _particleMass.length = _n_species;
        foreach (isp; 0 .. _n_species) {
            _particleMass[isp] = mol_masses[isp]/Avogadro_number;
            _particleMass[isp] *= 1000.0; // kg -> g
        }

        _R.length = _n_species;
        foreach (isp; 0 .. _n_species) {
            _R[isp] = R_universal/_mol_masses[isp];
        }
        _pgMixEOS = new PerfectGasMixEOS(_R);

        _del_hf.length = _n_species;
        foreach (isp; 0 .. _n_species) {
            _del_hf[isp] = del_hf[_species_names[isp]];
        }

        _Cp_tr_rot.length = _n_species;
        foreach (isp; 0 .. _n_species) {
            _Cp_tr_rot[isp] = (5./2.)*_R[isp];
            if (canFind(molecularSpeciesNames, _species_names[isp])) {
                _Cp_tr_rot[isp] += _R[isp];
                molecularSpecies ~= isp;
            }
        }

        // Setup storage of parameters for collision integrals.
        _A_11.length = _n_species;
        _B_11.length = _n_species;
        _C_11.length = _n_species;
        _D_11.length = _n_species;
        _Delta_11.length = _n_species;
        _alpha.length = _n_species;
        _A_22.length = _n_species;
        _B_22.length = _n_species;
        _C_22.length = _n_species;
        _D_22.length = _n_species;
        _Delta_22.length = _n_species;
        _mu.length = _n_species;
        foreach (isp; 0 .. _n_species) {
            _A_11[isp].length = isp+1;
            _B_11[isp].length = isp+1;
            _C_11[isp].length = isp+1;
            _D_11[isp].length = isp+1;
            _A_22[isp].length = isp+1;
            _B_22[isp].length = isp+1;
            _C_22[isp].length = isp+1;
            _D_22[isp].length = isp+1;
            _mu[isp].length = isp+1;
            // The following are NOT ragged arrays, unlike above.
            _Delta_11[isp].length = _n_species;
            _Delta_22[isp].length = _n_species;
            _alpha[isp].length = _n_species; 
            foreach (jsp; 0 .. isp+1) {
                string key = _species_names[isp] ~ "-" ~ _species_names[jsp];
                if (!(key in A_11)) {
                    // Just reverser the order, eg. N2-O2 --> O2-N2
                    key = _species_names[jsp] ~ "-" ~ _species_names[isp];
                }
                _A_11[isp][jsp] = A_11[key];
                _B_11[isp][jsp] = B_11[key];
                _C_11[isp][jsp] = C_11[key];
                _D_11[isp][jsp] = D_11[key];
                _A_22[isp][jsp] = A_22[key];
                _B_22[isp][jsp] = B_22[key];
                _C_22[isp][jsp] = C_22[key];
                _D_22[isp][jsp] = D_22[key];
                double M_isp = mol_masses[isp];
                double M_jsp = mol_masses[jsp];
                _mu[isp][jsp] = (M_isp*M_jsp)/(M_isp + M_jsp);
                _mu[isp][jsp] *= 1000.0; // convert kg/mole --> g/mole
                double M_ratio = M_isp/M_jsp;
                double numer = (1.0 - M_ratio)*(0.45 - 2.54*M_ratio);
                double denom = (1.0 + M_ratio)^^2;
                _alpha[isp][jsp] = 1.0 + numer/denom;
                _alpha[jsp][isp] = _alpha[isp][jsp];
            }
        }
    }

    override string toString() const
    {
        char[] repr;
        repr ~= "TwoTemperatureAir";
        return to!string(repr);
    }

    override void update_thermo_from_pT(GasState Q)
    {
        _pgMixEOS.update_density(Q);
        Q.u = transRotEnergy(Q);
        Q.u_modes[0] = vibEnergy(Q, Q.T_modes[0]);
    }

    override void update_thermo_from_rhou(GasState Q)
    {
        // We can compute T by direct inversion since the Cp in 
        // in translation and rotation are fully excited,
        // and, as such, constant.
        double sumA = 0.0;
        double sumB = 0.0;
        foreach (isp; 0 .. _n_species) {
            sumA += Q.massf[isp]*(_Cp_tr_rot[isp]*T_REF - _del_hf[isp]);
            sumB += Q.massf[isp]*(_Cp_tr_rot[isp] - _R[isp]);
        }
        Q.T = (Q.u + sumA)/sumB;
        // Next, we can compute Q.T_modes by iteration.
        // We'll use a Newton method since the function
        // should vary smoothly at the polynomial breaks.
        Q.T_modes[0] = vibTemperature(Q);
        // Now we can compute pressure from the perfect gas
        // equation of state.
        _pgMixEOS.update_pressure(Q);
    }

    override void update_thermo_from_rhoT(GasState Q)
    {
        _pgMixEOS.update_pressure(Q);
        Q.u = transRotEnergy(Q); 
        Q.u_modes[0] = vibEnergy(Q, Q.T_modes[0]);
    }
    
    override void update_thermo_from_rhop(GasState Q)
    {
        // In this function, we assume that T_modes is set correctly
        // in addition to density and pressure.
        _pgMixEOS.update_temperature(Q);
        Q.u = transRotEnergy(Q);
        Q.u_modes[0] = vibEnergy(Q, Q.T_modes[0]);
    }

    override void update_thermo_from_ps(GasState Q, double s)
    {
        throw new GasModelException("update_thermo_from_ps not implemented in TwoTemperatureAir.");
    }

    override void update_thermo_from_hs(GasState Q, double h, double s)
    {
        throw new GasModelException("update_thermo_from_hs not implemented in TwoTemperatureAir.");
    }

    override void update_sound_speed(GasState Q)
    {
        // We compute the frozen sound speed based on an effective gamma
        double R = gas_constant(Q);
        Q.a = sqrt(gamma(Q)*R*Q.T);
    }

    override void update_trans_coeffs(GasState Q)
    {
        massf2molef(Q, _molef);
        // Computation of transport coefficients via collision integrals.
        // Equations follow those in Gupta et al. (1990)
        double kB = Boltzmann_constant;
        double T = Q.T;
        foreach (isp; 0 .. _n_species) {
            foreach (jsp; 0 .. isp+1) {
                double expnt = _A_22[isp][jsp]*(log(T))^^2 + _B_22[isp][jsp]*log(T) + _C_22[isp][jsp];
                double pi_Omega_22 = exp(_D_22[isp][jsp])*pow(T, expnt); 
                _Delta_22[isp][jsp] = (16./5)*1.546e-20*sqrt(2.0*_mu[isp][jsp]/(PI*_R_U_cal*T))*pi_Omega_22;
                _Delta_22[jsp][isp] = _Delta_22[isp][jsp];
            }
        }
        double sumA = 0.0;
        double sumB;
        foreach (isp; 0 .. n_species) {
            sumB = 0.0;
            foreach (jsp; 0 .. n_species) {
                sumB += _molef[jsp]*_Delta_22[isp][jsp];
            }
            sumA += _particleMass[isp]*_molef[isp]/sumB;
        }
        Q.mu = sumA * (1.0e-3/1.0e-2); // convert g/(cm.s) -> kg/(m.s)
        
        // k = k_tr + k_rot
        sumA = 0.0;
        foreach (isp; 0 .. _n_species) {
            sumB = 0.0;
            foreach (jsp; 0 .. n_species) {
                sumB += _alpha[isp][jsp]*_molef[jsp]*_Delta_22[isp][jsp];
            }
            sumA += _molef[isp]/sumB;
        }
        double kB_erg = 1.38066e-16; // erg/K
        double k_tr = 2.3901e-8*(15./4.)*kB_erg*sumA;
        k_tr *= (4.184/1.0e-2); // cal/(cm.s.K) --> J/(m.s.K)

        foreach (isp; 0 .. _n_species) {
            foreach (jsp; 0 .. isp+1) {
                double expnt = _A_11[isp][jsp]*(log(T))^^2 + _B_11[isp][jsp]*log(T) + _C_11[isp][jsp];
                double pi_Omega_11 = exp(_D_11[isp][jsp])*pow(T, expnt); 
                _Delta_11[isp][jsp] = (8.0/3)*1.546e-20*sqrt(2.0*_mu[isp][jsp]/(PI*_R_U_cal*T))*pi_Omega_11;
                _Delta_11[jsp][isp] = _Delta_11[isp][jsp];
            }
        }
        double k_rot = 0.0;
        double k_vib = 0.0;
        foreach (isp; molecularSpecies) {
            sumB = 0.0;
            foreach (jsp; 0 .. _n_species) {
                sumB += _molef[jsp]*_Delta_11[isp][jsp];
            }
            k_rot += _molef[isp]/sumB;
            double Cp_vib = vibSpecHeatConstV(Q.T_modes[0], isp);
            k_vib += (Cp_vib*_mol_masses[isp]/R_universal)*_molef[isp]/sumB;
        }
        k_rot *= 2.3901e-8*kB_erg;
        k_rot *= (4.184/1.0e-2); // cal/(cm.s.K) --> J/(m.s.K)
        Q.k = k_tr + k_rot;

        k_vib *= 2.3901e-8*kB_erg;
        k_vib *= (4.184/1.0e-2); // cal/(cm.s.K) --> J/(m.s.K)
        Q.k_modes[0] = k_vib;
    }

    override double dudT_const_v(in GasState Q)
    {
        double Cv = 0.0;
        double Cv_tr_rot, Cv_vib;
        foreach (isp; 0 .. _n_species) {
            Cv_tr_rot = transRotSpecHeatConstV(isp);
            Cv_vib = vibSpecHeatConstV(Q.T_modes[0], isp);
            Cv += Q.massf[isp] * (Cv_tr_rot + Cv_vib);
        } 
        return Cv;
    }
    override double dhdT_const_p(in GasState Q)
    {
        // Using the fact that internal structure specific heats
        // are equal, that is, Cp_vib = Cv_vib
        double Cp = 0.0;
        double Cp_vib;
        foreach (isp; 0 .. _n_species) {
            Cp_vib = vibSpecHeatConstV(Q.T_modes[0], isp);
            Cp += Q.massf[isp] * (_Cp_tr_rot[isp] + Cp_vib);
        }
        return Cp;
    }
    override double dpdrho_const_T(in GasState Q)
    {
        double R = gas_constant(Q);
        return R * Q.T;
    }
    override double gas_constant(in GasState Q)
    {
        return  mass_average(Q, _R);
    }
    override double internal_energy(in GasState Q)
    {
        return Q.u + Q.u_modes[0];
    }
    override double enthalpy(in GasState Q)
    {
        double e = transRotEnergy(Q) + vibEnergy(Q, Q.T_modes[0]);
        double R = gas_constant(Q);
        double h = e + R*Q.T;
        return h;
    }
    override double entropy(in GasState Q)
    {
        throw new GasModelException("entropy not implemented in TwoTemperatureNitrogen.");
    }

    double vibEnergy(double Tve, int isp)
    {
        double h_at_Tve = enthalpyFromCurveFits(Tve, isp);
        double h_ve = h_at_Tve - _Cp_tr_rot[isp]*(Tve - T_REF) - _del_hf[isp];
        //      writeln("Tve= ", Tve, " h_at_Tve= ", h_at_Tve, " h_ve= ", h_ve);
        return h_ve;
    }

private:
    PerfectGasMixEOS _pgMixEOS;
    double _R_U_cal = 1.987; // cal/(mole.K)
    double[] _molef;
    double[] _particleMass;
    double[] _R;
    double[] _del_hf;
    double[] _Cp_tr_rot;
    double[7] _A; // working storage of coefficients
    double[][] _A_11, _B_11, _C_11, _D_11, _Delta_11, _alpha;
    double[][] _A_22, _B_22, _C_22, _D_22, _Delta_22, _mu;


    /**
     * In order to get smooth variations in thermodynamic properties
     * at the edges of the polynomial breaks, Gupta et al. suggest
     * taking a linear average of the coefficient values near the
     * the polynomial breaks. They describe this process in words
     * on p.14 of their report, and give a Fortran implementation in
     * Appendix C (pp 40 & 41).
     */
    void determineCoefficients(double T, int isp)
    {
        string spName = species_name(isp);
        if (T < 800.0) {
            _A[] = thermoCoeffs[spName][0][];
        }
        if (T >= 800.0 && T <= 1200.0) {
            double wB = (1./400.0)*(T - 800.0);
            double wA = 1.0 - wB;
            _A[] = wA*thermoCoeffs[spName][0][] + wB*thermoCoeffs[spName][1][];
        }
        if (T > 1200.0 && T < 5500.0) {
            _A[] = thermoCoeffs[spName][1][];
        }
        if (T >= 5500.0 && T <= 6500.0) {
            double wB = (1./1000.0)*(T - 5500.0);
            double wA = 1.0 - wB;
            _A[] = wA*thermoCoeffs[spName][1][] + wB*thermoCoeffs[spName][2][];
        }
        if (T > 6500.0 && T < 14500.0) {
            _A[] = thermoCoeffs[spName][2][];
        }
        if (T >= 14500.0 && T <= 15500.0) {
            double wB = (1./1000.0)*(T - 14500.0);
            double wA = 1.0 - wB;
            _A[] = wA*thermoCoeffs[spName][2][] + wB*thermoCoeffs[spName][3][];
        }
        if (T > 15500.0 && T < 24500.0) {
            _A[] = thermoCoeffs[spName][3][];
        }
        if (T >= 24500.0 && T <= 25500.0) {
            double wB = (1./1000.0)*(T - 24500.0);
            double wA = 1.0 - wB;
            _A[] = wA*thermoCoeffs[spName][3][] + wB*thermoCoeffs[spName][4][];
        }
        if ( T > 25500.0) {
            _A[] = thermoCoeffs[spName][4][];
        }
    }

    double CpFromCurveFits(double T, int isp)
    {
        /* Assume that Cp is constant off the edges of the curve fits.
         * For T < 300.0, this is a reasonable assumption to make.
         * For T > 30000.0, that assumption might be questionable.
         */
        if (T < 300.0) {
            determineCoefficients(300.0, isp);
            T = 300.0;
        }
        if (T > 30000.0) {
            determineCoefficients(30000.0, isp);
            T = 30000.0;
        }
        // For all other cases, use supplied temperature
        determineCoefficients(T, isp);
        double T2 = T*T;
        double T3 = T2*T;
        double T4 = T3*T;
        double Cp = (_A[0] + _A[1]*T + _A[2]*T2 + _A[3]*T3 + _A[4]*T4);
        Cp *= (R_universal/_mol_masses[isp]);
        return Cp;
    }

    double enthalpyFromCurveFits(double T, int isp)
    {
        /* Gupta et al suggest that specific enthalpy below 300 K
         * should be calculated assuming that the specific heat at
         * constant pressure is constant. That suggestion is used
         * here. Additionally, we apply the same idea to temperatures
         * above 30000 K. We will assume that specific heat is constant
         * above 30000 K.
         */
        if (T < T_REF) {
            double Cp = CpFromCurveFits(300.0, isp);
            double h = Cp*(T - T_REF) + _del_hf[isp];
            return h;
        }
        if (T <= T_REF && T < 300.0) {
            // For the short region between 298.15(=T_REF) to 300.0 K,
            // we just do a linear blend between the value at 298.15 K
            // and the value at 300.0 K. This is to ensure that the
            // reference point is correct at 298.15 and that the enthalpy
            // value matches up at 300.0 K correctly.
            double h_REF = _del_hf[isp];
            double h_300 = enthalpyFromCurveFits(300.0, isp);
            double w = T - T_REF;
            double h = (1.0 - w)*h_REF + w*h_300;
            return h;
        }
        if ( T > 30000.0) {
            double Cp = CpFromCurveFits(300000.0, isp);
            double h = Cp*(T - 30000.0) + enthalpyFromCurveFits(30000.0, isp);
            return h;
        }
        // For all other, determine coefficients and compute specific enthalpy.
        determineCoefficients(T, isp);
        double T2 = T*T;
        double T3 = T2*T;
        double T4 = T3*T;
        double h = _A[0] + _A[1]*T/2. + _A[2]*T2/3. + _A[3]*T3/4. + _A[4]*T4/5. + _A[5]/T;
        h *= (R_universal*T/_mol_masses[isp]);
        return h;
    }

    double vibEnergy(in GasState Q, double Tve)
    {
        double e_ve = 0.0;
        foreach (isp; molecularSpecies) {
            e_ve += Q.massf[isp] * vibEnergy(Tve, isp);
        }
        return e_ve;
    }

    double transRotEnergy(in GasState Q)
    {
        double e_tr_rot = 0.0;
        foreach (isp; 0 .. _n_species) {
            double h_tr_rot = _Cp_tr_rot[isp]*(Q.T - T_REF) + _del_hf[isp];
            e_tr_rot += Q.massf[isp]*(h_tr_rot - _R[isp]*Q.T);
        }
        return e_tr_rot;
    }

    double vibSpecHeatConstV(double Tve, int isp)
    {
        return CpFromCurveFits(Tve, isp) - _Cp_tr_rot[isp];
    }

    double vibSpecHeatConstV(in GasState Q, double Tve)
    {
        double Cv_vib = 0.0;
        foreach (isp; molecularSpecies) {
            Cv_vib += Q.massf[isp] * vibSpecHeatConstV(Tve, isp);
        }
        return Cv_vib;
    }

    double transRotSpecHeatConstV(int isp)
    {
        return _Cp_tr_rot[isp] - _R[isp];
    }

    double transRotSpecHeatConstV(in GasState Q)
    {
        double Cv = 0.0;
        foreach (isp; 0 .. _n_species) {
            Cv += Q.massf[isp]*transRotSpecHeatConstV(isp);
        }
        return Cv;
    }

    double vibTemperature(in GasState Q)
    {
        int MAX_ITERATIONS = 20;
        // We'll keep adjusting our temperature estimate
        // until it is less than TOL.
        double TOL = 1.0e-6;
        
        // Take the supplied T_modes[0] as the initial guess.
        double T_guess = Q.T_modes[0];
        double f_guess = vibEnergy(Q, T_guess) - Q.u_modes[0];
        // Before iterating, check if the supplied guess is
        // good enough. Define good enough as 1/100th of a Joule.
        double E_TOL = 0.01;
        if (fabs(f_guess) < E_TOL) {
            // Given temperature is good enough.
            return Q.T_modes[0];
        }

        // Begin iterating.
        int count = 0;
        double Cv, dT;
        foreach (iter; 0 .. MAX_ITERATIONS) {
            Cv = vibSpecHeatConstV(Q, T_guess);
            dT = -f_guess/Cv;
            T_guess += dT;
            if (fabs(dT) < TOL) {
                break;
            }
            f_guess = vibEnergy(Q, T_guess) - Q.u_modes[0];
            count++;
        }
        
        if (count == MAX_ITERATIONS) {
            string msg = "The 'vibTemperature' function failed to converge.\n";
            msg ~= format("The final value for Tvib was: %12.6f\n", T_guess);
            msg ~= "The supplied GasState was:\n";
            msg ~= Q.toString() ~ "\n";
            throw new GasModelException(msg);
        }

        return T_guess;
    }

}

version(two_temperature_air_test) {
    int main()
    {
        auto gm = new TwoTemperatureAir("5-species", ["N2", "O2", "N", "O", "NO"]);
        auto Q = new GasState(5, 1);
        
        Q.p = 666.0;
        Q.T = 293;
        Q.T_modes[0] = 293;
        Q.massf = [0.78, 0.22, 0.0, 0.0, 0.0];
        gm.update_thermo_from_pT(Q);

        writeln(Q);

        gm.update_thermo_from_rhou(Q);
        
        writeln(Q);

        return 0;
                                        
    }
}

static double[string] __mol_masses;
static double[string] del_hf;
static double[7][5][string] thermoCoeffs;
static double[string] A_11, B_11, C_11, D_11;
static double[string] A_22, B_22, C_22, D_22;

static this()
{
    /*
    molecularSpecies["N2"] = true;
    molecularSpecies["O2"] = true;
    molecularSpecies["NO"] = true;
    molecularSpecies["N2+"] = true;
    molecularSpecies["O2+"] = true;
    molecularSpecies["NO+"] = true;
    */

    __mol_masses["N"] = 14.0067e-3;
    __mol_masses["O"] = 0.01599940; 
    __mol_masses["N2"] = 28.0134e-3;
    __mol_masses["O2"] = 0.03199880;
    __mol_masses["NO"] = 0.03000610;
    __mol_masses["N+"] = 14.0061514e-3;
    __mol_masses["O+"] = 15.9988514e-3;
    __mol_masses["N2+"] = 28.0128514e-3;
    __mol_masses["O2+"] = 31.9982514e-3;
    __mol_masses["NO+"] = 30.0055514e-3;
    __mol_masses["e-"] = 0.000548579903e-3;

    /**
     * See Table I in Gnoffo et al.
     */
    del_hf["N"]   = 112.951e3*4.184/__mol_masses["N"];
    del_hf["O"]   = 59.544e3*4.184/__mol_masses["O"];
    del_hf["N2"]  = 0.0;
    del_hf["O2"]  = 0.0;
    del_hf["NO"]  = 21.6009e3*4.184/__mol_masses["NO"];
    del_hf["N+"]  = 449.709e3*4.184/__mol_masses["N+"];
    del_hf["O+"]  = 374.867e3*4.184/__mol_masses["O+"];
    del_hf["N2+"] = 364.9392e3*4.184/__mol_masses["N2+"];
    del_hf["O2+"] = 280.2099e3*4.184/__mol_masses["O2+"];
    del_hf["NO+"] = 237.3239e3*4.184/__mol_masses["NO+"];
    del_hf["e-"]  =  0.0;

    thermoCoeffs["N2"] = 
        [
         [  0.3674826e+01, -0.1208150e-02,  0.2324010e-05, -0.6321755e-09, -0.2257725e-12, -0.1061160e+04,  0.23580e+01 ], // 300 -- 1000 K
         [  0.2896319e+01,  0.1515486e-02, -0.5723527e-06,  0.9980739e-10, -0.6522355e-14, -0.9058620e+03,  0.43661e+01 ], // 1000 -- 6000 K
         [     0.3727e+01,     0.4684e-03,    -0.1140e-06,     0.1154e-10,    -0.3293e-15,    -0.1043e+04,  0.46264e+01 ], // 6000 -- 15000 K
         [  0.9637690e+01, -0.2572840e-02,  0.3301980e-06, -0.1431490e-10,  0.2033260e-15, -0.1043000e+04, -0.37587e+02 ], // 15000 -- 25000 K
         [ -0.5168080e+01,  0.2333690e-02, -0.1295340e-06,  0.2787210e-11, -0.2135960e-16, -0.1043000e+04,  0.66217e+02 ] // 25000 -- 30000 K
         ];

    thermoCoeffs["O2"] = 
        [
         [  0.3625598e+01, -0.1878218e-02,  0.7055454e-05, -0.6763513e-08,  0.2155599e-11, -0.1047520e+04,  0.43628e+01 ], // 300 -- 1000 K
         [  0.3621953e+01,  0.7361826e-03, -0.1965222e-06,  0.3620155e-10, -0.2894562e-14, -0.1201980e+04,  0.38353e+01 ], // 1000 -- 6000 K
         [     0.3721e+01,     0.4254e-03,    -0.2835e-07,     0.6050e-12,    -0.5186e-17,    -0.1044e+04,  0.23789e+01 ], // 6000 -- 15000 K
         [  0.3486660e+01,  0.5238420e-03, -0.3912340e-07,  0.1009350e-11, -0.8871830e-17, -0.1044000e+04,  0.48179e+01 ], // 15000 -- 25000 K
         [  0.3961980e+01,  0.3944550e-03, -0.2950580e-07,  0.7397450e-12, -0.6420930e-17, -0.1044000e+04,  0.13985e+01 ]
         ];

    thermoCoeffs["N"] = 
        [
         [  0.2503071e+01, -0.2180018e-04,  0.5420528e-07, -0.5647560e-10,  0.2099904e-13,  0.5609890e+05,  0.41676e+01 ], // 300 -- 1000 K
         [  0.2450268e+01,  0.1066145e-03, -0.7465337e-07,  0.1879652e-10, -0.1025983e-14,  0.5611600e+05,  0.42618e+01 ], // 1000 -- 6000 K
         [     0.2748e+01,    -0.3909e-03,     0.1338e-06,    -0.1191e-10,     0.3369e-15,     0.5609e+05,  0.28720e+01 ], // 6000 -- 15000 K
         [ -0.1227990e+01,  0.1926850e-02, -0.2437050e-06,  0.1219300e-10, -0.1991840e-15,  0.5609000e+05,  0.28469e+02 ], // 15000 -- 25000 K
         [  0.1552020e+02, -0.3885790e-02,  0.3228840e-06, -0.9605270e-11,  0.9547220e-16,  0.5609000e+05, -0.88120e+02 ]  // 25000 -- 30000 K
         ];

    thermoCoeffs["O"] = 
        [
         [  0.2946428e+01, -0.1638166e-02,  0.2421031e-05, -0.1602843e-08,  0.3890696e-12,  0.2914760e+05,  0.35027e+01 ], // 300 -- 1000 K
         [  0.2542059e+01, -0.2755061e-04, -0.3102803e-08,  0.4551067e-11, -0.4368051e-15,  0.2923080e+05,  0.49203e+01 ], // 1000 -- 6000 K
         [     0.2546e+01,    -0.5952e-04,     0.2701e-07,    -0.2798e-11,     0.9380e-16,    0.29150e+05,  0.50490e+01 ], // 6000 -- 15000 K
         [ -0.9787120e-02,  0.1244970e-02, -0.1615440e-06,  0.8037990e-11, -0.1262400e-15,  0.2915000e+05,  0.21711e+02 ], // 15000 -- 25000 K
         [  0.1642810e+02, -0.3931300e-02,  0.2983990e-06, -0.8161280e-11,  0.7500430e-16,  0.2915000e+05, -0.94358e+02 ], // 25000 -- 30000 K
         ];
        
    thermoCoeffs["NO"] =
        [
         [  0.4045952e+01, -0.3418178e-02,  0.7981919e-05, -0.6113931e-08,  0.1591907e-11,  0.9745390e+04,  0.51497e+01 ], // 300 -- 1000 K
         [  0.3189000e+01,  0.1338228e-02, -0.5289932e-06,  0.9591933e-10, -0.6484793e-14,  0.9828330e+04,  0.66867e+01 ], // 1000 -- 6000 K
         [     0.3845e+01,     0.2521e-03,    -0.2658e-07,     0.2162e-11,    -0.6381e-16,  0.9764000e+04,  0.31541e+01 ], // 6000 -- 15000 K
         [  0.4330870e+01, -0.5808630e-04,  0.2805950e-07, -0.1569410e-11,  0.2410390e-16,  0.9764000e+04,  0.10735e+00 ], // 15000 -- 25000 K
         [  0.2350750e+01,  0.5864300e-03, -0.3131650e-07,  0.6049510e-12, -0.4055670e-17,  0.9764000e+04,  0.14026e+02 ], // 25000 -- 30000 K
         ];

    // Parameters for collision integrals
    // Collision cross-section Omega_11
    A_11["N2-N2"]   =  0.0; B_11["N2-N2"]   = -0.0112; C_11["N2-N2"]   = -0.1182; D_11["N2-N2"]   =  4.8464;
    A_11["O2-N2"]   =  0.0; B_11["O2-N2"]   = -0.0465; C_11["O2-N2"]   =  0.5729; D_11["O2-N2"]   =  1.6185; 
    A_11["O2-O2"]   =  0.0; B_11["O2-O2"]   = -0.0410; C_11["O2-O2"]   =  0.4977; D_11["O2-O2"]   =  1.8302;
    A_11["N-N2"]    =  0.0; B_11["N-N2"]    = -0.0194; C_11["N-N2"]    =  0.0119; D_11["N-N2"]    =  4.1055; 
    A_11["N-O2"]    =  0.0; B_11["N-O2"]    = -0.0179; C_11["N-O2"]    =  0.0152; D_11["N-O2"]    =  3.9996; 
    A_11["N-N"]     =  0.0; B_11["N-N"]     = -0.0033; C_11["N-N"]     = -0.0572; D_11["N-N"]     =  5.0452;
    A_11["O-N2"]    =  0.0; B_11["O-N2"]    = -0.0139; C_11["O-N2"]    = -0.0825; D_11["O-N2"]    =  4.5785;
    A_11["O-O2"]    =  0.0; B_11["O-O2"]    = -0.0226; C_11["O-O2"]    =  0.1300; D_11["O-O2"]    =  3.3363;
    A_11["O-N"]     =  0.0; B_11["O-N"]     =  0.0048; C_11["O-N"]     = -0.4195; D_11["O-N"]     =  5.7774;
    A_11["O-O"]     =  0.0; B_11["O-O"]     = -0.0034; C_11["O-O"]     = -0.0572; D_11["O-O"]     =  4.9901;
    A_11["NO-N2"]   =  0.0; B_11["NO-N2"]   = -0.0291; C_11["NO-N2"]   =  0.2324; D_11["NO-N2"]   =  3.2082; 
    A_11["NO-O2"]   =  0.0; B_11["NO-O2"]   = -0.0438; C_11["NO-O2"]   =  0.5352; D_11["NO-O2"]   =  1.7252;
    A_11["NO-N"]    =  0.0; B_11["NO-N"]    = -0.0185; C_11["NO-N"]    =  0.0118; D_11["NO-N"]    =  4.0590;
    A_11["NO-O"]    =  0.0; B_11["NO-O"]    = -0.0179; C_11["NO-O"]    =  0.0152; D_11["NO-O"]    =  3.9996; 
    A_11["NO-NO"]   =  0.0; B_11["NO-NO"]   = -0.0364; C_11["NO-NO"]   =  0.3825; D_11["NO-NO"]   =  2.4718;
    // Collision cross-section Omega_22
    A_22["N2-N2"]   =  0.0; B_22["N2-N2"]   = -0.0203; C_22["N2-N2"]   =  0.0683; D_22["N2-N2"]   =  4.0900;
    A_22["O2-N2"]   =  0.0; B_22["O2-N2"]   = -0.0558; C_22["O2-N2"]   =  0.7590; D_22["O2-N2"]   =  0.8955;
    A_22["O2-O2"]   =  0.0; B_22["O2-O2"]   = -0.0485; C_22["O2-O2"]   =  0.6475; D_22["O2-O2"]   =  1.2607;
    A_22["N-N2"]    =  0.0; B_22["N-N2"]    = -0.0190; C_22["N-N2"]    =  0.0239; D_22["N-N2"]    =  4.1782; 
    A_22["N-O2"]    =  0.0; B_22["N-O2"]    = -0.0203; C_22["N-O2"]    =  0.0703; D_22["N-O2"]    =  3.8818;
    A_22["N-N"]     =  0.0; B_22["N-N"]     = -0.0118; C_22["N-N"]     = -0.0960; D_22["N-N"]     =  4.3252;
    A_22["O-N2"]    =  0.0; B_22["O-N2"]    = -0.0169; C_22["O-N2"]    = -0.0143; D_22["O-N2"]    =  4.4195;
    A_22["O-O2"]    =  0.0; B_22["O-O2"]    = -0.0247; C_22["O-O2"]    =  0.1783; D_22["O-O2"]    =  3.2517;
    A_22["O-N"]     =  0.0; B_22["O-N"]     =  0.0065; C_22["O-N"]     = -0.4467; D_22["O-N"]     =  6.0426;
    A_22["O-O"]     =  0.0; B_22["O-O"]     = -0.0207; C_22["O-O"]     =  0.0780; D_22["O-O"]     =  3.5658;
    A_22["NO-N2"]   =  0.0; B_22["NO-N2"]   = -0.0385; C_22["NO-N2"]   =  0.4226; D_22["NO-N2"]   =  2.4507;
    A_22["NO-O2"]   =  0.0; B_22["NO-O2"]   = -0.0522; C_22["NO-O2"]   =  0.7045; D_22["NO-O2"]   =  1.0738;
    A_22["NO-N"]    =  0.0; B_22["NO-N"]    = -0.0196; C_22["NO-N"]    =  0.0478; D_22["NO-N"]    =  4.0321;
    A_22["NO-O"]    =  0.0; B_22["NO-O"]    = -0.0203; C_22["NO-O"]    =  0.0703; D_22["NO-O"]    =  3.8818;
    A_22["NO-NO"]   =  0.0; B_22["NO-NO"]   = -0.-453; C_22["NO-NO"]   =  0.5624; D_22["NO-NO"]   =  1.7669;


    

}

