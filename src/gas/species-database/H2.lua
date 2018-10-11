db.H2 = {}
db.H2.atomicConstituents = {H=2,}
db.H2.charge = 0
db.H2.M = {
   value = 0.00201588,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'molecular weight from CEA2'
}
db.H2.gamma = {
   value = 1.40000000,
   units = 'non-dimensional',
   description = '(ideal) ratio of specific heats at room temperature',
   reference = 'diatomic molecule at low temperatures, gamma = 7/5'
}
db.H2.sigma = {
   value = 2.920,
   units = 'Angstrom',
   description = 'Lennard-Jones potential distance',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.H2.epsilon = {
   value = 38.000,
   units = 'K',
   description = 'Lennard-Jones potential well depth.',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.H2.Lewis = {
   value = 0.317
}
db.H2.ceaThermoCoeffs = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
          4.078323210e+04,
         -8.009186040e+02,
          8.214702010e+00,
         -1.269714457e-02,
          1.753605076e-05,
         -1.202860270e-08,
          3.368093490e-12,
          2.682484665e+03,
         -3.043788844e+01,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 6000.0,
      coeffs = {
          5.608128010e+05,
         -8.371504740e+02,
          2.975364532e+00,
          1.252249124e-03,
         -3.740716190e-07,
          5.936625200e-11,
         -3.606994100e-15,
          5.339824410e+03,
         -2.202774769e+00,
      }
   },
   segment2 = {
      T_lower = 6000.0,
      T_upper = 20000.0,
      coeffs = {
          4.966884120e+08,
         -3.147547149e+05,
          7.984121880e+01,
         -8.414789210e-03,
          4.753248350e-07,
         -1.371873492e-11,
          1.605461756e-16,
          2.488433516e+06,
         -6.695728110e+02,
      }
   },
}
db.H2.ceaViscosity = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper = 1000.0,
      A =  7.4553182e-01,
      B =  4.3555109e+01,
      C = -3.2579340e+03,
      D =  1.3556243e-01
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  9.6730605e-01,
      B =  6.7931897e+02,
      C = -2.1025179e+05,
      D = -1.8251697e+00
   },
   segment2 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A =  1.0126129e+00,
      B =  1.4973739e+03,
      C = -1.4428484e+06,
      D = -2.3254928e+00
   },
}
db.H2.ceaThermCond = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper = 1000.0,
      A =  1.0059461e+00,
      B =  2.7951262e+02,
      C = -2.9792018e+04,
      D =  1.1996252e+00
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  1.0582450e+00,
      B =  2.4875372e+02,
      C =  1.1736907e+04,
      D =  8.2758695e-01
   },
   segment2 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A = -2.2364420e-01,
      B = -6.9650442e+03,
      C = -7.7771313e+04,
      D =  1.3189369e+01
   },
}
db.H2.grimechThermoCoeffs = {
   notes = 'data from GRIMECH 3.0',
   nsegments = 2, 
   segment0 ={
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         0,
         0,
          2.34433112E+00,
          7.98052075E-03,
         -1.94781510E-05,
          2.01572094E-08,
         -7.37611761E-12,
         -9.17935173E+02,
          6.83010238E-01,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 3500.0,
      coeffs = {
         0,
         0,
          3.33727920E+00,
         -4.94024731E-05,
          4.99456778E-07,
         -1.79566394E-10,
          2.00255376E-14,
         -9.50158922E+02,
         -3.20502331E+00,
      }
   }
}
