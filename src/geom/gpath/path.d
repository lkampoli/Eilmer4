/** path.d
 * Geometry-building elements for our 3D world -- one-parameter elements.
 * Note that these are geometric paths, as distinct from the file-system paths.
 *
 * Author: Peter J and Rowan G.
 * Version: 2015-02-19 first code
 *          2015-04-21 added Arc, Bezier, Polyline
 *          2015-07-02 simplify classes
 *          2017-11-26 refactor package
 */

module geom.gpath.path;

import std.conv;
import std.math;
import std.stdio;
import std.string;
import geom;
import nm.bbla;

class Path {
public:
    abstract Path dup() const;
    abstract Vector3 opCall(double t) const;
    Vector3 dpdt(double t) const
    {
	// Obtain the derivative approximately, via a finite-difference.
	double dt = 0.001;
	Vector3 p0 = this.opCall(t);
	Vector3 derivative;
	if ( t+dt > 1.0 ) {
	    // t is close to the t=1.0 boundary, use a one-sided difference.
	    Vector3 pminus1 = this.opCall(t-dt);
	    derivative = (p0 - pminus1) / dt;
	} else if ( t-dt < 0.0 ) {
	    // s is close to the s=0 boundary, use a one-sided difference.
	    Vector3 pplus1 = this.opCall(t+dt);
	    derivative = (pplus1 - p0) / dt;
	} else {
	    // Not near a boundary, use central-difference.
	    Vector3 pminus1 = this.opCall(t-dt);
	    Vector3 pplus1 = this.opCall(t+dt);
	    derivative = (pplus1 - pminus1) / (2.0 * dt);
	}
	return derivative;
    }
    Vector3 d2pdt2(double t) const
    {
	// Obtain the derivative approximately, via a finite-difference.
	double dt = 0.001;
	Vector3 p0 = this.opCall(t);
	Vector3 derivative;
	if ( t+dt > 1.0 ) {
	    // t is close to the t=1.0 boundary, use a one-sided difference.
	    Vector3 pminus1 = this.opCall(t-dt);
	    Vector3 pminus2 = this.opCall(t-2*dt);
	    derivative = (p0 - 2*pminus1 + pminus2) / pow(dt,2);
	} else if ( t-dt < 0.0 ) {
	    // s is close to the s=0 boundary, use a one-sided difference.
	    Vector3 pplus1 = this.opCall(t+dt);
	    Vector3 pplus2 = this.opCall(t+2*dt);
	    derivative = (pplus2 - 2*pplus1 + p0) / pow(dt,2);
	} else {
	    // Not near a boundary, use central-difference.
	    Vector3 pminus1 = this.opCall(t-dt);
	    Vector3 pplus1 = this.opCall(t+dt);
	    derivative = (pplus1 - 2*p0 + pminus1) / pow(dt,2);
	}
	return derivative;
    }
    double partial_length(double ta, double tb) const
    {
	if( tb < ta ) {
	    double tmp = ta; ta = tb; tb = tmp;
	}
	double L = 0.0;
	int n = 100;
	double dt = (tb - ta) / n;
	Vector3 p0 = this.opCall(ta);
	Vector3 p1, dp;
	foreach (i; 1 .. n+1) {
	    p1 = this.opCall(ta + dt * i);
	    dp = p1 - p0;
	    L += abs(dp);
	    p0 = p1;
	}
	return L;
    }
    double length() const
    {
	return partial_length(0.0, 1.0);
    }
    Vector3 point_from_length(double length, out double t) const
    {
	double L = 0.0;
	int n = 1000;
	double dt = 1.0 / n;
	Vector3 p0 = this.opCall(0.0);
	Vector3 p1, dp;
	foreach (i; 1 .. n+1) {
	    p1 = this.opCall(dt * i);
	    dp = p1 - p0;
	    L += abs(dp);
	    p0 = p1;
	    if( L > length ) {
		t = dt * i;
		return p1;
	    }
	}
	t = dt * n;
	return p1;
    }
    abstract override string toString() const;
    abstract string classString() const;
    bool intersect2D(const Vector3 ps, const Vector3 d, out double t, int nseg=20) const
    // Determine the intersection of a projected line on the Path.
    // Input:
    //     ps starting point for projected line
    //     d direction of projected line
    // Output:
    //     t parametric position of intersection along the Path
    // Returns:
    //     true, if the intersection point was located;
    //     false, if the intersection was not found
    // See PJ's workbook page 34, 2017-06-24 for notation and derivation.
    {
	if (cast(Line)this !is null) { nseg = 1; } // straight Line
	double delt = 1.0/nseg;
	double t0 = 0.0; Vector3 p0 = this.opCall(0.0);
	foreach (i; 0 .. nseg) {
	    double t1 = delt*(i+1); Vector3 p1 = this.opCall(t1);
	    double tOnSegment;
	    bool intersectionOK = geom.intersect2D(p0, p1, ps, d, tOnSegment);
	    if (intersectionOK && tOnSegment >= 0.0 && tOnSegment <= 1.0) {
		t = t0 + tOnSegment*delt;
		return true;
	    }
	    t0 = t1; p0 = p1; // for next segment
	}
	return false;
    } // end intersect2D()
} // end class Path


class Line : Path {
public:
    Vector3 p0; // end-point at t=0
    Vector3 p1; // end-point at t=1
    this(in Vector3 p0, in Vector3 p1)
    {
	this.p0 = p0; this.p1 = p1;
    }
    this(ref const(Line) other)
    {
	p0 = other.p0; p1 = other.p1;
    }
    override Line dup() const
    {
	return new Line(p0, p1);
    }
    override Vector3 opCall(double t) const 
    {
	return (1.0-t)*p0 + t*p1;
    }
    override Vector3 dpdt(double t) const 
    {
	return p1 - p0;
    }
    override Vector3 d2pdt2(double t) const 
    {
	return Vector3(0.0,0.0,0.0);
    }
    override string toString() const
    {
	return "Line(p0=" ~ to!string(p0) ~ ", p1=" ~ to!string(p1) ~ ")";
    }
    override string classString() const
    {
	return "Line";
    }
    override double partial_length(double ta, double tb) const
    {
	Vector3 dp = p1 - p0;
	return fabs(tb - ta) * abs(dp);
    }
    override Vector3 point_from_length(double length, out double t) const
    {
	Vector3 dp = p1 - p0;
	t = length/(abs(dp));
	return this.opCall(t);
    }
} // end class Line


unittest {
    auto a = Vector3([1.0, 2.2, 3.0]);
    auto b = Vector3(1.0);
    auto ab = new Line(a, b);
    auto c = ab(0.5);
    assert(approxEqualVectors(c, Vector3(1.0, 1.1, 1.5)), "Line");
    auto ab2 = ab.dup();
    auto d = ab2(0.5);
    assert(approxEqualVectors(c, d), "Line.dup");
    auto pth = new Line(Vector3(0.0,1.0), Vector3(1.0,1.0));
    auto ps = Vector3(0.5,0.5);
    auto dir = Vector3(0.0,1.0);
    double t;
    auto found = pth.intersect2D(ps, dir, t);
    assert(found, "intersect2D not found on Line");
    assert(approxEqual(t,0.5), "intersect2D parametric location on Line");
}


class Arc : Path {
public:
    Vector3 a; // beginning point (t = 0)
    Vector3 b; // end point (t = 1)
    Vector3 c; // centre of curvature
    // Arc constructed from start-point a, end-point b and centre of curvature c.
    this(in Vector3 a, in Vector3 b, in Vector3 c)
    {
	this.a = a; this.b = b; this.c = c;
    }
    this(ref const(Arc) other)
    {
	a = other.a; b = other.b; c = other.c;
    }
    override Arc dup() const
    {
	return new Arc(a, b, c);
    }
    override Vector3 opCall(double t) const 
    {
	double L;
	Vector3 p;
	evaluate_position_and_length(t, p, L);
	return p;
    }
    override string toString() const
    {
	return "Arc(a=" ~ to!string(a) ~ ", b=" ~ to!string(b) ~ ", c=" ~ to!string(c) ~ ")";
    }
    override string classString() const
    {
	return "Arc";
    }
    override double length() const
    {
	// Returns the geometric length.
	double L;
	Vector3 p;
	evaluate_position_and_length(1.0, p, L);
	return L;
    }
    
    void evaluate_position_and_length(in double t, out Vector3 loc, out double L) const
    {
	// Both the position of the point and the length of the full arc are evaluated
	// using mostly the same process of transforming to the plane local to the arc.
	Vector3 ca, cb, tangent1, tangent2, n, cb_local;
	double ca_mag, cb_mag, theta;

	L = 0.0;
	ca = a - c; ca_mag = abs(ca);
	cb = b - c; cb_mag = abs(cb);
	if ( fabs(ca_mag - cb_mag) > 1.0e-5 ) {
	    throw new Error(text("Arc.evaluate(): radii do not match ca=",ca," cb=",cb));
	}
	// First vector in plane.
	tangent1 = Vector3(ca); tangent1.normalize(); 
	// Compute unit normal to plane of all three points.
	n = cross(ca, cb);
	if ( abs(n) > 0.0 ) {
	    n.normalize();
	} else {
	    throw new Error(text("Arc.evaluate(): cannot find plane of three points."));
	}
	// Third (orthogonal) vector is in the original plane.
	tangent2 = cross(n, tangent1); 
	// Now transform to local coordinates so that we can do 
	// the calculation of the point along the arc in 
	// the local xy-plane, with ca along the x-axis.
	cb_local = cb;
	Vector3 zero = Vector3(0.0,0.0,0.0);
	cb_local.transform_to_local_frame(tangent1, tangent2, n, zero);
	if ( fabs(cb_local.z) > 1.0e-6 ) {
	    throw new Error(text("Arc.evaluate(): problem with transformation cb_local=", cb_local));
	}
	// Angle of the final point on the arc is in the range -pi < th <= +pi.
	theta = atan2(cb_local.y, cb_local.x);
	// The length of the circular arc.
	L = theta * cb_mag;
	// Move the second point around the arc in the local xy-plane.
	theta *= t;
	loc.set(cos(theta)*cb_mag, sin(theta)*cb_mag, 0.0);
	// Transform back to global xyz coordinates
	// and remember to add the centre coordinates.
	loc.transform_to_global_frame(tangent1, tangent2, n, c);
    } // end evaluate_position_and_length()
} // end class Arc

class Arc3 : Arc {
    // Arc constructed from start-point a, end-point b and another intermediate point m.
    // Internally it is stored as an Arc object.
    Vector3 m;
    this(in Vector3 a, in Vector3 m, in Vector3 b)
    {
	Vector3 n = cross(m - a, m - b); // normal to plane of arc
	if (abs(n) <= 1.0e-11) {
	    throw new Error(text("Arc3: Points appear colinear.",
				 " a=", to!string(a),
				 " m=", to!string(m),
				 " b=", to!string(b)));
	}
	// The centre of the circle lies along the bisector of am and 
	// the bisector of mb.
	Vector3 mid_am = 0.5 * (a + m);
	Vector3 bisect_am = cross(n, a - m);
	Vector3 mid_mb = 0.5 * (b + m);
	Vector3 bisect_mb = cross(n, b - m);
	// Solve least-squares problem to get s_am, s_mb.
	auto amatrix = new Matrix([[bisect_am.x, bisect_mb.x],
				   [bisect_am.y, bisect_mb.y],
				   [bisect_am.z, bisect_mb.z]]);
	Vector3 diff_mid = mid_mb - mid_am;
	auto rhs = new Matrix([diff_mid.x, diff_mid.y, diff_mid.z], "column");
	auto s_values = lsqsolve(amatrix, rhs);
	double s_am = s_values[0,0];
	double s_mb = s_values[1,0];
	Vector3 c = mid_am + s_am * bisect_am;
	Vector3 c_check = mid_mb + s_mb * bisect_mb;
	Vector3 delc = c_check - this.c;
	if (abs(delc) > 1.0e-9) {
	    throw new Error(text("Arc3: Points inconsistent centre estimates.",
				 " c=", to!string(this.c),
				 " c_check=", to!string(c_check)));
	}
	super(a, b, c);
	this.m = m;
    }
    this(ref const(Arc3) other)
    {
	this(other.a, other.m, other.b);
    }
    override Arc3 dup() const
    {
	return new Arc3(a, m, b);
    }
    override string toString() const
    {
	return "Arc3(a=" ~ to!string(a) ~ ", m=" ~ to!string(m) ~ ", b=" ~ to!string(b) ~ ")";
    }
    override string classString() const
    {
	return "Arc3";
    }
} // end class Arc3

unittest {
    auto a = Vector3([2.0, 2.0, 0.0]);
    auto b = Vector3([1.0, 2.0, 1.0]);
    auto c = Vector3([1.0, 2.0, 0.0]);
    auto abc = new Arc(a, b, c);
    auto d = abc(0.5);
    assert(approxEqualVectors(d, Vector3(1.7071068, 2.0, 0.7071068)), "Arc");
    auto adb = new Arc3(a, d, b);
    assert(approxEqualVectors(d, adb(0.5)), "Arc3");
    //
    auto pth = new Arc3(Vector3(0.0,1.0), Vector3(0.5,1.2), Vector3(1.0,1.0));
    auto ps = Vector3(0.5,0.5);
    auto dir = Vector3(0.0,1.0);
    double t;
    auto found = pth.intersect2D(ps, dir, t, 10);
    assert(found, "intersect2D not found on Arc3");
    assert(approxEqual(t,0.5), "intersect2D parametric location on Arc3");
}


class Helix : Path {
public:
    Vector3 a0; // beginning point on local z-axis (t = 0)
    Vector3 a1; // end point on local z-axis (t = 1)
    Vector3 xdsh; // local x-axis, unit vector
    Vector3 ydsh; // local y-axis, unit vector
    Vector3 zdsh; // local z-axis, unit vector
    double r0, r1; // starting and ending radii
    double theta01; // angle (in radians) from starting point to ending point,
    // assuming the right-hand screw convention.
    //
    // Helix constructed from fundamental parameters.
    this(in Vector3 a0, in Vector3 a1, in Vector3 xlocal,
	 double r0, double r1, double dtheta)
    {
	this.a0 = a0; this.a1 = a1;
	this.r0 = r0; this.r1 = r1;
	this.theta01 = dtheta;
	// set up local unit vectors at p0
	xdsh = unit(xlocal);
	zdsh = a1 - a0; zdsh.normalize(); // along the axis of the helix
	ydsh = cross(zdsh, xdsh); // normal to both
    }
    // Helix constructed from point_start to point_end about an axis
    // from axis0 to axis1.
    // We will compute the fundamantal parameters from these points.
    this(in Vector3 point_start, in Vector3 point_end, 
	 in Vector3 axis0, in Vector3 axis1) 
    {
	// Local vectors relative to axis0.
	Vector3 a = axis1 - axis0;
	Vector3 b = point_start - axis0;
	Vector3 c = point_end - axis0;
	zdsh = unit(a);
	Vector3 a0b = b - dot(b,a)*zdsh;
	xdsh = unit(a0b);
	ydsh = cross(zdsh,xdsh);
	a0 = axis0 + dot(b,zdsh)*zdsh;
	a1 = axis0 + dot(c,zdsh)*zdsh;
	r0 = dot(b,xdsh);
	Vector3 a1c = c - dot(c,zdsh)*zdsh;
	r1 = abs(a1c);
	Vector3 origin = Vector3(0.0, 0.0, 0.0);
	a1c.transform_to_local_frame(xdsh, ydsh, zdsh, origin);
	theta01 = atan2(a1c.y, a1c.x);
    }
    this(ref const(Helix) other)
    {
	a0 = other.a0; a1 = other.a1;
	r0 = other.r0; r1 = other.r1;
	theta01 = other.theta01;
	xdsh = other.xdsh; ydsh = other.ydsh; zdsh = other.zdsh;
    }
    override Helix dup() const
    {
	return new Helix(a0, a1, xdsh, r0, r1, theta01);
    }
    override Vector3 opCall(double t) const 
    {
	double r = r0*(1.0-t) + r1*t;
	double theta = theta01 * t;
	Vector3 p = r*cos(theta)*xdsh + r*sin(theta)*ydsh + a0*(1.0-t) + a1*t;
	return p;
    }
    override string toString() const
    {
	return "Helix(a0=" ~ to!string(a0) ~
	    ", a1=" ~ to!string(a1) ~
	    ", xdsh=" ~ to!string(xdsh) ~
	    ", r0=" ~ to!string(r0) ~
	    ", r1=" ~ to!string(r1) ~
	    ", theta01=" ~ to!string(theta01) ~
	    ")";
    }
    override string classString() const
    {
	return "Helix";
    }
} // end class Helix

unittest {
    auto axis0 = Vector3([0.0, 0.0, 0.0]);
    auto axis1 = Vector3([1.0, 0.0, 0.0]);
    auto pstart = Vector3([0.0, 1.0, 0.0]);
    auto pend = Vector3([1.0, 0.0, 1.0]);
    auto h1 = new Helix(pstart, pend, axis0, axis1);
    auto p = h1(0.5);
    assert(approxEqualVectors(p, Vector3(0.5, 0.7071068, 0.7071068)), "Helix");
    auto a0 = Vector3([0.0, 0.0, 0.0]);
    auto a1 = Vector3([1.0, 0.0, 0.0]); // axis is in global-frame x-direction
    auto xlocal = Vector3([0.0, 1.0, 0.0]); // pointing at start point
    auto r0 = 1.0;
    auto r1 = 1.0;
    auto dtheta = PI/2;
    auto h2 = new Helix(a0, a1, xlocal, r0, r1, dtheta);
    auto p2 = h2(0.5);
    assert(approxEqualVectors(p2, Vector3(0.5, 0.7071068, 0.7071068)),
	   "Helix from fundamental parameters");
}


class Bezier : Path {
public:
    Vector3[] B; // collection of control points
    this(in Vector3[] B)
    {
	if (B.length == 0) {
	    throw new Error(text("Bezier() No control points present."));
	}
	if (B.length == 1) {
	    throw new Error(text("Bezier() Only one control point, not enough for a curve."));
	}
	this.B = B.dup();
	set_deriv_control_points();
    }
    this(ref const(Bezier) other)
    {
	this(other.B);
    }
    override Bezier dup() const
    {
	return new Bezier(B);
    }
    override Vector3 opCall(double t) const 
    {
	// Evaluate B(t)
	return deCasteljau(B, t);
    } // end opCall()
    override Vector3 dpdt(double t) const
    {
	return deCasteljau(C, t);
    }
    override Vector3 d2pdt2(double t) const
    {
	return deCasteljau(D, t);
    }
    override string toString() const
    {
	return "Bezier(B=" ~ to!string(B) ~ ")";
    }
    override string classString() const
    {
	return "Bezier";
    }

protected:
    Vector3[] C; // derivative curve
    Vector3[] D; // second derivative curve
    void set_deriv_control_points()
    {
	size_t n = B.length - 1;
	if ( n == 0) {
	    // shouldn't reach here due to check in constructor
	    throw new Error(text("Bezier() Curve is a point, derivative not defined"));
	}
	C.length = n;
	foreach (i; 0 .. n){
	    C[i] = n*(B[i+1] - B[i]);
	}
	if ( n == 1 ) {
	    D = [Vector3(0)];
	    return;
	}
	D.length = n - 1;
	foreach (i; 0 .. n-1){
	    D[i] = (n-1)*(C[i+1] - C[i]);
	}
    }
    Vector3 deCasteljau(ref const(Vector3[]) B, double t) const
    {
	if ( B.length == 1 ) return B[0];
	size_t n_order = B.length - 1;
	// Apply de Casteljau's algorithm. 
	Vector3[] Q = B.dup(); // work array will be overwritten
	foreach (k; 0 .. n_order) {
	    foreach (i; 0 .. n_order-k) {
		Q[i] = (1.0 - t) * Q[i] + t * Q[i+1];
	    }
	}
	return Q[0];
    }
} // end class Bezier


unittest {
    auto a = Vector3([2.0, 2.0, 0.0]);
    auto b = Vector3([1.0, 2.0, 1.0]);
    auto c = Vector3([1.0, 2.0, 0.0]);
    auto abc = new Arc(a, b, c);
    auto d = abc(0.5);
    auto adb = new Bezier([a, d, b]);
    auto e = adb(0.5);
    assert(approxEqualVectors(e, Vector3(1.60355, 2, 0.603553)), "Bezier");
    auto ab = new Bezier([a, b]);
    assert(approxEqualVectors(ab.dpdt(0.5), Vector3(-1, 0, 1)), "Bezier");
    assert(approxEqualVectors(ab.d2pdt2(0.5), Vector3(0)), "Bezier");
    auto acb = new Bezier([a, c, b]);
    assert(approxEqualVectors(acb.dpdt(0.5), Vector3(-1, 0, 1)), "Bezier");
    assert(approxEqualVectors(acb.d2pdt2(0.5), Vector3(2,0,2)), "Bezier");
}


class Polynomial : Path {
    // polynomial in the form y = sum(c_i * x^^i)|i=0..n
    // Momar Hughes, 4th-year thesis, October 2015
public:
    Vector3[] P; // array of control points to interpolate
    double[] C; // array of coefficients
	
    this(in Vector3[] P)
    {
	if (P.length == 0) {
	    throw new Error(text("Polynomial() No control points present."));
	} // end if
	if (P.length == 1) {
	    throw new Error(text("Polynomial() Only one control point, not enough for a curve."));
	} // end if
	this.P = P.dup();
	evaluate_coefficients();
    }
    this(in double[] C,double x0,double x1)
    {
    	if (C.length == 0) {
	    throw new Error(text("Polynomial() No coefficients provided."));
	} // end if
	this.C = C.dup();
	this.P.length = 2;
	this.P[0] = evaluate_polynomial(x0);
	this.P[1] = evaluate_polynomial(x1);
    }
    this(in Vector3[] P,in double[] C)
    {
    	if (C.length == 0) {
	    throw new Error(text("Polynomial() No coefficients provided."));
	} // end if
	this.C = C.dup();
	foreach(point;P){
	    if(point.y != evaluate_polynomial(point.x).y){
		throw new Error(text("Polynomial() points and coefficients do not match."));
	    } // end if
	} // end foreach
	this.P = P.dup();
    }
    this(ref const(Polynomial) other)
    {
	this.P = other.P.dup();
	this.C = other.C.dup();
    }
    override Polynomial dup() const
    {
	return new Polynomial(P,C);
    } // end dup()
    override Vector3 opCall(double t) const
    {
	// Evaluate P(t)
	double xt = P[0].x + t*(P[$-1].x-P[0].x);
	return evaluate_polynomial(xt);
    } // end opCall()
    override Vector3 dpdt(double t) const
    {
	// Evaluate P(t)
	double xt;
	xt = P[0].x + t*(P[$-1].x-P[0].x);
	return derivative_polynomial(xt);
    }
    override string toString() const
    {
	return "Polynomial(P=" ~ to!string(P) ~ ")";
    }
    override string classString() const
    {
	return "Polynomial";
    }

protected:    
    void evaluate_coefficients()
    {
	size_t n = P.length;
	auto A = new Matrix(n);
	auto b = new Matrix(n,1);
	foreach(i;0 .. n){
	    b[i,0] = P[i].y;
	    foreach(j;0 .. n){
		A[i,j] = P[i].x^^j;
	    } // end foreach
	} // end foreach
	auto x = lsqsolve(A,b);
	foreach(i;0 .. n){
	    C ~= x[i,0];
	} // end foreach
    } // end evaluate_coefficients ()
    
    Vector3 evaluate_polynomial(double x) const
    {
    	double y=0.0;
	foreach(i;0 .. C.length){
	    y += C[i] * x^^i;
	} // end foreach
	return Vector3(x,y);
    } // end evaluate_polynomial ()

    Vector3 derivative_polynomial(double x) const
    {
    	double dy=0.0;
	foreach(i;0 .. C.length){
	    dy += C[i] * i * x^^(i-1);
	} // end foreach
	return Vector3(1.0,dy);
    } // end evaluate_polynomial ()

} // end class Polynomial


class Polyline : Path {
public:
    Path[] segments; // collection of Path segments
    double[] t_values; // collection of segment break-points (in parameter t)

    // Construct from the Path segments.
    this(in Path[] segments)
    {
	if (segments.length == 0) {
	    throw new Error(text("Polyline() No segments present."));
	}
	foreach (myseg; segments) this.segments ~= myseg.dup(); 
	t_values.length = this.segments.length;
	reset_breakpoints();
    }
    
    // Construct as a spline through specified points.
    this(const Vector3[] p, double tolerance=1.0e-10)
    {
	auto m = p.length - 1;
	// Given m+1 interpolation points p, determine the m-segment
	// Bezier polyline that interpolates these points as a spline. 
	// This is done by first determining the array of weight points
	// which define the spline and then evaluating the cubic 
	// Bezier segments.
	// Reference:
	//     G. Engelin & F. Uhlig (1996)
	//     Numerical Algorithms with C
	//     Springer, Berlin
	//     Section 12.3.1
 
	Vector3[] d; d.length = m+1;  // weight points
	// For a natural spline, the first and last weight points
	// are also the first and last interpolation points.
	d[0] = p[0];
	d[m] = p[m];

	// For the initial guess at the remaining weight points,
	// just use the supplied data points.
	foreach (i; 1 .. m) { d[i] = p[i]; }
	// Apply Gauss-Seidel iteration until
	// the internal weight points converge.
	Vector3 old_p;
	double max_diff;
	foreach (j; 1 .. 50) {
	    max_diff = 0.0;
	    foreach (i; 1 .. m) {
		old_p = d[i];
		d[i] = 0.25 * (6.0 * p[i] - d[i-1] - d[i+1]);
		Vector3 diff = d[i] - old_p;
		max_diff = fmax(max_diff, abs(diff));
	    } // end foreach i
	    if ( max_diff < tolerance ) break;
	} // end foreach j

	// Final stage; calculate the Bezier segments
	Vector3[4] p03;
	Path[] seg;
	foreach (i; 0 ..  m) {
	    p03[0] = p[i];
	    p03[1] = (2.0 * d[i] + d[i+1]) / 3.0;
	    p03[2] = (d[i] + 2.0 * d[i+1]) / 3.0;
	    p03[3] = p[i+1];
	    seg ~= new Bezier(p03);
	}
	// and pack them away.
	this(seg);
    } // end spline constructor

    // Contructs a spline from a file containing x(,y(,z)) coordinates.
    this(string fileName)
    {
	// This function takes a filename and processes it assuming that each
	// line contains (x,y,z) triples (space-delimited).  If any values are
	// missing on a given line, they are assumed to be 0.0.  The x,y,z-triples
	// are gathered and used to create the Spline.
	// Ported Python code Spline2 from libgeom2.i 2015-10-05 by PJ
	Vector3[] points;
	auto f = File(fileName, "r");
	foreach (line; f.byLine) {
	    auto tokens = line.strip().split();
	    if (tokens.length == 0) continue; // ignore blank lines
	    if (tokens[0] == "#") continue; // ignote comment lines
	    double x = to!double(tokens[0]);
	    double y = 0.0; if (tokens.length > 1) { y = to!double(tokens[1]); }
	    double z = 0.0; if (tokens.length > 2) { z = to!double(tokens[2]); }
	    points ~= Vector3(x, y, z);
	}
	this(points);
    } // end spline constructor
    
    this(ref const(Polyline) other)
    {
	this(other.segments);
    }
    
    override Polyline dup() const
    {
	return new Polyline(segments);
    }
    
    override Vector3 opCall(double t) const 
    {
	// Evaluate B(t) without considering arc_length parameterization flag
	// or subrange.
	auto n = segments.length;
	if ( n == 1 ) return segments[0](t);
	size_t i;
	for ( i = 0; i < n; ++i ) {
	    if ( t <= t_values[i] ) break;
	}
	if ( i >= n ) i = n - 1;  // last segment
	// At this point, t_values[i-1] < t <= t_values[i] (we hope)
	// Have assumed that the t breakpoints are well behaved.
	double t_local;
	if ( i == 0 ) {
	    t_local = t / t_values[i];
	} else {
	    t_local = (t - t_values[i-1]) / (t_values[i] - t_values[i-1]);
	}
	return segments[i](t_local);
    } // end opCall()
    
    override string toString() const
    {
	return "Polyline(segments=" ~ to!string(segments) ~ ")";
    }
    override string classString() const
    {
	return "Polyline";
    }

private:
    void reset_breakpoints()
    {
	// Set up the parameter breakpoints based on cumulative length.
	t_values[0] = segments[0].length();
	foreach (i; 1 .. segments.length) t_values[i] = t_values[i-1] + segments[i].length(); 
	double L_total = t_values[$-1];
	foreach (i; 0 .. segments.length) t_values[i] /= L_total; 
    } // end reset_breakpoints()
} // end class Polyline


unittest {
    auto a = Vector3([2.0, 2.0, 0.0]);
    auto b = Vector3([1.0, 2.0, 1.0]);
    auto c = Vector3([1.0, 2.0, 0.0]);
    auto abc = new Arc(a, b, c);
    auto polyline = new Polyline([abc, new Line(b, c)]);
    auto f = polyline(0.5);
    assert(approxEqualVectors(f, Vector3(1.28154, 2, 0.95955)), "Polyline");
}


class ReParameterizedPath : Path {
public:
    Path underlying_path;
    this(const Path other)
    {
	underlying_path = other.dup();
    }
    override Vector3 opCall(double t) const 
    {
	double tdsh = underlying_t(t);
	return underlying_path(tdsh);
    }
    override Vector3 dpdt(double t) const
    {
	double tdsh = underlying_t(t);
	return underlying_path.dpdt(tdsh)*d_underlying_t_dt(tdsh);
    }
    override Vector3 d2pdt2(double t) const
    {
	double tdsh = underlying_t(t);
	return underlying_path.d2pdt2(tdsh)*pow(d_underlying_t_dt(tdsh), 2) + underlying_path.dpdt(tdsh)*d2_underlying_t_dt2(tdsh);
    }
    abstract override string toString() const
    {
	return "ReParameterizedPath(underlying_path=" ~ to!string(underlying_path) ~ ")";
    }
    override string classString() const
    {
	return "ReParameterizedPath";
    }

protected:
    abstract double underlying_t(double t) const;
    abstract double d_underlying_t_dt(double t) const;
    abstract double d2_underlying_t_dt2(double t) const;

} // end class ReParameterizedPath

class ArcLengthParameterizedPath : ReParameterizedPath {
public:
    this(const Path other)
    {
	super(other);
	set_arc_length_vector(100);
    }
    this(ref const(ArcLengthParameterizedPath) other)
    {
	this(other.underlying_path);
    }
    override ArcLengthParameterizedPath dup() const
    {
	return new ArcLengthParameterizedPath(this.underlying_path);
    }
    override string toString() const
    {
	return "ArcLengthParameterizedPath(underlying_path=" ~ to!string(underlying_path) ~ ")";
    }
    override string classString() const
    {
	return "ArcLengthParametrizedPath";
    }

protected:
    double[] arc_length_vector;
    void set_arc_length_vector(int N)
    {
	// Compute the arc_lengths for a number of sample points 
	// so that these can later be used to do a reverse interpolation
	// on the evaluation parameter.
	arc_length_vector.length = 0;
	if ( N == 0 ) return;
	double dt = 1.0 / N;
	double L = 0.0;
	arc_length_vector ~= L;
	Vector3 p0 = underlying_path(0.0);
	Vector3 p1;
	foreach (i; 1 .. N+1) {
	    p1 = underlying_path(dt * i);
	    Vector3 dp = p1 - p0;
	    L += abs(dp);
	    arc_length_vector ~= L;
	    p0 = p1;
	}
    } // end set_arc_length_vector()
    override double underlying_t(double t) const
    {
	// The incoming parameter value, t, is proportional to arc_length fraction.
	if (t <= 0.0) return 0.0;
	if (t >= 1.0) return 1.0;
	// Do a reverse look-up from the arc_length fraction to the original t parameter
	// of the underlying Path.
	double L_target = t * arc_length_vector[$-1];
	// Starting from the right-hand end,
	// let's try to find a point to the left of L_target.
	// If the value is out of range, this should just result in
	// us extrapolating one of the end segments -- that's OK.
	int i = to!int(arc_length_vector.length) - 1;
	double dt = 1.0 / (arc_length_vector.length - 1);
	while ( L_target < arc_length_vector[i] && i > 0 ) i--;
	double frac = (L_target - arc_length_vector[i]) /
	    (arc_length_vector[i+1] - arc_length_vector[i]);
	return (1.0 - frac) * dt*i + frac * dt*(i+1);
    }
    override double d_underlying_t_dt(double t) const
    {
	// input "t" is underlying_t
	// derivative of inverse fn
	return 1.0/d_arc_f_dt(t);
    }
    override double d2_underlying_t_dt2(double t) const
    {
	// input "t" is underlying_t
	// derivative of inverse fn
	return -d2_arc_f_dt2(t)/pow(d_arc_f_dt(t),3);
    }
private:
    double d_arc_f_dt(double t) const
    {
	// "t" is underlying_t
	Vector3 dpdt = underlying_path.dpdt(t);
	return abs(dpdt)/arc_length_vector[$-1];
    }
    double d2_arc_f_dt2(double t) const
    {
	// "t" is underlying_t
	//chain rule on d_arc_f_dt
	Vector3 dpdt = underlying_path.dpdt(t);
	return dot(unit(dpdt),underlying_path.d2pdt2(t))/arc_length_vector[$-1];
    }
} // end class ArcLengthParameterizedPath


unittest {
    auto a = Vector3([0.0, 0.0, 0.0]);
    auto b = Vector3([1.0, 1.0, 1.0]);
    auto c = Vector3([4.0, 4.0, 4.0]);
    auto abc = new Bezier([a, b, c]);
    auto abc_dsh = new ArcLengthParameterizedPath(abc);
    auto f = abc_dsh(0.5);
    assert(approxEqualVectors(f, Vector3(2,2,2)), "ArcLengthParameterizedPath");
    
    a = Vector3([2.0, 2.0, 0.0]);
    b = Vector3([1.0, 2.0, 1.0]);
    c = Vector3([1.0, 2.0, 0.0]);
    auto acb = new ArcLengthParameterizedPath(new Bezier([a, c, b])); 
    auto L = acb.underlying_path.length();
    auto dA = Vector3(-1, 0, 1);
    auto dAdt = abs(dA)/L;
    Vector3 d2A = Vector3(-1, 0, 1);
    auto d2Adt2 = dot(unit(d2A),Vector3(2,0,2))/L;
    // check to finite-difference in Path
    assert(approxEqualVectors(acb.dpdt(0.5), acb.Path.dpdt(0.5)), "ArcLengthParameterizedPath");
    assert(approxEqualVectors(acb.d2pdt2(0.5), acb.Path.d2pdt2(0.5)), "ArcLengthParameterizedPath");
    // the following checks are kind of redundant since they just follow the same math as the function definitions
    assert(approxEqualVectors(acb.dpdt(0.5), Vector3(-1, 0, 1)/dAdt), "ArcLengthParameterizedPath");
    assert(approxEqualVectors(acb.d2pdt2(0.5), Vector3(2,0,2)/pow(dAdt,2)-Vector3(-1, 0, 1)*d2Adt2/pow(dAdt,3)), "ArcLengthParameterizedPath");
}


class SubRangedPath : ReParameterizedPath {
public:
    double t0;
    double t1;
    this(const Path other, double newt0, double newt1)
    {
	super(other);
	t0 = newt0;
	t1 = newt1;
    }
    this(ref const(SubRangedPath) other)
    {
	this(other.underlying_path, other.t0, other.t1);
    }
    override SubRangedPath dup() const
    {
	return new SubRangedPath(this.underlying_path, this.t0, this.t1);
    }
    override string toString() const
    {
	return "SubRangedPath(underlying_path=" ~ to!string(underlying_path) 
	    ~ ", t0=" ~ to!string(t0) ~ " t1=" ~ to!string(t1) ~ ")";
    }
    override string classString() const
    {
	return "SubRangedPath";
    }
protected:
    override double underlying_t(double t) const
    {
	return t0 + (t1 - t0)*t;
    }
    override double d_underlying_t_dt(double t) const
    {
	return t1 - t0;
    }
    override double d2_underlying_t_dt2(double t) const
    {
	return 0;
    }
} // end class SubRangedPath


class ReversedPath : SubRangedPath {
    // Just a particular case of SubRangedPath
    this(const Path other)
    {
	super(other, 1.0, 0.0);
    }
    override ReversedPath dup() const
    {
	return new ReversedPath(this.underlying_path);
    }
} // end class ReversedPath


unittest {
    auto a = Vector3([2.0, 2.0, 0.0]);
    auto b = Vector3([1.0, 2.0, 1.0]);
    auto c = Vector3([1.0, 2.0, 0.0]);
    auto abc = new Arc(a, b, c);
    auto polyline = new Polyline([abc, new Line(b, c)]);
    auto rev_poly = new ReversedPath(polyline);
    assert(approxEqualVectors(polyline(0.25), rev_poly(0.75)), "ReversedPath");
    auto acb = new SubRangedPath(new Bezier([a, c, b]), 0.5, 0.75); 
    assert(approxEqualVectors(acb.dpdt(0), Vector3(-1, 0, 1)/4), "SubRangedPath");
    assert(approxEqualVectors(acb.d2pdt2(0), Vector3(2,0,2)/16), "SubRangedPath");
    auto r_acb = new ReversedPath(new Bezier([a, c, b]));
    assert(approxEqualVectors(r_acb.dpdt(0.5), -Vector3(-1, 0, 1)), "ReversedPath");
    assert(approxEqualVectors(r_acb.d2pdt2(0.5), Vector3(2,0,2)), "ReversedPath");
}


class TransformedPath : Path {
public:
    Path original_path;
    this(const Path other)
    {
	original_path = other.dup();
    }
    override Vector3 opCall(double t) const 
    {
	Vector3 p = original_path(t);
	return apply_transform(p);
    }
    abstract override string toString() const
    {
	return "TransformedPath(original_path=" ~ to!string(original_path) ~ ")";
    }
    override string classString() const
    {
	return "TransformedPath";
    }

protected:
    abstract Vector3 apply_transform(ref Vector3 p) const;

} // end class TransformedPath


class TranslatedPath : TransformedPath {
    Vector3 shift;
    this(const Path other, const Vector3 shift)
    {
	super(other);
	this.shift = shift; 
    }
    override TranslatedPath dup() const
    {
	return new TranslatedPath(this.original_path, this.shift);
    }
    override string toString() const
    {
	return "TranslatedPath(original_path=" ~ to!string(original_path) 
	    ~ ", shift=" ~ to!string(shift) ~ ")";
    }
    override string classString() const
    {
	return "TranslatedPath";
    }

protected:
    override Vector3 apply_transform(ref Vector3 p) const
    {
	return p+shift;
    }
} // end class TranslatedPath


class MirrorImagePath : TransformedPath {
    Vector3 point;
    Vector3 normal;
    this(const Path other, const Vector3 point, const Vector3 normal)
    {
	super(other);
	this.point = point;
	this.normal = normal;
    }
    override MirrorImagePath dup() const
    {
	return new MirrorImagePath(this.original_path, this.point, this.normal);
    }
    override string toString() const
    {
	return "MirrorImagePath(original_path=" ~ to!string(original_path) 
	    ~ ", point=" ~ to!string(point) ~ ", normal=" ~ to!string(normal) ~ ")";
    }
    override string classString() const
    {
	return "MirrorImagePath";
    }

protected:
    override Vector3 apply_transform(ref Vector3 p) const
    {
	return p.mirror_image(point, normal);
    }
} // end class MirrorImagePath


class RotatedAboutZAxisPath : TransformedPath {
    double dtheta; // in radians
    this(const Path other, double angle)
    {
	super(other);
	dtheta = angle; 
    }
    override RotatedAboutZAxisPath dup() const
    {
	return new RotatedAboutZAxisPath(this.original_path, this.dtheta);
    }
    override string toString() const
    {
	return "RotatedAboutZAxisPath(original_path=" ~ to!string(original_path) 
	    ~ ", angle=" ~ to!string(dtheta) ~ ")";
    }
    override string classString() const
    {
	return "RotatedAboutZAxisPath";
    }

protected:
    override Vector3 apply_transform(ref Vector3 p) const
    {
	return p.rotate_about_zaxis(dtheta);
    }
} // end class RotatedAboutZAxisPath


unittest {
    auto a = Vector3([2.0, 0.0, 0.0]);
    auto b = Vector3([0.0, 2.0, 0.0]);
    auto c = Vector3([0.0, 0.0, 0.0]);
    auto abc = new Arc(a, b, c);
    auto abc_rotated = new RotatedAboutZAxisPath(abc, PI/4);
    // writeln("abc_rotated(1.0)=", abc_rotated(1.0));
    assert(approxEqualVectors(abc_rotated(1.0), sqrt(2.0)*Vector3(-1, 1, 0)),
			      "RotatedAboutZAxisPath");
}