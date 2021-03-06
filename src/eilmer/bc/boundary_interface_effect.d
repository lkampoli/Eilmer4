// boundary_interface_effect.d
//
// Effects needed to compute viscous fluxes and the like.
//
// PJ and RG, 2015-04-28, initial code mainly from 
//    the break-up of the Fixed_T boundary condition.
//

module bc.boundary_interface_effect;

import std.json;
import std.string;
import std.conv;
import std.stdio;
import std.math;
import nm.complex;
import nm.number;

import geom;
import json_helper;
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
import solidfvcell;
import solidfvinterface;
import gas_solid_interface;


BoundaryInterfaceEffect make_BIE_from_json(JSONValue jsonData, int blk_id, int boundary)
{
    string bieType = jsonData["type"].str;
    // At the point at which we call this function, we may be inside the block-constructor.
    // Don't attempt the use the block-owned gas model.
    auto gmodel = GlobalConfig.gmodel_master; 
    // If we need access to a gas model in here, 
    // be sure to use GlobalConfig.gmodel_master.
    BoundaryInterfaceEffect newBIE;
    switch (bieType) {
    case "copy_cell_data":
        newBIE = new BIE_CopyCellData(blk_id, boundary);
        break;
    case "flow_state_copy_to_interface":
        auto flowstate = new FlowState(jsonData["flowstate"], gmodel);
        newBIE = new BIE_FlowStateCopy(blk_id, boundary, flowstate);
        break;
    case "flow_state_copy_from_profile_to_interface":
        string fname = getJSONstring(jsonData, "filename", "");
        string match = getJSONstring(jsonData, "match", "xyz");
        newBIE = new BIE_FlowStateCopyFromProfile(blk_id, boundary, fname, match);
        break;
    case "zero_velocity":
        newBIE = new BIE_ZeroVelocity(blk_id, boundary);
        break;
    case "translating_surface":
        Vector3 v_trans = getJSONVector3(jsonData, "v_trans", Vector3(0.0,0.0,0.0));
        newBIE = new BIE_TranslatingSurface(blk_id, boundary, v_trans);
        break;
    case "rotating_surface":
        Vector3 r_omega = getJSONVector3(jsonData, "r_omega", Vector3(0.0,0.0,0.0));
        Vector3 centre = getJSONVector3(jsonData, "centre", Vector3(0.0,0.0,0.0));
        newBIE = new BIE_RotatingSurface(blk_id, boundary, r_omega, centre);
        break;
    case "fixed_temperature":
        double Twall = getJSONdouble(jsonData, "Twall", 300.0);
        newBIE = new BIE_FixedT(blk_id, boundary, Twall);
        break;
    case "fixed_composition":
        double[] massfAtWall = getJSONdoublearray(jsonData, "wall_massf_composition", [1.0,]);
        newBIE = new BIE_FixedComposition(blk_id, boundary, massfAtWall);
        break;
    case "update_thermo_trans_coeffs":
        newBIE = new BIE_UpdateThermoTransCoeffs(blk_id, boundary);
        break;
    case "wall_k_omega":
        newBIE = new BIE_WallKOmega(blk_id, boundary);
        break;
    case "wall_function_interface_effect":
        string thermalCond = getJSONstring(jsonData, "thermal_condition", "FIXED_T");
        thermalCond = toUpper(thermalCond);
        newBIE = new BIE_WallFunction(blk_id, boundary, thermalCond);
        break;
    case "temperature_from_gas_solid_interface":
        int otherBlock = getJSONint(jsonData, "other_block", -1);
        string otherFaceName = getJSONstring(jsonData, "other_face", "none");
        int neighbourOrientation = getJSONint(jsonData, "neighbour_orientation", 0);
        newBIE = new BIE_TemperatureFromGasSolidInterface(blk_id, boundary,
                                                          otherBlock, face_index(otherFaceName),
                                                          neighbourOrientation);
        break;
    case "user_defined":
        string fname = getJSONstring(jsonData, "filename", "none");
        newBIE = new BIE_UserDefined(blk_id, boundary, fname);
        break;
    default:
        string errMsg = format("ERROR: The BoundaryInterfaceEffect type: '%s' is unknown.", bieType);
        throw new FlowSolverException(errMsg);
    }
    return newBIE;
}


class BoundaryInterfaceEffect {
public:
    FluidBlock blk;
    int which_boundary;
    string desc;

    this(int id, int boundary, string description)
    {
        blk = globalFluidBlocks[id];
        which_boundary = boundary;
        desc = description;
    }
    void post_bc_construction() {}
    override string toString() const
    {
        return "BoundaryInterfaceEffect()";
    }
    void apply(double t, int gtl, int ftl)
    {
        final switch (blk.grid_type) {
        case Grid_t.unstructured_grid: 
            apply_unstructured_grid(t, gtl, ftl);
            break;
        case Grid_t.structured_grid:
            apply_structured_grid(t, gtl, ftl);
        }
    }   
    void apply_for_interface(double t, int gtl, int ftl, FVInterface f)
    {
        final switch (blk.grid_type) {
        case Grid_t.unstructured_grid: 
            apply_for_interface_unstructured_grid(t, gtl, ftl, f);
            break;
        case Grid_t.structured_grid:
	    throw new Error("BFE: apply_for_interface not yet implemented for structured grid");
        }
    }
    abstract void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f);
    abstract void apply_unstructured_grid(double t, int gtl, int ftl);
    abstract void apply_structured_grid(double t, int gtl, int ftl);
} // end class BoundaryInterfaceEffect


class BIE_CopyCellData : BoundaryInterfaceEffect {
    this(int id, int boundary, double Twall=300.0)
    {
        super(id, boundary, "CopyCellData");
    }

    override string toString() const 
    {
        return "CopyCellData()";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
	if (bc.outsigns[f.i_bndry] == 1) {
	    f.fs.copy_values_from(f.left_cell.fs);
	} else {
	    f.fs.copy_values_from(f.right_cell.fs);
	}
    }
    
    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
        foreach (i, f; bc.faces) {
            if (bc.outsigns[i] == 1) {
                f.fs.copy_values_from(f.left_cell.fs);
            } else {
                f.fs.copy_values_from(f.right_cell.fs);
            }
        } // end foreach face
    }
    
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(cell.fs);
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(cell.fs);
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(cell.fs);
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(cell.fs);
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(cell.fs);
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(cell.fs);
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()
} // end class BIE_CopyCellData

class BIE_FlowStateCopy : BoundaryInterfaceEffect {

    this(int id, int boundary, in FlowState _fstate)
    {
        super(id, boundary, "flowStateCopy");
        fstate = new FlowState(_fstate);
    }

    override string toString() const 
    {
        return "flowStateCopy(fstate=" ~ to!string(fstate) ~ ")";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
	f.fs.copy_values_from(fstate);
    }
    
    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
        foreach (i, f; bc.faces) {
            f.fs.copy_values_from(fstate);
        } // end foreach face
    }
    
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(fstate);
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(fstate);
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(fstate);
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(fstate);
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(fstate);
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    FlowState fs = IFace.fs;
                    fs.copy_values_from(fstate);
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()

private:
    FlowState fstate;

} // end class BIE_FlowStateCopy


class BIE_FlowStateCopyFromProfile : BoundaryInterfaceEffect {
public:
    this(int id, int boundary, string fileName, string match)
    {
        super(id, boundary, "flowStateCopyFromProfile");
        fprofile = new FlowProfile(fileName, match);
    }

    override string toString() const 
    {
        return format("flowStateCopyFromProfile(filename=\"%s\", match=\"%s\")",
                      fprofile.fileName, fprofile.posMatch);
    }

    @nogc
    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        throw new Error("BIE_FlowStateCopyFromProfile.apply_for_interface_unstructured_grid() not yet implemented");
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
        foreach (i, f; bc.faces) {
            f.fs.copy_values_from(fprofile.get_flowstate(f.id, f.pos));
            fprofile.adjust_velocity(f.fs, f.pos);
        }
    }
    
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface f;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    f = cell.iface[Face.north];
                    f.fs.copy_values_from(fprofile.get_flowstate(f.id, f.pos));
                    fprofile.adjust_velocity(f.fs, f.pos);
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    f = cell.iface[Face.east];
                    f.fs.copy_values_from(fprofile.get_flowstate(f.id, f.pos));
                    fprofile.adjust_velocity(f.fs, f.pos);
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    f = cell.iface[Face.south];
                    f.fs.copy_values_from(fprofile.get_flowstate(f.id, f.pos));
                    fprofile.adjust_velocity(f.fs, f.pos);
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    f = cell.iface[Face.west];
                    f.fs.copy_values_from(fprofile.get_flowstate(f.id, f.pos));
                    fprofile.adjust_velocity(f.fs, f.pos);
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    f = cell.iface[Face.top];
                    f.fs.copy_values_from(fprofile.get_flowstate(f.id, f.pos));
                    fprofile.adjust_velocity(f.fs, f.pos);
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    f = cell.iface[Face.bottom];
                    f.fs.copy_values_from(fprofile.get_flowstate(f.id, f.pos));
                    fprofile.adjust_velocity(f.fs, f.pos);
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()

private:
    FlowProfile fprofile;

} // end class BIE_FlowStateCopyFromProfile


class BIE_ZeroVelocity : BoundaryInterfaceEffect {
    this(int id, int boundary)
    {
        super(id, boundary, "ZeroVelocity");
    }

    override string toString() const 
    {
        return "ZeroVelocity()";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        auto gmodel = blk.myConfig.gmodel;      
        BoundaryCondition bc = blk.bc[which_boundary];
	FlowState fs = f.fs;
	fs.vel.refx = 0.0; fs.vel.refy = 0.0; fs.vel.refz = 0.0;
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        auto gmodel = blk.myConfig.gmodel;      
        BoundaryCondition bc = blk.bc[which_boundary];
        foreach (i, f; bc.faces) {
            FlowState fs = f.fs;
            fs.vel.refx = 0.0; fs.vel.refy = 0.0; fs.vel.refz = 0.0;
        } // end foreach face
    }

    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = 0.0; fs.vel.refy = 0.0; fs.vel.refz = 0.0;
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = 0.0; fs.vel.refy = 0.0; fs.vel.refz = 0.0;
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = 0.0; fs.vel.refy = 0.0; fs.vel.refz = 0.0;
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = 0.0; fs.vel.refy = 0.0; fs.vel.refz = 0.0;
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = 0.0; fs.vel.refy = 0.0; fs.vel.refz = 0.0;
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = 0.0; fs.vel.refy = 0.0; fs.vel.refz = 0.0;
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()
} // end class BIE_ZeroVelocity


class BIE_TranslatingSurface : BoundaryInterfaceEffect {
    // The boundary surface is translating with fixed velocity v_trans.
    Vector3 v_trans;

    this(int id, int boundary, Vector3 v_trans)
    {
        super(id, boundary, "TranslatingSurface");
        this.v_trans = v_trans;
    }

    override string toString() const 
    {
        return "TranslatingSurface(v_trans=" ~ to!string(v_trans) ~ ")";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        throw new Error("BIE_TranslatingSurface.apply_for_interface_unstructured_grid() not implemented yet");
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        throw new Error("BIE_TranslatingSurface.apply_unstructured_grid() not implemented yet");
    }

    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = v_trans.x; fs.vel.refy = v_trans.y; fs.vel.refz = v_trans.z;
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = v_trans.x; fs.vel.refy = v_trans.y; fs.vel.refz = v_trans.z;
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = v_trans.x; fs.vel.refy = v_trans.y; fs.vel.refz = v_trans.z;
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = v_trans.x; fs.vel.refy = v_trans.y; fs.vel.refz = v_trans.z;
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = v_trans.x; fs.vel.refy = v_trans.y; fs.vel.refz = v_trans.z;
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    FlowState fs = IFace.fs;
                    fs.vel.refx = v_trans.x; fs.vel.refy = v_trans.y; fs.vel.refz = v_trans.z;
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()
} // end class BIE_TranslatingSurface


class BIE_RotatingSurface : BoundaryInterfaceEffect {
    // The boundary surface is rotating with fixed angular velocity r_omega
    // about centre.
    Vector3 r_omega;
    Vector3 centre;

    this(int id, int boundary, Vector3 r_omega, Vector3 centre)
    {
        super(id, boundary, "RotatingSurface");
        this.r_omega = r_omega;
        this.centre = centre;
    }

    override string toString() const 
    {
        return "RotatingSurface(r_omega=" ~ to!string(r_omega) ~ 
            ", centre=" ~ to!string(centre) ~ ")";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        throw new Error("BIE_RotatingSurface.apply_for_interface_unstructured_grid() not implemented yet");
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        throw new Error("BIE_RotatingSurface.apply_unstructured_grid() not implemented yet");
    }

    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    FlowState fs = IFace.fs;
                    fs.vel = cross(r_omega, IFace.pos-centre);
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    FlowState fs = IFace.fs;
                    fs.vel = cross(r_omega, IFace.pos-centre);
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    FlowState fs = IFace.fs;
                    fs.vel = cross(r_omega, IFace.pos-centre);
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    FlowState fs = IFace.fs;
                    fs.vel = cross(r_omega, IFace.pos-centre);
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    FlowState fs = IFace.fs;
                    fs.vel = cross(r_omega, IFace.pos-centre);
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    FlowState fs = IFace.fs;
                    fs.vel = cross(r_omega, IFace.pos-centre);
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()
} // end class BIE_RotatingSurface


class BIE_FixedT : BoundaryInterfaceEffect {
public:
    double Twall;

    this(int id, int boundary, double Twall)
    {
        super(id, boundary, "FixedT");
        this.Twall = Twall;
    }

    override string toString() const 
    {
        return "FixedT(Twall=" ~ to!string(Twall) ~ ")";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        auto gmodel = blk.myConfig.gmodel;      
        BoundaryCondition bc = blk.bc[which_boundary];
	FlowState fs = f.fs;
	fs.gas.T = Twall;
	version(multi_T_gas) {
	    foreach(ref elem; fs.gas.T_modes) { elem = Twall; }
	}
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        auto gmodel = blk.myConfig.gmodel;      
        BoundaryCondition bc = blk.bc[which_boundary];
        foreach (i, f; bc.faces) {
            FlowState fs = f.fs;
            fs.gas.T = Twall;
            version(multi_T_gas) {
                foreach(ref elem; fs.gas.T_modes) { elem = Twall; }
            }
        } // end foreach face
    }

    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    FlowState fs = IFace.fs;
                    fs.gas.T = Twall;
                    version(multi_T_gas) {
                        foreach(ref elem; fs.gas.T_modes) { elem = Twall; }
                    }
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    FlowState fs = IFace.fs;
                    fs.gas.T = Twall;
                    version(multi_T_gas) {
                        foreach(ref elem; fs.gas.T_modes) { elem = Twall; }
                    }
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    FlowState fs = IFace.fs;
                    fs.gas.T = Twall;
                    version(multi_T_gas) {
                        foreach(ref elem; fs.gas.T_modes) { elem = Twall; }
                    }
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    FlowState fs = IFace.fs;
                    fs.gas.T = Twall;
                    version(multi_T_gas) {
                        foreach(ref elem; fs.gas.T_modes) { elem = Twall; }
                    }
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    FlowState fs = IFace.fs;
                    fs.gas.T = Twall;
                    version(multi_T_gas) {
                        foreach(ref elem; fs.gas.T_modes) { elem = Twall; }
                    }
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    FlowState fs = IFace.fs;
                    fs.gas.T = Twall;
                    version(multi_T_gas) {
                        foreach(ref elem; fs.gas.T_modes) { elem = Twall; }
                    }
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()
} // end class BIE_FixedT

class BIE_FixedComposition : BoundaryInterfaceEffect {
public:    
    double[] massfAtWall;
    
    this(int id, int boundary, double[] massfAtWall)
    {
        super(id, boundary, "FixedComposition");
        this.massfAtWall = massfAtWall;
    }

    override string toString() const 
    {
        return "FixedComposition(massfAtWall=" ~ to!string(massfAtWall) ~ ")";
    }

    @nogc
    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        throw new Error("BIE_FicedComposition.apply_for_interface_unstructured_grid() not yet implemented");
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        uint nsp = blk.myConfig.n_species;
        BoundaryCondition bc = blk.bc[which_boundary];
        foreach (i, f; bc.faces) {
            FlowState fs = f.fs;
            version(multi_species_gas) {
                for(uint isp=0; isp<nsp; isp++) {
                    fs.gas.massf[isp] = massfAtWall[isp];   
                }
            }
        } // end foreach face
    }

    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        uint nsp = blk.myConfig.n_species;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    FlowState fs = IFace.fs;
                    version(multi_species_gas) {
                        for(uint isp=0; isp<nsp; isp++) {
                            fs.gas.massf[isp] = massfAtWall[isp];   
                        }
                    }
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    FlowState fs = IFace.fs;
                    version(multi_species_gas) {
                        for(uint isp=0; isp<nsp; isp++) {
                            fs.gas.massf[isp] = massfAtWall[isp];   
                        }
                    }
                } // en for j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    FlowState fs = IFace.fs;
                    for(uint isp=0; isp<nsp; isp++) {
                        fs.gas.massf[isp] = massfAtWall[isp];   
                    }
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    FlowState fs = IFace.fs;
                    version(multi_species_gas) {
                        for(uint isp=0; isp<nsp; isp++) {
                            fs.gas.massf[isp] = massfAtWall[isp];   
                        }
                    }
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    FlowState fs = IFace.fs;
                    version(multi_species_gas) {
                        for(uint isp=0; isp<nsp; isp++) {
                            fs.gas.massf[isp] = massfAtWall[isp];   
                        }
                    }
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    FlowState fs = IFace.fs;
                    version(multi_species_gas) {
                        for(uint isp=0; isp<nsp; isp++) {
                            fs.gas.massf[isp] = massfAtWall[isp];   
                        }
                    }
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()
} // end class BIE_FixedComposition


class BIE_UpdateThermoTransCoeffs : BoundaryInterfaceEffect {
    this(int id, int boundary)
    {
        super(id, boundary, "UpdateThermoTransCoeffs");
    }

    override string toString() const 
    {
        return "UpdateThermoTransCoeffs()";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
        auto gmodel = blk.myConfig.gmodel;
	FlowState fs = f.fs;
	gmodel.update_thermo_from_pT(fs.gas);
	gmodel.update_trans_coeffs(fs.gas);
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
        auto gmodel = blk.myConfig.gmodel;
        foreach (i, f; bc.faces) {
            if (bc.outsigns[i] == 1) {
                FlowState fs = f.fs;
                gmodel.update_thermo_from_pT(fs.gas);
                gmodel.update_trans_coeffs(fs.gas);
            } else {
                FlowState fs = f.fs;
                gmodel.update_thermo_from_pT(fs.gas);
                gmodel.update_trans_coeffs(fs.gas);
            }
        } // end foreach face
    }
    
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    FlowState fs = IFace.fs;
                    gmodel.update_thermo_from_pT(fs.gas);
                    gmodel.update_trans_coeffs(fs.gas);
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    FlowState fs = IFace.fs;
                    gmodel.update_thermo_from_pT(fs.gas);
                    gmodel.update_trans_coeffs(fs.gas);
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    FlowState fs = IFace.fs;
                    gmodel.update_thermo_from_pT(fs.gas);
                    gmodel.update_trans_coeffs(fs.gas);
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    FlowState fs = IFace.fs;
                    gmodel.update_thermo_from_pT(fs.gas);
                    gmodel.update_trans_coeffs(fs.gas);
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    FlowState fs = IFace.fs;
                    gmodel.update_thermo_from_pT(fs.gas);
                    gmodel.update_trans_coeffs(fs.gas);
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    FlowState fs = IFace.fs;
                    gmodel.update_thermo_from_pT(fs.gas);
                    gmodel.update_trans_coeffs(fs.gas);
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()
} // end class BIE_UpdateThermoTransCoeffs

class BIE_WallKOmega : BoundaryInterfaceEffect {
    this(int id, int boundary)
    {
        super(id, boundary, "WallKOmega");
    }

    override string toString() const 
    {
        return "WallKOmega()";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
        version(komega) {
	    if (bc.outsigns[f.i_bndry] == 1) {
		number d0 = distance_between(f.left_cell.pos[gtl], f.pos);
		if (f.left_cell.in_turbulent_zone) {
		    f.fs.turb[1] = ideal_omega_at_wall(f.left_cell, d0);
		    f.fs.turb[0] = 0.0;
		} else {
		    f.fs.turb[1] = f.left_cell.fs.turb[1];
		    f.fs.turb[0] = f.left_cell.fs.turb[0];
		}
	    } else {
		number d0 = distance_between(f.right_cell.pos[gtl], f.pos);
		if (f.right_cell.in_turbulent_zone) {
		    f.fs.turb[1] = ideal_omega_at_wall(f.right_cell, d0);
		    f.fs.turb[0] = 0.0;
		} else {
		    f.fs.turb[1] = f.right_cell.fs.turb[1];
		    f.fs.turb[0] = f.right_cell.fs.turb[0];
		}
	    }
	}
    } // end apply_unstructured_grid()
    
    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        BoundaryCondition bc = blk.bc[which_boundary];
        version(komega) {
            foreach (i, f; bc.faces) {
                if (bc.outsigns[i] == 1) {
                    number d0 = distance_between(f.left_cell.pos[gtl], f.pos);
                    if (f.left_cell.in_turbulent_zone) {
                        f.fs.turb[1] = ideal_omega_at_wall(f.left_cell, d0);
                        f.fs.turb[0] = 0.0;
                    } else {
                        f.fs.turb[1] = f.left_cell.fs.turb[1];
                        f.fs.turb[0] = f.left_cell.fs.turb[0];
                    }
                } else {
                    number d0 = distance_between(f.right_cell.pos[gtl], f.pos);
                    if (f.right_cell.in_turbulent_zone) {
                        f.fs.turb[1] = ideal_omega_at_wall(f.right_cell, d0);
                        f.fs.turb[0] = 0.0;
                    } else {
                        f.fs.turb[1] = f.right_cell.fs.turb[1];
                        f.fs.turb[0] = f.right_cell.fs.turb[0];
                    }
                }
            } // end foreach face
        }
    } // end apply_unstructured_grid()
    
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        size_t i, j, k;
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");

        version(komega) {
            final switch (which_boundary) {
            case Face.north:
                j = blk.jmax;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (i = blk.imin; i <= blk.imax; ++i) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.north];
                        number d0 = distance_between(cell.pos[gtl], IFace.pos);
                        FlowState fs = IFace.fs;
                        fs.turb[0] = 0.0;
                        fs.turb[1] = ideal_omega_at_wall(cell, d0);
                    } // end i loop
                } // end for k
                break;
            case Face.east:
                i = blk.imax;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.east];
                        number d0 = distance_between(cell.pos[gtl], IFace.pos);
                        FlowState fs = IFace.fs;
                        fs.turb[0] = 0.0;
                        fs.turb[1] = ideal_omega_at_wall(cell, d0);
                    } // end j loop
                } // end for k
                break;
            case Face.south:
                j = blk.jmin;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (i = blk.imin; i <= blk.imax; ++i) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.south];
                        number d0 = distance_between(cell.pos[gtl], IFace.pos);
                        FlowState fs = IFace.fs;
                        fs.turb[0] = 0.0;
                        fs.turb[1] = ideal_omega_at_wall(cell, d0);
                    } // end i loop
                } // end for k
                break;
            case Face.west:
                i = blk.imin;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.west];
                        number d0 = distance_between(cell.pos[gtl], IFace.pos);
                        FlowState fs = IFace.fs;
                        fs.turb[0] = 0.0;
                        fs.turb[1] = ideal_omega_at_wall(cell, d0);
                    } // end j loop
                } // end for k
                break;
            case Face.top:
                k = blk.kmax;
                for (i = blk.imin; i <= blk.imax; ++i) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.top];
                        number d0 = distance_between(cell.pos[gtl], IFace.pos);
                        FlowState fs = IFace.fs;
                        fs.turb[0] = 0.0;
                        fs.turb[1] = ideal_omega_at_wall(cell, d0);
                    } // end j loop
                } // end for i
                break;
            case Face.bottom:
                k = blk.kmin;
                for (i = blk.imin; i <= blk.imax; ++i) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        cell = blk.get_cell(i,j,k);
                        IFace = cell.iface[Face.bottom];
                        number d0 = distance_between(cell.pos[gtl], IFace.pos);
                        FlowState fs = IFace.fs;
                        fs.turb[0] = 0.0;
                        fs.turb[1] = ideal_omega_at_wall(cell, d0);
                    } // end j loop
                } // end for i
                break;
            } // end switch which_boundary
        }
    } // end apply()

    @nogc
    number ideal_omega_at_wall(in FVCell cell, number d0)
    // As recommended by Wilson Chan, we use Menter's correction
    // for omega values at the wall. This appears as Eqn A12 in 
    // Menter's paper.
    // Reference:
    // Menter (1994)
    // Two-Equation Eddy-Viscosity Turbulence Models for
    // Engineering Applications.
    // AIAA Journal, 32:8, pp. 1598--1605
    {
        auto wall_gas = cell.fs.gas;
        // Note: d0 is half_cell_width_at_wall.
        number nu = wall_gas.mu / wall_gas.rho;
        double beta1 = 0.075;
        return 10 * (6 * nu) / (beta1 * d0 * d0);
    }
} // end class BIE_WallKOmega

class BIE_WallFunction : BoundaryInterfaceEffect {
    this(int id, int boundary, string thermalCond)
    {
        super(id, boundary, "WallFunction_InterfaceEffect");
        _isFixedTWall = (thermalCond == "FIXED_T") ? true : false;
        _faces_need_to_be_flagged = true;
    }

    override string toString() const 
    {
        return "WallFunction_InterfaceEffect()";
    }

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        throw new FlowSolverException("WallFunction_InterfaceEffect bc not implemented for unstructured grids.");
    }

    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        throw new FlowSolverException("WallFunction_InterfaceEffect bc not implemented for unstructured grids.");
    }
    
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        auto blk = cast(SFluidBlock) this.blk;
        assert(blk !is null, "Oops, this should be an SFluidBlock object.");
        size_t i, j, k;
        if (_faces_need_to_be_flagged) {
            // Flag faces, just once.
            final switch (which_boundary) {
            case Face.north:
                j = blk.jmax;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (i = blk.imin; i <= blk.imax; ++i) {
                        blk.get_cell(i,j,k).iface[Face.north].use_wall_function_shear_and_heat_flux = true;
                    }
                }
                break;
            case Face.east:
                i = blk.imax;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        blk.get_cell(i,j,k).iface[Face.east].use_wall_function_shear_and_heat_flux = true;
                    }
                }
                break;
            case Face.south:
                j = blk.jmin;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (i = blk.imin; i <= blk.imax; ++i) {
                        blk.get_cell(i,j,k).iface[Face.south].use_wall_function_shear_and_heat_flux = true;
                    }
                }
                break;
            case Face.west:
                i = blk.imin;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        blk.get_cell(i,j,k).iface[Face.west].use_wall_function_shear_and_heat_flux = true;
                    }
                }
                break;
            case Face.top:
                k = blk.kmax;
                for (i = blk.imin; i <= blk.imax; ++i) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        blk.get_cell(i,j,k).iface[Face.top].use_wall_function_shear_and_heat_flux = true;
                    }
                }
                break;
            case Face.bottom:
                k = blk.kmin;
                for (i = blk.imin; i <= blk.imax; ++i) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        blk.get_cell(i,j,k).iface[Face.bottom].use_wall_function_shear_and_heat_flux = true;
                    }
                }
                break;
            } // end switch which_boundary
            _faces_need_to_be_flagged = false;
        } // end if _faces_need_to_be_flagged
        //
        // Do some real work.
        //
        FVCell cell;
        FVInterface IFace;
        auto gmodel = blk.myConfig.gmodel;

        final switch (which_boundary) {
        case Face.north:
            j = blk.jmax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.north];
                    wall_function(cell, IFace); 
                } // end i loop
            } // end for k
            break;
        case Face.east:
            i = blk.imax;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.east];
                    wall_function(cell, IFace);
                } // end j loop
            } // end for k
            break;
        case Face.south:
            j = blk.jmin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (i = blk.imin; i <= blk.imax; ++i) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.south];
                    wall_function(cell, IFace);
                } // end i loop
            } // end for k
            break;
        case Face.west:
            i = blk.imin;
            for (k = blk.kmin; k <= blk.kmax; ++k) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.west];
                    wall_function(cell, IFace);
                } // end j loop
            } // end for k
            break;
        case Face.top:
            k = blk.kmax;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.top];
                    wall_function(cell, IFace);
                } // end j loop
            } // end for i
            break;
        case Face.bottom:
            k = blk.kmin;
            for (i = blk.imin; i <= blk.imax; ++i) {
                for (j = blk.jmin; j <= blk.jmax; ++j) {
                    cell = blk.get_cell(i,j,k);
                    IFace = cell.iface[Face.bottom];
                    wall_function(cell, IFace);
                } // end j loop
            } // end for i
            break;
        } // end switch which_boundary
    } // end apply()

    void wall_function(const FVCell cell, FVInterface IFace)
    // Implement Nichols' and Nelson's wall function boundary condition
    // Reference:
    //  Nichols RH & Nelson CC (2004)
    //  Wall Function Boundary Conditions Inclding Heat Transfer
    //  and Compressibility.
    //  AIAA Journal, 42:6, pp. 1107--1114
    // NOTE: IFace.fs will receive updated values of tke and omega for later
    //       copying to boundary cells.
    {
        auto gmodel = blk.myConfig.gmodel;
        // Compute recovery factor
        number cp = gmodel.Cp(cell.fs.gas); 
        number Pr = cell.fs.gas.mu * cp / cell.fs.gas.k;
        number gas_constant = gmodel.R(cell.fs.gas);
        number recovery = pow(Pr, (1.0/3.0));
        // Compute tangent velocity at nearest interior point and wall interface
        number du, vt1_2_angle;
        number cell_tangent0, cell_tangent1, face_tangent0, face_tangent1;
        Vector3 cellVel = cell.fs.vel;
        Vector3 faceVel = IFace.fs.vel;
        cellVel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2); 
        faceVel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
        if ( blk.myConfig.dimensions == 2 ) {
            cell_tangent0 = sqrt( pow(cellVel.y, 2.0) + pow(cellVel.z, 2.0) );
            face_tangent0 = sqrt( pow(faceVel.y, 2.0) + pow(faceVel.z, 2.0) );
            du = fabs(cell_tangent0 - face_tangent0);
        } else {
            cell_tangent0 = cellVel.y;
            cell_tangent1 = cellVel.z;
            face_tangent0 = faceVel.y;
            face_tangent1 = faceVel.z;
            vt1_2_angle = atan2(fabs(cellVel.z - faceVel.z), fabs(cellVel.y - faceVel.y));
            du = sqrt( pow((cell_tangent0-face_tangent0),2.0) + pow((cell_tangent1-face_tangent1),2.0) );
        }
        // Compute wall gas properties from either ...
        number T_wall, rho_wall;
        if ( _isFixedTWall ) {
            // ... user-specified wall temperature, or ... 
            T_wall = IFace.fs.gas.T; 
            rho_wall = IFace.fs.gas.rho;
        } else {
            // ... using Crocco-Busemann relation (Eq 11) 
            T_wall = cell.fs.gas.T + recovery * du * du / (2.0 * cp);
            // Update gas properties at the wall, assuming static pressure
            // at the wall is the same as that in the first wall cell
            IFace.fs.gas.T = T_wall;
            IFace.fs.gas.p = cell.fs.gas.p;
            gmodel.update_thermo_from_pT(IFace.fs.gas);
            gmodel.update_trans_coeffs(IFace.fs.gas);
            rho_wall = IFace.fs.gas.rho;
        }
        // Compute wall shear stess (and heat flux for fixed temperature wall) 
        // using the surface stress tensor. This provides initial values to
        // solve for tau_wall and q_wall iteratively
        number wall_dist = distance_between(cell.pos[0], IFace.pos);
        number dudy = du / wall_dist;
        number mu_lam_wall = IFace.fs.gas.mu;
        number mu_lam = cell.fs.gas.mu;
        number tau_wall_old = mu_lam_wall * dudy;
        number dT, dTdy, k_lam_wall, q_wall_old;
        if ( _isFixedTWall ) {
            dT = fabs( cell.fs.gas.T - IFace.fs.gas.T );
            dTdy = dT / wall_dist;
            k_lam_wall = IFace.fs.gas.k;
            q_wall_old = k_lam_wall * dTdy;
        }
        // Constants from Spalding's Law of the Wall theory and 
        // Nichols' wall function implementation
        double kappa = 0.4;
        double B = 5.5;
        double C_mu = 0.09;
        size_t counter_tau = 0; size_t counter_q = 0;
        double tolerance = 1.0e-10;
        number diff_tau = 100.0; number diff_q = 100.0;
        number tau_wall = 0.0; number q_wall = 0.0;
        number u_tau = 0.0; number u_plus = 0.0; number Gam = 0.0;
        number Beta = 0.0; number Q = 0.0; number Phi = 0.0;
        number y_plus_white = 0.0; number y_plus = 0.0; number alpha = 0.0;
        // Iteratively solve for the wall-function corrected shear stress
        // (and heat flux for fixed temperature walls)
        while ( diff_q > tolerance ) {
            counter_tau = 0; // Resets counter for tau_wall to zero
            while ( diff_tau > tolerance ) {
                // Friction velocity and u+ (Eq 2)
                u_tau = sqrt( tau_wall_old / rho_wall );
                u_plus = du / u_tau;
                // Gamma, Beta, Qm and Phi (Eq 7)
                Gam = recovery * u_tau * u_tau / (2.0 * cp * T_wall); 
                if ( _isFixedTWall ) {
                    Beta = q_wall_old * mu_lam_wall / (rho_wall*T_wall*k_lam_wall*u_tau);
                } else {
                    Beta = 0.0;
                }
                Q = sqrt(Beta*Beta + 4.0*Gam);
                Phi = asin(-1.0 * Beta / Q);
                // In the calculation of y+ defined by White and Christoph
                // (Eq 9), the equation breaks down when the value of 
                // asin((2.0*Gam*u_plus - Beta)/Q) goes larger than 1.0 or
                // smaller than -1.0. For cases where we initialise the flow
                // solution with high flow velocity, du (and hence u_plus)
                // becomes large enough to exceed this limit. A limiter is
                // therefore implemented here to help get past this initially
                // large velocity gradient at the wall. Note that this limiter
                // is not in Nichols and Nelson's paper. We set the limit to
                // either a value just below 1.0, or just above -1.0, to avoid
                // the calculation of y_white_y_plus (Eq. 15) from blowing up.
                alpha = (2.0*Gam*u_plus - Beta)/Q;
                if (alpha > 0.0) alpha = fmin(alpha, 1-1e-12);
                else alpha = fmax(alpha, -1+1e-12);
                // y+ defined by White and Christoph (Eq 9)
                y_plus_white = exp((kappa/sqrt(Gam))*(asin(alpha) - Phi))*exp(-1.0*kappa*B);
                // Spalding's unified form for defining y+ (Eq 8)
                y_plus = u_plus + y_plus_white - exp(-1.0*kappa*B) * ( 1.0 + kappa*u_plus
                                                                           + pow((kappa*u_plus), 2.0) / 2.0
                                                                           + pow((kappa*u_plus), 3.0) / 6.0 );
                // Calculate an updated value for the wall shear stress and heat flux 
                tau_wall = 1.0/rho_wall * pow(y_plus*mu_lam_wall/wall_dist, 2.0);
                // Difference between old and new tau_wall and q_wall. Update old value
                diff_tau = fabs(tau_wall - tau_wall_old);
                tau_wall_old += 0.25 * (tau_wall - tau_wall_old);
                // Limit number of iteration loops to 1000.
                counter_tau++;
                if (counter_tau > 1000) break; 
            } // End of "while ( diff_tau > tolerance )" loop
            //
            if ( _isFixedTWall ) {
                // Compute Beta and q_wall values
                Beta = (cell.fs.gas.T/T_wall - 1.0 + Gam*u_plus*u_plus) / u_plus;
                q_wall = Beta * (rho_wall*T_wall*k_lam_wall*u_tau) / mu_lam_wall;
                diff_q = fabs( q_wall - q_wall_old );
                q_wall_old += 0.25 * (q_wall - q_wall_old);
            } else {
                // For adiabatic wall cases, we just break out of the q_wall loop.
                break; 
            } 
            // Limit number of iteration loops to 1000.
            counter_q++;
            if (counter_q > 1000) break; 
        } // End of "while ( diff_q > tolerance )" loop
        //
        // Store wall shear stress and heat flux to be used later to replace viscous  
        // stress in flux calculations. Also, for wall shear stress, transform value 
        // back to the global frame of reference.
        double reverse_flag0 = 1.0; double reverse_flag1 = 1.0;
        Vector3 local_tau_wall;
        if ( blk.myConfig.dimensions == 2 ) {
            if ( face_tangent0 > cell_tangent0 ) reverse_flag0 = -1.0;
        } else {
            if ( face_tangent0 > cell_tangent0 ) reverse_flag0 = -1.0;
            if ( face_tangent1 > cell_tangent1 ) reverse_flag1 = -1.0;
        }
        if ( IFace.bc_id == Face.north || IFace.bc_id == Face.east || IFace.bc_id == Face.top ) {
            if ( blk.myConfig.dimensions == 2 ) {
                IFace.tau_wall_x = -1.0 * reverse_flag0 * tau_wall * IFace.n.y;
                IFace.tau_wall_y = -1.0 * reverse_flag0 * tau_wall * IFace.n.x;
                IFace.tau_wall_z = 0.0;
            } else {
                local_tau_wall = Vector3(to!number(0.0), 
                                         -1.0 * reverse_flag0 * tau_wall * cos(vt1_2_angle),
                                         -1.0 * reverse_flag1 * tau_wall * sin(vt1_2_angle));
            }
            if (_isFixedTWall) {
                IFace.q = -1.0 * q_wall;
            } else {
                IFace.q = 0.0;
            }
        } else { // South, West and Bottom
            if ( blk.myConfig.dimensions == 2 ) {
                IFace.tau_wall_x = reverse_flag0 * tau_wall * IFace.n.y;
                IFace.tau_wall_y = reverse_flag0 * tau_wall * IFace.n.x;
                IFace.tau_wall_z = 0.0;
            } else {
                local_tau_wall = Vector3(to!number(0.0),
                                         reverse_flag0 * tau_wall * cos(vt1_2_angle),
                                         reverse_flag1 * tau_wall * sin(vt1_2_angle));
            }
            if ( _isFixedTWall ) {
                IFace.q = q_wall;
            } else {
                IFace.q = 0.0;
            }
        }
        if ( blk.myConfig.dimensions == 3 ) {
            local_tau_wall.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
            IFace.tau_wall_x = local_tau_wall.x;
            IFace.tau_wall_y = local_tau_wall.y;
            IFace.tau_wall_z = local_tau_wall.z;
        }
        // Turbulence model boundary conditions (Eq 15 & 14)
        // Note that the formulation of y_white_y_plus (Eq 15) is now directly
        // affected by the limiter which was set earlier to help get past large
        // velocity gradients at the wall for cases with initialised with high
        // velocity in flow domain.
        number y_white_y_plus = 2.0 * y_plus_white * kappa*sqrt(Gam)/Q
                * pow((1.0 - pow(alpha,2.0)), 0.5);
        number mu_coeff = 1.0 + y_white_y_plus
                - kappa*exp(-1.0*kappa*B) * (1.0 + kappa*u_plus + kappa*u_plus*kappa*u_plus/2.0)
                - mu_lam/mu_lam_wall;
        // Limit turbulent-to-laminar viscosity ratio between zero and the global limit.
        if ( mu_coeff < 0.0 ) mu_coeff = 0.0;
        mu_coeff = fmin(mu_coeff, blk.myConfig.max_mu_t_factor);
        // Compute turbulent viscosity; forcing mu_t to zero, if result is negative.
        number mu_t = mu_lam_wall * mu_coeff;
        // Compute omega (Eq 19 - 21)
        number omega_i = 6.0*mu_lam_wall / (0.075*rho_wall*wall_dist*wall_dist);
        number omega_o = u_tau / (sqrt(C_mu)*kappa*wall_dist);
        number omega = sqrt(omega_i*omega_i + omega_o*omega_o);
        // Compute tke (Eq 22)
        assert(cell.fs.gas.rho > 0.0, "density not positive");
        assert(mu_t >= 0.0, "mu_t lesser than zero");
        assert(omega > 0.0, "omega not greater than zero");
        number tke = omega * mu_t / cell.fs.gas.rho;
        version(komega) {
            // Assign updated values of tke and omega to IFace.fs for
            // later copying to boundary cells.
            IFace.fs.turb[0] = tke;
            IFace.fs.turb[1] = omega;
        }
        return;
    } // end wall_function()

private:
    bool _isFixedTWall;
    bool _faces_need_to_be_flagged = true;
} // end class BIE_WallFunction


// NOTE: This GAS DOMAIN boundary effect has a large
//       and important side-effect:
//       IT ALSO SETS THE FLUX IN THE ADJACENT SOLID DOMAIN
//       AT THE TIME IT IS CALLED.
// TODO: We need to work out a way to coordinate this 
//       interface effect (ie. the setting of temperature)
//       with the flux effect. Ideally, we only want to compute
//       the temperature/flux once per update. This will require
//       some storage at the block level, or in the in the
//       gas/solid interface module since we can't share information
//       (easily) between different types of boundary condition
//       objects. We need to store the energy flux somewhere where it
//       so that we can use it again in the boundary flux effect.
//       It's no good storing the flux in the interface object since
//       that will be changed during the diffusive flux calculation.
 
class BIE_TemperatureFromGasSolidInterface : BoundaryInterfaceEffect {
public:
    int neighbourSolidBlk;
    int neighbourSolidFace;
    int neighbourOrientation;

    this(int id, int boundary, 
         int otherBlock, int otherFace, int orient)
    {
        super(id, boundary, "TemperatureFromGasSolidInterface");
        neighbourSolidBlk = otherBlock;
        neighbourSolidFace = otherFace;
        neighbourOrientation = orient;
    }

    override string toString() const 
    {
        return "TemperatureFromGasSolidInterface()";
    }

    @nogc
    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
        throw new Error("BIE_TemperatureFromGasSolidInterface.apply_unstructured_grid() not implemented yet");
    }

    @nogc
    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        throw new Error("BIE_TemperatureFromGasSolidInterface.apply_unstructured_grid() not implemented yet");
    }

    @nogc
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        auto myBC = blk.bc[which_boundary];
        computeFluxesAndTemperatures(ftl, myBC.gasCells, myBC.faces, myBC.solidCells, myBC.solidIFaces);
    }

} // end class BIE_TemperatureFromGasSolidInterface
