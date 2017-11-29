/**
 * Authors: Rowan G. and Peter J.
 * Date: 2017-07-13
 *
 * A model for single-species diatomic nitrogen with
 * two temperatures: a transrotational temperature and
 * a vibrational temperature.
 *
 */

module gas.two_temperature_nitrogen;

import std.math;
import std.conv;
import std.stdio;

import gas.gas_model;
import gas.gas_state;
import gas.physical_constants;
import gas.diffusion.cea_viscosity;

class TwoTemperatureNitrogen : GasModel {
public:
    this()
    {
	_n_species = 1;
	_n_modes = 1;
	_species_names.length = 1;
	_species_names[0] = "N2";
	create_species_reverse_lookup();
    }

    override string toString() const
    {
	char[] repr;
	repr ~= "TwoTemperatureNitrogen";
	return to!string(repr);
    }

    override void update_thermo_from_pT(GasState Q) const
    {
	Q.rho = Q.p/(Q.Ttr*_R_N2);
	Q.u = (5./2.)*Q.Ttr*_R_N2; // translational+rotational modes
	Q.u_modes[0] = (_R_N2*_theta_N2)/(exp(_theta_N2/Q.T_modes[0]) - 1.0); // vib
    }

    override void update_thermo_from_rhou(GasState Q) const
    {
	Q.Ttr = Q.u/((5./2.)*_R_N2);
	Q.T_modes[0] = _theta_N2/log((_R_N2*_theta_N2/Q.u_modes[0]) + 1.0);
	Q.p = Q.rho*_R_N2*Q.Ttr;
    }

    override void update_thermo_from_rhoT(GasState Q) const
    {
	Q.p = Q.rho*_R_N2*Q.Ttr;
	Q.u = (5./2.)*Q.Ttr*_R_N2;
	Q.u_modes[0] = (_R_N2*_theta_N2)/(exp(_theta_N2/Q.T_modes[0]) - 1.0);
    }
    
    override void update_thermo_from_rhop(GasState Q) const
    {
	Q.Ttr = Q.p/(Q.rho*_R_N2);
	// Assume Q.T_modes[0] is set independently, and correct.
	Q.u = (5./2.)*Q.Ttr*_R_N2;
	Q.u_modes[0] = (_R_N2*_theta_N2)/(exp(_theta_N2/Q.T_modes[0]) - 1.0);
    }

    override void update_thermo_from_ps(GasState Q, double s) const
    {
	throw new GasModelException("update_thermo_from_ps not implemented in TwoTemperatureNitrogen.");
    }

    override void update_thermo_from_hs(GasState Q, double h, double s) const
    {
	throw new GasModelException("update_thermo_from_hs not implemented in TwoTemperatureNitrogen.");
    }

    override void update_sound_speed(GasState Q) const
    {
	Q.a = sqrt(_gamma*_R_N2*Q.Ttr);
    }

    override void update_trans_coeffs(GasState Q) const
    {
	// Computation of transport coefficients via collision integrals.
	// Equations follow those in Gupta et al. (1990)
	// Constants are from Wright et al.
	// For details see Daniel Potter's PhD thesis.
	double kB = Boltzmann_constant;
	double T = Q.Ttr;
	double expnt = _A_22*(log(T))^^2 + _B_22*log(T) + _C_22;
	double pi_sig2_Omega_22 = exp(_D_22)*pow(T, expnt) * 1.0e-20; // Ang^2 --> m^2
	double Delta_22 = (16./5)*sqrt(2.0*_mu/(PI*kB*T))*pi_sig2_Omega_22;
	Q.mu = _m / Delta_22;
	
	double k_trans = (15./4)*kB*(1./(alpha*Delta_22));
	// Compute k_rot as function of Ttr
	expnt = _A_11*(log(T))^^2 + _B_11*log(T) + _C_11;
	double pi_sig2_Omega_11 = exp(_D_11)*pow(T, expnt) * 1.0e-20; // Ang^2 --> m^2
	double Delta_11 = (8./3)*sqrt(2.0*_mu/(PI*kB*T))*pi_sig2_Omega_11;
	double k_rot = kB*(1./Delta_11);
	Q.k = k_trans + k_rot;
	// Compute k_vib as function of Tv
	double Tv = Q.T_modes[0];
	double Cvv_R = (_theta_N2/(2.0*Tv)/(sinh(_theta_N2/(2.0*Tv))))^^2;
	expnt = _A_11*(log(Tv))^^2 + _B_11*log(Tv) + _C_11;
	pi_sig2_Omega_11 = exp(_D_11)*pow(Tv, expnt) * 1.0e-20; // Ang^2 --> m^2
	Delta_11 = (8./3)*sqrt(2.0*_mu/(PI*kB*Tv))*pi_sig2_Omega_11;
	Q.k_modes[0] = kB*(Cvv_R/Delta_11);
    }

    override double dudT_const_v(in GasState Q) const
    {
	return (5./2.)*_R_N2;
    }
    override double dhdT_const_p(in GasState Q) const
    {
	return (7./2.)*_R_N2;
    }
    override double dpdrho_const_T(in GasState Q) const
    {
	return _R_N2*Q.Ttr;
    }
    override double gas_constant(in GasState Q) const
    {
	return _R_N2;
    }
    override double internal_energy(in GasState Q) const
    {
	return Q.u + Q.u_modes[0]; // all internal energy
    }
    override double enthalpy(in GasState Q) const
    {
	return Q.u + Q.u_modes[0] + Q.p/Q.rho;
    }
    override double entropy(in GasState Q) const
    {
	throw new GasModelException("entropy not implemented in TwoTemperatureNitrogen.");
    }

private:
    double _R_N2 = 296.805; // gas constant for N2
    double _theta_N2 = 3354.0; // K, characteristic vib temp for N2
    double _gamma = 7./5.; // ratio of specific heats.
    double _m = 28.0134e-3/Avogadro_number; // mass of single particle
    double _mu = 0.5*28.0134e-3/Avogadro_number; // reduced mass on single particle
    double alpha = 1.0; // parameter in therm. cond. expression
    // Viscosity parameters
    double _A_22 = -0.0087;
    double _B_22 = 0.1948;
    double _C_22 = -1.6023;
    double _D_22 = 8.1845;
    // Thermal conductivity parameters
    double _A_11 = -0.0066;
    double _B_11 = 0.1392;
    double _C_11 = -1.1559;
    double _D_11 = 6.9352;
}

