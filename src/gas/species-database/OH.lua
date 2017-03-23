db.OH = {}
db.OH.atomicConstituents = {O=1,H=1,}
db.OH.charge = 0
db.OH.M = {
   value = 0.01700734,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'CEA2::thermo.inp'
}
db.OH.gamma = {
   value = 1.38600000,
   units = 'non-dimensional',
   description = 'ratio of specific heats at room temperature (= Cp/(Cp - R))',
   reference = 'using Cp evaluated from CEA2 coefficients at T=300.0 K'
}
db.OH.ceaThermoCoeffs = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         -1.998858990e+03,
          9.300136160e+01,
          3.050854229e+00,
          1.529529288e-03,
         -3.157890998e-06,
          3.315446180e-09,
         -1.138762683e-12,
          2.991214235e+03,
          4.674110790e+00,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 6000.0,
      coeffs = {
          1.017393379e+06,
         -2.509957276e+03,
          5.116547860e+00,
          1.305299930e-04,
         -8.284322260e-08,
          2.006475941e-11,
         -1.556993656e-15,
          2.019640206e+04,
         -1.101282337e+01,
      }
   },
   segment2 = {
      T_lower = 6000.0,
      T_upper = 20000.0,
      coeffs = {
          2.847234193e+08,
         -1.859532612e+05,
          5.008240900e+01,
         -5.142374980e-03,
          2.875536589e-07,
         -8.228817960e-12,
          9.567229020e-17,
          1.468393908e+06,
         -4.023555580e+02,
      }
   },
}
db.OH.grimechThermoCoeffs = {
   notes = 'data from GRIMECH 3.0',
   nsegments = 2, 
   segment0 ={
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         0,
         0,
          3.99201543E+00,
         -2.40131752E-03,
          4.61793841E-06,
         -3.88113333E-09,
          1.36411470E-12,
          3.61508056E+03,
         -1.03925458E-01,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 3500.0,
      coeffs = {
         0,
         0,
          3.09288767E+00,
          5.48429716E-04,
          1.26505228E-07,
         -8.79461556E-11,
          1.17412376E-14,
          3.85865700E+03,
          4.47669610E+00,
      }
   }
}
db.OH.ceaViscosity = {
   nsegments = 2,
   segment0 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  5.9711536e-01,
      B = -4.6100678e+02,
      C =  3.7606286e+04,
      D =  2.4041761e+00
   },
   segment1 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A =  6.4287721e-01,
      B = -1.8173747e+02,
      C = -8.8543767e+04,
      D =  1.9636057e+00
   },
}
db.OH.ceaThermCond = {
   nsegments = 2,
   segment0 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  6.8627561e-01,
      B = -7.4033274e+02,
      C =  2.7559033e+04,
      D =  2.8308741e+00
   },
   segment1 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A = -4.7918112e-01,
      B = -9.3769908e+03,
      C =  7.0509952e+06,
      D =  1.4203688e+01
   },
}
