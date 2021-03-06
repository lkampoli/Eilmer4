/**
 * vector3.d  Vector primitives for our 3D world.
 *
 * Author: Peter J.
 * Version: 2014-06-16 first cut.
 *          2015-02-18 Attempt to reduce the number of redundant object copies
 *          by declaring some of the "in Vector3" parameters as "ref const(Vector3)".
 *          This has been somewhat successful, however, a few "in" parameters remain
 *          so that the vector arithmetic is a lot cleaner in the code.
 *          Effectively this hides the creation of Vector3 temporaries 
 *          that would otherwise have to appear explicitly in the code.
 *          2017-11-26 Repackage to make better use of the file system with smaller files.
 *          2018-05-29 Complex numbers accommodated.
 */
module geom.elements.vector3;

import std.conv;
import std.stdio;
import std.math;
import std.string;
import nm.complex;
import nm.number;

struct Vector3 {
    public number[3] _p;

    @nogc this(in number[] p)
    {
        switch ( p.length ) {
        case 0: _p[0] = _p[1] = _p[2] = 0.0; break;
        case 1: _p[0] = p[0]; _p[1] = _p[2] = 0.0; break;
        case 2: _p[0] = p[0]; _p[1] = p[1]; _p[2] = 0.0; break;
        default: _p[0] = p[0]; _p[1] = p[1]; _p[2] = p[2]; break;
        }
    }

    @nogc this(in number p0, in number p1=0.0, in number p2=to!number(0.0))
    {
        _p[0] = p0;
        _p[1] = p1;
        _p[2] = p2;
    }

    version(complex_numbers) {
        @nogc this(in double[] p)
            {
                switch ( p.length ) {
                case 0: _p[0] = _p[1] = _p[2] = 0.0; break;
                case 1: _p[0] = p[0]; _p[1] = _p[2] = 0.0; break;
                case 2: _p[0] = p[0]; _p[1] = p[1]; _p[2] = 0.0; break;
                default: _p[0] = p[0]; _p[1] = p[1]; _p[2] = p[2]; break;
                }
            }

        @nogc this(in double p0, in double p1=0.0, in double p2=0.0)
            {
                _p[0] = p0;
                _p[1] = p1;
                _p[2] = p2;
            }
    } // end version complex_numbers
    
    @nogc this(in Vector3 other)
    {
        _p[0] = other._p[0];
        _p[1] = other._p[1];
        _p[2] = other._p[2];
    }

    // Postblit constructor (Alexandrescu Section 7.1.3.4) so that
    // the copy of the struct can become completely independent of 
    // its source.
    this(this)
    {
        _p = _p.dup;
    }

    // For a lot of geometric work, it will be convenient to use
    // x,y,z notation.
    @nogc @property number x() const { return _p[0]; }
    @nogc @property number y() const { return _p[1]; }
    @nogc @property number z() const { return _p[2]; }
    // Note that the following three properties hand out references
    // to the elements, so that we may change their values.
    @nogc @property ref number refx() { return _p[0]; }
    @nogc @property ref number refy() { return _p[1]; }
    @nogc @property ref number refz() { return _p[2]; }

    @property Vector3 dup() const
    {
        return Vector3(this);
    }

    @nogc ref Vector3 set(ref const(Vector3) other)
    // Convenience function for setting the components of an existing object.
    {
        _p[0] = other._p[0]; _p[1] = other._p[1]; _p[2] = other._p[2];
        return this;
    }

    @nogc ref Vector3 set(Vector3* other)
    // Convenience function for setting the components of an existing object.
    {
        _p[0] = other._p[0]; _p[1] = other._p[1]; _p[2] = other._p[2];
        return this;
    }

    @nogc ref Vector3 set(number x, number y, number z=to!number(0.0))
    // Convenience function for setting the components of an existing object.
    // Note that we may supply just the x,y coordinates.
    {
        _p[0] = x; _p[1] = y; _p[2] = z;
        return this;
    }

    version(complex_numbers) {
        // We want to retain the flavour with double numbers.
        @nogc ref Vector3 set(double x, double y, double z=0.0)
        // Convenience function for setting the components of an existing object.
        // Note that we may supply just the x,y coordinates.
        {
            _p[0] = x; _p[1] = y; _p[2] = z;
            return this;
        }
    } // end version complex_numbers
    
    @nogc ref Vector3 clear()
    // Convenience function for setting-to-zero the components of an existing object.
    {
        _p[0] = 0.0; _p[1] = 0.0; _p[2] = 0.0;
        return this;
    }

    @nogc ref Vector3 add(ref const(Vector3) other)
    // Convenience function for adding the components of an existing object.
    // This avoids the temporary associated with += (below)
    {
        _p[0] += other._p[0]; _p[1] += other._p[1]; _p[2] += other._p[2];
        return this;
    }

    @nogc ref Vector3 add(Vector3* other)
    // Convenience function for adding the components of an existing object.
    // This avoids the temporary associated with += (below)
    {
        _p[0] += other._p[0]; _p[1] += other._p[1]; _p[2] += other._p[2];
        return this;
    }

    @nogc ref Vector3 add(ref const(Vector3) other, number factor)
    // Convenience function for adding the components of an existing object, scaled.
    // This avoids the temporary associated with += (below)
    {
        _p[0] += other._p[0]*factor; _p[1] += other._p[1]*factor; _p[2] += other._p[2]*factor;
        return this;
    }

    @nogc ref Vector3 add(Vector3* other, number factor)
    // Convenience function for adding the components of an existing object, scaled.
    // This avoids the temporary associated with += (below)
    {
        _p[0] += other._p[0]*factor; _p[1] += other._p[1]*factor; _p[2] += other._p[2]*factor;
        return this;
    }

    @nogc ref Vector3 scale(number factor)
    // Convenience function for scaling the components of an existing object.
    // This avoids the temporary associated with *= (below)
    {
        _p[0] *= factor; _p[1] *= factor; _p[2] *= factor;
        return this;
    }
    
    version(complex_numbers) {
        // We want to retain the flavour with double numbers.

        @nogc ref Vector3 add(ref const(Vector3) other, double factor)
        // Convenience function for adding the components of an existing object, scaled.
        // This avoids the temporary associated with += (below)
        {
            _p[0] += other._p[0]*factor; _p[1] += other._p[1]*factor; _p[2] += other._p[2]*factor;
            return this;
        }

        @nogc ref Vector3 add(Vector3* other, double factor)
        // Convenience function for adding the components of an existing object, scaled.
        // This avoids the temporary associated with += (below)
        {
            _p[0] += other._p[0]*factor; _p[1] += other._p[1]*factor; _p[2] += other._p[2]*factor;
            return this;
        }

        @nogc ref Vector3 scale(double factor)
        // Convenience function for scaling the components of an existing object.
        // This avoids the temporary associated with *= (below)
        {
            _p[0] *= factor; _p[1] *= factor; _p[2] *= factor;
            return this;
        }
    } // end version complex_numbers
    
    string toString() const
    {
        return "Vector3(" ~ to!string(_p) ~ ")";
    }

    // Some operators, at least those that make sense.
    Vector3 opUnary(string op)()
        if (op == "+")
    {
        Vector3 result;
        result._p[0] = this._p[0]; result._p[1] = this._p[1]; result._p[2] = this._p[2];
        return result;
    }

    Vector3 opUnary(string op)()
        if (op == "-")
    {
        Vector3 result;
        result._p[0] = -(this._p[0]); result._p[1] = -(this._p[1]); result._p[2] = -(this._p[2]);
        return result;
    }

    Vector3 opBinary(string op)(in Vector3 rhs) const
        if (op == "+")
    {
        Vector3 result;
        result._p[0] = this._p[0] + rhs._p[0];
        result._p[1] = this._p[1] + rhs._p[1];
        result._p[2] = this._p[2] + rhs._p[2];
        return result;
    }

    Vector3 opBinary(string op)(in Vector3 rhs) const
        if (op == "-")
    {
        Vector3 result;
        result._p[0] = this._p[0] - rhs._p[0];
        result._p[1] = this._p[1] - rhs._p[1];
        result._p[2] = this._p[2] - rhs._p[2];
        return result;
    }

    Vector3 opBinary(string op)(in number rhs) const
        if (op == "*")
    {
        Vector3 result;
        result._p[0] = this._p[0] * rhs;
        result._p[1] = this._p[1] * rhs;
        result._p[2] = this._p[2] * rhs;
        return result;
    }

    version(complex_numbers) {
        // Retain the double version.
        Vector3 opBinary(string op)(in double rhs) const
            if (op == "*")
        {
            Vector3 result;
            result._p[0] = this._p[0] * rhs;
            result._p[1] = this._p[1] * rhs;
            result._p[2] = this._p[2] * rhs;
            return result;
        }
    } // end version complex_numbers

    Vector3 opBinaryRight(string op)(in number lhs) const
        if (op == "*")
    {
        Vector3 result;
        result._p[0] = this._p[0] * lhs;
        result._p[1] = this._p[1] * lhs;
        result._p[2] = this._p[2] * lhs;
        return result;
    }

    version(complex_numbers) {
        // Retain the double version.
        Vector3 opBinaryRight(string op)(in double lhs) const
            if (op == "*")
        {
            Vector3 result;
            result._p[0] = this._p[0] * lhs;
            result._p[1] = this._p[1] * lhs;
            result._p[2] = this._p[2] * lhs;
            return result;
        }
    } // end version complex_numbers
    
    Vector3 opBinary(string op)(in number rhs) const
        if (op == "/")
    {
        Vector3 result;
        result._p[0] = this._p[0] / rhs;
        result._p[1] = this._p[1] / rhs;
        result._p[2] = this._p[2] / rhs;
        return result;
    }

    version(complex_numbers) {
        // Retain the double version.
        Vector3 opBinary(string op)(in double rhs) const
            if (op == "/")
        {
            Vector3 result;
            result._p[0] = this._p[0] / rhs;
            result._p[1] = this._p[1] / rhs;
            result._p[2] = this._p[2] / rhs;
            return result;
        }
    } // end version complex_numbers

    // Assignment operators. (Alexandrescu Section 7.1.5.1)
    @nogc void opAssign(ref Vector3 rhs)
    {
        _p[0] = rhs._p[0]; _p[1] = rhs._p[1]; _p[2] = rhs._p[2];
    }

    @nogc void opAssign(Vector3 rhs)
    {
        _p[0] = rhs._p[0]; _p[1] = rhs._p[1]; _p[2] = rhs._p[2];
    }

    // Combined assignment operators do change the original object.
    @nogc void opOpAssign(string op)(in Vector3 rhs)
        if (op == "+")
    {
        _p[0] += rhs._p[0]; _p[1] += rhs._p[1]; _p[2] += rhs._p[2];
    }

    @nogc void opOpAssign(string op)(in Vector3 rhs)
        if (op == "-")
    {
        _p[0] -= rhs._p[0]; _p[1] -= rhs._p[1]; _p[2] -= rhs._p[2];
    }

    // 2018-08-28 PJ found that to call from within @nogc functions,
    // we had to use ref const(Vector3) rather than in Vector3
    // as the type of the parameter rhs.
    // So, we now have two sets of these combined-operator assignments
    // but the compiler seems to be able to pick the one it needs.
    @nogc void opOpAssign(string op)(ref const(Vector3) rhs)
        if (op == "+")
    {
        _p[0] += rhs._p[0]; _p[1] += rhs._p[1]; _p[2] += rhs._p[2];
    }

    @nogc void opOpAssign(string op)(ref const(Vector3) rhs)
        if (op == "-")
    {
        _p[0] -= rhs._p[0]; _p[1] -= rhs._p[1]; _p[2] -= rhs._p[2];
    }

    @nogc void opOpAssign(string op)(in number rhs)
        if (op == "*")
    {
        _p[0] *= rhs; _p[1] *= rhs; _p[2] *= rhs;
    }

    @nogc void opOpAssign(string op)(in number rhs)
        if (op == "/")
    {
        _p[0] /= rhs; _p[1] /= rhs; _p[2] /= rhs;
    }

    version(complex_numbers) {
        // Retain the double version.
        @nogc void opOpAssign(string op)(in double rhs)
            if (op == "*")
        {
            _p[0] *= rhs; _p[1] *= rhs; _p[2] *= rhs;
        }

        @nogc void opOpAssign(string op)(in double rhs)
            if (op == "/")
        {
            _p[0] /= rhs; _p[1] /= rhs; _p[2] /= rhs;
        }
    } // end version complex_numbers

    // Other vector-specific operations.

    /**
     * Scales the vector to unit magnitude.
     */
    @nogc void normalize()
    {
        number magnitude = sqrt(this.dot(this));
        if (magnitude > 0.0) {
            // need to do the divide on the _p[] array for DMD 2.069.0
            this._p[0] /= magnitude; this._p[1] /= magnitude; this._p[2] /= magnitude;
        } else {
            // Clean up, in case dot() underflows.
            this._p[0] = this._p[1] = this._p[2] = 0.0;
        }
        // Flush small components to zero.
        const double small = 1.0e-30;
        version(complex_numbers) {
            if (fabs(this._p[0].re) < small && fabs(this._p[0].im) < small) { this._p[0] = 0.0; }
            if (fabs(this._p[1].re) < small && fabs(this._p[1].im) < small) { this._p[1] = 0.0; }
            if (fabs(this._p[2].re) < small && fabs(this._p[2].im) < small) { this._p[2] = 0.0; }
        } else {
            if (fabs(this._p[0]) < small) { this._p[0] = 0.0; }
            if (fabs(this._p[1]) < small) { this._p[1] = 0.0; }
            if (fabs(this._p[2]) < small) { this._p[2] = 0.0; }
        }
    }

    @nogc number dot(ref const(Vector3) other) const
    {
        return this._p[0] * other._p[0] + 
            this._p[1] * other._p[1] +
            this._p[2] * other._p[2];
    }

    // Transform functions used to reorient vector values in the CFD codes.

    /**
     * Rotate v from the global xyz coordinate system into the local frame
     * defined by the orthogonal unit vectors n,t1,t2.
     *
     * We assume, without checking, that these vectors do nicely define 
     * such a local system.
     */
    @nogc void transform_to_local_frame(ref const(Vector3) n,
                                        ref const(Vector3) t1,
                                        ref const(Vector3) t2)
    {
        number v_x = this.dot(n); // normal component
        number v_y = this.dot(t1); // tangential component 1
        number v_z = this.dot(t2); // tangential component 2
        _p[0] = v_x;
        _p[1] = v_y;
        _p[2] = v_z;
    }

    /**
     * Rotate v back into the global (xyz) coordinate system.
     */
    @nogc void transform_to_global_frame(ref const(Vector3) n,
                                         ref const(Vector3) t1,
                                         ref const(Vector3) t2)
    {
        number v_x = _p[0]*n._p[0] + _p[1]*t1._p[0] + _p[2]*t2._p[0]; // global-x
        number v_y = _p[0]*n._p[1] + _p[1]*t1._p[1] + _p[2]*t2._p[1]; // global-y
        number v_z = _p[0]*n._p[2] + _p[1]*t1._p[2] + _p[2]*t2._p[2]; // global-z
        _p[0] = v_x;
        _p[1] = v_y;
        _p[2] = v_z;
    }
    // Change of coordinate system; rotation with translation.

    // Transform coordinates from global frame to local (dash) frame.
    // Local frame is defined by unit vectors (n, t1 and t2) at location c.
    @nogc void transform_to_local_frame(ref const(Vector3) n,
                                        ref const(Vector3) t1,
                                        ref const(Vector3) t2,
                                        ref const(Vector3) c)
    {
        _p[0] -= c._p[0]; _p[1] -= c._p[1]; _p[2] -= c._p[2]; // shift to local origin
        number v_x = this.dot(n); // normal component
        number v_y = this.dot(t1); // tangential component 1
        number v_z = this.dot(t2); // tangential component 2
        _p[0] = v_x;
        _p[1] = v_y;
        _p[2] = v_z;
    }

    /**
     * Rotate v back into the global (xyz) coordinate system.
     */
    @nogc void transform_to_global_frame(ref const(Vector3) n,
                                         ref const(Vector3) t1,
                                         ref const(Vector3) t2,
                                         ref const(Vector3) c)
    {
        number v_x = _p[0]*n._p[0] + _p[1]*t1._p[0] + _p[2]*t2._p[0] + c._p[0]; // global-x
        number v_y = _p[0]*n._p[1] + _p[1]*t1._p[1] + _p[2]*t2._p[1] + c._p[1]; // global-y
        number v_z = _p[0]*n._p[2] + _p[1]*t1._p[2] + _p[2]*t2._p[2] + c._p[2]; // global-z
        _p[0] = v_x;
        _p[1] = v_y;
        _p[2] = v_z;
    }

    /**
     * General matrix transformation (used when rotating flowstate vectors).
     */
    @nogc void apply_matrix_transform(ref const(number[]) Rmatrix)
    {
        // Write out the matrix multiplication, long-hand.
        number old_p0 = _p[0];
        number old_p1 = _p[1];
        number old_p2 = _p[2];
        _p[0] = Rmatrix[0]*old_p0 + Rmatrix[1]*old_p1 + Rmatrix[2]*old_p2;
        _p[1] = Rmatrix[3]*old_p0 + Rmatrix[4]*old_p1 + Rmatrix[5]*old_p2;
        _p[2] = Rmatrix[6]*old_p0 + Rmatrix[7]*old_p1 + Rmatrix[8]*old_p2;
    }
    version(complex_numbers) {
        // Retain the flavour with double numbers in the matrix.
        @nogc void apply_matrix_transform(ref const(double[]) Rmatrix)
        {
            // Write out the matrix multiplication, long-hand.
            number old_p0 = _p[0];
            number old_p1 = _p[1];
            number old_p2 = _p[2];
            _p[0] = Rmatrix[0]*old_p0 + Rmatrix[1]*old_p1 + Rmatrix[2]*old_p2;
            _p[1] = Rmatrix[3]*old_p0 + Rmatrix[4]*old_p1 + Rmatrix[5]*old_p2;
            _p[2] = Rmatrix[6]*old_p0 + Rmatrix[7]*old_p1 + Rmatrix[8]*old_p2;
        }
    }

    /**
     * Compute mirror-image location for plane defined by point and normal.
     */
    @nogc ref Vector3 mirror_image(ref const(Vector3) point,
                                   ref const(Vector3) normal)
    {
        Vector3 n = Vector3(normal.x, normal.y, normal.z); n.normalize();
        // Construct tangents to the plane.
        Vector3 different = n + Vector3(1.0, 1.0, 1.0);
        Vector3 t1; cross(t1, n, different); t1.normalize();
        Vector3 t2; cross(t2, n, t1); t2.normalize();
        // Mirror image the vector in a frame local to the plane.
        transform_to_local_frame(n, t1, t2, point);
        _p[0] = -_p[0];
        transform_to_global_frame(n, t1, t2, point);
        return this;
    }

    /**
     * Rotate point about the z-axis by angle dtheta, in radians.
     */
    @nogc ref Vector3 rotate_about_zaxis(double dtheta)
    {
        number x = _p[0];
        number y = _p[1];
        double theta = atan2(y.re,x.re) + dtheta;
        double r = sqrt(x.re*x.re + y.re*y.re);
        _p[0] = r * cos(theta);
        _p[1] = r * sin(theta);
        return this;
    }

    /**
     * Alternative implementation for rotation in (x,y)-plane.
     */
    @nogc ref Vector3 rotate2d(double dtheta)
    {
        number x = _p[0];
        number y = _p[1];
        double sn = sin(dtheta);
        double cs = cos(dtheta);
        _p[0] = x*cs - y*sn;
        _p[1] = y*cs + x*sn;
        return this;
    }
} // end class Vector3

/**
 * Returns the distance between two points.
 */
@nogc
double distance_between(ref const(Vector3) v1, ref const(Vector3) v2)
{
    number d = sqrt((v1.x-v2.x)^^2 + (v1.y-v2.y)^^2 + (v1.z-v2.z)^^2);
    return d.re;
}

/**
 * Returns the scalar dot product of two vectors.
 */
@nogc
number dot(ref const(Vector3) v1, ref const(Vector3) v2)
{
    number result = 0.0;
    // Maybe we should be careful with underflow and overflow...
    result = v1._p[0]*v2._p[0] + v1._p[1]*v2._p[1] + v1._p[2]*v2._p[2];
    return result;
}

/**
 * Returns magnitude of the vector.
 */
@nogc
number abs(ref const(Vector3) v)
{
    return sqrt(v.dot(v));
}

/**
 * Returns a unit vector in the same direction as v.
 */
Vector3 unit(ref const(Vector3) v)
{
    Vector3 v2 = Vector3(v);
    v2.normalize();
    return v2;
}

/**
 * Vector cross product for use in a single statement that will not make temporaries.
 */
@nogc
void cross(ref Vector3 v3, ref const(Vector3) v1, ref const(Vector3) v2)
{
    v3._p[0] = v1._p[1] * v2._p[2] - v2._p[1] * v1._p[2];
    v3._p[1] = v2._p[0] * v1._p[2] - v1._p[0] * v2._p[2];
    v3._p[2] = v1._p[0] * v2._p[1] - v2._p[0] * v1._p[1];
}

/**
 * Vector cross product for use in Vector3 expressions.
 * We need to keep the "in" qualifiers.
 */
@nogc
Vector3 cross(in Vector3 v1, in Vector3 v2)
{
    Vector3 v3;
    cross(v3, v1, v2);
    return v3;
}

/**
 * Component forms
 */

@nogc
number dot_product(number ax, number ay, number az, number bx, number by, number bz)
{
    return ax*bx + ay*by + az*bz;
}

@nogc
void cross_product(number ax, number ay, number az, number bx, number by, number bz,
                   ref number cx, ref number cy, ref number cz)
{
    cx = ay*bz - az*by;
    cy = az*bx - ax*bz;
    cz = ax*by - ay*bx;
    return;
}

/**
 * Returns true if all of the components of two vectors are approximately equal.
 */
@nogc
bool approxEqualVectors(in Vector3 v1, in Vector3 v2,
                        double maxRelDiff=1.0e-2, double maxAbsDiff=1.0e-5)
{
    return (approxEqualNumbers(v1._p[0], v2._p[0], maxRelDiff, maxAbsDiff) && 
            approxEqualNumbers(v1._p[1], v2._p[1], maxRelDiff, maxAbsDiff) &&
            approxEqualNumbers(v1._p[2], v2._p[2], maxRelDiff, maxAbsDiff));
}

version(vector3_test) {
    import util.msg_service;
    int main() {
        // Check that we have separate data with the correct values.
        Vector3 a = Vector3([1.0, 2.2, 3.0]);
        Vector3 b = Vector3(1.0);
        assert(a.x == 1.0, failedUnitTest());
        assert(a.y == 2.2, failedUnitTest());
        assert(a.z == 3.0, failedUnitTest());
        assert(a.x == b.x, failedUnitTest());
        assert(b.y == 0.0, failedUnitTest());
        assert(b.z == 0.0, failedUnitTest());
        b.set(a);
        assert(a.x == b.x && a.y == b.y && a.z == b.z, failedUnitTest());
        b.set(1.0, 0.0, 0.0);
        assert(b.x == 1.0 && b.y == 0.0 && b.z == 0.0, failedUnitTest());

        // Check operators
        b = -a;
        assert(b.x == -a.x && b.y == -a.y && b.z == -a.z, failedUnitTest());

        b = Vector3(1.0);
        Vector3 c = a + b;
        assert(c.y == a.y+b.y, failedUnitTest());
        c = a - b;
        assert(c.y == a.y-b.y, failedUnitTest());
        Vector3 d = a.dup;
        a.refy = 99.0;
        assert(a.y == 99.0 && d.y == 2.2, failedUnitTest());
        Vector3 d2 = a;
        a.refy = 3.3;
        assert(a.y == 3.3 && d2.y == 99.0, failedUnitTest());

        Vector3 e = a * 2.0;
        Vector3 f = 3.0 * d;
        assert(e.z == 6.0 && f.z == 9.0, failedUnitTest());
        Vector3 g = d / 3.0;
        assert(g.z == 1.0, failedUnitTest());

        g += f;
        assert(g.z == 10.0, failedUnitTest());
        g /= 2.0;
        assert(g.z == 5.0, failedUnitTest());

        a = Vector3(1.0, 0.0, 0.0);
        a.rotate_about_zaxis(PI/4);
        assert(approxEqualVectors(a, Vector3(0.7071, 0.7071, 0)), failedUnitTest());

        a = Vector3(1.0, 0.0, 0.0);
        Vector3 point = Vector3(0.0, 1.0, 0.0);
        Vector3 normal = Vector3(0.0, 1.0, 0.0);
        a.mirror_image(point, normal);
        assert(approxEqualVectors(a, Vector3(1.0, 2.0, 0)), failedUnitTest());

        Vector3 u = unit(g);
        assert(approxEqualNumbers(abs(u), to!number(1.0)), failedUnitTest());

        Vector3 x = Vector3(1.0, 0.0, 0.0);
        Vector3 y = Vector3(0.0, 1.0, 0.0);
        Vector3 z = cross(x,y);
        Vector3 zref = Vector3(0.0,0.0,1.0);
        assert(approxEqualVectors(z, zref), failedUnitTest());

        Vector3 n = Vector3(1.0,1.0,0.0); n = unit(n);
        Vector3 t1 = Vector3(-1.0,1.0,0.0); t1 = unit(t1);
        Vector3 t2 = cross(n, t1);
        Vector3 h = Vector3(1.0,0.0,1.0);
        Vector3 h_ref = Vector3(h);
        h.transform_to_local_frame(n, t1, t2);
        assert(approxEqualVectors(h, Vector3(sqrt(1.0/2.0), -sqrt(1.0/2.0), 1.0)),
               failedUnitTest());
        h.transform_to_global_frame(n, t1, t2);
        assert(approxEqualVectors(h, h_ref), failedUnitTest());

        Vector3 a45 = Vector3(cos(to!number(PI)/4),sin(to!number(PI)/4));
        Vector3 a60 = Vector3(cos(to!number(PI)/3),sin(to!number(PI)/3));
        assert(approxEqualVectors(a45.rotate2d(15.0*PI/180), a60), failedUnitTest());
        Vector3 a30 = Vector3(cos(to!number(PI)/6),sin(to!number(PI)/6));
        assert(approxEqualVectors(a30.rotate2d(30.0*PI/180), a60), failedUnitTest());
               
        return 0;
    }
} // end vector3_test
