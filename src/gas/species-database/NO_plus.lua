db['NO+'] = {}
db['NO+'].atomicConstituents = {O=1,N=1,}
db['NO+'].charge = 1
db['NO+'].M = {
   value = 30.0055514e-3,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'CEA2::thermo.inp'
}
db['NO+'].ceaThermoCoeffs = {
   nsegments = 3,
   T_break_points = {298.15, 1000.0, 6000.0, 20000.0},
   T_blend_ranges = {400.0, 1000.0},
   segment0 = {
      1.398106635e+03,
     -1.590446941e+02,
      5.122895400e+00,
     -6.394388620e-03,
      1.123918342e-05,
     -7.988581260e-09,
      2.107383677e-12,
      1.187495132e+05,
     -4.398433810e+00
   },
   segment1 = {
      6.069876900e+05,
     -2.278395427e+03,
      6.080324670e+00,
     -6.066847580e-04,
      1.432002611e-07,
     -1.747990522e-11,
      8.935014060e-16,
      1.322709615e+05,
     -1.519880037e+01
   },
   segment2 = {
      2.676400347e+09,
     -1.832948690e+06,
      5.099249390e+02, 
     -7.113819280e-02,
      5.317659880e-06,
     -1.963208212e-10,
      2.805268230e-15,
      1.443308939e+07,
     -4.324044462e+03 
   },
}
-- No CEA transport data for NO+, just use NO
db['NO+'].ceaViscosity = db.NO.ceaViscosity  
db['NO+'].ceaThermCond = db.NO.ceaThermCond  
