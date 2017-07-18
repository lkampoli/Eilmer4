db.HO2 = {}
db.HO2.atomicConstituents = {O=2,H=1,}
db.HO2.charge = 0
db.HO2.M = {
   value = 0.03300674,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'CEA2::thermo.inp'
}
db.HO2.gamma = {
   value = 1.31200000,
   units = 'non-dimensional',
   description = 'ratio of specific heats at room temperature (= Cp/(Cp - R))',
   reference = 'using Cp evaluated from CEA2 coefficients at T=300.0 K'
}
db.HO2.sigma = {
   value = 3.458,
   units = 'Angstrom',
   description = 'Lennard-Jones potential distance',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.HO2.epsilon = {
   value = 107.400,
   units = 'K',
   description = 'Lennard-Jones potential well depth.',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.HO2.ceaThermoCoeffs = {
   nsegments = 2,
   segment0 = {
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         -7.598882540e+04,
          1.329383918e+03,
         -4.677388240e+00,
          2.508308202e-02,
         -3.006551588e-05,
          1.895600056e-08,
         -4.828567390e-12,
         -5.873350960e+03,
          5.193602140e+01,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 6000.0,
      coeffs = {
         -1.810669724e+06,
          4.963192030e+03,
         -1.039498992e+00,
          4.560148530e-03,
         -1.061859447e-06,
          1.144567878e-10,
         -4.763064160e-15,
         -3.200817190e+04,
          4.066850920e+01,
      }
   },
}
db.HO2.grimechThermoCoeffs = {
   notes = 'data from GRIMECH 3.0',
   nsegments = 2, 
   segment0 ={
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         0,
         0,
          4.30179801E+00,
         -4.74912051E-03,
          2.11582891E-05,
         -2.42763894E-08,
          9.29225124E-12,
          2.94808040E+02,
          3.71666245E+00,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 3500.0,
      coeffs = {
         0,
         0,
          4.01721090E+00,
          2.23982013E-03,
         -6.33658150E-07,
          1.14246370E-10,
         -1.07908535E-14,
          1.11856713E+02,
          3.78510215E+00,
      }
   }
}
