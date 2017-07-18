db.CO2 = {}
db.CO2.atomicConstituents = {}
db.CO2.charge = 0
db.CO2.M = {
   value = 0.04401,
   units = 'kg/mol',
}
db.CO2.gamma = {
   value = 1.3,
   note = "valid at low temperatures"
}
db.CO2.sigma = {
   value = 3.763,
   units = 'Angstrom',
   description = 'Lennard-Jones potential distance',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.CO2.epsilon = {
   value = 244.000,
   units = 'K',
   description = 'Lennard-Jones potential well depth.',
   reference = 'GRI-Mech 3.0 transport file.'
}
db.CO2.entropyRefValues = {
   s1 = 0.0,
   T1 = 298.15,
   p1 = 101.325e3
}
db.CO2.sutherlandVisc = {
   mu_ref = 14.8e-6, 
   T_ref = 293.15,
   S = 240.0,
   reference = "Crane Company (1988) - Flow of fluids through valves, fittings and pipes"
}
db.CO2.sutherlandThermCond = {
   T_ref = 273.0, --these have not been updated
   k_ref = 0.0241, --these have not been updated
   S = 194.0,--these have not been updated
   reference = "Table 1-3, White (2006)"
}

db.CO2.ceaThermoCoeffs = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper =  1000.0,
      coeffs = {
	 4.943650540e+04,
	-6.264116010e+02,
	 5.301725240e+00,
	 2.503813816e-03,
	-2.127308728e-07,
	-7.689988780e-10,
	 2.849677801e-13,
	-4.528198460e+04,
	-7.048279440e+00
      }
   },
   segment1 = { 
      T_lower = 1000.0,
      T_upper = 6000.0,
      coeffs = {
	 1.176962419e+05,
	-1.788791477e+03,
	 8.291523190e+00,
	-9.223156780e-05,
	 4.863676880e-09,
	-1.891053312e-12,
	 6.330036590e-16,
	-3.908350590e+04,
	-2.652669281e+01
      }
   },
   segment2 = { 
      T_lower = 6000.0,
      T_upper = 20000.0,
      coeffs = {
	-1.544423287e+09,
	 1.016847056e+06,
	-2.561405230e+02,
	 3.369401080e-02,
	-2.181184337e-06,
	 6.991420840e-11,
	-8.842351500e-16,
	-8.043214510e+06,
	 2.254177493e+03
      }
   } -- from thermo.inp Gurvich, 1991 pt1 p211 pt2 p200
}

db.CO2.grimechThermoCoeffs = {
   notes = 'data from GRIMECH 3.0',
   nsegments = 2, 
   segment0 ={
      T_lower = 200.0,
      T_upper = 1000.0,
      coeffs = {
         0,
         0,
          2.35677352E+00,
          8.98459677E-03,
         -7.12356269E-06,
          2.45919022E-09,
         -1.43699548E-13,
         -4.83719697E+04,
          9.90105222E+00,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 3500.0,
      coeffs = {
         0,
         0,
          3.85746029E+00,
          4.41437026E-03,
         -2.21481404E-06,
          5.23490188E-10,
         -4.72084164E-14,
         -4.87591660E+04,
          2.27163806E+00,
      }
   }
}

db.CO2.ceaViscosity = {
   nsegments = 3,
   segment0 = {
      T_lower =200.0,
      T_upper =1000.0,
      A= 0.51137258e+00,
      B= -0.22951321e+03,
      C= 0.13710678e+05,
      D= 0.27075538e+01
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0, 
      A= 0.63978285e+00,
      B= -0.42637076e+02,
      C= -0.15522605e+05,
      D= 0.16628843e+01
     -- ref = 'from CEA2::trans.inp which cites Bousheri et al. (1987) and Svehla (1994)'
   },
   segment2 = {
      T_lower = 5000.0,
      T_upper = 15000.0, 
      A= 0.72150912e+00,
      B= 0.75012895e+03,
      C= -0.11825507e+07,
      D= 0.85493645e+00
     -- ref = 'from CEA2::trans.inp which cites Bousheri et al. (1987) and Svehla (1994)'
   }
}

db.CO2.ceaThermCond = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper =1000.0, 
      A = 0.48056568e+00,
      B = -0.50786720e+03,
      C = 0.35088811e+05,
      D = 0.36747794e+01
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0, 
      A = 0.69857277e+00,
      B = -0.11830477e+03,
      C = -0.50688859e+05,
      D =  0.18650551e+01
   },
   segment2 = {
      T_lower = 5000.0,
      T_upper = 15000.0, 
      A = 0.10518358e+01,
      B = -0.42555944e+04,
      C = 0.14288688e+08,
      D = -0.88950473e+00
   }
      --ref = 'from CEA2::trans.inp which cites Bousheri et al. (1987) and Svehla (1994)'
}

