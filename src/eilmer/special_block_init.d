/** special_block_init.d
 * 
 * This module houses functions that do some special initialisation
 * of blocks at runtime.
 *
 * Authors: Rowan G. and Peter J.
 *
 */

module special_block_init;

import std.stdio;
import std.algorithm.searching;
import nm.complex;
import nm.number;

import globalconfig;
import fluidblock;
import fvcell;
import fvinterface;

void diffuseWallBCsIntoBlock(FluidBlock blk, int nPasses, double Twall)
{
    FVCell[] cellsAlongWalls;
    FVCell[size_t] cellsInDiffusionZone;
    size_t[] cellsAddedLastStep;
    size_t[] cellsAddedThisStep;

    // Determine which walls if any are no-slip walls
    bool[size_t] noSlipWalls;
    foreach (bcId, bc; blk.bc) {
        if (bc.is_wall_with_viscous_effects) {
            noSlipWalls[bcId] = true;
        }
    }
    
    // Determine which cells are against a no-slip wall.
    foreach (bcId; noSlipWalls.byKey()) {
        foreach (i, face; blk.bc[bcId].faces) {
            if (blk.bc[bcId].outsigns[i] == 1) {
                cellsAlongWalls ~= face.left_cell;
            }
            else {
                cellsAlongWalls ~= face.right_cell;
            }
        }
    }

    // Cells along a wall get the properties at the wall.
    foreach (bcId; noSlipWalls.byKey()) {
        blk.bc[bcId].applyPreSpatialDerivActionAtBndryFaces(0.0, 0, 0);
    }
    foreach (cell; cellsAlongWalls) {
        foreach (face; cell.iface) {
            if (face.is_on_boundary && (face.bc_id in noSlipWalls)) {
                if (Twall > 0.0) {
                    cell.fs.gas.T = Twall;
                    foreach (ref T; cell.fs.gas.T_modes) T = Twall;
                }
                else {
                    cell.fs.gas.T = face.fs.gas.T;
                    // We set the other modes to the transrotational temperature
                    // since we are expecting the gas to at equilibrium (or very close to)
                    // a cold wall with no-slip.
                    foreach (ref T; cell.fs.gas.T_modes) T = face.fs.gas.T;
                }
                cell.fs.vel.set(face.fs.vel);
                if (cell.in_turbulent_zone) {
                    version(komega) {
                        cell.fs.tke = face.fs.tke;
                        cell.fs.omega = face.fs.omega;
                    }
                    cell.fs.mu_t = face.fs.mu_t;
                    cell.fs.k_t = face.fs.k_t;
                }
                blk.myConfig.gmodel.update_thermo_from_pT(cell.fs.gas);
                cell.encode_conserved(0, 0, 0.0);
                cell.decode_conserved(0, 0, 0.0);
            } 
        }
    }
    
    // Gather the cells adjacent to the wall cells
    // as the first layer in the diffusion zone.
    foreach (cell; cellsAlongWalls) {
        foreach (face; cell.iface) {
            if (face.is_on_boundary) {
                // The only cells this interface touches
                // are ghost cells or wall cells.
                // We do not want these in the diffusion zone.
                continue;
            }
            if (!cellsAlongWalls.canFind(face.left_cell)) {
                cellsInDiffusionZone[face.left_cell.id] = face.left_cell;
                if (!cellsAddedLastStep.canFind(face.left_cell.id)) {
                    cellsAddedLastStep ~= face.left_cell.id;
                }
            }
            if (!cellsAlongWalls.canFind(face.right_cell)) {
                cellsInDiffusionZone[face.right_cell.id] = face.right_cell;
                if (!cellsAddedLastStep.canFind(face.right_cell.id)) {
                    cellsAddedLastStep ~= face.right_cell.id;
                }
            }
        }
    }

    // Now perform averaging of flow properties for cells
    // in the diffusion zone.
    foreach (pass; 0 .. nPasses) {
        // Do the averaging
        foreach (cell; cellsInDiffusionZone.byValue()) {
            int nNbrCells = 0;
            number T_avg = 0.0;
            number velx_avg = 0.0;
            number vely_avg = 0.0;
            number velz_avg = 0.0;
            version(komega) {
                number tke_avg = 0.0;
                number omega_avg = 0.0;
            }
            number mu_t_avg = 0.0;
            number k_t_avg = 0.0;
            foreach (face; cell.iface) {
                if (face.is_on_boundary) continue;
                if (face.left_cell.id == cell.id) {
                    // Then right cell must be a neighbour
                    ++nNbrCells;
                    T_avg += face.right_cell.fs.gas.T;
                    velx_avg += face.right_cell.fs.vel.x;
                    vely_avg += face.right_cell.fs.vel.y;
                    velz_avg += face.right_cell.fs.vel.z;
                    version(komega) {
                        tke_avg += face.right_cell.fs.tke;
                        omega_avg += face.right_cell.fs.omega;
                    }
                    mu_t_avg += face.right_cell.fs.mu_t;
                    k_t_avg += face.right_cell.fs.k_t;
                }
                else {
                    // The left cell must be a neighbour;
                    ++nNbrCells;
                    T_avg += face.left_cell.fs.gas.T;
                    velx_avg += face.left_cell.fs.vel.x;
                    vely_avg += face.left_cell.fs.vel.y;
                    velz_avg += face.left_cell.fs.vel.z;
                    version(komega) {
                        tke_avg += face.left_cell.fs.tke;
                        omega_avg += face.left_cell.fs.omega;
                    }
                    mu_t_avg += face.left_cell.fs.mu_t;
                    k_t_avg += face.left_cell.fs.k_t;
                }
            }
            // Place the averaged value in cell.
            cell.fs.gas.T = T_avg / nNbrCells;
            cell.fs.vel.refx = velx_avg / nNbrCells;
            cell.fs.vel.refy = vely_avg / nNbrCells;
            cell.fs.vel.refz = velz_avg / nNbrCells;
            if (cell.in_turbulent_zone) {
                version(komega) {
                    cell.fs.tke = tke_avg / nNbrCells;
                    cell.fs.omega = omega_avg / nNbrCells;
                }
                cell.fs.mu_t = mu_t_avg / nNbrCells;
                cell.fs.k_t = k_t_avg / nNbrCells;
            }
            blk.myConfig.gmodel.update_thermo_from_pT(cell.fs.gas);
            cell.encode_conserved(0, 0, 0.0);
            cell.decode_conserved(0, 0, 0.0);
        }

        // Add a new layer of cells for diffusion step
        if (pass != (nPasses-1)) { // We don't need to grab new cells on the final pass.
            cellsAddedThisStep.length = 0;
            foreach (cellId; cellsAddedLastStep) {
                auto cell = cellsInDiffusionZone[cellId];
                foreach (face; cell.iface) {
                    if (face.is_on_boundary) {
                        // The only cells this interface touches
                        // are ghost cells or wall cells.
                        // We do not want these in the diffusion zone.
                        continue;
                    }
                    if (face.left_cell.id == cell.id) {
                        // Interested in right_cell.
                        if ( !(face.right_cell.id in cellsInDiffusionZone) &&
                             !cellsAlongWalls.canFind(face.right_cell) ) {
                            cellsInDiffusionZone[face.right_cell.id] = face.right_cell;
                            cellsAddedThisStep ~= face.right_cell.id;
                        }
                    }
                    else {
                        // Interested in left_cell.
                        if ( !(face.left_cell.id in cellsInDiffusionZone) &&
                             !cellsAlongWalls.canFind(face.left_cell) ) {
                            cellsInDiffusionZone[face.left_cell.id] = face.left_cell;
                            cellsAddedThisStep ~= face.left_cell.id;
                        }
                    }
                }
            }
            cellsAddedLastStep = cellsAddedThisStep.dup;
        }
    }
}
