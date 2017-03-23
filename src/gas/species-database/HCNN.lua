db.HCNN = {}
db.HCNN.atomicConstituents = {C=1,H=1,N=2,}
db.HCNN.charge = 0
db.HCNN.M = {
   value = 41.032040e-3,
   units = 'kg/mol',
   description = 'molecular mass',
   reference = 'Periodic table'
}
db.HCNN.gamma = {
   value = 1.2032e00,
   units = 'non-dimensional',
   description = 'ratio of specific heats at 300.0K',
   reference = 'evaluated using Cp/R from Chemkin-II coefficients'
}
db.HCNN.grimechThermoCoeffs = {
   notes = 'data from GRIMECH 3.0',
   nsegments = 2, 
   segment0 ={
      T_lower = 300.0,
      T_upper = 1000.0,
      coeffs = {
         0,
         0,
          0.25243194E+01,
          0.15960619E-01,
         -0.18816354E-04,
          0.12125540E-07,
         -0.32357378E-11,
          0.54261984E+05,
          0.11675870E+02,
      }
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      coeffs = {
         0,
         0,
          0.58946362E+01,
          0.39895959E-02,
         -0.15982380E-05,
          0.29249395E-09,
         -0.20094686E-13,
          0.53452941E+05,
         -0.51030502E+01,
      }
   }
}
