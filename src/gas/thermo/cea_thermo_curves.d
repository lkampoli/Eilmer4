/**
 * cea_thermo_curves.d
 * Implements evaluation of Cp, h and s based
 * on the curve form used by the CEA program.
 *
 * Author: Rowan G. and Peter J.
 */

module gas.thermo.cea_thermo_curves;

import std.math;
import std.stdio;
import core.stdc.stdlib : exit;
import std.string;
import std.conv;
import nm.complex;
import nm.number;
import util.lua;
import util.lua_service;
import gas : GasModelException;

class CEAThermoCurve
{
public:
    this(lua_State* L, double R)
    {
        _R = R;
        double[] coeffs;
        try {
            auto nseg = getInt(L, -1, "nsegments");
            _coeffs.length = nseg;
            getArrayOfDoubles(L, -1, "T_break_points", _T_breaks);
            getArrayOfDoubles(L, -1, "T_blend_ranges", _T_blends);
            foreach (i; 0 .. nseg) {
                auto key = format("segment%d", i);
                lua_getfield(L, -1, key.toStringz);
                getArrayOfDoubles(L, -1, "coeffs", coeffs);
                _coeffs[i][] = coeffs[];
                lua_pop(L, 1);
            }
        }
        catch (Exception e) {
            writeln("ERROR: There was a problem reading one of the thermo curves");
            writeln("ERROR: while trying to construct a CEAThermo object.\n");
            writeln("ERROR: Exception message is:\n");
            writeln(e.msg);
            exit(1);
        }
    }
    @nogc
    number eval_Cp(number T)
    {
        /* We don't try to do any fancy extrapolation
         * off the ends of the curves. Beyond the range
         * of validity we simply take the value at
         * the end of the range.
         */
        if (T < _T_breaks[0]) {
            T = _T_breaks[0];
        }
        if (T > _T_breaks[$-1]) {
            T = _T_breaks[$-1];
        }
        determineCoefficients(T);
        number Cp_on_R = _a[0]/(T*T) + _a[1]/T + _a[2] + _a[3]*T;
        Cp_on_R += _a[4]*T*T + _a[5]*T*T*T + _a[6]*T*T*T*T;
        return _R*Cp_on_R;
    }
    @nogc
    number eval_h(number T)
    {
        /* We don't try to do any fancy extrapolation beyond the limits
         * of the curves. We will simply take Cp as constant and
         * integrate using that assumption to get the portion of
         * enthalpy that is contributed beyond the temperature range.
         */
        if (T < _T_breaks[0]) {
            number T_low = _T_breaks[0];
            // We use a recursive call so that we can evaluate h @ T_low
            number h_low = eval_h(T_low);
            number Cp_low = eval_Cp(T_low);
            number h = h_low - Cp_low*(T_low - T);
            return h;
        }
        if (T > _T_breaks[$-1]) {
            number T_high = _T_breaks[$-1];
            // We use a recursive call so that we can evaluate h @ T_high
            number h_high = eval_h(T_high);
            number Cp_high = eval_Cp(T_high);
            number h = h_high + Cp_high*(T - T_high);
            return h;
        }
        // For all other cases, determine the coefficients and evaluate.
        determineCoefficients(T);
        number h_on_RT = -_a[0]/(T*T) + _a[1]/T * log(T) + _a[2] + _a[3]*T/2.0;
        h_on_RT +=  _a[4]*T*T/3.0 + _a[5]*T*T*T/4.0 + _a[6]*T*T*T*T/5.0 + _a[7]/T;
        return _R*T*h_on_RT;

    }
    @nogc
    number eval_s(number T)
    {
        /* We don't try any fancy extrapolation beyond the limits
         * of the curves. We will simply take Cp as constant and
         * integrate using that assumption to get the portion of
         * entropy that is contributed beyond the temperature range.
         */
        if (T < _T_breaks[0]) {
            number T_low = _T_breaks[0];
            // We use a recursive call so that we can evaluate s @ T_low
            number s_low = eval_s(T_low);
            number Cp_low = eval_Cp(T_low);
            number s = s_low - Cp_low*log(T_low/T);
            return s;
        }
        if (T > _T_breaks[$-1]) {
            number T_high = _T_breaks[$-1];
            // We use a recursive call so that we can evaluate s @ T_high
            number s_high = eval_s(T_high);
            number Cp_high = eval_Cp(T_high);
            number s = s_high + Cp_high*log(T/T_high);
            return s;
        }
        // For all other cases, determine the coefficients and evaluate.
        determineCoefficients(T);
        number s_on_R = -_a[0]/(2.0*T*T) - _a[1]/T + _a[2]*log(T) + _a[3]*T;
        s_on_R += _a[4]*T*T/2.0 + _a[5]*T*T*T/3.0 + _a[6]*T*T*T*T/4.0 + _a[8];
        return _R*s_on_R;
    }
private:
    double _R;
    double[] _T_breaks;
    double[] _T_blends;
    double[9] _a;
    double[9][] _coeffs;
    CEAThermoCurve[] _curves;

    @nogc
    void determineCoefficients(number T)
    {
        // First look at extremities.
        if (T < (_T_breaks[1] - 0.5*_T_blends[0])) {
            _a[] = _coeffs[0][];
            return;
        }
        if (T > (_T_breaks[$-1] + 0.5*_T_blends[$-1])) {
            _a[] = _coeffs[$-1][];
            return;
        }
        // Now look within the polynomial
        foreach (i; 1 .. _T_breaks.length-1) {
            double T_blend_low = _T_breaks[i] - 0.5*_T_blends[i-1];
            double T_blend_high =  _T_breaks[i] + 0.5*_T_blends[i-1];
            // Test if T is in blend region.
            if (T >= T_blend_low && T <= T_blend_high) {
                double wB = (1./_T_blends[i-1])*(T.re - T_blend_low);
                double wA = 1.0 - wB;
                foreach (j; 0 .. _a.length) _a[j] = wA*_coeffs[i-1][j] + wB*_coeffs[i][j];
                return;
            }
            // Test if T is above blend region.
            if (T > T_blend_high && T < (_T_breaks[i+1] - 0.5*_T_blends[i])) {
                _a[] = _coeffs[i][];
                return;
            } 
        }
        // We should never reach this point of code.
        string msg = "Coefficients for CEA curve could not be determined.";
        debug { msg ~= format("\nT=%.6e", T); }
        throw new GasModelException(msg);
    }
}


version(cea_thermo_curves_test) {
    int main() {

        import util.msg_service;
        // 1. Test CEA thermo curve for monatomic oxygen
        auto L = init_lua_State();
        doLuaFile(L, "sample-data/O-thermo.lua");
        lua_getglobal(L, "CEA_coeffs");
        double R = 8.31451/0.0159994;
        auto oThermo = new CEAThermoCurve(L, R);
        lua_close(L);
        number T = 500.0;
        assert(approxEqual(1328.627, oThermo.eval_Cp(T).re, 1.0e-6), failedUnitTest());
        T = 3700.0;
        assert(approxEqual(20030794.683, oThermo.eval_h(T).re, 1.0e-6), failedUnitTest());
        T = 10000.0;
        assert(approxEqual(14772.717, oThermo.eval_s(T).re, 1.0e-3), failedUnitTest());
        
        version(complex_numbers) {
            // Try out the complex derivative evaluation
            double h = 1.0e-20;
            T = complex(3700.0, h);
            number enthalpy = oThermo.eval_h(T);
            double Cp_cd = enthalpy.im / h;
            number Cp_eval = oThermo.eval_Cp(T);
            assert(approxEqual(Cp_cd, Cp_eval.re, 1.0e-6), failedUnitTest());
        }
        return 0;
    }
}
