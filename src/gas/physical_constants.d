/**
 * physical_constants.d
 *
 * We store some oft used physical constants
 * in one place for use with the gas models.
 *
 * Author: Rowan G. and Peter J.
 */

module gas.physical_constants;

///Universal gas constant (S.I. units)
immutable double R_universal = 8.31451; // J/(mol.K) -- Tipler (1991)
// One atmosphere, in Pascals
immutable double P_atm = 101.325e3;          // Pa
immutable double Boltzmann_constant = 1.380658e-23; // J/K -- Tipler (1991)
immutable double Avogadro_number = 6.02214e23;
immutable double electron_volt_energy = 1.60219e-19; // J
