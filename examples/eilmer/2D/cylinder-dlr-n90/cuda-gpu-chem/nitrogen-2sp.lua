-- Auto-generated by prep-gas on: 12-Jul-2017 22:32:50

model = 'ThermallyPerfectGas'
species = {'N2', 'N', }

N2 = {}
N2.M = 0.02801340
N2.sigma = 3.62100000
N2.epsilon = 97.53000000
N2.thermoCoeffs = {
  origin = 'CEA',
  nsegments = 3, 
  segment0 = {
    T_lower = 200.0,
    T_upper = 1000.0,
    coeffs = {
       2.210371497e+04,
      -3.818461820e+02,
       6.082738360e+00,
      -8.530914410e-03,
       1.384646189e-05,
      -9.625793620e-09,
       2.519705809e-12,
       7.108460860e+02,
      -1.076003744e+01,
    }
  },
  segment1 = {
    T_lower = 1000.0,
    T_upper = 6000.0,
    coeffs = {
       5.877124060e+05,
      -2.239249073e+03,
       6.066949220e+00,
      -6.139685500e-04,
       1.491806679e-07,
      -1.923105485e-11,
       1.061954386e-15,
       1.283210415e+04,
      -1.586640027e+01,
    }
  },
  segment2 = {
    T_lower = 6000.0,
    T_upper = 20000.0,
    coeffs = {
       8.310139160e+08,
      -6.420733540e+05,
       2.020264635e+02,
      -3.065092046e-02,
       2.486903333e-06,
      -9.705954110e-11,
       1.437538881e-15,
       4.938707040e+06,
      -1.672099740e+03,
    }
  },
}
N2.ceaViscosity = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper = 1000.0,
      A =  6.2526577e-01,
      B = -3.1779652e+01,
      C = -1.6407983e+03,
      D =  1.7454992e+00,
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  8.7395209e-01,
      B =  5.6152222e+02,
      C = -1.7394809e+05,
      D = -3.9335958e-01,
   },
   segment2 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A =  8.8503551e-01,
      B =  9.0902171e+02,
      C = -7.3129061e+05,
      D = -5.3503838e-01,
   },
}
N2.ceaThermCond = {
   nsegments = 3,
   segment0 = {
      T_lower = 200.0,
      T_upper = 1000.0,
      A =  8.5439436e-01,
      B =  1.0573224e+02,
      C = -1.2347848e+04,
      D =  4.7793128e-01,
   },
   segment1 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  8.8407146e-01,
      B =  1.3357293e+02,
      C = -1.1429640e+04,
      D =  2.4417019e-01,
   },
   segment2 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A =  2.4176185e+00,
      B =  8.0477749e+03,
      C =  3.1055802e+06,
      D = -1.4517761e+01,
   },
}
N = {}
N.M = 0.01400670
N.sigma = 3.62100000
N.epsilon = 97.53000000
N.thermoCoeffs = {
  origin = 'CEA',
  nsegments = 3, 
  segment0 = {
    T_lower = 200.0,
    T_upper = 1000.0,
    coeffs = {
       0.000000000e+00,
       0.000000000e+00,
       2.500000000e+00,
       0.000000000e+00,
       0.000000000e+00,
       0.000000000e+00,
       0.000000000e+00,
       5.610463780e+04,
       4.193905036e+00,
    }
  },
  segment1 = {
    T_lower = 1000.0,
    T_upper = 6000.0,
    coeffs = {
       8.876501380e+04,
      -1.071231500e+02,
       2.362188287e+00,
       2.916720081e-04,
      -1.729515100e-07,
       4.012657880e-11,
      -2.677227571e-15,
       5.697351330e+04,
       4.865231506e+00,
    }
  },
  segment2 = {
    T_lower = 6000.0,
    T_upper = 20000.0,
    coeffs = {
       5.475181050e+08,
      -3.107574980e+05,
       6.916782740e+01,
      -6.847988130e-03,
       3.827572400e-07,
      -1.098367709e-11,
       1.277986024e-16,
       2.550585618e+06,
      -5.848769753e+02,
    }
  },
}
N.ceaViscosity = {
   nsegments = 2,
   segment0 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  8.3724737e-01,
      B =  4.3997150e+02,
      C = -1.7450753e+05,
      D =  1.0365689e-01,
   },
   segment1 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A =  8.9986588e-01,
      B =  1.4112801e+03,
      C = -1.8200478e+06,
      D = -5.5811716e-01,
   },
}
N.ceaThermCond = {
   nsegments = 2,
   segment0 = {
      T_lower = 1000.0,
      T_upper = 5000.0,
      A =  8.3771661e-01,
      B =  4.4243270e+02,
      C = -1.7578446e+05,
      D =  8.9942915e-01,
   },
   segment1 = {
      T_lower = 5000.0,
      T_upper = 15000.0,
      A =  9.0001710e-01,
      B =  1.4141175e+03,
      C = -1.8262403e+06,
      D =  2.4048513e-01,
   },
}