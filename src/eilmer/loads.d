/**
 * Eilmer4 boundary interface loads writing functions.
 *
 * Author: Kyle Damm
 * First code: 2017-03-17
 * Edits by Will Landsberg and Tim Cullen
 * 
 * 2018-01-20 Some code clean up by PJ;
 * [TODO] more is needed for MPI context.
 */

module loads;

import std.stdio;
import std.string;
import std.file;
import std.array;
import std.algorithm;
import std.format;
import std.parallelism;
import std.math;
import std.conv;
import std.typecons : Tuple;
import std.json;
import nm.complex;
import nm.number;

import fvcore;
import json_helper;
import globalconfig;
import globaldata;
import fvcell;
import fileutil;
import solidfvcell;
import solidblock;
import flowstate;
import flowgradients;
import geom;
import fluidblock;
import sfluidblock: SFluidBlock;
import ufluidblock: UFluidBlock;
import fvinterface;
import bc;
import mass_diffusion;

string loadsDir = "loads";

void init_current_tindx_dir(int current_loads_tindx)
{
    string dirName = format("%s/t%04d", loadsDir, current_loads_tindx);
    ensure_directory_is_present(dirName);
}

void init_loads_times_file()
{
    string fname = loadsDir ~ "/" ~ GlobalConfig.base_file_name ~ "-loads.times";
    std.file.write(fname, "# 1:loads_index 2:sim_time\n");
}

void update_loads_times_file(double sim_time, int current_loads_tindx)
{
    string fname = loadsDir ~ "/" ~ GlobalConfig.base_file_name ~ "-loads.times";
    std.file.append(fname, format("%04d %.18e \n", current_loads_tindx, sim_time));
}

void write_boundary_loads_to_file(double sim_time, int current_loads_tindx) {
    init_current_tindx_dir(current_loads_tindx);
    foreach (blk; localFluidBlocks) {
        if (blk.active) {
            final switch (blk.grid_type) {
            case Grid_t.unstructured_grid: 
                auto ublk = cast(UFluidBlock) blk;
                assert(ublk !is null, "Oops, this should be a UFluidBlock object.");
                apply_unstructured_grid(ublk, sim_time, current_loads_tindx);
                break;
            case Grid_t.structured_grid:
                auto sblk = cast(SFluidBlock) blk;
                assert(sblk !is null, "Oops, this should be an SFluidBlock object.");
                apply_structured_grid(sblk, sim_time, current_loads_tindx);
            } // end final switch
        } // if (blk.active)
    } // end foreach
} // end write_boundary_loads_to_file()

string generate_boundary_load_file(int blkid, int current_loads_tindx, double sim_time, string group)
{
    // generate data file -- naming format tindx_groupname.dat
    string fname = format("%s/t%04d/b%04d.t%04d.%s.dat", loadsDir, current_loads_tindx,
                          blkid, current_loads_tindx, group);
    // check if file exists already, if not create file
    if (!exists(fname)) {
        auto f = File(fname, "w");
        f.writeln("# t = ", sim_time);
        f.writeln("# 1:pos.x 2:pos.y 3:pos.z 4:area 5:q_total 6:q_cond 7:q_diff 8:tau 9:l_tau 10:m_tau 11:n_tau 12:sigma "~
                  "13:n.x 14:n.y 15:n.z 16:T 17:Re_wall 18:y+ 19:cellWidthNormalToSurface");
        f.close();
    }
    return fname;
} // end generate_boundary_load_file()

void apply_unstructured_grid(UFluidBlock blk, double sim_time, int current_loads_tindx)
{
    foreach (bndary; blk.bc) {
        if (canFind(bndary.group, GlobalConfig.boundary_group_for_loads)) {
            string fname = generate_boundary_load_file(blk.id, current_loads_tindx, sim_time, bndary.group);
            foreach (i, iface; bndary.faces) {
                // cell width normal to surface
                number w = (bndary.outsigns[i] == 1) ? iface.left_cell.L_min : iface.right_cell.L_min;
                compute_and_store_loads(iface, w, sim_time, fname);
            }
        }
    }
} // end apply_unstructured_grid()

void apply_structured_grid(SFluidBlock blk, double sim_time, int current_loads_tindx) {
    foreach (bndary; blk.bc) {
        if (canFind(bndary.group, GlobalConfig.boundary_group_for_loads)) {
            string fname = generate_boundary_load_file(blk.id, current_loads_tindx, sim_time, bndary.group);
            size_t i, j, k;
            FVCell cell;
            FVInterface IFace;
            number cellWidthNormalToSurface;
            final switch (bndary.which_boundary) {
            case Face.north:
                j = blk.jmax;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (i = blk.imin; i <= blk.imax; ++i) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.north];
                        cellWidthNormalToSurface = cell.jLength;
                        compute_and_store_loads(IFace, cellWidthNormalToSurface, sim_time, fname);
                    } // end i loop
                } // end for k
                break;
            case Face.east:
                i = blk.imax;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.east];
                        cellWidthNormalToSurface = cell.iLength;
                        compute_and_store_loads(IFace, cellWidthNormalToSurface, sim_time, fname);
                    } // end j loop
                } // end for k
                break;
            case Face.south:
                j = blk.jmin;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (i = blk.imin; i <= blk.imax; ++i) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.south];
                        cellWidthNormalToSurface = cell.jLength;                        
                        compute_and_store_loads(IFace, cellWidthNormalToSurface, sim_time, fname);
                    } // end i loop
                } // end for k
                break;
            case Face.west:
                i = blk.imin;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.west];
                        cellWidthNormalToSurface = cell.iLength;
                        compute_and_store_loads(IFace, cellWidthNormalToSurface, sim_time, fname);
                    } // end j loop
                } // end for k
                break;
            case Face.top:
                k = blk.kmax;
                for (i = blk.imin; i <= blk.imax; ++i) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.top];
                        cellWidthNormalToSurface = cell.kLength;
                        compute_and_store_loads(IFace, cellWidthNormalToSurface, sim_time, fname);
                    } // end j loop
                } // end for i
                break;
            case Face.bottom:
                k = blk.kmin;
                for (i = blk.imin; i <= blk.imax; ++i) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.bottom];
                        cellWidthNormalToSurface = cell.kLength;
                        compute_and_store_loads(IFace, cellWidthNormalToSurface, sim_time, fname);
                    } // end j loop
                } // end for i
                break;
            } // end switch which_boundary
        } // end if
    } // end foreach
} // end apply_structured_grid()

void compute_and_store_loads(FVInterface iface, number cellWidthNormalToSurface, double sim_time, string fname)
{
    auto gmodel = GlobalConfig.gmodel_master;
    FlowState fs = iface.fs;
    FlowGradients grad = iface.grad;
    // iface orientation
    number nx = iface.n.x; number ny = iface.n.y; number nz = iface.n.z;
    number t1x = iface.t1.x; number t1y = iface.t1.y; number t1z = iface.t1.z;
    number t2x = iface.t2.x; number t2y = iface.t2.y; number t2z = iface.t2.z;
    // iface properties
    number mu_wall = fs.gas.mu;
    number k_wall = fs.gas.k;
    number P = fs.gas.p;
    number T_wall = fs.gas.T;
    number a_wall = fs.gas.a;
    number rho_wall = fs.gas.rho;
    number sigma_wall, tau_wall, l_tau, m_tau, n_tau, Re_wall, nu_wall, u_star, y_plus;
    number q_total, q_cond, q_diff;
    if (GlobalConfig.viscous) {
        number dTdx = grad.T[0]; number dTdy = grad.T[1]; number dTdz = grad.T[2]; 
        number dudx = grad.vel[0][0]; number dudy = grad.vel[0][1]; number dudz = grad.vel[0][2];
        number dvdx = grad.vel[1][0]; number dvdy = grad.vel[1][1]; number dvdz = grad.vel[1][2];
        number dwdx = grad.vel[2][0]; number dwdy = grad.vel[2][1]; number dwdz = grad.vel[2][2];
        // compute heat load
        number dTdn = dTdx*nx + dTdy*ny + dTdz*nz; // dot product
        q_cond = k_wall * dTdn; // heat load (positive sign means heat flows to the wall)
        q_diff = 0.0;
        if (GlobalConfig.mass_diffusion_model != MassDiffusionModel.none) {
            foreach (isp; 0 .. gmodel.n_species) {
                number h = gmodel.enthalpy(fs.gas, to!int(isp));
                q_diff += -iface.jx[isp]*h*nx - iface.jy[isp]*h*ny - iface.jz[isp]*h*nz;
            }
        }
        q_total = q_cond + q_diff;
        // compute stress tensor at interface in global reference frame
        number lmbda = -2.0/3.0 * mu_wall;
        number tau_xx = 2.0*mu_wall*dudx + lmbda*(dudx + dvdy + dwdz);
        number tau_yy = 2.0*mu_wall*dvdy + lmbda*(dudx + dvdy + dwdz);
        number tau_zz = 2.0*mu_wall*dwdz + lmbda*(dudx + dvdy + dwdz);
        number tau_xy = mu_wall * (dudy + dvdx);
        number tau_xz = mu_wall * (dudz + dwdx);
        number tau_yz = mu_wall * (dvdz + dwdy);
        number sigma_x = P + tau_xx;
        number sigma_y = P + tau_yy;
        number sigma_z = P + tau_zz;
        // compute direction cosines for interface normal
        // [TODO] Kyle, shouldn't the nx, ny and nz values already be direction cosines? PJ 2017-09-09
        number l = nx / sqrt(nx*nx + ny*ny + nz*nz);
        number m = ny / sqrt(nx*nx + ny*ny + nz*nz);
        number n = nz / sqrt(nx*nx + ny*ny + nz*nz);
        // transform stress tensor -- we only need stress on a single surface
        // we can avoid performing the entire transformation by following
        // the procedure in Roark's Formulas for Stress and Strain (Young and Budynas) pg. 21.
        sigma_wall = sigma_x*l*l+sigma_y*m*m+sigma_z*n*n+2.0*tau_xy*l*m+2.0*tau_yz*m*n+2.0*tau_xz*n*l;
        tau_wall = sqrt((sigma_x*l+tau_xy*m+tau_xz*n)*(sigma_x*l+tau_xy*m+tau_xz*n)
                        +(tau_xy*l+sigma_y*m+tau_yz*n)*(tau_xy*l+sigma_y*m+tau_yz*n)
                        +(tau_xz*l+tau_yz*m+sigma_z*n)*(tau_xz*l+tau_yz*m+sigma_z*n)
                        -sigma_wall*sigma_wall);
        // tau_wall directional cosines
        if (tau_wall == 0.0){
            l_tau = l;
            m_tau = m;
            n_tau = n;
        } else {
            l_tau = 1.0/tau_wall * ((sigma_x - sigma_wall)*l+tau_xy*m+tau_xz*n);
            m_tau = 1.0/tau_wall * (tau_xy*l+(sigma_y - sigma_wall)*m+tau_yz*n);
            n_tau = 1.0/tau_wall * (tau_xz*l+tau_yz*m+(sigma_z-sigma_wall)*n);
        }
        // compute y+
        nu_wall = mu_wall / rho_wall;
        u_star = sqrt(tau_wall / rho_wall);
        y_plus = u_star*(cellWidthNormalToSurface/2.0) / nu_wall;
        // compute cell Reynolds number
        Re_wall = rho_wall * a_wall * cellWidthNormalToSurface / mu_wall;
    } else {
        // For an inviscid simulation, we have only pressure.
        sigma_wall = P;
        tau_wall = 0.0;
        l_tau = 0.0; m_tau = 0.0; n_tau = 0.0;
        q_total = 0.0;
        q_cond = 0.0;
        q_diff = 0.0;
        Re_wall = 0.0;
        y_plus = 0.0;
    }
    // store in file
    auto writer = format("%20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e %20.16e\n",
                         iface.pos.x.re, iface.pos.y.re, iface.pos.z.re, iface.area[0].re,
                         q_total.re, q_cond.re, q_diff.re, tau_wall.re, l_tau.re, m_tau.re, n_tau.re, sigma_wall.re,
                         nx.re, ny.re, nz.re, T_wall.re, Re_wall.re, y_plus.re,
                         cellWidthNormalToSurface.re);
    std.file.append(fname, writer);    
} // end compute_and_store_loads()


struct RunTimeLoads {
    Tuple!(size_t,size_t)[] surfaces;
    Vector3 momentCentre;
    Vector3 resultantForce = Vector3(0.0, 0.0, 0.0);
    Vector3 resultantMoment = Vector3(0.0, 0.0, 0.0);
}

void initRunTimeLoads(JSONValue jsonData)
{
    int nLoadsGroups = getJSONint(jsonData, "ngroups", 0);
    foreach (group; 0 .. nLoadsGroups) {
        auto jsonDataForGroup = jsonData["group-" ~ to!string(group)];
        string groupName = getJSONstring(jsonDataForGroup, "groupLabel", "");
        double x = getJSONdouble(jsonDataForGroup, "momentCtr_x", 0.0);
        double y = getJSONdouble(jsonDataForGroup, "momentCtr_y", 0.0);
        double z = getJSONdouble(jsonDataForGroup, "momentCtr_z", 0.0);
        if (groupName in runTimeLoads) {
            string errMsg = "The group name for run-time loads configuration is not unique.\n";
            errMsg ~= format("The problem occurred when tring to add '%s' to the list of runTimeLoads.", groupName);
            throw new Error(errMsg);
        }
        runTimeLoads[groupName] = RunTimeLoads();
        runTimeLoads[groupName].momentCentre = Vector3(x, y, z);
        // Now look over all blocks and configure the surfaces list
        foreach (iblk, blk; globalFluidBlocks) {
            foreach (ibndry, bndry; blk.bc) {
                if (groupName == bndry.group) {
                    runTimeLoads[groupName].surfaces ~= Tuple!(size_t,size_t)(iblk, ibndry);
                }
            }
        }
    }

    writeln("Configuration of run-time loads:");
    foreach (name, group; runTimeLoads) {
        writeln("   groupLabel= ", name);
        writeln("   Includes surfaces: ");
        foreach (blkNbndry; group.surfaces) {
            writefln("      blk-%d--boundary-%d", blkNbndry[0], blkNbndry[1]);
        }
    }
    
}



void computeRunTimeLoads()
{
    
    foreach (ref group; runTimeLoads) {
        group.resultantForce = Vector3(0.0, 0.0, 0.0);
        group.resultantMoment = Vector3(0.0, 0.0, 0.0);
        foreach (blkNbndry; group.surfaces) {
            auto iblk = blkNbndry[0];
            auto ibndry = blkNbndry[1];
            foreach (iface, face; globalFluidBlocks[iblk].bc[ibndry].faces) {
                FlowState fs = face.fs;
                FlowGradients grad = face.grad;
                // iface orientation
                number nx = face.n.x; number ny = face.n.y; number nz = face.n.z;
                number t1x = face.t1.x; number t1y = face.t1.y; number t1z = face.t1.z;
                number t2x = face.t2.x; number t2y = face.t2.y; number t2z = face.t2.z;
                // iface properties
                number mu_wall = fs.gas.mu;
                number p = fs.gas.p;
                number area = face.area[0];
                number pdA = p * area;
                int outsign = globalFluidBlocks[iblk].bc[ibndry].outsigns[iface];
                Vector3 pressureForce = Vector3(pdA * nx * outsign,
                                                pdA * ny * outsign,
                                                pdA * nz * outsign);
                Vector3 momentArm = face.pos - group.momentCentre;
                Vector3 momentContrib = cross(momentArm, pressureForce);

                group.resultantForce.refx += pressureForce.x;
                group.resultantForce.refy += pressureForce.y;
                group.resultantForce.refz += pressureForce.z;

                group.resultantMoment.refx += momentContrib.x;
                group.resultantMoment.refy += momentContrib.y;
                group.resultantMoment.refz += momentContrib.z;

                if (GlobalConfig.viscous) {
                    Vector3 shearForce = Vector3(face.F.momentum.x * area * outsign,
                                                 face.F.momentum.y * area * outsign,
                                                 face.F.momentum.z * area * outsign);
                    momentContrib = cross(momentArm, shearForce);

                    group.resultantForce.refx += shearForce.x;
                    group.resultantForce.refy += shearForce.y;
                    group.resultantForce.refz += shearForce.z;

                    group.resultantMoment.refx += momentContrib.x;
                    group.resultantMoment.refy += momentContrib.y;
                    group.resultantMoment.refz += momentContrib.z;
                }
            }
        }
    }
}

                

                

                

                

