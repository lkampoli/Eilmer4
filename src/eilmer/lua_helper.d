// lua_helper.d
//
// A place to put some frequently used functions
// for interacting with the Lua stack. Some of the functions
// are for interacting in the D code. Other functions
// (marked extern(C)) are functions made available in the
// Lua script.
//
// RG & PJ 2015-03-17 -- First hack (with Guiness in hand)

import std.stdio;
import std.conv;
import std.string;
import std.algorithm;

import util.lua;
import nm.complex;
import nm.number;

import gas;
import geom: gridTypeName, Grid_t;
import geom.luawrap;
import fvcell;
import fvinterface;
import luaflowstate;
import globalconfig;
import globaldata;
import solidfvcell;
import sfluidblock;
import ufluidblock;

// -----------------------------------------------------
// Functions to synchronise an array in the Dlang domain with a table in Lua

void push_array_to_Lua(T)(lua_State *L, ref T array_in_dlang, string name_in_Lua)
{
    lua_getglobal(L, name_in_Lua.toStringz);
    if (!lua_istable(L, -1)) {
        // TOS is not a table, so dispose of it and make a fresh table.
        lua_pop(L, 1);
        lua_newtable(L);
        lua_setglobal(L, name_in_Lua.toStringz);
        lua_getglobal(L, name_in_Lua.toStringz);
    }
    assert(lua_istable(L, -1), format("Did not find Lua table %s", name_in_Lua));
    foreach (i, elem; array_in_dlang) {
        lua_pushnumber(L, elem);
        lua_rawseti(L, -2, to!int(i+1));
    }
    lua_pop(L, 1); // dismiss the table
}

void get_array_from_Lua(T)(lua_State *L, ref T array_in_dlang, string name_in_Lua)
{
    lua_getglobal(L, name_in_Lua.toStringz);
    assert(lua_istable(L, -1), format("Did not find Lua table %s", name_in_Lua));
    foreach (i; 0 .. array_in_dlang.length) {
        lua_rawgeti(L, -1, to!int(i+1)); // get an item to top of stack
        array_in_dlang[i] = (lua_isnumber(L, -1)) ? to!double(lua_tonumber(L, -1)) : 0.0;
        lua_pop(L, 1); // discard item
    }
    lua_pop(L, 1); // dismiss the table
}

// -----------------------------------------------------
// Convenience functions for user's Lua script

void setSampleHelperFunctions(lua_State *L)
{
    lua_pushcfunction(L, &luafn_infoFluidBlock);
    lua_setglobal(L, "infoFluidBlock");
    lua_pushcfunction(L, &luafn_sampleFluidFace);
    lua_setglobal(L, "sampleFluidFace");
    lua_pushcfunction(L, &luafn_sampleFluidFace);
    lua_setglobal(L, "sampleFace"); // alias for sampleFluidFace; [TODO] remove eventually
    lua_pushcfunction(L, &luafn_sampleFluidCell);
    lua_setglobal(L, "sampleFluidCell");
    lua_pushcfunction(L, &luafn_sampleFluidCell);
    lua_setglobal(L, "sampleFlow"); // alias for sampleFluidCell; [TODO] remove eventually
    lua_pushcfunction(L, &luafn_runTimeLoads);
    lua_setglobal(L, "getRunTimeLoads");
}

extern(C) int luafn_infoFluidBlock(lua_State *L)
{
    // Expect FluidBlock index on the lua_stack.
    auto blkId = lua_tointeger(L, 1);
    auto blk = globalFluidBlocks[blkId];
    // Return the interesting bits as a table.
    lua_newtable(L);
    int tblIdx = lua_gettop(L);
    lua_pushinteger(L, GlobalConfig.dimensions); lua_setfield(L, tblIdx, "dimensions");
    lua_pushstring(L, blk.label.toStringz); lua_setfield(L, tblIdx, "label");
    lua_pushstring(L, gridTypeName(blk.grid_type).toStringz); lua_setfield(L, tblIdx, "grid_type");
    if (blk.grid_type == Grid_t.structured_grid) {
        auto sblk = cast(SFluidBlock) blk;
        assert(sblk !is null, "Oops, this should be an SFluidBlock object.");
        // For a structured_grid
        lua_pushinteger(L, sblk.nicell); lua_setfield(L, tblIdx, "nicell");
        lua_pushinteger(L, sblk.njcell); lua_setfield(L, tblIdx, "njcell");
        lua_pushinteger(L, sblk.nkcell); lua_setfield(L, tblIdx, "nkcell");
        lua_pushinteger(L, sblk.imin); lua_setfield(L, tblIdx, "imin");
        lua_pushinteger(L, sblk.jmin); lua_setfield(L, tblIdx, "jmin");
        lua_pushinteger(L, sblk.kmin); lua_setfield(L, tblIdx, "kmin");
        lua_pushinteger(L, sblk.imax); lua_setfield(L, tblIdx, "imax");
        lua_pushinteger(L, sblk.jmax); lua_setfield(L, tblIdx, "jmax");
        lua_pushinteger(L, sblk.kmax); lua_setfield(L, tblIdx, "kmax");
        string[] corner_names;
        if (GlobalConfig.dimensions == 3) {
            corner_names = ["p000","p100","p110","p010","p001","p101","p111","p011"];
        } else {
            corner_names = ["p00","p10","p11","p01"];
        }
        foreach (i; 0 .. corner_names.length) {
            lua_newtable(L);
            lua_pushnumber(L, sblk.corner_coords[i*3+0]); lua_setfield(L, -2, "x");
            lua_pushnumber(L, sblk.corner_coords[i*3+1]); lua_setfield(L, -2, "y");
            lua_pushnumber(L, sblk.corner_coords[i*3+2]); lua_setfield(L, -2, "z");
            lua_setfield(L, tblIdx, corner_names[i].toStringz);
        }
    }
    // For an unstructured_grid or structured_grid
    lua_pushinteger(L, blk.cells.length); lua_setfield(L, tblIdx, "ncells");
    lua_pushinteger(L, blk.faces.length); lua_setfield(L, tblIdx, "nfaces");
    lua_pushinteger(L, blk.vertices.length); lua_setfield(L, tblIdx, "nvertices");
    return 1;
} // end luafn_infoFluidBlock()

extern(C) int luafn_sampleFluidCell(lua_State *L)
{
    // Get arguments from lua_stack
    auto blkId = lua_tointeger(L, 1);
    if (!canFind(GlobalConfig.localBlockIds, blkId)) {
        string msg = format("Block id %d is not local to process.", blkId);
        luaL_error(L, msg.toStringz);
    }
    auto i = lua_tointeger(L, 2);
    auto j = lua_tointeger(L, 3);
    auto k = lua_tointeger(L, 4);

    // Grab the appropriate cell
    auto sblk = cast(SFluidBlock) globalFluidBlocks[blkId];
    FVCell cell;
    if (sblk) {
        try {
            cell = sblk.get_cell!()(i, j, k);
        } catch (Exception e) {
            string msg = format("Failed to locate vertex[%d,%d,%d] in block %d.", i, j, k, blkId);
            luaL_error(L, msg.toStringz);
        }
    } else {
        string msg = "Not implemented.";
        msg ~= " You have asked for an ijk-index cell in an unstructured-grid block.";
        luaL_error(L, msg.toStringz);
    }
    
    // Return the interesting bits as a table.
    lua_newtable(L);
    int tblIdx = lua_gettop(L);
    pushFluidCellToTable(L, tblIdx, cell, 0, globalFluidBlocks[blkId].myConfig.gmodel);
    return 1;
} // end luafn_sampleFluidCell()

extern(C) int luafn_sampleFluidFace(lua_State *L)
{
    // Get arguments from lua_stack
    string which_face = to!string(lua_tostring(L, 1));
    auto blkId = lua_tointeger(L, 2);
    if (!canFind(GlobalConfig.localBlockIds, blkId)) {
        string msg = format("Block id %d is not local to process.", blkId);
        luaL_error(L, msg.toStringz);
    }
    auto i = lua_tointeger(L, 3);
    auto j = lua_tointeger(L, 4);
    auto k = lua_tointeger(L, 5);

    FVInterface face;
    // Grab the appropriate face
    auto sblk = cast(SFluidBlock) globalFluidBlocks[blkId];
    auto ublk = cast(UFluidBlock) globalFluidBlocks[blkId];
    try {
        switch (which_face) {
        case "i": face = sblk.get_ifi!()(i, j, k); break;
        case "j": face = sblk.get_ifj!()(i, j, k); break;
        case "k": face = sblk.get_ifk!()(i, j, k); break;
        case "u": face = ublk.faces[i]; break; // unstructured grid
        default:
            string msg = "You have asked for an unknown type of face.";
            luaL_error(L, msg.toStringz);
        }
    } catch (Exception e) {
        string msg = format("Failed to locate face[%d,%d,%d] in block %d.", i, j, k, blkId);
        luaL_error(L, msg.toStringz);
    }    
    // Return the interesting bits as a table.
    lua_newtable(L);
    int tblIdx = lua_gettop(L);
    pushFluidFaceToTable(L, tblIdx, face, 0, globalFluidBlocks[blkId].myConfig.gmodel);
    return 1;
} // end luafn_sampleFluidFace()

extern(C) int luafn_runTimeLoads(lua_State *L)
{
    string loadsGroup = to!string(lua_tostring(L, 1));
    size_t grpIdx;
    size_t* grpIdxPtr = (loadsGroup in runTimeLoadsByName);
    if (grpIdxPtr !is null) {
        grpIdx = *grpIdxPtr;
    }
    else {
        string msg = "You have asked for an unknown loads group: "~loadsGroup;
        luaL_error(L, msg.toStringz);
    }
    // Set force as table {x=.., y=..., z=...}
    lua_newtable(L);
    int tblIdx = lua_gettop(L);
    lua_pushnumber(L, runTimeLoads[grpIdx].resultantForce.x);
    lua_setfield(L, tblIdx, "x");
    lua_pushnumber(L, runTimeLoads[grpIdx].resultantForce.y);
    lua_setfield(L, tblIdx, "y");
    lua_pushnumber(L, runTimeLoads[grpIdx].resultantForce.z);
    lua_setfield(L, tblIdx, "z");
     // Set moment as table {x=.., y=..., z=...}
    lua_newtable(L);
    tblIdx = lua_gettop(L);
    lua_pushnumber(L, runTimeLoads[grpIdx].resultantMoment.x);
    lua_setfield(L, tblIdx, "x");
    lua_pushnumber(L, runTimeLoads[grpIdx].resultantMoment.y);
    lua_setfield(L, tblIdx, "y");
    lua_pushnumber(L, runTimeLoads[grpIdx].resultantMoment.z);
    lua_setfield(L, tblIdx, "z");
        
    return 2;
}

// -----------------------------------------------------
// D code functions

/**
 * Push the interesting data from a FVCell and FVInterface to a Lua table
 *
 */
void pushFluidCellToTable(lua_State* L, int tblIdx, ref const(FVCell) cell, 
                          size_t gtl, GasModel gmodel)
{
    lua_pushnumber(L, cell.pos[gtl].x); lua_setfield(L, tblIdx, "x");
    lua_pushnumber(L, cell.pos[gtl].y); lua_setfield(L, tblIdx, "y");
    lua_pushnumber(L, cell.pos[gtl].z); lua_setfield(L, tblIdx, "z");
    lua_pushnumber(L, cell.volume[gtl]); lua_setfield(L, tblIdx, "vol");
    pushFlowStateToTable(L, tblIdx, cell.fs, gmodel);
} // end pushFluidCellToTable()

void pushFluidFaceToTable(lua_State* L, int tblIdx, ref const(FVInterface) face, 
                          size_t gtl, GasModel gmodel)
{
    lua_pushnumber(L, face.pos.x); lua_setfield(L, tblIdx, "x");
    lua_pushnumber(L, face.pos.y); lua_setfield(L, tblIdx, "y");
    lua_pushnumber(L, face.pos.z); lua_setfield(L, tblIdx, "z");
    lua_pushnumber(L, face.area[gtl]); lua_setfield(L, tblIdx, "area");
    lua_pushnumber(L, face.n.x); lua_setfield(L, tblIdx, "nx");
    lua_pushnumber(L, face.n.y); lua_setfield(L, tblIdx, "ny");
    lua_pushnumber(L, face.n.z); lua_setfield(L, tblIdx, "nz");
    lua_pushnumber(L, face.t1.x); lua_setfield(L, tblIdx, "t1x");
    lua_pushnumber(L, face.t1.y); lua_setfield(L, tblIdx, "t1y");
    lua_pushnumber(L, face.t1.z); lua_setfield(L, tblIdx, "t1z");
    lua_pushnumber(L, face.t2.x); lua_setfield(L, tblIdx, "t2x");
    lua_pushnumber(L, face.t2.y); lua_setfield(L, tblIdx, "t2y");
    lua_pushnumber(L, face.t2.z); lua_setfield(L, tblIdx, "t2z");
    lua_pushnumber(L, face.Ybar); lua_setfield(L, tblIdx, "Ybar");
    lua_pushnumber(L, face.gvel.x); lua_setfield(L, tblIdx, "gvelx");
    lua_pushnumber(L, face.gvel.y); lua_setfield(L, tblIdx, "gvely");
    lua_pushnumber(L, face.gvel.z); lua_setfield(L, tblIdx, "gvelz");
    pushFlowStateToTable(L, tblIdx, face.fs, gmodel);
} // end pushFluidFaceToTable()

// ----------------------------------------------------------------------
// Functions related to solid domains
extern(C) int luafn_sampleSolidCell(lua_State *L)
{
    // Get arguments from lua_stack
    auto blkId = lua_tointeger(L, 1);
    auto i = lua_tointeger(L, 2);
    auto j = lua_tointeger(L, 3);
    auto k = lua_tointeger(L, 4);

    // Grab the appropriate cell
    auto cell = solidBlocks[blkId].getCell(i, j, k);
    
    // Return the interesting bits as a table.
    lua_newtable(L);
    int tblIdx = lua_gettop(L);
    pushSolidCellToTable(L, tblIdx, cell);
    return 1;
} // end luafn_sampleFluidCell()

void pushSolidCellToTable(lua_State* L, int tblIdx, ref const(SolidFVCell) cell)
{
    lua_pushnumber(L, cell.pos.x); lua_setfield(L, tblIdx, "x");
    lua_pushnumber(L, cell.pos.y); lua_setfield(L, tblIdx, "y");
    lua_pushnumber(L, cell.pos.z); lua_setfield(L, tblIdx, "z");
    lua_pushnumber(L, cell.volume); lua_setfield(L, tblIdx, "vol");
    lua_pushnumber(L, cell.T); lua_setfield(L, tblIdx, "T");
    lua_pushnumber(L, cell.sp.rho); lua_setfield(L, tblIdx, "rho");
    lua_pushnumber(L, cell.sp.Cp); lua_setfield(L, tblIdx, "Cp");
    lua_pushnumber(L, cell.sp.k); lua_setfield(L, tblIdx, "k");

    lua_pushnumber(L, cell.sp.k11); lua_setfield(L, tblIdx, "k11");
    lua_pushnumber(L, cell.sp.k12); lua_setfield(L, tblIdx, "k12");
    lua_pushnumber(L, cell.sp.k13); lua_setfield(L, tblIdx, "k13");
    lua_pushnumber(L, cell.sp.k21); lua_setfield(L, tblIdx, "k21");
    lua_pushnumber(L, cell.sp.k22); lua_setfield(L, tblIdx, "k22");
    lua_pushnumber(L, cell.sp.k23); lua_setfield(L, tblIdx, "k23");
    lua_pushnumber(L, cell.sp.k31); lua_setfield(L, tblIdx, "k31");
    lua_pushnumber(L, cell.sp.k32); lua_setfield(L, tblIdx, "k32");
    lua_pushnumber(L, cell.sp.k33); lua_setfield(L, tblIdx, "k33");

} // end pushSolidCellToTable()



