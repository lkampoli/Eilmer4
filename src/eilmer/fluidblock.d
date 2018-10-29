// fluidblock.d
// Base class for blocks of cells, for use within the Eilmer flow solver.
// Peter J. 2014-07-18 first cut.

module fluidblock;

import std.conv;
import std.stdio;
import std.math;
import std.json;
import util.lua;
import nm.complex;
import nm.number;
import nm.bbla;
import nm.smla;
import util.lua_service;
import gas.luagas_model;
import geom;
import gas;
import kinetics;
import globalconfig;
import globaldata;
import fvcore;
import flowstate;
import fvvertex;
import fvinterface;
import fvcell;
import flowgradients;
import bc;
import user_defined_source_terms;
import conservedquantities;
import lua_helper;
import grid_motion;
import grid_deform;

// To distinguish ghost cells from active cells, we start their id values at
// an arbitrarily high value.  It seem high to me (PJ) but feel free to adjust it
// if you start using grids larger I expect.
enum ghost_cell_start_id = 1_000_000_000;


// The flow solver handles structured- and unstructured-grid blocks via this base class.
// Mostly, we view the block as an unstructured bag of cells because that requires least
// knowledge in the calling code.
class FluidBlock {
public:
    int id; // block identifier: assumed to be the same as the block number.
    Grid_t grid_type; // structured or unstructured
    string label;
    LocalConfig myConfig;
    lua_State* myL;
    //
    bool active; // if true, block participates in the time integration
    // The active flag is used principally for the block-marching calculation,
    // where we want to integrate a few blocks at a time.
    //
    double omegaz; // Angular velocity (in rad/s) of the rotating frame.
                   // There is only one component, about the z-axis.
    number mass_residual, energy_residual; // monitor these for steady state
    Vector3 mass_residual_loc, energy_residual_loc; // locations of worst case
    ConservedQuantities Linf_residuals;
    number c_h, divB_damping_length; //divergence cleaning parameters for MHD
    int mncell;                 // number of monitor cells
    number[] initial_T_value; // for monitor cells to check against
    //
    // Collections of cells, vertices and faces are held as arrays of references.
    // These allow us to conveniently work through the items via foreach statements.
    FVCell[] cells;
    FVInterface[] faces;
    FVVertex[] vertices;
    BoundaryCondition[] bc; // collection of references to the boundary conditions
    //
    // We need to know the number of cells even if the grid is not read
    // for this block in the local process.
    size_t ncells_expected;
    size_t globalCellIdStart = 0; // needed to compute globalCellId
    //
    // Sometimes we need to look up cells and faces that are attached to a vertex.
    size_t[][] cellIndexListPerVertex;
    size_t[][] faceIndexListPerVertex;
    //
    // Work-space that gets reused.
    // The following objects are used in the convective_flux method.
    FlowState Lft;
    FlowState Rght;

    // list of vertex id's that makeup the fluidblock boundary
    // (used in the grid deformation methods in conjunction with
    // the shape sensitivity calculator).
    size_t[] boundaryVtxIndexList;

    // Shape sensitivity calculator workspace.
    version(shape_sensitivity) {
        immutable size_t MAX_PERTURBED_INTERFACES = 200;
        FVCell cellSave;
        FVInterface[MAX_PERTURBED_INTERFACES] ifaceP;

        // local objective function evaluation
        number locObjFcn;
        // arrays used to temporarily store data during construction of the flow Jacobian transpose 
        number[][] aa;
        size_t[][] ja;
        // local effects matrix for flow Jacobian transpose.
        // dimensions: [# local cells x # primitive vars] X [# local cells x # primitive vars]
        SMatrix!number JlocT;
        // external effects matrix for flow Jacobian transpose.
        // dimensions: [# local boundary cells x # primitive vars] X [# global cells x # primitive vars]
        SMatrix!number JextT;
        // Matrix used in preconditioning (low order, local, flow Jacobian).
        SMatrix!number P;
        // objective function senstivity w.r.t primitive variables
        number[] f;
        // adjoint variables
        number[] psi;
        // residual sensitivity w.r.t. design variables (transposed)
        Matrix!number rT;           
        // local dot product of the residual sensitivity w.r.t. design variables (transposed) with the adjoint variables
        number[] rTdotPsi;
        // These arrays and matrices are directly tied to using the
        // GMRES iterative solver (use some directly from steady-state solver).
        number[] Z, z, wext, zext;
    }
    
    version(steady_state)
    {
    // Work-space for steady-state solver
    // These arrays and matrices are directly tied to using the
    // GMRES iterative solver.
    SMatrix!number JcT; // transposed Jacobian (w.r.t conserved variables)
    SMatrix!number Jc; // Jacobian (w.r.t conserved variables)
    ConservedQuantities maxRate, residuals;
    double normAcc, dotAcc;
    size_t nvars;
    Matrix!number Minv;
    number[] FU, dU, Dinv, r0, x0;
    number[] v, w, zed;
    number[] g0, g1;
    Matrix!number Q1;
    Matrix!number V;
    }

    this(int id, Grid_t grid_type, size_t ncells, string label)
    {
        this.id = id;
        this.grid_type = grid_type;
        this.ncells_expected = ncells;
        this.label = label;
        myConfig = dedicatedConfig[id];
        Linf_residuals = new ConservedQuantities(dedicatedConfig[id].gmodel.n_species,
                                                 dedicatedConfig[id].gmodel.n_modes);
        // Workspace for flux_calc method.
        Lft = new FlowState(dedicatedConfig[id].gmodel);
        Rght = new FlowState(dedicatedConfig[id].gmodel);
        // Lua interpreter for the block. 
        // It will be available for computing user-defined source terms.
        myL = luaL_newstate();
        luaL_openlibs(myL);
        registerGasModel(myL, LUA_GLOBALSINDEX);
        lua_pushinteger(myL, id);
        lua_setglobal(myL, "blkId");
        pushObj!(GasModel, GasModelMT)(myL, dedicatedConfig[id].gmodel);
        lua_setglobal(myL, "gmodel");
        lua_pushinteger(myL, dedicatedConfig[id].gmodel.n_species);
        lua_setglobal(myL, "n_species");
        lua_pushinteger(myL, dedicatedConfig[id].gmodel.n_modes);
        lua_setglobal(myL, "n_modes");
        // Although we make the helper functions available within 
        // the block-specific Lua interpreter, we should use 
        // those functions only in the context of the master thread.
        setSampleHelperFunctions(myL);
        setGridMotionHelperFunctions(myL);
    }

    ~this()
    {
        lua_close(myL);
    }

    override string toString() const { return "Block(id=" ~ to!string(id) ~ ")"; }
    @nogc size_t globalCellId(size_t localCellId) { return globalCellIdStart + localCellId; }

    @nogc abstract int get_interpolation_order();
    @nogc abstract void set_interpolation_order(int order);
    abstract void init_lua_globals();
    abstract void init_boundary_conditions(JSONValue json_data);
    @nogc abstract ref FVCell get_cell(size_t i, size_t j, size_t k=0);
    @nogc abstract ref FVInterface get_ifi(size_t i, size_t j, size_t k=0);
    @nogc abstract ref FVInterface get_ifj(size_t i, size_t j, size_t k=0);
    @nogc abstract ref FVInterface get_ifk(size_t i, size_t j, size_t k=0);
    @nogc abstract ref FVVertex get_vtx(size_t i, size_t j, size_t k=0);
    abstract void find_enclosing_cell(ref const(Vector3) p, ref size_t indx, ref bool found);
    abstract void init_grid_and_flow_arrays(string gridFileName);
    abstract void compute_primary_cell_geometric_data(size_t gtl);
    abstract void compute_least_squares_setup(size_t gtl);
    abstract void sync_vertices_from_underlying_grid(size_t gtl=0);
    abstract void sync_vertices_to_underlying_grid(size_t gtl=0);
    abstract void read_new_underlying_grid(string fileName);
    abstract void write_underlying_grid(string fileName);
    abstract double read_solution(string filename, bool overwrite_geometry_data);
    abstract void write_solution(string filename, double sim_time);
    abstract void propagate_inflow_data_west_to_east();
    abstract void convective_flux_phase0(bool allow_high_order_interpolation, size_t gtl=0);
    abstract void convective_flux_phase1(bool allow_high_order_interpolation, size_t gtl=0);
    
    void identify_reaction_zones(int gtl)
    // Set the reactions-allowed flag for cells in this block.
    {
        size_t total_cells_in_reaction_zones = 0;
        size_t total_cells = 0;
        foreach(cell; cells) {
            if ( myConfig.reaction_zones.length > 0 ) {
                cell.fr_reactions_allowed = false;
                foreach(rz; myConfig.reaction_zones) {
                    if ( rz.is_inside(cell.pos[gtl], myConfig.dimensions) ) {
                        cell.fr_reactions_allowed = true;
                    }
                } // foreach rz
            } else {
                cell.fr_reactions_allowed = true;
            }
            total_cells_in_reaction_zones += (cell.fr_reactions_allowed ? 1: 0);
            total_cells += 1;
        } // foreach cell
        if ( myConfig.reacting && myConfig.verbosity_level >= 2 ) {
            writeln("identify_reaction_zones(): block ", id,
                    " cells inside zones = ", total_cells_in_reaction_zones, 
                    " out of ", total_cells);
            if ( myConfig.reaction_zones.length == 0 ) {
                writeln("Note that for no user-specified zones,",
                        " the whole domain is allowed to be reacting.");
            }
        }
    } // end identify_reaction_zones()

    void identify_turbulent_zones(int gtl)
    // Set the in-turbulent-zone flag for cells in this block.
    {
        size_t total_cells_in_turbulent_zones = 0;
        size_t total_cells = 0;
        foreach(cell; cells) {
            if ( myConfig.turbulent_zones.length > 0 ) {
                cell.in_turbulent_zone = false;
                foreach(tz; myConfig.turbulent_zones) {
                    if ( tz.is_inside(cell.pos[gtl], myConfig.dimensions) ) {
                        cell.in_turbulent_zone = true;
                    }
                } // foreach tz
            } else {
                cell.in_turbulent_zone = true;
            }
            total_cells_in_turbulent_zones += (cell.in_turbulent_zone ? 1: 0);
            total_cells += 1;
        } // foreach cell
        if ( myConfig.turbulence_model != TurbulenceModel.none && 
             myConfig.verbosity_level >= 2 ) {
            writeln("identify_turbulent_zones(): block ", id,
                    " cells inside zones = ", total_cells_in_turbulent_zones, 
                    " out of ", total_cells);
            if ( myConfig.turbulent_zones.length == 0 ) {
                writeln("Note that for no user-specified zones,",
                        " the whole domain is allowed to be turbulent.");
            }
        }
    } // end identify_turbulent_zones()

    void estimate_turbulence_viscosity()
    {
        final switch (myConfig.turbulence_model) {
        case TurbulenceModel.none:
            foreach (cell; cells) cell.turbulence_viscosity_zero();
            return;
        case TurbulenceModel.baldwin_lomax:
            throw new FlowSolverException("need to port baldwin_lomax_turbulence_model");
        case TurbulenceModel.spalart_allmaras:
            throw new FlowSolverException("Should implement Spalart-Allmaras some day.");
        case TurbulenceModel.k_omega:
            foreach (cell; cells) cell.turbulence_viscosity_k_omega();
            break;

        }
        foreach (cell; cells) {
            cell.turbulence_viscosity_factor(myConfig.transient_mu_t_factor);
            cell.turbulence_viscosity_limit(myConfig.max_mu_t_factor);
            cell.turbulence_viscosity_zero_if_not_in_zone();
        }
    } // end estimate_turbulence_viscosity()

    @nogc
    void set_cell_dt_chem(double dt_chem)
    {
        foreach ( cell; cells ) cell.dt_chem = dt_chem;
    }

    @nogc
    void detect_shock_points()
    // Detects shocks by looking for compression between adjacent cells.
    //
    // The velocity component normal to the cell interfaces
    // is used as the indicating variable.
    {
        // Change in normalised velocity to indicate a shock.
        // A value of -0.05 has been found suitable to detect the levels of
        // shock compression observed in the "sod" and "cone20" test cases.
        // It may need to be tuned for other situations, especially when
        // viscous effects are important.
        double tol = myConfig.compression_tolerance;
        // First, work across interfaces and locate shocks using the (local) normal velocity.
        foreach (iface; faces) {
            auto cL = iface.left_cell;
            auto cR = iface.right_cell;
            if (cL && cR) {
                number uL = geom.dot(cL.fs.vel, iface.n);
                number uR = geom.dot(cR.fs.vel, iface.n);
                number aL = cL.fs.gas.a;
                number aR = cR.fs.gas.a;
                number a_min = (aL < aR) ? aL : aR;
                iface.fs.S = ((uR - uL)/a_min) < tol;
            } else {
                iface.fs.S = 0;
            }
        }
        // Finally, mark cells as shock points if any of their interfaces are shock points.
        foreach (cell; cells) {
            cell.fs.S = false;
            foreach (face; cell.iface) {
                if (face.fs.S) cell.fs.S = true;
            }
        }
    } // end detect_shock_points()

    int count_invalid_cells(int gtl, int ftl)
    // Returns the number of cells that contain invalid data,
    // optionally patching bad cell data as it goes.
    //
    // Since this function may be called at the end of each stage of the gasdynamic update,
    // we must patch the conserved quantities at the appropriate flow-level, as well as
    // patching the flow data.
    //
    // Bad flow data can be identified by the density of internal energy 
    // being on the minimum limit or the velocity being very large.
    // There is also a flag to indicate that the thermo data is dodgy from an earlier
    // call to one of the thermochemical update functions.
    {
        int number_of_invalid_cells = 0;
        foreach(cell; cells) {
            if (cell.data_is_bad || cell.fs.check_data(cell.pos[0], myConfig.flowstate_limits) == false) {
                ++number_of_invalid_cells;
                if (myConfig.report_invalid_cells) {
                    writefln("count_invalid_cells: block_id=%d, cell_id=%d at pos %s\n",
                             id, cell.id, to!string(cell.pos[gtl]));
                    writeln(cell);
                }
                if ( myConfig.adjust_invalid_cell_data ) {
                    // We shall set the cell data to something that
                    // is valid (and self consistent).
                    FlowState[] neighbour_flows;
                    if (myConfig.report_invalid_cells) {
                        writeln("Adjusting cell data to a local average.");
                    }
                    foreach (i; 0 .. cell.iface.length) {
                        auto face = cell.iface[i];
                        auto other_cell = (cell.outsign[i] == 1) ? face.right_cell : face.left_cell;
                        if (other_cell.fs.check_data(other_cell.pos[gtl], myConfig.flowstate_limits))
                            { neighbour_flows ~= other_cell.fs; }
                    }
                    if (neighbour_flows.length == 0) {
                        string msg = "Block::count_invalid_cells(): There were no valid neighbours " ~
                            "to replace flow data in cell.";
                        if (!myConfig.report_invalid_cells) {
                            msg ~= "\nTo get more information, rerun with config.report_invalid_cells=true";
                        }
                        throw new FlowSolverException(msg);
                    }
                    cell.fs.copy_average_values_from(neighbour_flows, myConfig.gmodel);
                    scale_mass_fractions(cell.fs.gas.massf, 0.0, 0.9); // big assertion-error-tolerance
                    cell.data_is_bad = false; // assume that we've fixed it at this point.
                    cell.encode_conserved(gtl, ftl, omegaz);
                    if (0 != cell.decode_conserved(gtl, ftl, omegaz)) {
                        string msg = "Block::count_invalid_cells(): " ~
                            "Tried to replace flow data in cell but it's still bad.";
                        if (!myConfig.report_invalid_cells) {
                            msg ~= "\nTo get more information, rerun with config.report_invalid_cells=true";
                        }
                        throw new FlowSolverException(msg);
                    }
                    if (myConfig.report_invalid_cells) {
                        writefln("after flow-data replacement: block_id = %d, cell pos %.18e,%.18e,%.18e\n",
                                 id, cell.pos[gtl].x, cell.pos[gtl].y, cell.pos[gtl].z);
                        writeln(cell);
                    }
                } // end adjust_invalid_cell_data 
            } // end of if invalid data...
        } // foreach cell
        return number_of_invalid_cells;
    } // end count_invalid_cells()

    @nogc
    void flow_property_spatial_derivatives(int gtl)
    {
        final switch (myConfig.spatial_deriv_locn) {
        case SpatialDerivLocn.vertices:
            if (myConfig.dimensions == 2) {
                final switch (myConfig.spatial_deriv_calc) {
                case SpatialDerivCalc.least_squares:
                    foreach(vtx; vertices) { 
                        vtx.grad.gradients_leastsq(vtx.cloud_fs, vtx.cloud_pos, vtx.ws_grad);
                    }
                    break;
                case SpatialDerivCalc.divergence:
                    foreach(vtx; vertices) {
                        vtx.grad.gradients_xy_div(vtx.cloud_fs, vtx.cloud_pos);
                    }
                } // end switch
            } else {
                // Have only least-squares in 3D.
                foreach(vtx; vertices) {
                    vtx.grad.gradients_leastsq(vtx.cloud_fs, vtx.cloud_pos, vtx.ws_grad);
                }
            }
            foreach (iface; faces) {
                iface.average_vertex_deriv_values();
            }
            break;
        case SpatialDerivLocn.faces:
            if (myConfig.dimensions == 2) {
                final switch (myConfig.spatial_deriv_calc) {
                case SpatialDerivCalc.least_squares:
                    foreach(iface; faces) { 
                        iface.grad.gradients_leastsq(iface.cloud_fs, iface.cloud_pos, iface.ws_grad);
                    }
                    break;
                case SpatialDerivCalc.divergence:
                    foreach(iface; faces) {
                        iface.grad.gradients_xy_div(iface.cloud_fs, iface.cloud_pos);
                    }
                } // end switch
            } else { //3D
                final switch (myConfig.spatial_deriv_calc) {
                case SpatialDerivCalc.least_squares:
                    foreach(iface; faces) {
                        iface.grad.gradients_leastsq(iface.cloud_fs, iface.cloud_pos, iface.ws_grad);
                    }
                    break;
                case SpatialDerivCalc.divergence:
                    foreach(iface; faces) {
                        assert(0, "divergence thereom not implemented for 3D");
                    }
                } // end switch
            } // end if (myConfig.dimensions)
        } // end switch (myConfig.spatial_deriv_locn)
    } // end flow_property_spatial_derivatives()
    
    @nogc
    void clear_fluxes_of_conserved_quantities()
    {
        foreach (iface; faces) { iface.F.clear(); }
    }

    void viscous_flux()
    {
        foreach (iface; faces) { iface.viscous_flux_calc(); } 
    }

    @nogc
    void init_residuals()
    // Initialization of data for later computing residuals.
    {
        mass_residual = 0.0;
        mass_residual_loc.clear();
        energy_residual = 0.0;
        energy_residual_loc.clear();
        foreach(FVCell cell; cells) {
            cell.rho_at_start_of_step = cell.fs.gas.rho;
            cell.rE_at_start_of_step = cell.U[0].total_energy;
        }
    } // end init_residuals()

    @nogc
    void compute_residuals(int gtl)
    // Compute the residuals using previously stored data.
    //
    // The largest residual of density for all cells was the traditional way
    // mbcns/Elmer estimated the approach to steady state.
    // However, with the splitting up of the increments for different physical
    // processes, this residual calculation code needed a bit of an update.
    // Noting that the viscous-stress, chemical and radiation increments
    // do not affect the mass within a cell, we now compute the residuals 
    // for both mass and (total) energy for all cells, the record the largest
    // with their location. 
    {
        mass_residual = 0.0;
        mass_residual_loc.clear();
        energy_residual = 0.0;
        energy_residual_loc.clear();
        foreach(FVCell cell; cells) {
            number local_residual = (cell.fs.gas.rho - cell.rho_at_start_of_step) / cell.fs.gas.rho;
            local_residual = fabs(local_residual);
            if ( local_residual > mass_residual ) {
                mass_residual = local_residual;
                mass_residual_loc.set(cell.pos[gtl]);
            }
            // In the following line, the zero index is used because,
            // at the end of the gas-dynamic update, that index holds
            // the updated data.
            local_residual = (cell.U[0].total_energy - cell.rE_at_start_of_step) / cell.U[0].total_energy;
            local_residual = fabs(local_residual);
            if ( local_residual > energy_residual ) {
                energy_residual = local_residual;
                energy_residual_loc.set(cell.pos[gtl]);
            }
        } // for cell
    } // end compute_residuals()

    @nogc
    void compute_Linf_residuals()
    // Compute Linf residuals for conserved quantities.
    // This is similar to the calculation above of
    // residual, but this differs by a factor of the timestep size
    // because here the residual is taken as R(U) = dU/dt.
    // We will assume that dUdt[0] is up-to-date.
    {
        Linf_residuals.copy_values_from(cells[0].dUdt[0]);
        Linf_residuals.mass = fabs(Linf_residuals.mass);
        Linf_residuals.momentum.set(fabs(Linf_residuals.momentum.x),
                                    fabs(Linf_residuals.momentum.y),
                                    fabs(Linf_residuals.momentum.z));
        Linf_residuals.total_energy = fabs(Linf_residuals.total_energy);
        foreach (cell; cells) {
            Linf_residuals.mass = fmax(Linf_residuals.mass, fabs(cell.dUdt[0].mass));
            Linf_residuals.momentum.set(fmax(Linf_residuals.momentum.x, fabs(cell.dUdt[0].momentum.x)),
                                        fmax(Linf_residuals.momentum.y, fabs(cell.dUdt[0].momentum.y)),
                                        fmax(Linf_residuals.momentum.z, fabs(cell.dUdt[0].momentum.z)));
            Linf_residuals.total_energy = fmax(Linf_residuals.total_energy, fabs(cell.dUdt[0].total_energy));
        }
    } // end compute_Linf_residuals()

    @nogc
    void residual_smoothing_dUdt(size_t ftl)
    {
        assert(ftl < cells[0].dUdt.length, "inconsistent flow time level and allocated dUdt");
        foreach (c; cells) {
            c.dUdt_copy.copy_values_from(c.dUdt[ftl]);
        }
        double eps = myConfig.residual_smoothing_weight;
        foreach (c; cells) {
            double total = 1.0;
            foreach (i, f; c.iface) {
                total += eps;
                auto other_cell = (c.outsign[i] > 0.0) ? f.right_cell : f.left_cell;
                if (other_cell && other_cell.is_interior) {
                    c.dUdt[ftl].add(other_cell.dUdt_copy, eps);
                }
            }
            c.dUdt[ftl].scale(1.0/total);
        }
    } // end residual_smoothing_dUdt()
    
    double update_c_h(double dt_current)
    // Update the c_h value for the divergence cleaning mechanism.
    {
        double min_L_for_block, cfl_local, cfl_max;
        bool first = true;
        foreach(FVCell cell; cells) {
            // Search for the minimum length scale and the maximum CFL value in the block.
            if (first) {
                min_L_for_block = cell.L_min.re;
                cfl_local = cell.signal_frequency() * dt_current;
                cfl_max = cfl_local;
                first = false;
            } else {
                min_L_for_block = fmin(cell.L_min.re, min_L_for_block);
                cfl_local = cell.signal_frequency() * dt_current;
                cfl_max = fmax(cfl_local, cfl_max);
            }
        }
        return cfl_max * min_L_for_block / dt_current;
    } // end update_c_h()

    double determine_time_step_size(double dt_current, bool check_cfl)
    // Compute the local time step limit for all cells in the block.
    // The overall time step is limited by the worst-case cell.
    {
        double cfl_value = GlobalConfig.cfl_value;
        double dt_local;
        double cfl_local;
        double signal;
        double cfl_allow; // allowable CFL number, t_order dependent
        double dt_allow;
        double cfl_min, cfl_max;
        // The following limits allow the simulation of the sod shock tube
        // to get just a little wobbly around the shock.
        // Lower values of cfl should be used for a smooth solution.
        switch (number_of_stages_for_update_scheme(myConfig.gasdynamic_update_scheme)) {
        case 1: cfl_allow = 0.9; break;
        case 2: cfl_allow = 1.2; break;
        case 3: cfl_allow = 1.6; break;
        default: cfl_allow = 0.9;
        }
        bool first = true;
        foreach(FVCell cell; cells) {
            signal = cell.signal_frequency();
            cfl_local = dt_current * signal; // Current (Local) CFL number
            dt_local = cfl_value / signal; // Recommend a time step size.
            if (first) {
                cfl_min = cfl_local;
                cfl_max = cfl_local;
                dt_allow = dt_local;
                first = false;
            } else {
                cfl_min = fmin(cfl_min, cfl_local);
                cfl_max = fmax(cfl_max, cfl_local);
                dt_allow = fmin(dt_allow, dt_local);
            }
        } // foreach cell
        if (check_cfl && (cfl_max < 0.0 || cfl_max > cfl_allow)) {
            string msg = text("Bad cfl number encountered cfl_max=", cfl_max,
                              " for FluidBlock ", id);
            throw new FlowSolverException(msg);
        }
        return dt_allow;
    } // end determine_time_step_size()

    void applyPreReconAction(double t, int gtl, int ftl)
    {
        foreach(boundary; bc) { boundary.applyPreReconAction(t, gtl, ftl); }
    }

    void applyPostConvFluxAction(double t, int gtl, int ftl)
    {
        foreach(boundary; bc) { boundary.applyPostConvFluxAction(t, gtl, ftl); }
    }

    void applyPreSpatialDerivActionAtBndryFaces(double t, int gtl, int ftl)
    {
        foreach(boundary; bc) { boundary.applyPreSpatialDerivActionAtBndryFaces(t, gtl, ftl); }
    }

    void applyPreSpatialDerivActionAtBndryCells(double t, int gtl, int ftl)
    {
        foreach(boundary; bc) { boundary.applyPreSpatialDerivActionAtBndryCells(t, gtl, ftl); }
    }

    void applyPostDiffFluxAction(double t, int gtl, int ftl)
    {
        foreach(boundary; bc) { boundary.applyPostDiffFluxAction(t, gtl, ftl); }
    }

    version(steady_state) {
    void allocate_GMRES_workspace()
    {
        size_t nConserved = nConservedQuantities;
        int n_species = GlobalConfig.gmodel_master.n_species();
        int n_modes = GlobalConfig.gmodel_master.n_modes();
        maxRate = new ConservedQuantities(n_species, n_modes);
        residuals = new ConservedQuantities(n_species, n_modes);

        size_t mOuter = to!size_t(GlobalConfig.sssOptions.maxOuterIterations);
        size_t mInner = to!size_t(GlobalConfig.sssOptions.nInnerIterations);
        size_t n = nConserved*cells.length;
        nvars = n;
        // Now allocate arrays and matrices
        FU.length = n;
        dU.length = n; dU[] = to!number(0.0);
        r0.length = n;
        x0.length = n;
        Dinv.length = n;
        v.length = n;
        w.length = n;
        zed.length = n;
        g0.length = mOuter+1;
        g1.length = mOuter+1;
        //h_outer.length = mOuter+1;
        //hR_outer.length = mOuter+1;
        V = new Matrix!number(n, mOuter+1);
        //H0_outer = new Matrix!number(mOuter+1, mOuter);
        //H1_outer = new Matrix!number(mOuter+1, mOuter);
        //Gamma_outer = new Matrix!number(mOuter+1, mOuter+1);
        //Q0_outer = new Matrix!number(mOuter+1, mOuter+1);
        Q1 = new Matrix!number(mOuter+1, mOuter+1);
    }
    }
} // end class FluidBlock
