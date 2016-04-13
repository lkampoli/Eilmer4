// user_defined_effects.d
//
// Authors: RG & PJ
// Date: 2015-03-14

import std.string;
import std.stdio;
import util.lua;
import util.lua_service;
import gas.luagas_model;

import geom;
import simcore;
import flowstate;
import fvcore;
import fvcell;
import fvinterface;
import globalconfig;
import globaldata;
import ghost_cell_effect;
import boundary_interface_effect;
import luaflowstate;
import lua_helper;
import bc;

class UserDefinedGhostCell : GhostCellEffect {
public:
    string luafname;
    this(int id, int boundary, string fname)
    {
	super(id, boundary, "UserDefined");
	luafname = fname;
	luaL_dofile(gasBlocks[id].myL, fname.toStringz);
    }
    override string toString() const
    {
	return "UserDefinedGhostCellEffect(fname=" ~ luafname ~ ")";
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
	size_t j = 0, k = 0;
	BasicCell ghost0, ghost1;
	BoundaryCondition bc = blk.bc[which_boundary];
	foreach (i, f; bc.faces) {
	    if (bc.outsigns[i] == 1) {
		ghost0 = f.right_cells[0];
		ghost1 = f.right_cells[1];
	    } else {
		ghost0 = f.left_cells[0];
		ghost1 = f.left_cells[1];
	    }
	    callGhostCellUDF(t, gtl, ftl, i, j, k, f, ghost0, ghost1);
	} // end foreach face
    }  // end apply_unstructured_grid()

    override void apply_structured_grid(double t, int gtl, int ftl)
    {
	size_t i, j, k;
	FVCell ghostCell0, ghostCell1;
	FVInterface IFace;

	final switch (which_boundary) {
	case Face.north:
	    j = blk.jmax;
	    for (k = blk.kmin; k <= blk.kmax; ++k)  {
		for (i = blk.imin; i <= blk.imax; ++i) {
		    // ghostCell0 is closest to domain
		    // ghostCell1 is one layer out.
		    ghostCell0 = blk.get_cell(i,j+1,k);
		    ghostCell1 = blk.get_cell(i,j+2,k);
		    IFace = ghostCell0.iface[Face.south];
		    callGhostCellUDF(t, gtl, ftl, i, j, k, IFace, ghostCell0, ghostCell1);
		} // end i loop
	    } // end k loop
	    break;
	case Face.east:
	    i = blk.imax;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (j = blk.jmin; j <= blk.jmax; ++j) {
		    ghostCell0 = blk.get_cell(i+1,j,k);
		    ghostCell1 = blk.get_cell(i+2,j,k);
		    IFace = ghostCell0.iface[Face.west];
		    callGhostCellUDF(t, gtl, ftl, i, j, k, IFace, ghostCell0, ghostCell1);
		} // end j loop
	    } // end k loop
	    break;
	case Face.south:
	    j = blk.jmin;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (i=blk.imin; i <= blk.imax; ++i) {
		    ghostCell0 = blk.get_cell(i,j-1,k);
		    ghostCell1 = blk.get_cell(i,j-2,k);
		    IFace = ghostCell0.iface[Face.north];
		    callGhostCellUDF(t, gtl, ftl, i, j, k, IFace, ghostCell0, ghostCell1);
		} // end i loop
	    } // end j loop
	    break;
	case Face.west:
	    i = blk.imin;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (j=blk.jmin; j <= blk.jmax; ++j) {
		    ghostCell0 = blk.get_cell(i-1,j,k);
		    ghostCell1 = blk.get_cell(i-2,j,k);
		    IFace = ghostCell0.iface[Face.east];
		    callGhostCellUDF(t, gtl, ftl, i, j, k, IFace, ghostCell0, ghostCell1);
		} // end j loop
	    } // end k loop
	    break;
	case Face.top:
	    k = blk.kmax;
	    for (i= blk.imin; i <= blk.imax; ++i) {
		for (j=blk.jmin; j <= blk.jmax; ++j) {
		    ghostCell0 = blk.get_cell(i,j,k+1);
		    ghostCell1 = blk.get_cell(i,j,k+2);
		    IFace = ghostCell0.iface[Face.bottom];
		    callGhostCellUDF(t, gtl, ftl, i, j, k, IFace, ghostCell0, ghostCell1);
		} // end j loop
	    } // end i loop
	    break;
	case Face.bottom:
	    k = blk.kmin;
	    for (i = blk.imin; i <= blk.imax; ++i) {
		for (j = blk.jmin; j <= blk.jmax; ++j) {
		    ghostCell0 = blk.get_cell(i,j,k-1);
		    ghostCell1 = blk.get_cell(i,j,k-2);
		    IFace = ghostCell0.iface[Face.top];
		    callGhostCellUDF(t, gtl, ftl, i, j, k, IFace, ghostCell0, ghostCell1);
		} // end j loop
	    } // end i loop
	    break;
	} // end switch which boundary
    }
			
private:
    void putFlowStateIntoGhostCell(lua_State* L, int tblIdx, BasicCell ghostCell)
    {
	auto gmodel = blk.myConfig.gmodel;
	try {
	    ghostCell.fs.gas.p = getDouble(L, tblIdx, "p");
	    getArrayOfDoubles(L, tblIdx, "T", ghostCell.fs.gas.T);
	    lua_getfield(L, tblIdx, "massf");
	    if ( lua_istable(L, -1) ) {
		int massfIdx = lua_gettop(L);
		getSpeciesValsFromTable(L, gmodel, massfIdx, ghostCell.fs.gas.massf, "massf");
	    }
	    else {
		if ( gmodel.n_species() == 1 ) {
		    ghostCell.fs.gas.massf[0] = 1.0;
		}
		else {
		    // There's no clear choice for multi-species.
		    // Maybe best to set everything to zero to 
		    // trigger some bad behaviour rather than
		    // one value to 1.0 and have the calculation
		    // proceed but not follow the users' intent.
		    ghostCell.fs.gas.massf[] = 0.0;
		}
	    }
	    lua_pop(L, 1);
	}
	catch (Exception e) {
	    string errMsg = "There was an error trying to read p, T or massf in user-supplied table.\n";
	    errMsg ~= "The error message from the lua state follows.\n";
	    errMsg ~= e.toString();
	    throw new Exception(errMsg);
	}
	gmodel.update_thermo_from_pT(ghostCell.fs.gas);
	gmodel.update_sound_speed(ghostCell.fs.gas);
	ghostCell.fs.vel.refx = getNumberFromTable(L, tblIdx, "velx", false, 0.0);
	ghostCell.fs.vel.refy = getNumberFromTable(L, tblIdx, "vely", false, 0.0);
	ghostCell.fs.vel.refz = getNumberFromTable(L, tblIdx, "velz", false, 0.0);
	ghostCell.fs.tke = getNumberFromTable(L, tblIdx, "tke", false, 0.0);
	ghostCell.fs.omega = getNumberFromTable(L, tblIdx, "omega", false, 0.0);
    }

    void callGhostCellUDF(double t, int gtl, int ftl, size_t i, size_t j, size_t k,
			  in FVInterface IFace, BasicCell ghostCell0, BasicCell ghostCell1)
    {
	// 1. Set up for calling function
	auto L = blk.myL;
	// 1a. Place function to call at TOS
	lua_getglobal(L, "ghostCell");
	// 1b. Then put arguments (as single table) at TOS
	lua_newtable(L);
	lua_pushnumber(L, t); lua_setfield(L, -2, "t");
	lua_pushnumber(L, dt_global); lua_setfield(L, -2, "dt");
	lua_pushinteger(L, step); lua_setfield(L, -2, "timeStep");
	lua_pushinteger(L, gtl); lua_setfield(L, -2, "gridTimeLevel");
	lua_pushinteger(L, ftl); lua_setfield(L, -2, "flowTimeLevel");
	lua_pushinteger(L, which_boundary); lua_setfield(L, -2, "boundaryId");
	// Geometric information for the face.
	lua_pushnumber(L, IFace.pos.x); lua_setfield(L, -2, "x");
	lua_pushnumber(L, IFace.pos.y); lua_setfield(L, -2, "y");
	lua_pushnumber(L, IFace.pos.z); lua_setfield(L, -2, "z");
	lua_pushnumber(L, IFace.n.x); lua_setfield(L, -2, "csX"); // unit-normal, cosine x-coordinate
	lua_pushnumber(L, IFace.n.y); lua_setfield(L, -2, "csY");
	lua_pushnumber(L, IFace.n.z); lua_setfield(L, -2, "csZ");
	lua_pushnumber(L, IFace.t1.x); lua_setfield(L, -2, "csX1");
	lua_pushnumber(L, IFace.t1.y); lua_setfield(L, -2, "csY1");
	lua_pushnumber(L, IFace.t1.z); lua_setfield(L, -2, "csZ1");
	lua_pushnumber(L, IFace.t2.x); lua_setfield(L, -2, "csX2");
	lua_pushnumber(L, IFace.t2.y); lua_setfield(L, -2, "csY2");
	lua_pushnumber(L, IFace.t2.z); lua_setfield(L, -2, "csZ2");
	// Structured-grid indices for the cell just inside the boundary.
	lua_pushinteger(L, i); lua_setfield(L, -2, "i");
	lua_pushinteger(L, j); lua_setfield(L, -2, "j");
	lua_pushinteger(L, k); lua_setfield(L, -2, "k");
	// Geometric information for the ghost cells (just outside the boundary).
	lua_pushnumber(L, ghostCell0.pos[0].x); lua_setfield(L, -2, "gc0x"); // ghostcell0 x-coordinate
	lua_pushnumber(L, ghostCell0.pos[0].y); lua_setfield(L, -2, "gc0y");
	lua_pushnumber(L, ghostCell0.pos[0].z); lua_setfield(L, -2, "gc0z");
	lua_pushnumber(L, ghostCell1.pos[0].x); lua_setfield(L, -2, "gc1x");
	lua_pushnumber(L, ghostCell1.pos[0].y); lua_setfield(L, -2, "gc1y");
	lua_pushnumber(L, ghostCell1.pos[0].z); lua_setfield(L, -2, "gc1z");

	// 2. Call LuaFunction and expect two tables of ghost cell flow state
	int number_args = 1;
	int number_results = 2; // expecting two table of ghostCells
	if ( lua_pcall(L, number_args, number_results, 0) != 0 ) {
	    luaL_error(L, "error running user-defined b.c. ghostCell function on boundaryId %d: %s\n",
		       which_boundary, lua_tostring(L, -1));
	}

	// 3. Grab Flowstate data from table and populate ghost cell
	// Stack positions:
	//    -2 :: ghostCell0
	//    -1 :: ghostCell1
	putFlowStateIntoGhostCell(L, -2, ghostCell0);
	putFlowStateIntoGhostCell(L, -1, ghostCell1);

	// 4. Clear stack
	lua_settop(L, 0);
    }
} // end class UserDefinedGhostCell


class BIE_UserDefined : BoundaryInterfaceEffect {
public:
    string luafname;
    this(int id, int boundary, string fname)
    {
	super(id, boundary, "UserDefined");
	luafname = fname;
	luaL_dofile(gasBlocks[id].myL, fname.toStringz);
    }

    override string toString() const
    {
	return "UserDefined(fname=" ~ luafname ~ ")";
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
	throw new Error("BIE_UserDefined.apply_unstructured_grid() not implemented yet");
    }

    override void apply_structured_grid(double t, int gtl, int ftl)
    {
	size_t i, j, k;
	FVCell cell;
	FVInterface IFace;

	final switch (which_boundary) {
	case Face.north:
	    j = blk.jmax;
	    for (k = blk.kmin; k <= blk.kmax; ++k)  {
		for (i = blk.imin; i <= blk.imax; ++i) {
		    cell = blk.get_cell(i,j,k);
		    IFace = cell.iface[Face.north];
		    callInterfaceUDF(t, gtl, ftl, i, j, k, IFace);
		} // end i loop
	    } // end k loop
	    break;
	case Face.east:
	    i = blk.imax;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (j = blk.jmin; j <= blk.jmax; ++j) {
		    cell = blk.get_cell(i,j,k);
		    IFace = cell.iface[Face.east];
		    callInterfaceUDF(t, gtl, ftl, i, j, k, IFace);
		} // end j loop
	    } // end k loop
	    break;
	case Face.south:
	    j = blk.jmin;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (i=blk.imin; i <= blk.imax; ++i) {
		    cell = blk.get_cell(i,j,k);
		    IFace = cell.iface[Face.south];
		    callInterfaceUDF(t, gtl, ftl, i, j, k, IFace);
		} // end i loop
	    } // end j loop
	    break;
	case Face.west:
	    i = blk.imin;
	    for (k = blk.kmin; k <= blk.kmax; ++k) {
		for (j=blk.jmin; j <= blk.jmax; ++j) {
		    cell = blk.get_cell(i,j,k);
		    IFace = cell.iface[Face.west];
		    callInterfaceUDF(t, gtl, ftl, i, j, k, IFace);
		} // end j loop
	    } // end k loop
	    break;
	case Face.top:
	    k = blk.kmax;
	    for (i= blk.imin; i <= blk.imax; ++i) {
		for (j=blk.jmin; j <= blk.jmax; ++j) {
		    cell = blk.get_cell(i,j,k);
		    IFace = cell.iface[Face.top];
		    callInterfaceUDF(t, gtl, ftl, i, j, k, IFace);
		} // end j loop
	    } // end i loop
	    break;
	case Face.bottom:
	    k = blk.kmin;
	    for (i = blk.imin; i <= blk.imax; ++i) {
		for (j = blk.jmin; j <= blk.jmax; ++j) {
		    cell = blk.get_cell(i,j,k);
		    IFace = cell.iface[Face.bottom];
		    callInterfaceUDF(t, gtl, ftl, i, j, k, IFace);
		} // end j loop
	    } // end i loop
	    break;
	} // end switch which boundary
    }
private:
    void putFlowStateIntoInterface(lua_State* L, int tblIdx, FVInterface iface)
    {
	// Now the user might only set some of the flowstate
	// since they might be relying on another boundary
	// effect to do some work.
	// So we need to test every possibility and only set
	// the non-nil values.
	auto gmodel = blk.myConfig.gmodel;
	FlowState fs = iface.fs;
	
	lua_getfield(L, tblIdx, "p");
	if ( !lua_isnil(L, -1) ) {
	    fs.gas.p = getDouble(L, tblIdx, "p");
	}
	lua_pop(L, 1);

	lua_getfield(L, tblIdx, "T");
	if ( !lua_isnil(L, -1) ) {
	    // Temperature should be provided as an array.
	    getArrayOfDoubles(L, tblIdx, "T", fs.gas.T);
	}
	lua_pop(L, 1);

	lua_getfield(L, tblIdx, "massf");
	if ( !lua_isnil(L, -1) ) {
	    int massfIdx = lua_gettop(L);
	    getSpeciesValsFromTable(L, gmodel, massfIdx, fs.gas.massf, "massf");
	}
	lua_pop(L, 1);

	lua_getfield(L, tblIdx, "velx");
	if ( !lua_isnil(L, -1) ) {
	    fs.vel.refx = getDouble(L, tblIdx, "velx");
	}
	lua_pop(L, 1);

	lua_getfield(L, tblIdx, "vely");
	if ( !lua_isnil(L, -1) ) {
	    fs.vel.refy = getDouble(L, tblIdx, "vely");
	}
	lua_pop(L, 1);

	lua_getfield(L, tblIdx, "velz");
	if ( !lua_isnil(L, -1) ) {
	    fs.vel.refz = getDouble(L, tblIdx, "velz");
	}
	lua_pop(L, 1);

	lua_getfield(L, tblIdx, "tke");
	if ( !lua_isnil(L, -1) ) {
	    fs.tke = getDouble(L, tblIdx, "tke");
	}
	lua_pop(L, 1);

	lua_getfield(L, tblIdx, "omega");
	if ( !lua_isnil(L, -1) ) {
	    fs.omega = getDouble(L, tblIdx, "omega");
	}
	lua_pop(L, 1);
    }
	    
    void callInterfaceUDF(double t, int gtl, int ftl, size_t i, size_t j, size_t k,
			  FVInterface IFace)
    {
	// 1. Set up for calling function
	auto L = blk.myL;
	// 1a. Place function to call at TOS
	lua_getglobal(L, "interface");
	// 1b. Then put arguments (as single table) at TOS
	lua_newtable(L);
	lua_pushnumber(L, t); lua_setfield(L, -2, "t");
	lua_pushnumber(L, dt_global); lua_setfield(L, -2, "dt");
	lua_pushinteger(L, step); lua_setfield(L, -2, "timeStep");
	lua_pushinteger(L, gtl); lua_setfield(L, -2, "gridTimeLevel");
	lua_pushinteger(L, ftl); lua_setfield(L, -2, "flowTimeLevel");
	lua_pushinteger(L, which_boundary); lua_setfield(L, -2, "boundaryId");
	lua_pushnumber(L, IFace.pos.x); lua_setfield(L, -2, "x");
	lua_pushnumber(L, IFace.pos.y); lua_setfield(L, -2, "y");
	lua_pushnumber(L, IFace.pos.z); lua_setfield(L, -2, "z");
	lua_pushnumber(L, IFace.n.x); lua_setfield(L, -2, "csX");
	lua_pushnumber(L, IFace.n.y); lua_setfield(L, -2, "csY");
	lua_pushnumber(L, IFace.n.z); lua_setfield(L, -2, "csZ");
	lua_pushnumber(L, IFace.t1.x); lua_setfield(L, -2, "csX1");
	lua_pushnumber(L, IFace.t1.y); lua_setfield(L, -2, "csY1");
	lua_pushnumber(L, IFace.t1.z); lua_setfield(L, -2, "csZ1");
	lua_pushnumber(L, IFace.t2.x); lua_setfield(L, -2, "csX2");
	lua_pushnumber(L, IFace.t2.y); lua_setfield(L, -2, "csY2");
	lua_pushnumber(L, IFace.t2.z); lua_setfield(L, -2, "csZ2");
	lua_pushinteger(L, i); lua_setfield(L, -2, "i");
	lua_pushinteger(L, j); lua_setfield(L, -2, "j");
	lua_pushinteger(L, k); lua_setfield(L, -2, "k");

	// 2. Call LuaFunction and expect a table of values for flow state
	int number_args = 1;
	int number_results = 1;
	if ( lua_pcall(L, number_args, number_results, 0) != 0 ) {
	    luaL_error(L, "error running user-defined b.c. interface function on boundaryId %d: %s\n",
		       which_boundary, lua_tostring(L, -1));
	}

	// 3. Grab Flowstate data from table and populate interface
	int tblIdx = lua_gettop(L);
	putFlowStateIntoInterface(L, tblIdx, IFace);

	// 4. Clear stack
	lua_settop(L, 0);
    }
} // end class UserDefinedGhostCell

