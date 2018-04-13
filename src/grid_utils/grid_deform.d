/** grid_deform.d
 * This file holds the methods used to deform a mesh for shape optimisation.
 *
 * Author: Kyle D.
 * Date: 2018-01-17
**/

module grid_deform;

import std.stdio;
import fluidblock;
import std.math;
import std.algorithm;
import geom;

void inverse_distance_weighting(FluidBlock myblk, Vector3[] bndaryVtxInitPos, Vector3[] bndaryVtxNewPos, size_t gtl, string[] NonFixedBoundaryList=[]) {
    
    // we assume the boundary vertices have already been perturbed, and have their new positions stored at the current gtl.
    // now we compute perturbed internal vertices
    foreach(vtxi; myblk.vertices) {
        double[2] numer_sum; numer_sum[0] = 0.0; numer_sum[1] = 0.0; double denom_sum = 0.0; 
        size_t nBndaryVtx = bndaryVtxInitPos.length;
        assert(bndaryVtxInitPos.length == bndaryVtxNewPos.length,
               "Inverse Distance Weighting: initial positions array length does not equal new positions array length");
        foreach ( i; 0..nBndaryVtx) {
            Vector3 ds;
            ds.refx = bndaryVtxNewPos[i].x - bndaryVtxInitPos[i].x;
            ds.refy = bndaryVtxNewPos[i].y - bndaryVtxInitPos[i].y;
            double r; double w;
            double dx = vtxi.pos[0].x - bndaryVtxInitPos[i].x; 
            double dy = vtxi.pos[0].y - bndaryVtxInitPos[i].y; 
            r = sqrt(dx*dx + dy*dy);
            w = 1.0 / (r*r);
            numer_sum[0] += ds.x * w; numer_sum[1] += ds.y * w;
            denom_sum += w;
        }
        // update vertex positions
        if (myblk.boundaryVtxIndexList.canFind(vtxi.id) == false) {
            vtxi.pos[gtl].refx = vtxi.pos[0].x + (numer_sum[0]/denom_sum);
            vtxi.pos[gtl].refy = vtxi.pos[0].y + (numer_sum[1]/denom_sum);
        }
    }
}
