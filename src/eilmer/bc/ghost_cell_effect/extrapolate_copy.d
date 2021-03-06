// extrapolate_copy.d

module bc.ghost_cell_effect.extrapolate_copy;

import std.json;
import std.string;
import std.conv;
import std.stdio;
import std.math;

import geom;
import globalconfig;
import globaldata;
import flowstate;
import fvcore;
import fvinterface;
import fvcell;
import fluidblock;
import sfluidblock;
import gas;
import bc;


class GhostCellExtrapolateCopy : GhostCellEffect {
public:
    int xOrder;
    
    this(int id, int boundary, int x_order)
    {
        super(id, boundary, "ExtrapolateCopy");
        xOrder = x_order;
    }

    override string toString() const 
    {
        return "ExtrapolateCopy(x_order=" ~ to!string(xOrder) ~ ")";
    }

    @nogc
    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        FVCell src_cell, ghost0;
        BoundaryCondition bc = blk.bc[which_boundary];
	if (bc.outsigns[f.i_bndry] == 1) {
	    src_cell = f.left_cell;
	    ghost0 = f.right_cell;
	} else {
	    src_cell = f.right_cell;
	    ghost0 = f.left_cell;
	}
	if (xOrder == 1) {
	    throw new Error("First order extrapolation not implemented.");
	} else {
	    // Zero-order extrapolation.
	    ghost0.fs.copy_values_from(src_cell.fs);
	}
    } // end apply_unstructured_grid()

    @nogc
    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        FVCell src_cell, ghost0;
        BoundaryCondition bc = blk.bc[which_boundary];
        foreach (i, f; bc.faces) {
            if (bc.outsigns[i] == 1) {
                src_cell = f.left_cell;
                ghost0 = f.right_cell;
            } else {
                src_cell = f.right_cell;
                ghost0 = f.left_cell;
            }
            if (xOrder == 1) {
                throw new Error("First order extrapolation not implemented.");
            } else {
                // Zero-order extrapolation.
                ghost0.fs.copy_values_from(src_cell.fs);
            }
        } // end foreach face
    } // end apply_unstructured_grid()

    @nogc
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        // Fill ghost cells with data from just inside the boundary
        // using zero-order extrapolation (i.e. just copy the data).
        // We assume that this boundary is an outflow boundary.
        size_t i, j, k;
        FVCell src_cell, dest_cell;
        FVCell cell_1, cell_2;
        auto gmodel = blk.myConfig.gmodel;
        size_t nsp = blk.myConfig.n_species;
        size_t nmodes = blk.myConfig.n_modes;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");
        bool nghost3 = (blk.n_ghost_cell_layers == 3);

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    if (xOrder == 1) {
                        //  |--- [2] ---|--- [1] ---|||--- [dest] ---|---[ghost cell 2]----
                        //      (j-1)        (j)           (j+1)
                        //  dest: ghost cell 1
                        //  [1]: first interior cell
                        //  [2]: second interior cell
                        // This extrapolation assumes that cell-spacing between
                        // cells 1 and 2 continues on in the exterior
                        cell_1 = blk.get_cell(i,j,k);
                        cell_2 = blk.get_cell(i,j-1,k);
                        dest_cell = blk.get_cell(i,j+1,k);
                        // Extrapolate on primitive variables
                        // 1. First exterior point
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        // 2. Second exterior point
                        //  |---[2]---|||---[1]---|---[dest]------
                        //      (j)        (j+1)       (j+2)
                        cell_2 = cell_1;
                        cell_1 = dest_cell;
                        dest_cell = blk.get_cell(i,j+2,k);
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        if (nghost3) {
                            // FIX-ME just a fudge for now, PJ 2019-09-28
                            dest_cell = blk.get_cell(i,j+3,k);
                            src_cell = blk.get_cell(i,j+2,k);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    } else {
                        // Zero-order extrapolation
                        src_cell = blk.get_cell(i,j,k);
                        dest_cell = blk.get_cell(i,j+1,k);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        dest_cell = blk.get_cell(i,j+2,k);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        if (nghost3) {
                            dest_cell = blk.get_cell(i,j+3,k);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    } 
                } // end i loop
            } // for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    if (xOrder == 1) {
                        //  |--- [2] ---|--- [1] ---|||--- [dest] ---|---[ghost cell 2]----
                        //      (i-1)        (i)           (i+1)
                        //  dest: ghost cell 1
                        //  [1]: first interior cell
                        //  [2]: second interior cell
                        // This extrapolation assumes that cell-spacing between
                        // cells 1 and 2 continues on in the exterior
                        cell_1 = blk.get_cell(i,j,k);
                        cell_2 = blk.get_cell(i-1,j,k);
                        dest_cell = blk.get_cell(i+1,j,k);
                        // Extrapolate on primitive variables
                        // 1. First exterior point
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        // 2. Second exterior point
                        //  |---[2]---|||---[1]---|---[dest]------
                        //      (i)        (i+1)       (i+2)
                        cell_2 = cell_1;
                        cell_1 = dest_cell;
                        dest_cell = blk.get_cell(i+2,j,k);
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        if (nghost3) {
                            // FIX-ME just a fudge for now, PJ 2019-09-28
                            dest_cell = blk.get_cell(i+3,j,k);
                            src_cell = blk.get_cell(i+2,j,k);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    }
                    else {
                        src_cell = blk.get_cell(i,j,k);
                        dest_cell = blk.get_cell(i+1,j,k);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        dest_cell = blk.get_cell(i+2,j,k);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        if (nghost3) {
                            dest_cell = blk.get_cell(i+3,j,k);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    }
                } // end j loop
            } // for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    if (xOrder == 1) {
                        //  |--- [2] ---|--- [1] ---|||--- [dest] ---|---[ghost cell 2]----
                        //      (j+1)        (j)           (j-1)
                        //  dest: ghost cell 1
                        //  [1]: first interior cell
                        //  [2]: second interior cell
                        // This extrapolation assumes that cell-spacing between
                        // cells 1 and 2 continues on in the exterior
                        cell_1 = blk.get_cell(i,j,k);
                        cell_2 = blk.get_cell(i,j+1,k);
                        dest_cell = blk.get_cell(i,j-1,k);
                        // Extrapolate on primitive variables
                        // 1. First exterior point
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        // 2. Second exterior point
                        //  |---[2]---|||---[1]---|---[dest]------
                        //      (j)        (j-1)       (j-2)
                        cell_2 = cell_1;
                        cell_1 = dest_cell;
                        dest_cell = blk.get_cell(i,j-2,k);
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        if (nghost3) {
                            // FIX-ME just a fudge for now, PJ 2019-09-28
                            dest_cell = blk.get_cell(i,j-3,k);
                            src_cell = blk.get_cell(i,j-2,k);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    } else {
                        src_cell = blk.get_cell(i,j,k);
                        dest_cell = blk.get_cell(i,j-1,k);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        dest_cell = blk.get_cell(i,j-2,k);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        if (nghost3) {
                            dest_cell = blk.get_cell(i,j-3,k);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    }
                } // end i loop
            } // for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    if (xOrder == 1) {
                        //  ---[ghost cell 2]---|--- [dest] ---|||--- [1] ---|---[2]----
                        //      (i-2)                 (i-1)           (i)       (i+1)
                        //  dest: ghost cell 1
                        //  [1]: first interior cell
                        //  [2]: second interior cell
                        // This extrapolation assumes that cell-spacing between
                        // cells 1 and 2 continues on in the exterior
                        cell_1 = blk.get_cell(i,j,k);
                        cell_2 = blk.get_cell(i+1,j,k);
                        dest_cell = blk.get_cell(i-1,j,k);
                        // Extrapolate on primitive variables
                        // 1. First exterior point
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        // 2. Second exterior point
                        //  |---[dest]---|---[1]---|||---[2]---|------|
                        //       (i-2)       (i-1)       (i)
                        cell_2 = cell_1;
                        cell_1 = dest_cell;
                        dest_cell = blk.get_cell(i-2,j,k);
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        if (nghost3) {
                            // FIX-ME just a fudge for now, PJ 2019-09-28
                            dest_cell = blk.get_cell(i-3,j,k);
                            src_cell = blk.get_cell(i-2,j,k);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    } else {
                        // Zero-order extrapolation
                        src_cell = blk.get_cell(i,j,k);
                        dest_cell = blk.get_cell(i-1,j,k);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        dest_cell = blk.get_cell(i-2,j,k);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        if (nghost3) {
                            dest_cell = blk.get_cell(i-3,j,k);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    }
                } // end j loop
            } // for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    if (xOrder == 1) {
                        //  |--- [2] ---|--- [1] ---|||--- [dest] ---|---[ghost cell 2]----
                        //      (k-1)        (k)           (k+1)
                        //  dest: ghost cell 1
                        //  [1]: first interior cell
                        //  [2]: second interior cell
                        // This extrapolation assumes that cell-spacing between
                        // cells 1 and 2 continues on in the exterior
                        cell_1 = blk.get_cell(i,j,k);
                        cell_2 = blk.get_cell(i,j,k-1);
                        dest_cell = blk.get_cell(i,j,k+1);
                        // Extrapolate on primitive variables
                        // 1. First exterior point
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        // 2. Second exterior point
                        //  |---[2]---|||---[1]---|---[dest]------
                        //      (k)        (k+1)       (k+2)
                        cell_2 = cell_1;
                        cell_1 = dest_cell;
                        dest_cell = blk.get_cell(i,j,k+2);
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        if (nghost3) {
                            // FIX-ME just a fudge for now, PJ 2019-09-28
                            dest_cell = blk.get_cell(i,j,k+3);
                            src_cell = blk.get_cell(i,j,k+2);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    } else {
                        // Zero-order extrapolation
                        src_cell = blk.get_cell(i,j,k);
                        dest_cell = blk.get_cell(i,j,k+1);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        dest_cell = blk.get_cell(i,j,k+2);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        if (nghost3) {
                            dest_cell = blk.get_cell(i,j,k+3);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    }
                } // end j loop
            } // for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    if (xOrder == 1) {
                        //  |--- [2] ---|--- [1] ---|||--- [dest] ---|---[ghost cell 2]----
                        //      (k+1)        (k)           (k-1)
                        //  dest: ghost cell 1
                        //  [1]: first interior cell
                        //  [2]: second interior cell
                        // This extrapolation assumes that cell-spacing between
                        // cells 1 and 2 continues on in the exterior
                        cell_1 = blk.get_cell(i,j,k);
                        cell_2 = blk.get_cell(i,j,k+2);
                        dest_cell = blk.get_cell(i,j,k-1);
                        // Extrapolate on primitive variables
                        // 1. First exterior point
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if ( nsp > 1 ) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        // 2. Second exterior point
                        //  |---[2]---|||---[1]---|---[dest]------
                        //      (k)        (k-1)       (k-2)
                        cell_2 = cell_1;
                        cell_1 = dest_cell;
                        dest_cell = blk.get_cell(i,j,k-2);
                        dest_cell.fs.gas.rho = 2.0*cell_1.fs.gas.rho - cell_2.fs.gas.rho;
                        dest_cell.fs.gas.u = 2.0*cell_1.fs.gas.u - cell_2.fs.gas.u;
                        version(multi_T_gas) {
                            for ( size_t imode = 0; imode < nmodes; ++imode ) {
                                dest_cell.fs.gas.u_modes[imode] = 2.0*cell_1.fs.gas.u_modes[imode] - cell_2.fs.gas.u_modes[imode];
                            }
                        }
                        version(multi_species_gas) {
                            if (nsp > 1) {
                                for ( size_t isp = 0; isp < nsp; ++isp ) {
                                    dest_cell.fs.gas.massf[isp] = 2.0*cell_1.fs.gas.massf[isp] - cell_2.fs.gas.massf[isp];
                                }
                                scale_mass_fractions(dest_cell.fs.gas.massf);
                            } else {
                                dest_cell.fs.gas.massf[0] = 1.0;
                            }
                        }
                        gmodel.update_thermo_from_rhou(dest_cell.fs.gas);
                        dest_cell.fs.vel.refx = 2.0*cell_1.fs.vel.x - cell_2.fs.vel.x;
                        dest_cell.fs.vel.refy = 2.0*cell_1.fs.vel.y - cell_2.fs.vel.y;
                        dest_cell.fs.vel.refz = 2.0*cell_1.fs.vel.z - cell_2.fs.vel.z;
                        version(MHD) {
                            dest_cell.fs.B.refx = 2.0*cell_1.fs.B.x - cell_2.fs.B.x;
                            dest_cell.fs.B.refy = 2.0*cell_1.fs.B.y - cell_2.fs.B.y;
                            dest_cell.fs.B.refz = 2.0*cell_1.fs.B.z - cell_2.fs.B.z;
                        }
                        version(komega) {
                            dest_cell.fs.turb[0] = 2.0*cell_1.fs.turb[0] - cell_2.fs.turb[0];
                            dest_cell.fs.turb[1] = 2.0*cell_1.fs.turb[1] - cell_2.fs.turb[1];
                        }
                        dest_cell.fs.mu_t = 2.0*cell_1.fs.mu_t - cell_2.fs.mu_t;
                        dest_cell.fs.k_t = 2.0*cell_1.fs.k_t - cell_2.fs.k_t;
                        if (nghost3) {
                            // FIX-ME just a fudge for now, PJ 2019-09-28
                            dest_cell = blk.get_cell(i,j,k-3);
                            src_cell = blk.get_cell(i,j,k-2);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    } else {
                        src_cell = blk.get_cell(i,j,k);
                        dest_cell = blk.get_cell(i,j,k-1);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        dest_cell = blk.get_cell(i,j,k-2);
                        dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        if (nghost3) {
                            dest_cell = blk.get_cell(i,j,k-3);
                            dest_cell.copy_values_from(src_cell, CopyDataOption.minimal_flow);
                        }
                    }
                } // end j loop
            } // for i
            break;
        } // end switch
    } // end apply_structured_grid()
} // end class GhostCellExtrapolateCopy
