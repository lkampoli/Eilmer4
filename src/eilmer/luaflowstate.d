/**
 * luaflowstate.d 
 * Lua interface to the FlowState class for users of the prep program.
 *
 * Authors: Rowan G. and Peter J.
 * Version: Initial cut.
 */

module luaflowstate;

import std.algorithm;
import std.array;
import std.format;
import std.stdio;
import std.string;
import std.conv;
import std.traits;
import gzip;
import util.lua;
import util.lua_service;
import gas;
import gas.luagas_model;
import flowstate;
import geom;
import luageom;
import sgrid;
import luasgrid;
import usgrid;
import luausgrid;
import globalconfig;
import luaglobalconfig;
import fvcell;

/// name for FlowState object in Lua scripts.
immutable string FlowStateMT = "FlowState"; 

static const(FlowState)[] flowStateStore;

// Makes it a little more consistent to make this
// available under this name.
FlowState checkFlowState(lua_State* L, int index)
{
    return checkObj!(FlowState, FlowStateMT)(L, index);
}

/** 
 * This function implements our constructor for the Lua interface.
 *
 * Construction of a FlowState object from in Lua will accept:
 * -----------------
 * fs = FlowState:new{p=1.0e5, T=300.0, velx=1000.0, vely=200.0, massf={spName=1.0}}
 * fs = FlowState:new{p=1.0e7, T={300.0}}
 * fs = FlowState:new()
 * fs = FlowState:new{}
 * -----------------
 * Missing velocity components are set to 0.0.
 * Missing mass fraction list is set to {1.0}.
 * For one-temperature gas models, single value for T is OK.
 * Temperature will always be accepted as an array.
 * For all other missing components, the values
 * are the defaults as given by the first constructor
 * in flowstate.d
 * The empty constructors forward through to PJ's
 * constructor that accepts a GasModel argument only.
 */
extern(C) int newFlowState(lua_State* L)
{
    auto managedGasModel = GlobalConfig.gmodel_master;
    if ( managedGasModel is null ) {
	string errMsg = `Error in call to FlowState:new.
It appears that you have not yet set the GasModel.
Be sure to call setGasModel(fname) before using a FlowState object.`;
	luaL_error(L, errMsg.toStringz);
    }

    lua_remove(L, 1); // Remove first argument "this".
    FlowState fs;

    int narg = lua_gettop(L);
    if ( narg == 0 ) {
	fs = new FlowState(managedGasModel);
	flowStateStore ~= pushObj!(FlowState, FlowStateMT)(L, fs);
	return 1;
    }
    // else narg >= 1
    if ( !lua_istable(L, 1) ) {
	string errMsg = "Error in call to FlowState:new. A table is expected as first argument.";
	luaL_error(L, errMsg.toStringz);
    }
    // At this point we have a table at idx=1. Let's check that all
    // fields in the table are valid.
    string[] validFields = ["p", "T", "p_e", "quality", "massf",
			    "velx", "vely", "velz",
			    "Bx", "By", "Bz",
			    "tke", "omega", "mu_t", "k_t"];
    bool allFieldsAreValid = true;
    string errMsg;
    lua_pushnil(L);
    while ( lua_next(L, 1) != 0 ) {
	string key = to!string(lua_tostring(L, -2));
	if ( find(validFields, key).empty ) {
	    allFieldsAreValid = false;
	    errMsg ~= format("ERROR: '%s' is not a valid input in FlowState:new{}\n", key);
	}
	lua_pop(L, 1);
    }
    if ( !allFieldsAreValid ) {
	luaL_error(L, errMsg.toStringz);
    }
    // Now we are committed to using the first constructor
    // in class FlowState. So we have to find at least
    // a pressure and temperature(s).
    errMsg = `Error in call to FlowState:new.
A valid pressure value 'p' is not found in arguments.
The value should be a number.`;
    double p = getNumberFromTable(L, 1, "p", true, double.init, true, errMsg);

    // Next test for T and if it's a single value or array.
    double[] T;
    lua_getfield(L, 1, "T");
    if ( lua_isnumber(L, -1 ) ) {
	double Tval = lua_tonumber(L, -1);
	foreach ( i; 0..managedGasModel.n_modes ) T ~= Tval;
    }
    else if ( lua_istable(L, -1 ) ) {
	getArrayOfDoubles(L, 1, "T", T);
	if ( T.length != managedGasModel.n_modes ) {
	    errMsg = "Error in call to FlowState:new.";
	    errMsg ~= "Length of T vector does not match number of modes in gas model.";
	    errMsg ~= format("T.length= %d; n_modes= %d\n", T.length, managedGasModel.n_modes);
	    throw new LuaInputException(errMsg);
	}
    }
    else  {
	errMsg = "Error in call to FlowState:new.";
	errMsg ~= "A valid temperature value 'T' is not found in arguments.";
	errMsg ~= "It should be listed as a single value, or list of values.";
	throw new LuaInputException(errMsg);
    }
    lua_pop(L, 1);
    // Now everything else is optional. If it has been set, then we will 
    // ensure that it can be retrieved correctly, or signal the user.
    // Values related to velocity.
    double velx = 0.0;
    double vely = 0.0;
    double velz = 0.0;
    string errMsgTmplt = "Error in call to FlowState:new.\n";
    errMsgTmplt ~= "A valid value for '%s' is not found in arguments.\n";
    errMsgTmplt ~= "The value, if present, should be a number.";
    velx = getNumberFromTable(L, 1, "velx", false, 0.0, true, format(errMsgTmplt, "velx"));
    vely = getNumberFromTable(L, 1, "vely", false, 0.0, true, format(errMsgTmplt, "vely"));
    velz = getNumberFromTable(L, 1, "velz", false, 0.0, true, format(errMsgTmplt, "velz"));
    auto vel = Vector3(velx, vely, velz);

    // Values related to mass fractions.
    double[] massf;
    lua_getfield(L, 1, "massf");
    if ( lua_isnil(L, -1) ) {
	massf ~= 1.0; // Nothing set, so massf = [1.0]
    }
    else if ( lua_istable(L, -1) ) {
	int massfIdx = lua_gettop(L);
	getSpeciesValsFromTable(L, managedGasModel, massfIdx, massf, "massf");
    }
    else  {
	errMsg = "Error in call to FlowState:new.";
	errMsg ~= "A field for mass fractions was found, but the contents are not valid.";
	errMsg ~= "The mass fraction should be given as a table of key-value pairs { speciesName=val }.";
	throw new LuaInputException(errMsg);
    }
    lua_pop(L, 1);

    // Value for quality
    double quality = getNumberFromTable(L, 1, "quality", false, 1.0, true, format(errMsgTmplt, "quality"));
    
    // Values for B (magnetic field)
    double Bx = 0.0;
    double By = 0.0;
    double Bz = 0.0;
    Bx = getNumberFromTable(L, 1, "Bx", false, 0.0, true, format(errMsgTmplt, "Bx"));
    By = getNumberFromTable(L, 1, "By", false, 0.0, true, format(errMsgTmplt, "By"));
    Bz = getNumberFromTable(L, 1, "Bz", false, 0.0, true, format(errMsgTmplt, "Bz"));
    auto B = Vector3(Bx, By, Bz);
    
    // Values related to k-omega model.
    double tke = getNumberFromTable(L, 1, "tke", false, 0.0, true, format(errMsgTmplt, "tke"));
    double omega = getNumberFromTable(L, 1, "omega", false, 0.0, true, format(errMsgTmplt, "omega"));
    double mu_t = getNumberFromTable(L, 1, "mu_t", false, 0.0, true, format(errMsgTmplt, "mu_t"));
    double k_t = getNumberFromTable(L, 1, "k_t", false, 0.0, true, format(errMsgTmplt, "k_t"));

    // We won't let user set 'S' -- shock detector value.
    int S = 0;

    fs = new FlowState(managedGasModel, p, T, vel, massf, quality, B,
		       tke, omega, mu_t, k_t);
    flowStateStore ~= pushObj!(FlowState, FlowStateMT)(L, fs);
    return 1;
}

/**
 * Provide a peek into the FlowState data as a Lua table.
 *
 * Basically, this gives the user a table to look at the values
 * in a FlowState in a read-only manner. (Well, in truth, the
 * table values can be changed, but they won't be reflected
 * in the FlowState object. This is consistent with the methods
 * of the FlowState object. Presently, there is no automatic
 * update if one fiddles with the gas properties in FlowState
 * object.
 */

string pushGasVar(string var)
{
    return `lua_pushnumber(L, fs.gas.` ~ var ~ `);
lua_setfield(L, tblIdx, "` ~ var ~`");`;
}

string pushGasVarArray(string var)
{
    return `lua_newtable(L);
foreach ( i, val; fs.gas.` ~ var ~ `) {
    lua_pushnumber(L, val); lua_rawseti(L, -2,to!int(i+1));
}
lua_setfield(L, tblIdx, "` ~ var ~`");`;
}

string pushFSVar(string var)
{
return `lua_pushnumber(L, fs.` ~ var ~ `);
lua_setfield(L, tblIdx, "` ~ var ~`");`;
}

string pushFSVecVar(string var)
{
return `lua_pushnumber(L, fs.`~var~`.x);
lua_setfield(L, tblIdx, "`~var~`x");
lua_pushnumber(L, fs.`~var~`.y);
lua_setfield(L, tblIdx, "`~var~`y");
lua_pushnumber(L, fs.`~var~`.z);
lua_setfield(L, tblIdx, "`~var~`z");`;
}

/**
 * Push FlowState values to a table at TOS in lua_State.
 */
void pushFlowStateToTable(lua_State* L, int tblIdx, in FlowState fs)
{
    auto managedGasModel = GlobalConfig.gmodel_master;
    mixin(pushGasVar("p"));
    mixin(pushGasVarArray("T"));
    mixin(pushGasVarArray("e"));
    mixin(pushGasVar("quality"));
    // -- massf as key-val table
    lua_newtable(L);
    foreach ( int isp, mf; fs.gas.massf ) {
	lua_pushnumber(L, mf);
	lua_setfield(L, -2, toStringz(managedGasModel.species_name(isp)));
    }
    lua_setfield(L, tblIdx, "massf");
    // -- done setting massf
    mixin(pushGasVar("a"));
    mixin(pushGasVar("rho"));
    mixin(pushGasVar("mu"));
    mixin(pushGasVarArray("k"));
    mixin(pushFSVar("tke"));
    mixin(pushFSVar("omega"));
    mixin(pushFSVar("mu_t"));
    mixin(pushFSVar("k_t"));
    mixin(pushFSVecVar("vel"));
    mixin(pushFSVecVar("B"));
}

/**
 * Gives the caller a table populated with FlowState values.
 *
 * Note that the table is flat, and that just a few GasState
 * variables have been unpacked. The fields in the returned table
 * form a superset of those that the user can set.
 */
extern(C) int toTable(lua_State* L)
{
    auto fs = checkFlowState(L, 1);
    lua_newtable(L); // anonymous table { }
    int tblIdx = lua_gettop(L);
    pushFlowStateToTable(L, tblIdx, fs);
    return 1;
}

string checkGasVar(string var)
{
    return `lua_getfield(L, 2, "`~var~`");
if ( !lua_isnil(L, -1) ) {
    fs.gas.`~var~` = luaL_checknumber(L, -1);
}
lua_pop(L, 1);`;
}

string checkGasVarArray(string var)
{
    return `lua_getfield(L, 2, "`~var~`");
if ( lua_istable(L, -1 ) ) {
    fs.gas.`~var~`.length = 0;
    getArrayOfDoubles(L, -2, "`~var~`", fs.gas.`~var~`);
}
lua_pop(L, 1);`;
}

string checkFSVar(string var)
{
    return `lua_getfield(L, 2, "`~var~`");
if ( !lua_isnil(L, -1) ) {
    fs.`~var~` = luaL_checknumber(L, -1);
}
lua_pop(L, 1);`;
}

extern(C) int fromTable(lua_State* L)
{
    auto managedGasModel = GlobalConfig.gmodel_master;
    auto fs = checkFlowState(L, 1);
    if ( !lua_istable(L, 2) ) {
	return 0;
    }
    // Look for gas variables: "p" and "qaulity"
    mixin(checkGasVar("p"));
    mixin(checkGasVar("quality"));
    // Look for a table with mass fraction info
    lua_getfield(L, 2, "massf");
    if ( lua_istable(L, -1) ) {
	int massfIdx = lua_gettop(L);
	getSpeciesValsFromTable(L, managedGasModel, massfIdx, fs.gas.massf, "massf");
    }
    lua_pop(L, 1);
    // Look for an array of temperatures.
    mixin(checkGasVarArray("T"));
    if ( fs.gas.T.length != GlobalConfig.gmodel_master.n_modes ) {
	string errMsg = "The temperature array ('T') did not contain"~
	    " the correct number of entries.\n";
	errMsg ~= format("T.length= %d; n_modes= %d\n", fs.gas.T.length,
			 GlobalConfig.gmodel_master.n_modes);
	luaL_error(L, errMsg.toStringz);
    }
    // We should call equation of state to make sure gas state is consistent.
    GlobalConfig.gmodel_master.update_thermo_from_pT(fs.gas);

    // Look for velocity components: "velx", "vely", "velz"
    lua_getfield(L, 2, "velx");
    if ( !lua_isnil(L, -1 ) ) {
	fs.vel.refx = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);
    lua_getfield(L, 2, "vely");
    if ( !lua_isnil(L, -1 ) ) {
	fs.vel.refy = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);
    lua_getfield(L, 2, "velz");
    if ( !lua_isnil(L, -1 ) ) {
	fs.vel.refz = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);
    // Look for B components: "Bx", "By", "Bz"
    lua_getfield(L, 2, "Bx");
    if ( !lua_isnil(L, -1 ) ) {
	fs.B.refx = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);
    lua_getfield(L, 2, "By");
    if ( !lua_isnil(L, -1 ) ) {
	fs.B.refy = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);
    lua_getfield(L, 2, "Bz");
    if ( !lua_isnil(L, -1 ) ) {
	fs.B.refz = luaL_checknumber(L, -1);
    }
    lua_pop(L, 1);
    // Now look turbulence quantities
    mixin(checkFSVar("tke"));
    mixin(checkFSVar("omega"));
    mixin(checkFSVar("mu_t"));
    mixin(checkFSVar("k_t"));
    return 0;
}

extern(C) int toJSONString(lua_State* L)
{
    auto fs = checkFlowState(L, 1);
    lua_pushstring(L, fs.toJSONString().toStringz);
    return 1;
}

extern(C) int write_initial_sg_flow_file_from_lua(lua_State* L)
{
    auto fname = to!string(luaL_checkstring(L, 1));
    auto grid = checkStructuredGrid(L, 2); 
    double t0 = luaL_checknumber(L, 4);
    FlowState fs;
    // Test if we have a simple flow state or something more exotic
    if ( isObjType(L, 3, "FlowState") ) {
	fs = checkFlowState(L, 3);
	write_initial_flow_file(fname, grid, fs, t0, GlobalConfig.gmodel_master);
	return 0;
    }
    // Else, we might have a callable lua function
    if ( lua_isfunction(L, 3) ) {
	// Assume we can use the function then.
	// A lot of code borrowed from flowstate.d
	// Keep in sync with write_initial_flow_file() function in that file.
	//
	// Numbers of cells derived from numbers of vertices in grid.
	int nicell = grid.niv - 1;
	int njcell = grid.njv - 1;
	int nkcell = grid.nkv - 1;
	if (GlobalConfig.dimensions == 2) nkcell = 1;
	//	
	// Write the data for the whole structured block.
	auto outfile = new GzipOut(fname);
	auto writer = appender!string();
	formattedWrite(writer, "structured_grid_flow 1.0\n");
	formattedWrite(writer, "label: %s\n", grid.label);
	formattedWrite(writer, "sim_time: %20.12e\n", t0);
	auto gmodel = GlobalConfig.gmodel_master;
	auto variable_list = variable_list_for_cell(gmodel);
	formattedWrite(writer, "variables: %d\n", variable_list.length);
	// Variable list for cell on one line.
	foreach(varname; variable_list) {
	    formattedWrite(writer, " \"%s\"", varname);
	}
	formattedWrite(writer, "\n");
	// Numbers of cells
	formattedWrite(writer, "dimensions: %d\n", GlobalConfig.dimensions);
	formattedWrite(writer, "nicell: %d\n", nicell);
	formattedWrite(writer, "njcell: %d\n", njcell);
	formattedWrite(writer, "nkcell: %d\n", nkcell);
	outfile.compress(writer.data);
	// The actual cell data.
	foreach (k; 0 .. nkcell) {
	    foreach (j; 0 .. njcell) {
		foreach (i; 0 .. nicell) {
		    auto p000 = grid[i,j,k];
		    auto p100 = grid[i+1,j,k];
		    auto p110 = grid[i+1,j+1,k];
		    auto p010 = grid[i,j+1,k];
		    // [TODO] provide better calculation using geom module.
		    // For the moment, it doesn't matter greatly because the solver 
		    // will compute it's own approximations
		    auto pos = 0.25*(p000 + p100 + p110 + p010);
		    auto volume = 0.0;
		    if (GlobalConfig.dimensions == 3) {
			auto p001 = grid[i,j,k+1];
			auto p101 = grid[i+1,j,k+1];
			auto p111 = grid[i+1,j+1,k+1];
			auto p011 = grid[i,j+1,k+1];
			pos = 0.5*pos + 0.125*(p001 + p101 + p111 + p011);
		    }
		    // Now grab flow state via Lua function call
		    lua_pushvalue(L, 3);
		    lua_pushnumber(L, pos.x);
		    lua_pushnumber(L, pos.y);
		    lua_pushnumber(L, pos.z);
		    if ( lua_pcall(L, 3, 1, 0) != 0 ) {
			string errMsg = "Error in Lua function call for setting FlowState\n";
			errMsg ~= "as a function of postion (x, y, z).\n";
			luaL_error(L, errMsg.toStringz);
		    }
		    fs = checkFlowState(L, -1);
		    if ( !fs ) {
			string errMsg = "Error in from Lua function call for setting FlowState\n";
			errMsg ~= "as a function of postion (x, y, z).\n";
			errMsg ~= "The returned object is not a proper FlowState object.";
			luaL_error(L, errMsg.toStringz);
		    }
		    outfile.compress(" " ~ cell_data_as_string(pos, volume, fs) ~ "\n");
		} // end foreach i
	    } // end foreach j
	} // end foreach k
	outfile.finish();
	return 0;
    } // end if lua_isfunction
    return -1;
} // end write_initial_sg_flow_file_from_lua()

extern(C) int write_initial_usg_flow_file_from_lua(lua_State* L)
{
    auto fname = to!string(luaL_checkstring(L, 1));
    auto grid = checkUnstructuredGrid(L, 2); 
    double t0 = luaL_checknumber(L, 4);
    FlowState fs;
    // Test if we have a simple flow state or something more exotic
    if ( isObjType(L, 3, "FlowState") ) {
	fs = checkFlowState(L, 3);
	write_initial_flow_file(fname, grid, fs, t0, GlobalConfig.gmodel_master);
	return 0;
    }
    // Else, we might have a callable lua function
    if ( lua_isfunction(L, 3) ) {
	// Assume we can use the function then.
	// A lot of code borrowed from flowstate.d
	// Keep in sync with write_initial_flow_file() function in that file.
	//
	// Numbers of cells derived from numbers of vertices in grid.
	int ncells = grid.ncells;
	//	
	// Write the data for the whole structured block.
	auto outfile = new GzipOut(fname);
	auto writer = appender!string();
	formattedWrite(writer, "ustructured_grid_flow 1.0\n");
	formattedWrite(writer, "label: %s\n", grid.label);
	formattedWrite(writer, "sim_time: %20.12e\n", t0);
	auto gmodel = GlobalConfig.gmodel_master;
	auto variable_list = variable_list_for_cell(gmodel);
	formattedWrite(writer, "variables: %d\n", variable_list.length);
	// Variable list for cell on one line.
	foreach(varname; variable_list) {
	    formattedWrite(writer, " \"%s\"", varname);
	}
	formattedWrite(writer, "\n");
	// Numbers of cells
	formattedWrite(writer, "dimensions: %d\n", GlobalConfig.dimensions);
	formattedWrite(writer, "ncells: %d\n", ncells);
	outfile.compress(writer.data);
	// The actual cell data.
	foreach (i; 0 .. ncells) {
	    Vector3 pos = Vector3(0.0, 0.0, 0.0);
	    foreach (id; grid.cells[i].vtx_id_list) { pos += grid.vertices[id]; }
	    pos /= grid.cells[i].vtx_id_list.length;
	    double volume = 0.0; 
	    // Now grab flow state via Lua function call
	    lua_pushvalue(L, 3);
	    lua_pushnumber(L, pos.x);
	    lua_pushnumber(L, pos.y);
	    lua_pushnumber(L, pos.z);
	    if ( lua_pcall(L, 3, 1, 0) != 0 ) {
		string errMsg = "Error in Lua function call for setting FlowState\n";
		errMsg ~= "as a function of postion (x, y, z).\n";
		luaL_error(L, errMsg.toStringz);
	    }
	    fs = checkFlowState(L, -1);
	    if ( !fs ) {
		string errMsg = "Error in from Lua function call for setting FlowState\n";
		errMsg ~= "as a function of postion (x, y, z).\n";
		errMsg ~= "The returned object is not a proper FlowState object.";
		luaL_error(L, errMsg.toStringz);
	    }
	    outfile.compress(" " ~ cell_data_as_string(pos, volume, fs) ~ "\n");
	} // end foreach i
	outfile.finish();
	return 0;
    } // end if lua_isfunction
    return -1;
} // end write_initial_usg_flow_file_from_lua()

void registerFlowState(lua_State* L)
{
    luaL_newmetatable(L, FlowStateMT.toStringz);
    
    /* metatable.__index = metatable */
    lua_pushvalue(L, -1); // duplicates the current metatable
    lua_setfield(L, -2, "__index");
    /* Register methods for use. */
    lua_pushcfunction(L, &newFlowState);
    lua_setfield(L, -2, "new");
    lua_pushcfunction(L, &toStringObj!(FlowState, FlowStateMT));
    lua_setfield(L, -2, "__tostring");
    lua_pushcfunction(L, &toTable);
    lua_setfield(L, -2, "toTable");
    lua_pushcfunction(L, &fromTable);
    lua_setfield(L, -2, "fromTable");
    lua_pushcfunction(L, &toJSONString);
    lua_setfield(L, -2, "toJSONString");
    // Make class visible
    lua_setglobal(L, FlowStateMT.toStringz);

    lua_pushcfunction(L, &write_initial_sg_flow_file_from_lua);
    lua_setglobal(L, "write_initial_sg_flow_file");
    lua_pushcfunction(L, &write_initial_usg_flow_file_from_lua);
    lua_setglobal(L, "write_initial_usg_flow_file");
}

