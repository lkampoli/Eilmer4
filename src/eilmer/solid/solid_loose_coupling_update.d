/**
 * solid_loose_coupling_update.d
 *
 * Author: Nigel Chong and Rowan G.
 * Date: 2017-04-18
 */

module solid_loose_coupling_update;

import globalconfig;
import globaldata;
import solidblock; 
import solidfvcell;  
import std.stdio; 
import std.parallelism; 
import nm.bbla;
import std.math;
import solidprops; 
import std.datetime; 
import solid_udf_source_terms;

// Working space for update.
// Declared here as globals for this module.

Matrix!double r0;
Matrix!double v;
Matrix!double vi;
Matrix!double wj;
Matrix!double dX; 
double[] h;
double[] hR;
double[] g0;
double[] g1;
Matrix!double H0;
Matrix!double H1;
Matrix!double Gamma;
Matrix!double Q0;
Matrix!double Q1;

void initSolidLooseCouplingUpdate()
{
    int ncells = 0;
    int m = GlobalConfig.sdluOptions.maxGMRESIterations;
    foreach (sblk; solidBlocks) {
        ncells += sblk.activeCells.length;
    }
    r0 = new Matrix!double(ncells, 1);
    v = new Matrix!double(ncells, m+1);
    vi = new Matrix!double(ncells, 1);
    wj = new Matrix!double(ncells, 1);
    dX = new Matrix!double(ncells, 1);
    g0.length = m+1;
    g1.length = m+1;
    h.length = m+1;
    hR.length = m+1;
    H0 = new Matrix!double(m+1, m);
    H1 = new Matrix!double(m+1, m);
    Gamma = new Matrix!double(m+1, m+1);
    Q0 = new Matrix!double(m+1, m+1);
    Q1 = new Matrix!double(m+1, m+1);
}

Matrix!double eval_dedts(Matrix!double eip1, int ftl, double sim_time)
// Evaulates the energy derivatives of all the cells in the solid block and puts them into an array (Matrix object)
// Evaluates derivative when cell energy is "eip1" 
 
// Returns: Matrix of doubles
{ 
    auto n = eip1.nrows;
    Matrix!double ret = zeros!double(n, 1); // array that will be returned (empty - to be populated)
    foreach (sblk; parallel(solidBlocks, 1)) {
        if (!sblk.active) continue;
        sblk.applyPreSpatialDerivAction(sim_time, ftl);
        sblk.clearSources(); 
        sblk.computeSpatialDerivatives(ftl); 
        sblk.computeFluxes();
    }
    if (GlobalConfig.apply_bcs_in_parallel) {
        foreach (sblk; parallel(solidBlocks, 1)) {
            if (sblk.active) { sblk.applyPostFluxAction(sim_time, ftl); }
        }
    } else {
        foreach (sblk; solidBlocks) {
            if (sblk.active) { sblk.applyPostFluxAction(sim_time, ftl); }
        }
    }
    int i = 0;
    foreach (sblk; parallel(solidBlocks, 1)) {
        foreach (scell; sblk.activeCells) { 
            if (GlobalConfig.udfSolidSourceTerms) {
                addUDFSourceTermsToSolidCell(sblk.myL, scell, sim_time);
            }
            scell.e[ftl] = eip1[i, 0];
            scell.T = updateTemperature(scell.sp, scell.e[ftl]);
            scell.timeDerivatives(ftl, GlobalConfig.dimensions);
            ret[i, 0] = scell.dedt[ftl];
            i += 1;
        }
    }
    return ret;
}


Matrix!double e_vec(int ftl)
// Puts energies from desired ftl into an array (Matrix object) 

// Returns: Matrix of doubles
{
    double[] test1;
    foreach (sblk; solidBlocks){ 
        foreach(scell; sblk.activeCells){
            test1 ~= scell.e[ftl];
        }
    } 
    auto len = test1.length; 
    Matrix!double ret = zeros!double(len, 1); 
    int count = 0;
    foreach (entry; test1){ 
        ret[count, 0] = entry; 
        count += 1;
    }
    return ret;
} 

Matrix!double F(Matrix!double eip1, Matrix!double ei, double dt_global, double sim_time) 
// Function for which root needs to be found (for Newton's method)
// Re-arranged implicit euler equation 

// Returns: Matrix of doubles
{
    return eip1 - ei - dt_global*eval_dedts(eip1, 1, sim_time); // lets get rid of dedt_vec... 
}

  
Matrix!double copy_vec(Matrix!double mat)  
// Copies an original vector to a new vector (i.e. leaves original untouched) 

// Returns: Matrix of doubles
{
    auto n = mat.nrows; 
    auto cop = zeros!double(n, 1); 
    foreach(i; 0 .. n){
        cop[i, 0] = mat[i, 0];
    }
    return cop; 
} 

double norm(Matrix!double vec)
// Calculates the euclidean norm of a vector 

// Returns: double
{
    auto n = vec.nrows;
    double total = 0; 
    foreach(i;0 .. n){      
        total += pow(vec[i,0],2);
    }
    double ret = pow(total, 0.5);
    return ret; 
} 

Matrix!double Jac(Matrix!double Yip1, Matrix!double Yi, double dt, double sim_time)
// Jacobian of F 

// Returns: Matrix of doubles
{ 
    double eps = GlobalConfig.sdluOptions.perturbationSize;
    auto n = Yip1.nrows;
    auto ret = eye!double(n);
    Matrix!double Fout;
    Matrix!double Fin = F(Yip1, Yi, dt, sim_time);
    Matrix!double cvec;
    foreach(i;0 .. n){ 
        cvec = copy_vec(Yip1);
        cvec[i, 0] += eps; 
        Fout = F(cvec, Yi, dt, sim_time); 
        foreach(j; 0 .. n){
            ret[j, i] = (Fout[j, 0] - Fin[j, 0])/(eps);               
        }
    }
    return ret;
}


void GMRES(Matrix!double A, Matrix!double b, Matrix!double x0, Matrix!double xm)
// Executes GMRES_step, can be used to repeat GMRES steps checking for multiple iterations, otherwise relatively useless 

// Returns: Matrix of doubles
{    
    double tol = GlobalConfig.sdluOptions.toleranceGMRESSolve;
    double[] xmV;
    xmV.length = xm.nrows;
    foreach (i; 0 .. xmV.length) xmV[i] = xm[i,0];
    GMRES_step(A, b, x0, xmV, tol);
    foreach (i; 0 .. xmV.length) xm[i,0] = xmV[i];
}

void GMRES_step(Matrix!double A, Matrix!double b, Matrix!double x0, double[] xm, double tol)
// Takes a single GMRES step using Arnoldi 
// Minimisation problem is solved using Least Squares via Gauss Jordan (see function below) 

// On return, xm is updated with result.
{
    immutable double ZERO_TOL = 1.0e-15;
    int m = GlobalConfig.sdluOptions.maxGMRESIterations;
    int maxIters = m;
    int iterCount;
    double residual;
    H0.zeros();
    H1.zeros();
    Q0.zeros();
    g0[] = 0.0;
    g1[] = 0.0;
    // r0 = b - A*x0
    dot!double(A, x0, r0);
    foreach (i; 0 .. r0.nrows) r0[i,0] = b[i,0] - r0[i,0];
    double beta = norm(r0);  
    g0[0] = beta;
    double residTol = tol*beta;
    v.zeros();
    foreach (i; 0 .. r0.nrows) v[i,0] = r0[i,0]/beta;
    foreach (i; 0 .. v.nrows) vi[i,0] = v[i,0];
    double hjp1j;
    Matrix!double y; 
    double hij;
    foreach (j; 0 .. m) {
        iterCount = j+1;
        dot!double(A, vi, wj);
        foreach (i; 0 .. j+1) {
            hij = 0.0;
            foreach (k; 0 .. wj.nrows) hij += wj[k,0] * v[k,i];
            H0[i,j] = hij;
            foreach (k; 0 .. wj.nrows) wj[k,0] -= hij*v[k,i];
        } 
        hjp1j = norm(wj);
        H0[j+1, j] = hjp1j;    

        // Add new column to 'v'
        foreach (k; 0 .. v.nrows) {
            vi[k,0] = wj[k,0]/hjp1j;
            v[k,j+1] = vi[k,0];
        }
        // Build rotated Hessenberg progressively
        if (j != 0) {
            // Extract final column in H0
            foreach (i; 0 .. j+1) h[i] = H0[i,j];
            // Rotate column by previous rotations
            // stored in Q0
            nm.bbla.dot!double(Q0, j+1, j+1, h, hR);
            // Place column back in H
            foreach (i; 0 .. j+1) H0[i,j] = hR[i];
        }
        // Now form new Gamma
        Gamma.eye();
        double c_j, s_j, denom;
        denom = sqrt(H0[j,j]*H0[j,j] + H0[j+1,j]*H0[j+1,j]);
        s_j = H0[j+1,j]/denom; 
        c_j = H0[j,j]/denom;
        Gamma[j,j] = c_j; Gamma[j,j+1] = s_j;
        Gamma[j+1,j] = -s_j; Gamma[j+1,j+1] = c_j;
        // Apply rotations
        nm.bbla.dot(Gamma, j+2, j+2, H0, j+1, H1);
        nm.bbla.dot(Gamma, j+2, j+2, g0, g1);
        // Accumulate Gamma rotations in Q.
        if (j == 0) {
            copy(Gamma, Q1);
        }
        else {
            nm.bbla.dot!double(Gamma, j+2, j+2, Q0, j+2, Q1);
        }
        // Prepare for next step
        copy(H1, H0);
        g0[] = g1[];
        copy(Q1, Q0);
        // Get residual
        residual = fabs(g1[j+1]);
        if (residual <= residTol) {
            m = j+1;
            break;
        }
    }
    if ( iterCount == maxIters )
        m = maxIters;
    
    // At end H := R up to row m
    //        g := gm up to row m
    upperSolve!double(H1, m, g1);
    nm.bbla.dot!double(v, v.nrows(), m, g1, xm);
    foreach (k; 0 .. xm.length) xm[k] += x0[k,0];
    return;
}

Matrix!double lsq_gmres(Matrix!double A, Matrix!double b)
// Solves the minimisation problem using least squares and direct solution (Gauss Jordan elimination)

// Returns: Matrix of doubles
{
    auto Ht = transpose!double(A); 
    auto c = hstack!double([dot!double(Ht, A), dot!double(Ht, b)]);
    gaussJordanElimination!double(c);  
    auto nr = c.nrows;
    return arr_2_vert_vec(c.getColumn(nr));
}

Matrix!double arr_2_vert_vec(double[] arr) 
// Takes an array (i.e. D equivalent of a python list) and converts it into a vertical Matrix 
// E.g. [1, 2, 3] --> Matrix[[1], [2], [3]]

// Returns: Matrix of doubles
{
    auto len = arr.length;
    auto ret = zeros!double(len, 1);
    foreach(i; 0 .. len){
        ret[i, 0] = arr[i];
    }
    return ret; 
}


void post(Matrix!double eip1, Matrix!double dei)
// Does the post processing of an implicit method step 

// Returns: none
{
    int i = 0;
    foreach (sblk; solidBlocks){ 
        foreach(scell; sblk.activeCells){
            double eicell = eip1[i, 0];
            scell.e[0] = eicell;
            scell.de_prev = dei[i, 0];
            scell.T = updateTemperature(scell.sp, eicell); //not necesary? 
            i += 1; 
        }
    }
}

void solid_domains_backward_euler_update(double sim_time, double dt_global) 
// Executes implicit method
{  

    writeln("== Begin Step ==");
    auto t0 = Clock.currTime();
    int n = 0;
    foreach (sblk; parallel(solidBlocks, 1)) {
        foreach (scell; sblk.activeCells) {
            if (sim_time-dt_global == 0){ 
                // initialise e0 values
                scell.e[0] = updateEnergy(scell.sp, scell.T); 
            }
            // make a guess for e[1]
            scell.e[1] = scell.e[0] + scell.de_prev; 
            n += 1;
        }
    }
    double eps = GlobalConfig.sdluOptions.toleranceNewtonUpdate;
    double omega = 0.01;
    
    auto ei = e_vec(0); 
    // retrieving guess
    auto eip1 = e_vec(0);
    // Begin prepping for newton loop
    auto Xk = copy_vec(eip1);
    auto Xkp1 = Xk + eps;
    auto Fk = F(Xk, ei, dt_global, sim_time); 
    auto Fkp1 = F(Xkp1, ei, dt_global, sim_time); // done so that fabs(normfk - normfkp1) satisfied
    int count = 0;
    int maxCount = GlobalConfig.sdluOptions.maxNewtonIterations;
    Matrix!double Jk;
    Matrix!double mFk; // e.g. minusFk --> mFk
    while(fabs(norm(Fk) - norm(Fkp1)) > eps){ 
        count += 1; 
        if (count != 1){
            Xk = Xkp1; 
            Fk = Fkp1;  
        }
        Jk = Jac(Xk, ei, dt_global, sim_time);
        mFk = -1*Fk;
        GMRES(Jk, mFk, Xk, dX);

        Xkp1 = Xk + dX; 
        Fkp1 = F(Xkp1, ei, dt_global, sim_time); 
        
        // Break out if stuck or taking too many computations
        if (count == maxCount){
            break;
        }

    }                                           
    eip1 = Xkp1;
    Matrix!double dei = eip1 - ei;
    Fk = Fkp1;
    post(eip1, dei); // post processing incl. writing solns for e, de and updating T.
    writeln("== End Step ==");
}

