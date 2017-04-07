db.CH2O = {}
db.CH2O.atomic_constituents = {C=1,H=2,O=1}
db.CH2O.charge = 0
db.CH2O.M = {
   value = 30.025980e-3,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'Periodic table'
}
db.CH2O.gamma = {
   value = 1.3065e+00,
   units = 'non-dimensional',
   description = 'ratio of specific heats at 300.0K',
   reference = 'evaluated using Cp/R from Chemkin-II coefficients'
}
db.CH2O.ceaThermoCoeffs = {
   notes = 'converted data from Eilmer 3, origin. Chemkin Thermo. Database Kee et al. (1993)',
   nsegments = 2, 
   segment0 ={
      T_lower = 200.0,
      T_upper = 1000.0,
     coeffs = {
   	 0.000000000e+00, 
	 0.000000000e+00, 
	 4.793723150e+00, 
	-9.908333690e-03, 
	 3.732200080e-05, 
	-3.792852610e-08, 
	 1.317726520e-11, 
	-1.430895670e+04, 
	 6.028129000e-01, 
      }
  },
  segment1 = {
     T_lower = 1000.0,
     T_upper = 3500.0,
     coeffs = {
   	 0.000000000e+00, 
	 0.000000000e+00, 
	 1.760690080e+00, 
	 9.200000820e-03, 
	-4.422588130e-06, 
	 1.006412120e-09, 
	-8.838556400e-14, 
	-1.399583230e+04, 
	 1.365632300e+01, 
      }
   }
}