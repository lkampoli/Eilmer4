// Authors: RG, PJ & KD
// Date: 2015-11-20

module grid_motion;

import std.string;
import std.conv;

import util.lua;
import util.lua_service;
import nm.luabbla;
import lua_helper;
import fvcore;
import globalconfig;
import globaldata;
import geom;
import geom.luawrap;
import block;
import std.stdio;

void setGridMotionHelperFunctions(lua_State *L)
{
    lua_pushcfunction(L, &luafn_getVtxPosition);
    lua_setglobal(L, "getVtxPosition");
    lua_pushcfunction(L, &luafn_setVtxVelocitiesForDomain);
    lua_setglobal(L, "setVtxVelocitiesForDomain");
    lua_pushcfunction(L, &luafn_setVtxVelocitiesForBlock);
    lua_setglobal(L, "setVtxVelocitiesForBlock");
    lua_pushcfunction(L, &luafn_setVtxVelocity);
    lua_setglobal(L, "setVtxVelocity");
}

extern(C) int luafn_getVtxPosition(lua_State *L)
{
    // Get arguments from lua_stack
    auto blkId = lua_tointeger(L, 1);
    auto i = lua_tointeger(L, 2);
    auto j = lua_tointeger(L, 3);
    auto k = lua_tointeger(L, 4);

    // Grab the appropriate vtx
    auto vtx = localFluidBlocks[blkId].get_vtx(i, j, k);
    
    // Return the interesting bits as a table with entries x, y, z.
    lua_newtable(L);
    lua_pushnumber(L, vtx.pos[0].x); lua_setfield(L, -2, "x");
    lua_pushnumber(L, vtx.pos[0].y); lua_setfield(L, -2, "y");
    lua_pushnumber(L, vtx.pos[0].z); lua_setfield(L, -2, "z");
    return 1;
}

extern(C) int luafn_setVtxVelocitiesForDomain(lua_State* L)
{
    // Expect a single argument: a Vector3 object
    auto vel = checkVector3(L, 1);

    foreach ( blk; localFluidBlocks ) {
        foreach ( vtx; blk.vertices ) {
            /* We assume that we'll only update grid positions
               at the start of the increment. This should work
               well except in the most critical cases of time
               accuracy.
            */
            vtx.vel[0] = *vel;
        }
    }
    // In case, the user gave use more return values than
    // we used, just set the lua stack to empty and let
    // the lua garbage collector do its thing.
    lua_settop(L, 0);
    return 0;
}

extern(C) int luafn_setVtxVelocitiesForBlock(lua_State* L)
{
    // Expect two arguments: 1. a Vector3 object
    //                       2. a block id
    auto vel = checkVector3(L, 1);
    auto blkId = lua_tointeger(L, 2);

    foreach ( vtx; localFluidBlocks[blkId].vertices ) {
        /* We assume that we'll only update grid positions
           at the start of the increment. This should work
           well except in the most critical cases of time
           accuracy.
        */
        vtx.vel[0] = *vel;
    }
    // In case, the user gave use more return values than
    // we used, just set the lua stack to empty and let
    // the lua garbage collector do its thing.
    lua_settop(L, 0);
    return 0;
}

/**
 * Sets the velocity of an individual vertex.
 *
 * This function can be called for structured 
 * or unstructured grids. We'll determine what
 * type grid is meant by the number of arguments
 * supplied. The following calls are allowed:
 *
 * setVtxVelocity(vel, blkId, vtxId)
 *   Sets the velocity vector for vertex vtxId in
 *   block blkId. This works for both structured
 *   and unstructured grids.
 *
 * setVtxVelocity(vel, blkId, i, j)
 *   Sets the velocity vector for vertex "i,j" in
 *   block blkId in a two-dimensional structured grid.
 *
 * setVtxVelocity(vel, blkId, i, j, k)
 *   Set the velocity vector for vertex "i,j,k" in
 *   block blkId in a three-dimensional structured grid.
 */
extern(C) int luafn_setVtxVelocity(lua_State* L)
{
    int narg = lua_gettop(L);
    auto vel = checkVector3(L, 1);
    auto blkId = lua_tointeger(L, 2);

    if ( narg == 3 ) {
        auto vtxId = lua_tointeger(L, 3);
        localFluidBlocks[blkId].vertices[vtxId].vel[0] = *vel;
    }
    else if ( narg == 4 ) {
        auto i = lua_tointeger(L, 3);
        auto j = lua_tointeger(L, 4);
        localFluidBlocks[blkId].get_vtx(i,j).vel[0] = *vel;
    }
    else if ( narg >= 5 ) {
        auto i = lua_tointeger(L, 3);
        auto j = lua_tointeger(L, 4);
        auto k = lua_tointeger(L, 5);
        localFluidBlocks[blkId].get_vtx(i,j,k).vel[0] = *vel;
    }
    else {
        string errMsg = "ERROR: Too few arguments passed to luafn: setVtxVelocity()\n";
        luaL_error(L, errMsg.toStringz);
    }
    lua_settop(L, 0);
    return 0;
}

void assign_vertex_velocities_via_udf(double sim_time, double dt)
{
    auto L = GlobalConfig.master_lua_State;
    lua_getglobal(L, "assignVtxVelocities");
    lua_pushnumber(L, sim_time);
    lua_pushnumber(L, dt);
    int number_args = 2;
    int number_results = 0;

    if ( lua_pcall(L, number_args, number_results, 0) != 0 ) {
        string errMsg = "ERROR: while running user-defined function assignVtxVelocities()\n";
        errMsg ~= to!string(lua_tostring(L, -1));
        throw new FlowSolverException(errMsg);
    }
}
