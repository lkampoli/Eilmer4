db.CO = {}
db.CO.atomicConstituents = {C=1,O=1,}
db.CO.charge = 0
db.CO.M = {
   value = 28.010100e-3,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'Periodic table'
}
db.CO.gamma = {
   value = 1.3992e+00,
   units = 'non-dimensional',
   description = 'ratio of specific heats at 300.0K',
   reference = 'evaluated using Cp/R from Chemkin-II coefficients'
}
db.CO.sigma = {
   value = 3.650,
   units = 'Angstrom',
   description = 'Lennard-Jones potential distance',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.CO.epsilon = {
   value = 98.100,
   units = 'K',
   description = 'Lennard-Jones potential well depth.',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.CO.Lewis = {
   value = 1.171
}
db.CO.ceaThermoCoeffs = {
   nsegments = 3,
   segment0 = {
      T_lower  = 200.0,
      T_upper = 1000.0,
      coeffs = { 
	 1.489045326e+04,
	-2.922285939e+02,
	 5.724527170e+00,
	-8.176235030e-03,
	 1.456903469e-05,
	-1.087746302e-08,
	 3.027941827e-12,
	-1.303131878e+04,
	-7.859241350e+00
      }
   },
   segment1 = { 
      T_lower  = 1000.0,
      T_upper = 6000.0,
      coeffs = {  
	 4.619197250e+05,
	-1.944704863e+03,
	 5.916714180e+00,
	-5.664282830e-04,
	 1.398814540e-07,
	-1.787680361e-11,
	 9.620935570e-16,
	-2.466261084e+03,
	-1.387413108e+01
      }  
   },
   segment2 = {
      T_lower  = 6000.0,
      T_upper = 20000.0,
      coeffs = { 
	 8.868662960e+08,
	-7.500377840e+05,
	 2.495474979e+02,
	-3.956351100e-02,
	 3.297772080e-06,
	-1.318409933e-10,
	 1.998937948e-15,
	 5.701421130e+06,
	-2.060704786e+03
      }
   },
}



db.CO.grimechThermoCoeffs = {
   notes = 'data from GRIMECH 3.0',
   nsegments = 2, 
   segment0 ={
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         0,
         0,
          3.57953347E+00,
         -6.10353680E-04,
          1.01681433E-06,
          9.07005884E-10,
         -9.04424499E-13,
         -1.43440860E+04,
          3.50840928E+00,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 3500.0,
      coeffs = {
         0,
         0,
          2.71518561E+00,
          2.06252743E-03,
         -9.98825771E-07,
          2.30053008E-10,
         -2.03647716E-14,
         -1.41518724E+04,
          7.81868772E+00,
      }
   }
}


db.CO.ceaViscosity = {
   nsegments = 3,
   segment0 = {
      T_lower =200.0,
      T_upper =1000.0,
      A= 0.62526577e+00, 
      B=-0.31779652e+02, 
      C=-0.16407983e+04, 
      D=0.17454992e+01
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0, 
      A= 0.87395209e+00,
      B= 0.56152222e+03,
      C= -0.17394809e+06,
      D= -0.39335958e+00
     -- ref = 'from CEA2::trans.inp which cites Bousheri et al. (1987) and Svehla (1994)'
   },
   segment2 = {
      T_lower = 5000.0,
      T_upper = 15000.0, 
      A= 0.88503551e+00,
      B= 0.90902171e+03,
      C= -0.73129061e+06,
      D= -0.53503838e+00
     -- ref = 'from CEA2::trans.inp which cites Bousheri et al. (1987) and Svehla (1994)'
   },
}

db.CO.ceaThermCond = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper =1000.0, 
      A = 0.85439436e+00,
      B = 0.10573224e+03,
      C = -0.12347848e+05,
      D = 0.47793128e+00
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0, 
      A = 0.88407146e+00,
      B = 0.13357293e+03,
      C = -0.11429640e+05,
      D = 0.24417019E+00
   },
   segment2 = {
      T_lower = 5000.0,
      T_upper = 15000.0, 
      A = 0.24175411e+01,
      B = 0.80462671e+04,
      C = 0.31090740e+07,
      D = -0.14516932e+02
   },
      --ref = 'from CEA2::trans.inp which cites Bousheri et al. (1987) and Svehla (1994)'
}

