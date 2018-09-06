// onedinterp.d
// One-dimensional interpolation/reconstruction of flow field.
//
// See MBCNS workbook 2000/2 page 36 (26-Jan-2001) for formulation.
// and MBCNS workbook 2005/Apr page 36 for new index labels
 
import std.math;
import std.stdio;
import nm.complex;
import nm.number;

import gas;
import fvcore;
import globalconfig;
import flowstate;
import fvinterface;
import fvcell;

immutable double epsilon_van_albada = 1.0e-12;

class OneDInterpolator {

private:
    // The following variables must be set to appropriate values
    // by xxxx_prepare() before their use in interp_xxxx_scalar().
    number aL0;
    number aR0;
    number lenL0_;
    number lenR0_;
    number two_over_lenL0_plus_lenL1;
    number two_over_lenR0_plus_lenL0;
    number two_over_lenR1_plus_lenR0;
    number two_lenL0_plus_lenL1;
    number two_lenR0_plus_lenR1;
    LocalConfig myConfig;

public:
    this(LocalConfig myConfig) 
    {
        this.myConfig = myConfig;
    }

    @nogc int get_interpolation_order()
    {
        return myConfig.interpolation_order;
    }

    @nogc void set_interpolation_order(int order)
    {
        myConfig.interpolation_order = order;
    }

    @nogc void both_prepare(number lenL1, number lenL0, number lenR0, number lenR1)
    // Set up intermediate data that depends only on the cell geometry.
    // It will remain constant when reconstructing the different scalar fields
    // over the same set of cells.
    {
        lenL0_ = lenL0;
        lenR0_ = lenR0;
        aL0 = 0.5 * lenL0 / (lenL1 + 2.0*lenL0 + lenR0);
        aR0 = 0.5 * lenR0 / (lenL0 + 2.0*lenR0 + lenR1);
        two_over_lenL0_plus_lenL1 = 2.0 / (lenL0 + lenL1);
        two_over_lenR0_plus_lenL0 = 2.0 / (lenR0 + lenL0);
        two_over_lenR1_plus_lenR0 = 2.0 / (lenR1 + lenR0);
        two_lenL0_plus_lenL1 = (2.0*lenL0 + lenL1);
        two_lenR0_plus_lenR1 = (2.0*lenR0 + lenR1);
    } // end both_prepare()

    @nogc number clip_to_limits(number q, number A, number B)
    // Returns q if q is between the values A and B, else
    // it returns the closer limit of the range [min(A,B), max(A,B)].
    {
        number lower_limit = (A <= B) ? A : B;
        number upper_limit = (A > B) ? A : B;
        number qclipped = (q > lower_limit) ? q : lower_limit;
        return (qclipped <= upper_limit) ? qclipped : upper_limit;
    } // end clip_to_limits()

    @nogc void interp_both_scalar(number qL1, number qL0, number qR0, number qR1,
                                  ref number qL, ref number qR)
    {
        number delLminus, del, delRplus, sL, sR;
        // Set up differences and limiter values.
        delLminus = (qL0 - qL1) * two_over_lenL0_plus_lenL1;
        del = (qR0 - qL0) * two_over_lenR0_plus_lenL0;
        delRplus = (qR1 - qR0) * two_over_lenR1_plus_lenR0;
        if (myConfig.apply_limiter) {
            // val Albada limiter as per Ian Johnston's thesis.
            sL = (delLminus*del + fabs(delLminus*del)) / 
                (delLminus*delLminus + del*del + epsilon_van_albada);
            sR = (del*delRplus + fabs(del*delRplus)) / 
                (del*del + delRplus*delRplus + epsilon_van_albada);
        } else {
            // Use unlimited high-order reconstruction.
            sL = 1.0;
            sR = 1.0;
        }
        // The actual high-order reconstruction, possibly limited.
        qL = qL0 + sL * aL0 * (del * two_lenL0_plus_lenL1 + delLminus * lenR0_);
        qR = qR0 - sR * aR0 * (delRplus * lenL0_ + del * two_lenR0_plus_lenR1);
        if (myConfig.extrema_clipping) {
            // An extra limiting filter to ensure that we do not compute new extreme values.
            // This was introduced to deal with very sharp transitions in species.
            qL = clip_to_limits(qL, qL0, qR0);
            qR = clip_to_limits(qR, qL0, qR0);
        }
    } // end of interp_both_scalar()

    @nogc void left_prepare(number lenL1, number lenL0, number lenR0)
    {
        lenL0_ = lenL0;
        lenR0_ = lenR0;
        aL0 = 0.5 * lenL0 / (lenL1 + 2.0*lenL0 + lenR0);
        two_over_lenL0_plus_lenL1 = 2.0 / (lenL0 + lenL1);
        two_over_lenR0_plus_lenL0 = 2.0 / (lenR0 + lenL0);
        two_lenL0_plus_lenL1 = (2.0*lenL0 + lenL1);
    } // end left_prepare()

    @nogc void interp_left_scalar(number qL1, number qL0, number qR0, ref number qL)
    {
        number delLminus, del, sL;
        delLminus = (qL0 - qL1) * two_over_lenL0_plus_lenL1;
        del = (qR0 - qL0) * two_over_lenR0_plus_lenL0;
        if (myConfig.apply_limiter) {
            sL = (delLminus*del + fabs(delLminus*del)) /
                (delLminus*delLminus + del*del + epsilon_van_albada);
        } else {
            sL = 1.0;
        }
        qL = qL0 + sL * aL0 * (del * two_lenL0_plus_lenL1 + delLminus * lenR0_);
        if (myConfig.extrema_clipping) {
            qL = clip_to_limits(qL, qL0, qR0);
        }
    } // end of interp_left_scalar()

    @nogc void right_prepare(number lenL0, number lenR0, number lenR1)
    {
        lenL0_ = lenL0;
        lenR0_ = lenR0;
        aR0 = 0.5 * lenR0 / (lenL0 + 2.0*lenR0 + lenR1);
        two_over_lenR0_plus_lenL0 = 2.0 / (lenR0 + lenL0);
        two_over_lenR1_plus_lenR0 = 2.0 / (lenR1 + lenR0);
        two_lenR0_plus_lenR1 = (2.0*lenR0 + lenR1);
    } // end right_prepare()

    @nogc void interp_right_scalar(number qL0, number qR0, number qR1, ref number qR)
    {
        number del, delRplus, sR;
        del = (qR0 - qL0) * two_over_lenR0_plus_lenL0;
        delRplus = (qR1 - qR0) * two_over_lenR1_plus_lenR0;
        if (myConfig.apply_limiter) {
            sR = (del*delRplus + fabs(del*delRplus)) /
                (del*del + delRplus*delRplus + epsilon_van_albada);
        } else {
            sR = 1.0;
        }
        qR = qR0 - sR * aR0 * (delRplus * lenL0_ + del * two_lenR0_plus_lenR1);
        if (myConfig.extrema_clipping) {
            qR = clip_to_limits(qR, qL0, qR0);
        }
    } // end of interp_right_scalar()


    // cannot use @nogc because the GasModel methods may allocate internal data
    void interp_both(ref FVInterface IFace,
                     ref FVCell cL1, ref FVCell cL0, ref FVCell cR0, ref FVCell cR1,
                     number cL1Length, number cL0Length, 
                     number cR0Length, number cR1Length, 
                     ref FlowState Lft, ref FlowState Rght,
                     bool allow_high_order_interpolation)
    {
        auto gmodel = myConfig.gmodel;
        auto nsp = gmodel.n_species;
        auto nmodes = gmodel.n_modes;
        // Low-order reconstruction just copies data from adjacent FV_Cell.
        // Even for high-order reconstruction, we depend upon this copy for
        // the viscous-transport and diffusion coefficients.
        Lft.copy_values_from(cL0.fs);
        Rght.copy_values_from(cR0.fs);
        // for some simulations we would like to have the boundaries to remain 1st order
        if (myConfig.suppress_reconstruction_at_boundaries && IFace.is_on_boundary) return;
        // else apply higher-order interpolation to all faces
        if (allow_high_order_interpolation && (myConfig.interpolation_order > 1)) {
            // High-order reconstruction for some properties.
            if (myConfig.interpolate_in_local_frame) {
                // Paul Petrie-Repar and Jason Qin have noted that the velocity needs
                // to be reconstructed in the interface-local frame of reference so that
                // the normal velocities are not messed up for mirror-image at walls.
                // PJ 21-feb-2012
                cL1.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
                cL0.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
                cR0.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
                cR1.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
            }
            both_prepare(cL1Length, cL0Length, cR0Length, cR1Length);
            interp_both_scalar(cL1.fs.vel.x, cL0.fs.vel.x, cR0.fs.vel.x, cR1.fs.vel.x,
                               Lft.vel.refx, Rght.vel.refx);
            interp_both_scalar(cL1.fs.vel.y, cL0.fs.vel.y, cR0.fs.vel.y, cR1.fs.vel.y,
                               Lft.vel.refy, Rght.vel.refy);
            interp_both_scalar(cL1.fs.vel.z, cL0.fs.vel.z, cR0.fs.vel.z, cR1.fs.vel.z,
                               Lft.vel.refz, Rght.vel.refz);
            if (myConfig.MHD) {
                interp_both_scalar(cL1.fs.B.x, cL0.fs.B.x, cR0.fs.B.x, cR1.fs.B.x,
                                   Lft.B.refx, Rght.B.refx);
                interp_both_scalar(cL1.fs.B.y, cL0.fs.B.y, cR0.fs.B.y, cR1.fs.B.y,
                                   Lft.B.refy, Rght.B.refy);
                interp_both_scalar(cL1.fs.B.z, cL0.fs.B.z, cR0.fs.B.z, cR1.fs.B.z,
                                   Lft.B.refz, Rght.B.refz);
                if (myConfig.divergence_cleaning) {
                    interp_both_scalar(cL1.fs.psi, cL0.fs.psi, cR0.fs.psi, cR1.fs.psi,
                                       Lft.psi, Rght.psi);
                }
            }
            if (myConfig.turbulence_model == TurbulenceModel.k_omega) {
                interp_both_scalar(cL1.fs.tke, cL0.fs.tke, cR0.fs.tke, cR1.fs.tke,
                                   Lft.tke, Rght.tke);
                interp_both_scalar(cL1.fs.omega, cL0.fs.omega, cR0.fs.omega, cR1.fs.omega,
                                   Lft.omega, Rght.omega);
            }
            auto gL1 = &(cL1.fs.gas); // Avoid construction of another object.
            auto gL0 = &(cL0.fs.gas);
            auto gR0 = &(cR0.fs.gas);
            auto gR1 = &(cR1.fs.gas);
            if (nsp > 1) {
                // Multiple species.
                foreach (isp; 0 .. nsp) {
                    interp_both_scalar(gL1.massf[isp], gL0.massf[isp], gR0.massf[isp], gR1.massf[isp],
                                       Lft.gas.massf[isp], Rght.gas.massf[isp]);
                }
                try {
                    scale_mass_fractions(Lft.gas.massf); 
                } catch(Exception e) {
                    writeln(e.msg);
                    Lft.gas.massf[] = gL0.massf[];
                }
                try {
                    scale_mass_fractions(Rght.gas.massf);
                } catch(Exception e) {
                    writeln(e.msg);
                    Rght.gas.massf[] = gR0.massf[];
                }
            } else {
                // Only one possible mass-fraction value for a single species.
                Lft.gas.massf[0] = 1.0;
                Rght.gas.massf[0] = 1.0;
            }
            // Interpolate on two of the thermodynamic quantities, 
            // and fill in the rest based on an EOS call. 
            // If an EOS call fails, fall back to just copying cell-centre data.
            // This does presume that the cell-centre data is valid. 
            string codeForThermoUpdateBoth(string funname)
            {
                string code = "
                try {
                    gmodel.update_thermo_from_"~funname~"(Lft.gas);
                } catch (Exception e) {
                    writeln(e.msg);
                    Lft.copy_values_from(cL0.fs);
                }
                try {
                    gmodel.update_thermo_from_"~funname~"(Rght.gas);
                } catch (Exception e) {
                    writeln(e.msg);
                    Rght.copy_values_from(cR0.fs);
                }
                ";
                return code;
            }
            final switch (myConfig.thermo_interpolator) {
            case InterpolateOption.pt: 
                interp_both_scalar(gL1.p, gL0.p, gR0.p, gR1.p, Lft.gas.p, Rght.gas.p);
                interp_both_scalar(gL1.T, gL0.T, gR0.T, gR1.T, Lft.gas.T, Rght.gas.T);
                if (myConfig.allow_reconstruction_for_energy_modes) {
                    foreach (i; 0 .. nmodes) {
                        interp_both_scalar(gL1.T_modes[i], gL0.T_modes[i], gR0.T_modes[i],
                                           gR1.T_modes[i], Lft.gas.T_modes[i], Rght.gas.T_modes[i]);
                    }
                } else {
                    foreach (i; 0 .. nmodes) {
                        Lft.gas.T_modes[i] = gL0.T_modes[i];
                        Rght.gas.T_modes[i] = gR0.T_modes[i];
                    }
                }
                mixin(codeForThermoUpdateBoth("pT"));
                break;
            case InterpolateOption.rhou:
                interp_both_scalar(gL1.rho, gL0.rho, gR0.rho, gR1.rho, Lft.gas.rho, Rght.gas.rho);
                interp_both_scalar(gL1.u, gL0.u, gR0.u, gR1.u, Lft.gas.u, Rght.gas.u);
                if (myConfig.allow_reconstruction_for_energy_modes) {
                    foreach (i; 0 .. nmodes) {
                        interp_both_scalar(gL1.u_modes[i], gL0.u_modes[i], gR0.u_modes[i],
                                           gR1.u_modes[i], Lft.gas.u_modes[i], Rght.gas.u_modes[i]);
                    }
                } else {
                    foreach (i; 0 .. nmodes) {
                        Lft.gas.u_modes[i] = gL0.u_modes[i];
                        Rght.gas.u_modes[i] = gR0.u_modes[i];
                    }
                }
                mixin(codeForThermoUpdateBoth("rhou"));
                break;
            case InterpolateOption.rhop:
                interp_both_scalar(gL1.rho, gL0.rho, gR0.rho, gR1.rho, Lft.gas.rho, Rght.gas.rho);
                interp_both_scalar(gL1.p, gL0.p, gR0.p, gR1.p, Lft.gas.p, Rght.gas.p);
                mixin(codeForThermoUpdateBoth("rhop"));
                break;
            case InterpolateOption.rhot: 
                interp_both_scalar(gL1.rho, gL0.rho, gR0.rho, gR1.rho, Lft.gas.rho, Rght.gas.rho);
                interp_both_scalar(gL1.T, gL0.T, gR0.T, gR1.T, Lft.gas.T, Rght.gas.T);
                if (myConfig.allow_reconstruction_for_energy_modes) {
                    foreach (i; 0 .. nmodes) {
                        interp_both_scalar(gL1.T_modes[i], gL0.T_modes[i], gR0.T_modes[i],
                                           gR1.T_modes[i], Lft.gas.T_modes[i], Rght.gas.T_modes[i]);
                    }
                } else {
                    foreach (i; 0 .. nmodes) {
                        Lft.gas.T_modes[i] = gL0.T_modes[i];
                        Rght.gas.T_modes[i] = gR0.T_modes[i];
                    }
                }
                mixin(codeForThermoUpdateBoth("rhoT"));
                break;
            } // end switch thermo_interpolator
            if (myConfig.interpolate_in_local_frame) {
                // Undo the transformation made earlier. PJ 21-feb-2012
                Lft.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                Rght.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cL1.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cL0.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cR0.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cR1.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
            }
        } // end of high-order reconstruction
    } // end interp_both()

    // cannot use @nogc because the GasModel methods may allocate internal data
    void interp_left(ref FVInterface IFace,
                     ref FVCell cL1, ref FVCell cL0, ref FVCell cR0,
                     number cL1Length, number cL0Length, number cR0Length,
                     ref FlowState Lft, ref FlowState Rght,
                     bool allow_high_order_interpolation)
    {
        auto gmodel = myConfig.gmodel;
        auto nsp = gmodel.n_species;
        auto nmodes = gmodel.n_modes;
        // Low-order reconstruction just copies data from adjacent FV_Cell.
        // Even for high-order reconstruction, we depend upon this copy for
        // the viscous-transport and diffusion coefficients.
        Lft.copy_values_from(cL0.fs);
        Rght.copy_values_from(cR0.fs);
        // for some simulations we would like to have the boundaries to remain 1st order
        if (myConfig.suppress_reconstruction_at_boundaries && IFace.is_on_boundary) return;
        // else apply higher-order interpolation to all faces
        if (allow_high_order_interpolation && (myConfig.interpolation_order > 1)) {
            // High-order reconstruction for some properties.
            if (myConfig.interpolate_in_local_frame) {
                // In the interface-local frame.
                cL1.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
                cL0.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
                cR0.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
            }
            left_prepare(cL1Length, cL0Length, cR0Length);
            interp_left_scalar(cL1.fs.vel.x, cL0.fs.vel.x, cR0.fs.vel.x, Lft.vel.refx);
            interp_left_scalar(cL1.fs.vel.y, cL0.fs.vel.y, cR0.fs.vel.y, Lft.vel.refy);
            interp_left_scalar(cL1.fs.vel.z, cL0.fs.vel.z, cR0.fs.vel.z, Lft.vel.refz);
            if (myConfig.MHD) {
                interp_left_scalar(cL1.fs.B.x, cL0.fs.B.x, cR0.fs.B.x, Lft.B.refx);
                interp_left_scalar(cL1.fs.B.y, cL0.fs.B.y, cR0.fs.B.y, Lft.B.refy);
                interp_left_scalar(cL1.fs.B.z, cL0.fs.B.z, cR0.fs.B.z, Lft.B.refz);
                if (myConfig.divergence_cleaning) {
                    interp_left_scalar(cL1.fs.psi, cL0.fs.psi, cR0.fs.psi, Lft.psi);
                }
            }
            if ( myConfig.turbulence_model == TurbulenceModel.k_omega ) {
                interp_left_scalar(cL1.fs.tke, cL0.fs.tke, cR0.fs.tke, Lft.tke);
                interp_left_scalar(cL1.fs.omega, cL0.fs.omega, cR0.fs.omega, Lft.omega);
            }
            auto gL1 = &(cL1.fs.gas); auto gL0 = &(cL0.fs.gas); auto gR0 = &(cR0.fs.gas);
            if (nsp > 1) {
                // Multiple species.
                foreach (isp; 0 .. nsp) {
                    interp_left_scalar(gL1.massf[isp], gL0.massf[isp], gR0.massf[isp], Lft.gas.massf[isp]);
                }
                try {
                    scale_mass_fractions(Lft.gas.massf);
                } catch(Exception e) {
                    writeln(e.msg);
                    Lft.gas.massf[] = gL0.massf[];
                }
            } else {
                // Only one possible mass-fraction value for a single species.
                Lft.gas.massf[0] = 1.0;
            }
            // Interpolate on two of the thermodynamic quantities, 
            // and fill in the rest based on an EOS call. 
            // If an EOS call fails, fall back to just copying cell-centre data.
            // This does presume that the cell-centre data is valid. 
            string codeForThermoUpdateLft(string funname)
            {
                string code = "
                try {
                    gmodel.update_thermo_from_"~funname~"(Lft.gas);
                } catch (Exception e) {
                    writeln(e.msg);
                    Lft.copy_values_from(cL0.fs);
                }
                ";
                return code;
            }
            final switch (myConfig.thermo_interpolator) {
            case InterpolateOption.pt: 
                interp_left_scalar(gL1.p, gL0.p, gR0.p, Lft.gas.p);
                interp_left_scalar(gL1.T, gL0.T, gR0.T, Lft.gas.T);
                foreach (i; 0 .. nmodes) {
                    interp_left_scalar(gL1.T_modes[i], gL0.T_modes[i], gR0.T_modes[i], Lft.gas.T_modes[i]);
                }
                mixin(codeForThermoUpdateLft("pT"));
                break;
            case InterpolateOption.rhou:
                interp_left_scalar(gL1.rho, gL0.rho, gR0.rho, Lft.gas.rho);
                interp_left_scalar(gL1.u, gL0.u, gR0.u, Lft.gas.u);
                foreach (i; 0 .. nmodes) {
                    interp_left_scalar(gL1.u_modes[i], gL0.u_modes[i], gR0.u_modes[i], Lft.gas.u_modes[i]);
                }
                mixin(codeForThermoUpdateLft("rhou"));
                break;
            case InterpolateOption.rhop:
                interp_left_scalar(gL1.rho, gL0.rho, gR0.rho, Lft.gas.rho);
                interp_left_scalar(gL1.p, gL0.p, gR0.p, Lft.gas.p);
                mixin(codeForThermoUpdateLft("rhop"));
                break;
            case InterpolateOption.rhot: 
                interp_left_scalar(gL1.rho, gL0.rho, gR0.rho, Lft.gas.rho);
                interp_left_scalar(gL1.T, gL0.T, gR0.T, Lft.gas.T);
                foreach (i; 0 .. nmodes) {
                    interp_left_scalar(gL1.T_modes[i], gL0.T_modes[i], gR0.T_modes[i], Lft.gas.T_modes[i]);
                }
                mixin(codeForThermoUpdateLft("rhoT"));
                break;
            } // end switch thermo_interpolator
            if (myConfig.interpolate_in_local_frame) {
                // Undo the transformation made earlier.
                Lft.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cL1.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cL0.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cR0.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
            }
        } // end of high-order reconstruction
    } // end interp_left()

    // cannot use @nogc because the GasModel methods may allocate internal data
    void interp_right(ref FVInterface IFace,
                      ref FVCell cL0, ref FVCell cR0, ref FVCell cR1,
                      number cL0Length, number cR0Length, number cR1Length,
                      ref FlowState Lft, ref FlowState Rght,
                      bool allow_high_order_interpolation)
    // Reconstruct flow properties at an interface from cells L0,R0,R1.
    //
    // This is essentially a one-dimensional interpolation process.  It needs only
    // the cell-average data and the lengths of the cells in the interpolation direction.
    {
        auto gmodel = myConfig.gmodel;
        auto nsp = gmodel.n_species;
        auto nmodes = gmodel.n_modes;
        // Low-order reconstruction just copies data from adjacent FV_Cell.
        // Even for high-order reconstruction, we depend upon this copy for
        // the viscous-transport and diffusion coefficients.
        Lft.copy_values_from(cL0.fs);
        Rght.copy_values_from(cR0.fs);
        // for some simulations we would like to have the boundaries to remain 1st order
        if (myConfig.suppress_reconstruction_at_boundaries && IFace.is_on_boundary) return;
        // else apply higher-order interpolation to all faces
        if (allow_high_order_interpolation && (myConfig.interpolation_order > 1)) {
            // High-order reconstruction for some properties.
            if (myConfig.interpolate_in_local_frame) {
                // In the interface-local frame.
                cL0.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
                cR0.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
                cR1.fs.vel.transform_to_local_frame(IFace.n, IFace.t1, IFace.t2);
            }
            right_prepare(cL0Length, cR0Length, cR1Length);
            interp_right_scalar(cL0.fs.vel.x, cR0.fs.vel.x, cR1.fs.vel.x, Rght.vel.refx);
            interp_right_scalar(cL0.fs.vel.y, cR0.fs.vel.y, cR1.fs.vel.y, Rght.vel.refy);
            interp_right_scalar(cL0.fs.vel.z, cR0.fs.vel.z, cR1.fs.vel.z, Rght.vel.refz);
            if (myConfig.MHD) {
                interp_right_scalar(cL0.fs.B.x, cR0.fs.B.x, cR1.fs.B.x, Rght.B.refx);
                interp_right_scalar(cL0.fs.B.y, cR0.fs.B.y, cR1.fs.B.y, Rght.B.refy);
                interp_right_scalar(cL0.fs.B.z, cR0.fs.B.z, cR1.fs.B.z, Rght.B.refz);
                if (myConfig.divergence_cleaning) {
                    interp_right_scalar(cL0.fs.psi, cR0.fs.psi, cR1.fs.psi, Rght.psi);
                }
            }
            if (myConfig.turbulence_model == TurbulenceModel.k_omega) {
                interp_right_scalar(cL0.fs.tke, cR0.fs.tke, cR1.fs.tke, Rght.tke);
                interp_right_scalar(cL0.fs.omega, cR0.fs.omega, cR1.fs.omega, Rght.omega);
            }
            auto gL0 = &(cL0.fs.gas); auto gR0 = &(cR0.fs.gas); auto gR1 = &(cR1.fs.gas);
            if (nsp > 1) {
                // Multiple species.
                foreach (isp; 0 .. nsp) {
                    interp_right_scalar(gL0.massf[isp], gR0.massf[isp], gR1.massf[isp], Rght.gas.massf[isp]);
                }
                try {
                    scale_mass_fractions(Rght.gas.massf);
                } catch(Exception e) {
                    writeln(e.msg);
                    Rght.gas.massf[] = gR0.massf[];
                }
            } else {
                // Only one possible mass-fraction value for a single species.
                Rght.gas.massf[0] = 1.0;
            }
            // Interpolate on two of the thermodynamic quantities, 
            // and fill in the rest based on an EOS call. 
            // If an EOS call fails, fall back to just copying cell-centre data.
            // This does presume that the cell-centre data is valid. 
            string codeForThermoUpdateRght(string funname)
            {
                string code = "
                try {
                    gmodel.update_thermo_from_"~funname~"(Rght.gas);
                } catch (Exception e) {
                    writeln(e.msg);
                    Rght.copy_values_from(cR0.fs);
                }
                ";
                return code;
            }
            final switch (myConfig.thermo_interpolator) {
            case InterpolateOption.pt: 
                interp_right_scalar(gL0.p, gR0.p, gR1.p, Rght.gas.p);
                interp_right_scalar(gL0.T, gR0.T, gR1.T, Rght.gas.T);
                foreach (i; 0 .. nmodes) {
                    interp_right_scalar(gL0.T_modes[i], gR0.T_modes[i], gR1.T_modes[i], Rght.gas.T_modes[i]);
                }
                mixin(codeForThermoUpdateRght("pT"));
                break;
            case InterpolateOption.rhou:
                interp_right_scalar(gL0.rho, gR0.rho, gR1.rho, Rght.gas.rho);
                interp_right_scalar(gL0.u, gR0.u, gR1.u, Rght.gas.u);
                foreach (i; 0 .. nmodes) {
                    interp_right_scalar(gL0.u_modes[i], gR0.u_modes[i], gR1.u_modes[i], Rght.gas.u_modes[i]);
                }
                mixin(codeForThermoUpdateRght("rhou"));
                break;
            case InterpolateOption.rhop:
                interp_right_scalar(gL0.rho, gR0.rho, gR1.rho, Rght.gas.rho);
                interp_right_scalar(gL0.p, gR0.p, gR1.p, Rght.gas.p);
                mixin(codeForThermoUpdateRght("rhop"));
                break;
            case InterpolateOption.rhot: 
                interp_right_scalar(gL0.rho, gR0.rho, gR1.rho, Rght.gas.rho);
                interp_right_scalar(gL0.T, gR0.T, gR1.T, Rght.gas.T);
                foreach (i; 0 .. nmodes) {
                    interp_right_scalar(gL0.T_modes[i], gR0.T_modes[i], gR1.T_modes[i], Rght.gas.T_modes[i]);
                }
                mixin(codeForThermoUpdateRght("rhoT"));
                break;
            } // end switch thermo_interpolator
            if (myConfig.interpolate_in_local_frame) {
                // Undo the transformation made earlier.
                Rght.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cL0.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cR0.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
                cR1.fs.vel.transform_to_global_frame(IFace.n, IFace.t1, IFace.t2);
            }
        } // end of high-order reconstruction
    } // end interp_right()

} // end class OneDInterpolator
