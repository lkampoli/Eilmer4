# unsteady-expansion-test.py
#
# $ cp ${DGD_REPO}/src/gas/sample-data/cea-air13species-gas-model.lua .
# $ python3 unsteady-expansion-test.py
#
# PJ, 2019-12-01
# 
import math
from eilmer.gas import GasModel, GasState, GasFlow

print("Unsteady expansion.")
gmodel = GasModel('cea-air13species-gas-model.lua')
state1 = GasState(gmodel)
state1.p = 100.0e3 # Pa
state1.T = 320.0 # K  ideal air, not high T
state1.update_thermo_from_pT()
state1.update_sound_speed()
print("  state1: %s" % state1)
v1 = 0.0
jplus = v1 + 2*state1.a/(1.4-1)
print("  v1=%g jplus=%g" % (v1,jplus))

print("Finite wave process along a cplus characteristic, stepping in pressure.")
state2 = GasState(gmodel)
flow = GasFlow(gmodel)
v2 = flow.finite_wave_dp(state1, v1, "cplus", 60.0e3, state2, 500)
print("  v2=%g" % v2)
print("  state2: %s" % state2)
print("  ideal v2=%g" % (jplus - 2*state2.a/(1.4-1)))

print("Finite wave process along a cplus characteristic, stepping in velocity.")
v2 = flow.finite_wave_dv(state1, v1, "cplus", 125.0, state2)
print("  v2=%g" % v2)
print("  state2: %s" % state2)
print("  ideal v2=%g" % (jplus - 2*state2.a/(1.4-1)))
