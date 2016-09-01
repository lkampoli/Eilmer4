db.NO_plus = {}
db.NO_plus.atomicConstituents = {O=1,N=1,}
db.NO_plus.charge = 0
db.NO_plus.M = {
   value = 30.0055514e-3,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'CEA2::thermo.inp'
}
db.NO_plus.ceaThermoCoeffs = {
   nsegments = 3,
   segment0 = {
      T_lower = 298.15,
      T_upper = 1000.0,
      coeffs = {
	 1.398106635e+03,
	-1.590446941e+02,
	 5.122895400e+00,
	-6.394388620e-03,
	 1.123918342e-05,
	-7.988581260e-09,
	 2.107383677e-12,
	 1.187495132e+05,
	-4.398433810e+00
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 6000.0,
      coeffs = {
	 6.069876900e+05,
	-2.278395427e+03,
	 6.080324670e+00,
	-6.066847580e-04,
	 1.432002611e-07,
	-1.747990522e-11,
	 8.935014060e-16,
	 1.322709615e+05,
	-1.519880037e+01
      }
   },
   segment2 = {
      T_lower = 6000.0,
      T_upper = 20000.0,
      coeffs = {
	 2.676400347e+09,
	-1.832948690e+06,
	 5.099249390e+02, 
	-7.113819280e-02,
	 5.317659880e-06,
	-1.963208212e-10,
	 2.805268230e-15,
	 1.443308939e+07,
	-4.324044462e+03 
      }
   },
}
-- No CEA transport data for NO+, just use NO
db.NO_plus.ceaViscosity = db.NO.ceaViscosity  
db.NO_plus.ceaThermCond = db.NO.ceaThermCond  