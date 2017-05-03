/**
 * fvinterface.d
 * Finite-volume cell-interface class, for use in the CFD codes.
 * Fluxes of conserved quantities are transported (between cells) across cell interfaces.

 * Author: Peter J. and Rowan G.
 * Version: 2014-07-17: initial cut, to explore options.
 *          2015-02-13: Keep an eye on the future of the moving_grid option.
 *          2015-05-04: keep references to adjoining cells and defining vertices.
 */

module fvinterface;

import std.conv;
import std.format;
import geom;
import gas;
import fvcore;
import fvvertex;
import fvcell;
import flowstate;
import flowgradients;
import conservedquantities;
import globalconfig;
import lsqinterp;

class FVInterface {
public:
    size_t id;  // allows us to work out where, in the block, the interface is
    bool is_on_boundary = false;  // by default, assume not on boundary
    size_t bc_id;  // if the face is on a block boundary, which one
    //
    // Geometry
    Vector3 pos;           // position of the (approx) midpoint
    Vector3 gvel;          // grid velocity at interface, m/s
    double Ybar;           // Y-coordinate of the mid-point
    double length;         // Interface length in the x,y-plane
    double[] area;         // Area m**2 for each grid-time-level.
                           // Area per radian in axisymmetric geometry
    Vector3 n;             // Direction cosines for unit normal
    Vector3 t1;            // tangent vector 1 (aka p)
    Vector3 t2;            // tangent vector 2 (aka q)
    FVVertex[] vtx;        // references to vertices for line (2D) and quadrilateral (3D) faces
    //
    // Adjoining cells.
    FVCell left_cell;      // interface normal points out of this adjoining cell
    FVCell right_cell;     // interface normal points into this adjoining cell
    //
    // Flow
    FlowState fs;          // Flow properties
    ConservedQuantities F; // Flux conserved quantity per unit area
    //
    // Viscous-flux-related quantities.
    FlowGradients grad;
    WLSQGradWorkspace ws_grad;
    Vector3*[] cloud_pos; // Positions of flow points for gradients calculation.
    FlowState[] cloud_fs; // References to flow states at those points.
    double[] jx; // diffusive mass flux in x
    double[] jy; // diffusive mass flux in y
    double[] jz; // diffusive mass flux in z
    //
    // Rowan's implicit solver workspace.
    version(steadystate) {
    double[][] dFdU_L;
    double[][] dFdU_R;
    }

    this(LocalConfig myConfig,
	 bool allocate_spatial_deriv_lsq_workspace,
	 size_t id_init=0)
    {
	id = id_init;
	area.length = myConfig.n_grid_time_levels;
	gvel = Vector3(0.0,0.0,0.0); // default to fixed grid
	auto gmodel = myConfig.gmodel;
	int n_species = gmodel.n_species;
	int n_modes = gmodel.n_modes;
	double Ttr = 300.0;
	double[] T_modes; foreach(i; 0 .. n_modes) { T_modes ~= 300.0; }
	fs = new FlowState(gmodel, 100.0e3, Ttr, T_modes, Vector3(0.0,0.0,0.0));
	F = new ConservedQuantities(n_species, n_modes);
	F.clear_values();
	grad = new FlowGradients(myConfig);
	if (allocate_spatial_deriv_lsq_workspace) {
	    ws_grad = new WLSQGradWorkspace();
	}
	jx.length = n_species;
	jy.length = n_species;
	jz.length = n_species;
	version(steadystate) {
	dFdU_L.length = 5; // number of conserved variables
	foreach (ref a; dFdU_L) a.length = 5;
	dFdU_R.length = 5;
	foreach (ref a; dFdU_R) a.length = 5;
	}
    }

    this(FVInterface other, GasModel gm)
    {
	id = other.id;
	pos = other.pos;
	gvel = other.gvel;
	Ybar = other.Ybar;
	length = other.length;
	area = other.area.dup;
	n = other.n;
	t1 = other.t1;
	t2 = other.t2;
	fs = new FlowState(other.fs, gm);
	F = new ConservedQuantities(other.F);
	grad = new FlowGradients(other.grad);
	if (other.ws_grad) ws_grad = new WLSQGradWorkspace(other.ws_grad);
	// Because we copy the following pointers and references,
	// we cannot have const (or "in") qualifier on other.
	cloud_pos = other.cloud_pos.dup();
	cloud_fs = other.cloud_fs.dup();
	jx = other.jx.dup();
	jy = other.jy.dup();
	jz = other.jz.dup();
	version(steadystate) {
	dFdU_L.length = 5; // number of conserved variables
	foreach (ref a; dFdU_L) a.length = 5;
	dFdU_R.length = 5;
	foreach (ref a; dFdU_R) a.length = 5;
	}
    }

    @nogc
    void copy_values_from(in FVInterface other, uint type_of_copy)
    {
	switch (type_of_copy) {
	case CopyDataOption.minimal_flow:
	case CopyDataOption.all_flow:
	    fs.copy_values_from(other.fs);
	    F.copy_values_from(other.F);
	    break;
	case CopyDataOption.grid:
	    pos.refx = other.pos.x; pos.refy = other.pos.y; pos.refz = other.pos.z;
	    gvel.refx = other.gvel.x; gvel.refy = other.gvel.y; gvel.refz = other.gvel.z;
	    Ybar = other.Ybar;
	    length = other.length;
	    area[] = other.area[];
	    n.refx = other.n.x; n.refy = other.n.y; n.refz = other.n.z;
	    t1.refx = other.t1.x; t1.refy = other.t1.y; t1.refz = other.t1.z;
	    t2.refx = other.t2.x; t2.refy = other.t2.y; t2.refz = other.t2.z;
	    break;
	case CopyDataOption.all: 
	default:
	    id = other.id;
	    pos.refx = other.pos.x; pos.refy = other.pos.y; pos.refz = other.pos.z;
	    gvel.refx = other.gvel.x; gvel.refy = other.gvel.y; gvel.refz = other.gvel.z;
	    Ybar = other.Ybar;
	    length = other.length;
	    area[] = other.area[];
	    n.refx = other.n.x; n.refy = other.n.y; n.refz = other.n.z;
	    t1.refx = other.t1.x; t1.refy = other.t1.y; t1.refz = other.t1.z;
	    t2.refx = other.t2.x; t2.refy = other.t2.y; t2.refz = other.t2.z;
	    fs.copy_values_from(other.fs);
	    F.copy_values_from(other.F);
	    grad.copy_values_from(other.grad);
	    // omit scratch workspace ws_grad
	} // end switch
    }

    @nogc
    void copy_grid_level_to_level(uint from_level, uint to_level)
    {
	area[to_level] = area[from_level];
    }

    override string toString() const
    {
	char[] repr;
	repr ~= "FVInterface(";
	repr ~= "id=" ~ to!string(id);
	repr ~= ", pos=" ~ to!string(pos);
	repr ~= ", vtx_ids=[";
	foreach (v; vtx) { repr ~= format("%d,", v.id); }
	repr ~= "]";
	repr ~= format(", left_cell_id=%d", left_cell.id);
	repr ~= format(", right_cell_id=%d", right_cell.id);
	repr ~= ", gvel=" ~ to!string(gvel);
	repr ~= ", Ybar=" ~ to!string(Ybar);
	repr ~= ", length=" ~ to!string(length);
	repr ~= ", area=" ~ to!string(area);
	repr ~= ", n=" ~ to!string(n);
	repr ~= ", t1=" ~ to!string(t1);
	repr ~= ", t2=" ~ to!string(t2);
	repr ~= ", fs=" ~ to!string(fs);
	repr ~= ", F=" ~ to!string(F);
	repr ~= ", grad=" ~ to!string(grad);
	repr ~= ", cloud_pos=" ~ to!string(cloud_pos);
	repr ~= ", cloud_fs=" ~ to!string(cloud_fs);
	repr ~= ")";
	return to!string(repr);
    }

    @nogc
    void average_vertex_deriv_values()
    {
	grad.copy_values_from(vtx[0].grad);
	foreach (i; 1 .. vtx.length) grad.accumulate_values_from(vtx[i].grad);
	grad.scale_values_by(1.0/to!double(vtx.length));
    } // end average_vertex_deriv_values()

    //@nogc
    // Removed presently because of call to GasModel.enthalpy.
    void viscous_flux_calc(ref LocalConfig myConfig)
    // Unified 2D and 3D viscous-flux calculation.
    // Note that the gradient values need to be in place before calling this procedure.
    {
	auto gmodel = myConfig.gmodel;
	size_t n_species = gmodel.n_species;
	double viscous_factor = myConfig.viscous_factor;
	double k_laminar = fs.gas.k;
	double mu_laminar = fs.gas.mu;
	if (myConfig.use_viscosity_from_cells) {
	    // Emulate Eilmer3 behaviour by using the viscous transport coefficients
	    // from the cells either side of the interface.
	    if (left_cell && right_cell) {
		k_laminar = 0.5*(left_cell.fs.gas.k+right_cell.fs.gas.k);
		mu_laminar = 0.5*(left_cell.fs.gas.mu+right_cell.fs.gas.mu);
	    } else if (left_cell) {
		k_laminar = left_cell.fs.gas.k;
		mu_laminar = left_cell.fs.gas.mu;
	    } else if (right_cell) {
		k_laminar = right_cell.fs.gas.k;
		mu_laminar = right_cell.fs.gas.mu;
	    } else {
		assert(0, "Oops, don't seem to have a cell available.");
	    }
	}
        double k_eff = viscous_factor * (fs.gas.k + fs.k_t);
	double mu_eff =  viscous_factor * (fs.gas.mu + fs.mu_t);
	double lmbda = -2.0/3.0 * mu_eff;
	// We separate diffusion based on laminar or turbulent
	// and treat the differently.
	if ( myConfig.turbulence_model != TurbulenceModel.none ) {
	    double Sc_t = myConfig.turbulence_schmidt_number;
	    double D_t = fs.mu_t / (fs.gas.rho * Sc_t);

	    for ( size_t isp = 0; isp < n_species; ++isp ) {
		jx[isp] = -fs.gas.rho * D_t * grad.massf[isp][0];
		jy[isp] = -fs.gas.rho * D_t * grad.massf[isp][1];
		jz[isp] = -fs.gas.rho * D_t * grad.massf[isp][2];
	    }
	}
	    
	if ( myConfig.diffusion ) {
	    // Apply a laminar diffusion model
	    // [TODO] Rowan, calculate_diffusion_fluxes(fs.gas, D_t, grad.f, jx, jy, jz);
	    // for( size_t isp = 0; isp < nsp; ++isp ) {
	    // 	jx[isp] = 0.0;
	    // 	jy[isp] = 0.0;
	    // 	jz[isp] = 0.0;
	    // }
	    // for( size_t isp = 0; isp < nsp; ++isp ) {
	    // 	jx[isp] *= viscous_factor;
	    // 	jy[isp] *= viscous_factor;
	    // 	jz[isp] *= viscous_factor;
	    // }
	}
	double tau_xx = 0.0;
	double tau_yy = 0.0;
	double tau_zz = 0.0;
	double tau_xy = 0.0;
	double tau_xz = 0.0;
	double tau_yz = 0.0;
	if (myConfig.dimensions == 3) {
	    double dudx = grad.vel[0][0];
	    double dudy = grad.vel[0][1];
	    double dudz = grad.vel[0][2];
	    double dvdx = grad.vel[1][0];
	    double dvdy = grad.vel[1][1];
	    double dvdz = grad.vel[1][2];
	    double dwdx = grad.vel[2][0];
	    double dwdy = grad.vel[2][1];
	    double dwdz = grad.vel[2][2];
	    // 3-dimensional planar stresses.
	    tau_xx = 2.0*mu_eff*dudx + lmbda*(dudx + dvdy + dwdz);
	    tau_yy = 2.0*mu_eff*dvdy + lmbda*(dudx + dvdy + dwdz);
	    tau_zz = 2.0*mu_eff*dwdz + lmbda*(dudx + dvdy + dwdz);
	    tau_xy = mu_eff * (dudy + dvdx);
	    tau_xz = mu_eff * (dudz + dwdx);
	    tau_yz = mu_eff * (dvdz + dwdy);
	} else {
	    // 2D
	    double dudx = grad.vel[0][0];
	    double dudy = grad.vel[0][1];
	    double dvdx = grad.vel[1][0];
	    double dvdy = grad.vel[1][1];
	    if (myConfig.axisymmetric) {
		// Viscous stresses at the mid-point of the interface.
		// Axisymmetric terms no longer include the radial multiplier
		// as that has been absorbed into the interface area calculation.
		double ybar = Ybar;
                if (ybar > 1.0e-10) { // something very small for a cell height
                    tau_xx = 2.0 * mu_eff * dudx + lmbda * (dudx + dvdy + fs.vel.y / ybar);
                    tau_yy = 2.0 * mu_eff * dvdy + lmbda * (dudx + dvdy + fs.vel.y / ybar);
                } else {
                    tau_xx = 0.0;
                    tau_yy = 0.0;
                }
                tau_xy = mu_eff * (dudy + dvdx);
	    } else {
		// 2-dimensional-planar stresses.
                tau_xx = 2.0 * mu_eff * dudx + lmbda * (dudx + dvdy);
                tau_yy = 2.0 * mu_eff * dvdy + lmbda * (dudx + dvdy);
                tau_xy = mu_eff * (dudy + dvdx);
	    }
	}
	// Thermal conductivity (NOTE: q is total energy flux)
	double qx = k_eff * grad.Ttr[0];
	double qy = k_eff * grad.Ttr[1];
	double qz = k_eff * grad.Ttr[2];
	if ( myConfig.turbulence_model != TurbulenceModel.none ) {
	    for ( int isp = 0; isp < n_species; ++isp ) {
		double h = gmodel.enthalpy(fs.gas, isp);
		qx -= jx[isp] * h;
		qy -= jy[isp] * h;
		qz -= jz[isp] * h;
	    }
	}

	if ( myConfig.diffusion ) {
	    // for( size_t isp = 0; isp < nsp; ++isp ) {
	    // 	double h = 0.0; // [TODO] Rowan, transport of species enthalpies?
	    // 	// double h = gm.enthalpy(fs.gas, isp);
	    // 	qx -= jx[isp] * h;
	    // 	qy -= jy[isp] * h;
	    // 	qz -= jz[isp] * h;
	    // 	// [TODO] Rowan, modal enthalpies ?
	    // }
	}
	double tau_kx = 0.0;
	double tau_ky = 0.0;
	double tau_kz = 0.0;
	double tau_wx = 0.0;
	double tau_wy = 0.0;
	double tau_wz = 0.0;
	if ( myConfig.turbulence_model == TurbulenceModel.k_omega &&
	     !(myConfig.axisymmetric && (Ybar <= 1.0e-10)) ) {
	    // Turbulence contribution to the shear stresses.
	    tau_xx -= 0.66667 * fs.gas.rho * fs.tke;
	    tau_yy -= 0.66667 * fs.gas.rho * fs.tke;
	    if (myConfig.dimensions == 3) { tau_zz -= 0.66667 * fs.gas.rho * fs.tke; }
	    // Turbulence contribution to heat transfer.
	    double sigma_star = 0.6;
	    double mu_effective = fs.gas.mu + sigma_star * fs.mu_t;
	    qx += mu_effective * grad.tke[0];
	    qy += mu_effective * grad.tke[1];
	    if (myConfig.dimensions == 3) { qz += mu_effective * grad.tke[2]; }
	    // Turbulence transport of the turbulence properties themselves.
	    tau_kx = mu_effective * grad.tke[0]; 
	    tau_ky = mu_effective * grad.tke[1];
	    if (myConfig.dimensions == 3) { tau_kz = mu_effective * grad.tke[2]; }
	    double sigma = 0.5;
	    mu_effective = fs.gas.mu + sigma * fs.mu_t;
	    tau_wx = mu_effective * grad.omega[0]; 
	    tau_wy = mu_effective * grad.omega[1]; 
	    if (myConfig.dimensions == 3) { tau_wz = mu_effective * grad.omega[2]; } 
	}
	// Combine into fluxes: store as the dot product (F.n).
	double nx = n.x;
	double ny = n.y;
	double nz = n.z;
	// Mass flux -- NO CONTRIBUTION, unless there's diffusion (below)
	F.momentum.refx -= tau_xx*nx + tau_xy*ny + tau_xz*nz;
	F.momentum.refy -= tau_xy*nx + tau_yy*ny + tau_yz*nz;
	F.momentum.refz -= tau_xz*nx + tau_yz*ny + tau_zz*nz;
	F.total_energy -=
	    (tau_xx*fs.vel.x + tau_xy*fs.vel.y + tau_xz*fs.vel.z + qx)*nx +
	    (tau_xy*fs.vel.x + tau_yy*fs.vel.y + tau_yz*fs.vel.z + qy)*ny +
	    (tau_xz*fs.vel.x + tau_yz*fs.vel.y + tau_zz*fs.vel.z + qz)*nz;
	if (myConfig.turbulence_model == TurbulenceModel.k_omega) {
	    F.tke -= tau_kx * nx + tau_ky * ny + tau_kz * nz;
	    F.omega -= tau_wx * nx + tau_wy * ny + tau_wz * nz;
	}
	if (myConfig.turbulence_model != TurbulenceModel.none) {
	    for ( int isp = 0; isp < n_species; ++isp ) {
		F.massf[isp] += jx[isp]*nx + jy[isp]*ny + jz[isp]*nz;
	    }
	}
	if (myConfig.diffusion) {
	    // Species mass flux
	    // [TODO] Rowan, what happens with user-defined flux?
	    // for( size_t isp = 0; isp < nsp; ++isp ) {
	    //	F.massf[isp] += jx[isp]*nx + jy[isp]*ny + jz[isp]*nz;
	    // }
	}
	// [TODO] Rowan, Modal energy flux?
    } // end viscous_flux_calc()

} // end of class FV_Interface
