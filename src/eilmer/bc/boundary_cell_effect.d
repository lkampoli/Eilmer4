/**
 * Boundary cell effects are confined to the layer of
 * cells against a boundary.
 *
 * Authors: Rowan G. and Peter J.
 * Date: 2017-07-20
 */

import std.json;
import std.string;

import fvcore: FlowSolverException;
import fvcell;
import fvinterface;
import geom;
import grid;
import block;
import globaldata;
import json_helper;

BoundaryCellEffect make_BCE_from_json(JSONValue jsonData, int blk_id, int boundary)
{
    string bceType = jsonData["type"].str;
    BoundaryCellEffect newBCE;
    switch (bceType) {
    case "wall_function_cell_effect":
	newBCE = new BCE_WallFunction(blk_id, boundary);
	break;
    default:
	string errMsg = format("ERROR: The BoundarCellEffect type: '%s' is unknown.", bceType);
	throw new FlowSolverException(errMsg);
    }
    return newBCE;
}

class BoundaryCellEffect {
public:
    Block blk;
    int which_boundary;
    string type;

    this(int id, int boundary, string _type)
    {
	blk = gasBlocks[id];
	which_boundary = boundary;
	type = _type;
    }
    // Most boundary cell effects will not need to do anything
    // special after construction.
    // However, the user-defined ghost cells bc need some
    // extra work done to set-up the Lua_state after all
    // of the blocks and bcs have been constructed.
    void post_bc_construction() {}
    override string toString() const
    {
	return "BoundaryCellEffect()";
    }
    void apply(double t, int gtl, int ftl)
    {
	final switch (blk.grid_type) {
	case Grid_t.unstructured_grid: 
	    apply_unstructured_grid(t, gtl, ftl);
	    break;
	case Grid_t.structured_grid:
	    apply_structured_grid(t, gtl, ftl);
	}
    }
    abstract void apply_unstructured_grid(double t, int gtl, int ftl);
    abstract void apply_structured_grid(double t, int gtl, int ftl);
}

/**
 * The BCE_WallFunction object must be called AFTER the BIE_WallFunction object
 * because it relies on updated values for tke and omega supplied at the interface.
 *
 * In simcore.d, the application of boundary effects respects this ordering:
 * boundary interface actions are called first, then boundary cell actions.
 */

class BCE_WallFunction : BoundaryCellEffect {
public:
    this(int id, int boundary)
    {
	super(id, boundary, "WallFunction_CellEffect");
    }

    override string toString() const
    {
	return "WallFunction_CellEffect()";
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
	throw new FlowSolverException("WallFunction_CellEffect bc not implemented for unstructured grids.");
    } // end apply_unstructured_grid()

    override void apply_structured_grid(double t, int gtl, int ftl)
    {
	size_t i, j, k;
	FVCell cell;
	FVInterface iface;

	final switch (which_boundary) {
	case Face.north:
	    j = blk.jmax;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (i = blk.imin; i <= blk.imax; ++i) {
		    cell = blk.get_cell(i,j,k);
		    iface = cell.iface[Face.north];
		    cell.fs.tke = iface.fs.tke;
		    cell.fs.omega = iface.fs.omega;
		} // end i loop
	    } // for k
	    break;
	case Face.east:
	    i = blk.imax;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (j = blk.jmin; j <= blk.jmax; ++j) {
		    cell = blk.get_cell(i,j,k);
		    iface = cell.iface[Face.east];
		    cell.fs.tke = iface.fs.tke;
		    cell.fs.omega = iface.fs.omega;
		} // end j loop
	    } // for k
	    break;
	case Face.south:
	    j = blk.jmin;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (i = blk.imin; i <= blk.imax; ++i) {
		    cell = blk.get_cell(i,j,k);
		    iface = cell.iface[Face.south];
		    cell.fs.tke = iface.fs.tke;
		    cell.fs.omega = iface.fs.omega;
		} // end i loop
	    } // for k
	    break;
	case Face.west:
	    i = blk.imin;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (j = blk.jmin; j <= blk.jmax; ++j) {
		    cell = blk.get_cell(i,j,k);
		    iface = cell.iface[Face.west];
		    cell.fs.tke = iface.fs.tke;
		    cell.fs.omega = iface.fs.omega;
		} // end j loop
	    } // for k
	    break;
	case Face.top:
	    k = blk.kmax;
	    for (i = blk.imin; i <= blk.imax; ++i) {
		for (j = blk.jmin; j <= blk.jmax; ++j) {
		    cell = blk.get_cell(i,j,k);
		    iface = cell.iface[Face.top];
		    cell.fs.tke = iface.fs.tke;
		    cell.fs.omega = iface.fs.omega;
		} // end j loop
	    } // for i
	    break;
	case Face.bottom:
	    k = blk.kmin;
	    for (i = blk.imin; i <= blk.imax; ++i) {
		for (j = blk.jmin; j <= blk.jmax; ++j) {
		    cell = blk.get_cell(i,j,k);
		    iface = cell.iface[Face.bottom];
		    cell.fs.tke = iface.fs.tke;
		    cell.fs.omega = iface.fs.omega;
		} // end j loop
	    } // for i
	    break;
	} // end switch
    } // end apply_structured_grid()

} // end class BCE_WallFunction