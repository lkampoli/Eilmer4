db.O = {}
db.O.atomicConstituents = {O=1,}
db.O.charge = 0
db.O.M = {
   value = 0.01599940,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'CEA2::thermo.inp'
}
db.O.gamma = {
   value = 1.66666667,
   units = 'non-dimensional',
   description = '(ideal) ratio of specific heats at room temperature',
   reference = 'monatomic gas'
}
db.O.ceaThermoCoeffs = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         -7.953611300e+03,
          1.607177787e+02,
          1.966226438e+00,
          1.013670310e-03,
         -1.110415423e-06,
          6.517507500e-10,
         -1.584779251e-13,
          2.840362437e+04,
          8.404241820e+00,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 6000.0,
      coeffs = {
          2.619020262e+05,
         -7.298722030e+02,
          3.317177270e+00,
         -4.281334360e-04,
          1.036104594e-07,
         -9.438304330e-12,
          2.725038297e-16,
          3.392428060e+04,
         -6.679585350e-01,
      }
   },
   segment2 = {
      T_lower = 6000.0,
      T_upper = 20000.0,
      coeffs = {
          1.779004264e+08,
         -1.082328257e+05,
          2.810778365e+01,
         -2.975232262e-03,
          1.854997534e-07,
         -5.796231540e-12,
          7.191720164e-17,
          8.890942630e+05,
         -2.181728151e+02,
      }
   },
}
db.O.grimechThermoCoeffs = {
   notes = 'data from GRIMECH 3.0',
   nsegments = 2, 
   segment0 ={
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         0,
         0,
          3.16826710E+00,
         -3.27931884E-03,
          6.64306396E-06,
         -6.12806624E-09,
          2.11265971E-12,
          2.91222592E+04,
          2.05193346E+00,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 3500.0,
      coeffs = {
         0,
         0,
          2.56942078E+00,
         -8.59741137E-05,
          4.19484589E-08,
         -1.00177799E-11,
          1.22833691E-15,
          2.92175791E+04,
          4.78433864E+00,
      }
   }
}
db.O.ceaViscosity = {
   nsegments = 2,
   segment0 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  7.7269241e-01,
      B =  8.3842977e+01,
      C = -5.8502098e+04,
      D =  8.5100827e-01
   },
   segment1 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A =  8.7669586e-01,
      B =  1.0158420e+03,
      C = -1.0884566e+06,
      D = -1.8001077e-01
   },
}
db.O.ceaThermCond = {
   nsegments = 2,
   segment0 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  7.7271664e-01,
      B =  8.3989100e+01,
      C = -5.8580966e+04,
      D =  1.5179900e+00
   },
   segment1 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A =  8.7676666e-01,
      B =  1.0170744e+03,
      C = -1.0906690e+06,
      D =  4.8644232e-01
   },
}
