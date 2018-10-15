/**
 * Author: Brad Semple, Rowan G.
 *
 */

module gas.electronically_specific_gas;

import std.algorithm.iteration : sum;
import std.math;
import std.stdio;
import std.string;
import std.path : relativePath;
import std.conv : to;
import util.lua;
import util.lua_service;
import nm.complex;
import nm.number;

import gas.gas_model;
import gas.gas_state;
import gas.physical_constants;
import gas.electronic_species;


class ElectronicallySpecificGas : GasModel {
public:
    this(lua_State *L) 
    {
        auto nElecSpecies = getInt(L, LUA_GLOBALSINDEX, "number_electronic_species");
        _n_species = cast(uint) nElecSpecies;
        _n_modes = 1;
        _species_names.length = _n_species; 
        _numden.length = _n_species;

        _s1 = getDouble(L, LUA_GLOBALSINDEX, "s1");
        _T1 = getDouble(L, LUA_GLOBALSINDEX, "T1");
        _p1 = getDouble(L, LUA_GLOBALSINDEX, "p1");

        lua_getfield(L, LUA_GLOBALSINDEX, "electronic_species");
        foreach (isp; 0 .. _n_species) {
            lua_rawgeti(L, -1, isp);
            if (lua_isnil(L, -1)) {
                string msg = format("There was an error when attempting to information about pseudo-species %d.\n", isp);
                throw new Error(msg);
            }
            _electronicSpecies ~= createElectronicSpecies(L);
            lua_pop(L, 1);
            _species_names[isp] = _electronicSpecies[$-1].name;
            _mol_masses ~= _electronicSpecies[$-1].mol_mass;
            _R ~= R_universal/_electronicSpecies[$-1].mol_mass;
            _level ~= _electronicSpecies[$-1].level;
            _group_degeneracy ~= _electronicSpecies[$-1].group_degeneracy;
            _dof ~= _electronicSpecies[$-1].dof;
        }
        lua_pop(L, 1);
        create_species_reverse_lookup();
    }

    override string toString() const
    {
        char[] repr;
        repr ~= "ElectronicSpeciesGas=()";
        return to!string(repr);
    }

    override void update_thermo_from_pT(GasState Q)
    {
        auto R_mix = gas_constant(Q);
        Q.rho = Q.p/(R_mix*Q.T);
        auto Cv_heavy = heavy_Cv(Q);
        Q.u = Cv_heavy*Q.T;
        auto Cv_electron = electron_Cv(Q);
        Q.u_modes[0]=Cv_electron*Q.T_modes[0];
    }

    override void update_thermo_from_rhou(GasState Q)
    {
        auto uNoneq = energyInNoneq(Q);
        auto Cv_heavy = heavy_Cv(Q);
        Q.T = (Q.u)/Cv_heavy; 
        auto Cv_electron = electron_Cv(Q);
        Q.T_modes[0] = Q.u_modes[0]/Cv_electron;
        auto R_mix = gas_constant(Q);
        Q.p = Q.rho*R_mix*Q.T;
    }

    override void update_thermo_from_rhoT(GasState Q)
    {
        auto R_mix = gas_constant(Q);
        Q.p = Q.rho*R_mix*Q.T;
        auto Cv_heavy = heavy_Cv(Q);
        Q.u = Cv_heavy*Q.T;
        auto Cv_electron = electron_Cv(Q);
        Q.u_modes[0] = Cv_electron*Q.T_modes[0];
    }

    override void update_thermo_from_rhop(GasState Q)
    {
        auto R_mix = gas_constant(Q);
        Q.T = Q.p/(Q.rho*R_mix);
        auto Cv_heavy = heavy_Cv(Q);
        Q.u = Cv_heavy*Q.T;
        auto Cv_electron = electron_Cv(Q);
        Q.u_modes[0] = Cv_electron*Q.T_modes[0];
    }

    override void update_thermo_from_ps(GasState Q, number s)
    {
        Q.T = _T1 * exp((1.0/_Cp)*((s - _s1) + _Rgas * log(Q.p/_p1)));
        update_thermo_from_pT(Q);
    }

    override void update_thermo_from_hs(GasState Q, number h, number s)
    {
        Q.T = h / _Cp;
        Q.p = _p1 * exp((1.0/_Rgas)*(_s1 - s + _Cp*log(Q.T/_T1)));
        update_thermo_from_pT(Q);
    }

    override void update_sound_speed(GasState Q)
    {
        auto R_mix = gas_constant(Q);
        auto Cv_mix = Cv(Q);
        auto gamma_mix = (R_mix/Cv_mix) + 1;
        Q.a = sqrt(gamma_mix*R_mix*Q.T);
    }

    override void update_trans_coeffs(GasState Q)
    {
        Q.mu = 0.0;
        Q.k = 0.0;
    }

    override number dudT_const_v(in GasState Q) const
    {
        number Cv = 0.0;
        foreach (isp; 0 .. _n_species) {
            Cv += Q.massf[isp] * (_dof[isp]/2.0) * _R[isp];
        }
        return Cv;
    }
    override number dhdT_const_p(in GasState Q) const
    {
        return gas_constant(Q) + dudT_const_v(Q);
    }
    override number dpdrho_const_T(in GasState Q) const
    {
        number R = gas_constant(Q);
        return R*Q.T;
    }
    override number gas_constant(in GasState Q) const
    {
        number R_mix = 0.0;
        foreach (isp; 0 .. _n_species) {
            R_mix += Q.massf[isp]*_R[isp];
        }
        return R_mix;
    }
    override number internal_energy(in GasState Q)
    {
        auto uNoneq = energyInNoneq(Q);
        return Q.u + Q.u_modes[0] + uNoneq;
    }
    override number enthalpy(in GasState Q) const
    {
        return Q.u + sum(Q.u_modes) + Q.p/Q.rho;
    }
    override number entropy(in GasState Q) const
    {
        return _s1 + _Cp * log(Q.T/_T1) - _Rgas * log(Q.p/_p1);
    }
    void relaxEnergy(double dt, GasState Q) //Uses the Appleton & Bray model to relax energy between the two energy modes
    {   
        massf2numden(Q,_numden);
        foreach(int i;0 .. _n_species){
            _numden[i] = _numden[i]/1e6;
        }
        number heatToElectron = AppletonBrayRate(Q,_numden);
        Q.u_modes[0] += dt*heatToElectron;
        Q.u -= dt*heatToElectron;
    }

private:
    ElectronicSpecies[] _electronicSpecies;
    double[] _R;
    int[] _level;
    int[] _group_degeneracy;
    int[] _dof;
    number[] _numden; //  #/cm^3

    // Thermodynamic constants
    double _Rgas; // J/kg/K
    number _Cv1; // J/kg/K
    number _Cv2; //J/kg/K
    double _Cv;
    double _Cp;
    double _gamma;   // ratio of specific heats
    // Reference values for entropy
    double _s1;  // J/kg/K
    double _T1;  // K
    double _p1;  // Pa

    //physical cconstants
    double _pi = 3.14159265359; //honestly, this should probably be defined in physical constants
    double _me = 9.10938356e-28; //electron mass in g
    double _kb = 1.3807e-16; //Boltzmann constant in cm^2 g s^-1 K^-1
    double _e = 4.8032e-10; // electron charge, cm^(3/2) g s^-2 K^-1


    //create array of coefficients for appleton and Bray energy relaxation method
    //Rows in order N2, N, O2, O
    //each element: a,b,c in equation cross_section = a + b*Te + c*Te^2
    double[][] AB_coef = [[7.5e-20, 5.5e-24, -1e-28],
                            [5.0e-20, 0.0, 0.0],
                            [2.0e-20, 6.0e-24, 0.0],
                            [1.2e-20, 1.7e-24, -2e-29]];

    number _cs;
    number _Nsum;
    number _Osum;
    number _sumterm;

    @nogc number energyInNoneq(const GasState Q) const {
        number uNoneq = 0.0;
        foreach (isp; 0 .. _n_species) {
            uNoneq += Q.massf[isp] * _electronicSpecies[isp].group_energy(Q);
        }
        return uNoneq;
    }

    @nogc number heavy_Cv(GasState Q)
    {
        _Cv1 = 0.0;
        foreach (isp; 0 .. 18){
            _Cv1 += Q.massf[isp] * (_dof[isp]/2.0) * _R[isp];
        }
        foreach (isp; 19 .. _n_species) {
            _Cv1 += Q.massf[isp] * (_dof[isp]/2.0) * _R[isp];
        }
        return _Cv1;
    }

    @nogc number electron_Cv(GasState Q)
    {   
        number elec_cv = Q.massf[18]*(_dof[18]/2.0) * _R[18];
        return elec_cv; 
    }

    @nogc number AppletonBrayRate(GasState Q, number[] _numden) 
    { //only call when gas state in number density /cm^3
        assert((_numden[0]>1e10),"Still in mass fraction, not number density?");
        @nogc number eff_coll_freq(number ni, bool ion, string species = "ion") 
        {
            if (ion) {
                return (8.0/3.0)*((_pi/_me)^^0.5)*ni*(_e^^4)*(1.0/((2*_kb*Q.T_modes[0])^^(3.0/2.0)))*
                                log(((_kb*Q.T_modes[0])^^3)/(_pi*_numden[18]*(_e^^6)));
            } else {
                switch (species)
                {
                    default:
                        throw new Exception("This shouldn't happen");
                    
                    case "N2":
                        _cs = AB_coef[0][0] + AB_coef[0][1]*Q.T_modes[0] + AB_coef[0][2]*(Q.T_modes[0]^^2); //energy exchange cross section
                        return ni*_cs*(((8*_kb*Q.T_modes[0])/(_pi*_me))^^0.5);

                    case "N":
                        _cs = AB_coef[1][0] + AB_coef[1][1]*Q.T_modes[0] + AB_coef[1][2]*(Q.T_modes[0]^^2); //energy exchange cross section
                        return ni*_cs*(((8*_kb*Q.T_modes[0])/(_pi*_me))^^0.5);
                    
                    case "O2":
                        _cs = AB_coef[2][0] + AB_coef[2][1]*Q.T_modes[0] + AB_coef[2][2]*(Q.T_modes[0]^^2); //energy exchange cross section
                        return ni*_cs*(((8*_kb*Q.T_modes[0])/(_pi*_me))^^0.5);
                    
                    case "O":
                        _cs = AB_coef[3][0] + AB_coef[3][1]*Q.T_modes[0] + AB_coef[3][2]*(Q.T_modes[0]^^2); //energy exchange cross section
                        return ni*_cs*(((8*_kb*Q.T_modes[0])/(_pi*_me))^^0.5);
                }
            }
        }
        _Nsum = 0.0;
        _Osum = 0.0;
        foreach(int isp;0 .. 8) {
            _Nsum += _numden[isp];
            _Osum += _numden[isp + 9];
        }
        _sumterm = 0.0;
        _sumterm += eff_coll_freq(_numden[19],false,"N2")/_mol_masses[19] + eff_coll_freq(_Nsum,false,"N")/_mol_masses[0] +
                    eff_coll_freq(_numden[8],true)/_mol_masses[8] + eff_coll_freq(_numden[20],false,"O2")/_mol_masses[20] + 
                    eff_coll_freq(_Osum,false,"O")/_mol_masses[9] + eff_coll_freq(_numden[17],true)/_mol_masses[17];
        return 3*_numden[18]*_me*1e3*R_universal*(Q.T - Q.T_modes[0])*_sumterm;
    }

    @nogc number electronMassf(GasState Q) {
        return Q.massf[18];
    }

    @nogc number heavyMassf(GasState Q) {
        return 1.0 - electronMassf(Q);
    }
}


version(electronically_specific_gas_test) {
    int main()
    {
        import util.msg_service;

        auto L = init_lua_State();
        doLuaFile(L, relativePath("../gas/sample-data/electronic_composition.lua"));
        auto gm = new ElectronicallySpecificGas(L);
        auto gd = new GasState(21,1);

        // gd.massf[] = 0.0;
        // gd.massf[0] = 0.037041674288877; //initialises massf of NI
        // gd.massf[9] = 0.010577876366622; //initialises massf of OI
        // gd.massf[19] = 0.74082290750449; //N2
        // gd.massf[20] = 0.21155752733244; //O2
        // gd.massf[18] = 1.0 - (gd.massf[0] + gd.massf[9] + gd.massf[19] + gd.massf[20]); //tiny massf for free electron
        gd.massf = [0.0313603, 0.00492971, 0.000741705, 1.06916e-06, 4.90114e-07, 
                        2.46998e-07, 9.58454e-08, 6.6456e-07, 6.41328e-06, 0.010005, 
                        0.000565079, 8.59624e-06, 2.58411e-07, 9.00322e-08, 5.80925e-08, 
                        3.67871e-08, 9.06483e-08, 4.16313e-07, 1.4773e-08, 0.740823, 0.211558];

        gd.p = 100000.0;
        gd.T = 300.0;
        gd.T_modes[0]=4000.0;
        gm.update_thermo_from_pT(gd);
        //writeln(gd);
        foreach(int i;0 .. 100000){
            gm.relaxEnergy(1e-8,gd);
            gm.update_thermo_from_rhou(gd);
        }
        //writeln(gd);
        double massfsum=0.0;
        foreach(number eachmassf;gd.massf) {
            massfsum += eachmassf;
        }
        assert(approxEqual(massfsum, 1.0, 1e-2), failedUnitTest());

        //convert to number density in #/cm^3
        return 0;
    }
    
}
