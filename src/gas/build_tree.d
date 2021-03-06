/**
 * build_tree.d
 * Based on a user-defined bivariate function F(x,y), build_tree generates a look-up table based on
 * the methods defined in tree_patch and writes it to a textfile which can be read by something else
 * (perhaps a GasModel) at run time using "buildTree_fromFile"
 *
 * Two functions are required:
 *      1. double F(double x,double y): the function which is being looked up
 *                      A rectangular area bounded by x_lo, x_hi, y_lo, y_hi can be set in main()
 *  2. double[2] F_transform(double x, double y): This maps the previous x,y to another two-dimensional
 *                      domain, returned as [X, Y]. This is used if x,y represents a nonsensical re-parameterization
 *                  of the original variables X, Y. The original variables X, Y are used to control the
 *                      extent of growth of the table. If irrelevant just use a dummy transform function where 
 *                         F_transform(x,y) = [x,y]
 * 
 *  This particular implementation uses a remapping of rho, e to u and v as described in CO2GasSW.d
 *      u, v correspond to x,y
 *  Author: Jonathan H.
 *  Version: 2015-10-03
 */

import std.stdio;
import std.math;
import std.mathspecial;
import std.algorithm; 
import std.string;
import std.conv;
import std.datetime;
import nm.tree_patch;
import gas.gas_model;
import gas.co2gas_sw;



//-----SETUP THE BIVARIATE FUNCTION F(X,Y) HERE ----------------

double rho_min = 0.05;
double rho_max = 1500;
double e_min = -5.5e5;
double e_max = 5.0e5;
//-----------------------------REMAP------------------------------
/*static double F(double u, double v){
        CO2GasSW gm = new CO2GasSW;
        auto gd = new GasState(1,1);//initializes using constructor of nspecies, n modes
        double[2] rhoe = gm.get_rhoe_uv(u,v,rho_min,rho_max,e_min,e_max);
        double rho = rhoe[0];
        double e = rhoe[1];
        gd.rho = rho;
        gd.u = e;
        gm.update_thermo_from_rhou(gd);
        //gm.update_sound_speed(gd);
        return gd.T;
        }
static double[2] F_transform(double x, double y){
        CO2GasSW gm = new CO2GasSW();
        return gm.get_rhoe_uv(x,y,rho_min,rho_max,e_min,e_max);
}*/
//--------------NO REMAP-----------------------------
/*static double F(double rho, double e){
        CO2GasSW gm = new CO2GasSW();
        auto gd = new GasState(1,1);//initializes using constructor of nspecies, n modes
        gd.rho = rho;
        gd.u = e;
        gm.update_thermo_from_rhou(gd);
        //gm.update_sound_speed(gd);
        return gd.T;
        }
static double[2] F_transform(double x, double y){
        return [x,y];
}*/
static double F(double x, double y){
        return 0.0002*x^^5 - y^^4 + x*y;
}
static double[2] F_transform(double x, double y){
        return [x,y];
}

void main(){
        double x_lo = -10.0;
        double x_hi = 40.0;
        double y_lo = -10.0;
        double y_hi = 40.0;
        /*double x_lo = rho_min;
        double x_hi = rho_max;
        double y_lo = e_min;
        double y_hi = e_max;*/
        immutable int n = 100;
        Tree myTree = new Tree(x_lo, x_hi, y_lo, y_hi);
        myTree.globalMaxError = 0.0000005;
        myTree.globalMinArea = 0.0000000001*(y_hi - y_lo)*(x_hi - x_lo);
        //myTree.X_min = rho_min;
        //myTree.X_max = rho_max;
        //myTree.Y_min = e_min;
        //myTree.Y_max = e_max;
        writeln("initialised the tree, with the first patch");
        writeln(myTree.Nodes[0].nodePatch.toString());
        myTree.grow(&F, &F_transform, myTree.Nodes[0]);
        writeln("refining the tree...");
        int numberRefined = 1;
        while (numberRefined) {
                        numberRefined = myTree.refine(&F, &F_transform);
        }
        if (numberRefined==0) myTree.refinedFlag = 1;
        writeln("finished refining the tree");
        int n_leafs = 0;
        //sets up control points for the Tree, and writes to a textFILE
         foreach(i,ref treeNode; myTree.Nodes){
                //N implies a LEAF NODE
                if (treeNode.splitID == 'N'){
                                n_leafs++;
                        }
                else if ((treeNode.left == null)||(treeNode.right == null)){
                                writefln("Bad Pointers at idx: %s", i);
                                writeln(treeNode);
                                }
                }
        //-----Write some Patches for plotting
        File patchFile = File("patch_xy_remap.dat", "w");
        foreach (node; myTree.Nodes){
                if (node.splitID == 'N'){
                        double[2] rhoT_0 = F_transform(node.nodePatch.x_lo,node.nodePatch.y_lo);
                        double[2] rhoT_1 = F_transform(node.nodePatch.x_lo,node.nodePatch.y_hi);
                        double[2] rhoT_2 = F_transform(node.nodePatch.x_hi,node.nodePatch.y_hi);
                        double[2] rhoT_3 = F_transform(node.nodePatch.x_hi,node.nodePatch.y_lo);
                        patchFile.writeln([rhoT_0[0],rhoT_1[0],rhoT_2[0],rhoT_3[0],rhoT_0[1],rhoT_1[1],rhoT_2[1],rhoT_3[1]]);
                        }
        }
        //myTree.writeLeaves();
                

                
        //writefln("rho_min: %s, rho_max: %s, e_min: %s, e_max: %s", rho_min, rho_max, e_min, e_max);
        writeln("finished growing the tree");
        writefln("nleafs: %s, n_nodes: %s", n_leafs,myTree.Nodes.length);
        writefln("globalMaxError: %s, globalMinArea: %s", myTree.globalMaxError, myTree.globalMinArea);
        writefln("minDeltaX: %s, minDeltaY: %s", myTree.minDeltaX, myTree.minDeltaY);
        //string filename = "T_rhoe_Tree.dat";
        //myTree.writeLUT(filename); 
        //writefln("Tree written to %s ", filename);

        //--Testing some derivatives
        //double search_x = 20; double search_y = 10.5;
        //auto patch = myTree.search(search_x, search_y);
        //int patchid = myTree.searchForNodeID(search_x, search_y);
        //auto originalBs = patch.bs;
        //writefln("Patch Original Control Points: %s", originalBs);
        //int vertex = 3;
        //auto derivs = patch.cornerDerivatives(vertex);
        //double x = patch.x_lo; double y = patch.y_lo;
        //double x = patch.x_hi; double y = patch.y_lo;
        //double x = patch.x_hi; double y = patch.y_hi;
        //double x = patch.x_lo; double y = patch.y_hi;
        //double f = patch.interpolateF(x,y);
        //myTree.Nodes[patchid].nodePatch.rewriteControlPoints(vertex, f,derivs[0], derivs[1],derivs[2]);
        //auto newBs =  myTree.Nodes[patchid].nodePatch.bs;
        //writefln("Patch New Control Points     : %s", newBs);
        //double[16] diffBs;
        //foreach (i, ref diff; diffBs) diff = originalBs[i] - newBs[i];
        //writefln("Difference                   : %s", diffBs);
        
        //testing side derivatives
        //char side = 'S';
        //double x = 0.5*(patch.x_lo + patch.x_hi); double y = patch.y_lo;
        //double x = patch.x_hi; double y = 0.5*(patch.y_lo + patch.y_hi);
        //double x = 0.5*(patch.x_lo + patch.x_hi); double y = patch.y_hi;
        //double x = patch.x_lo; double y = 0.5*(patch.y_lo + patch.y_hi);
        //auto derivs = patch.midsideDerivatives(side);
        //----------------------------------
        //double f_x = 0.001*x^^4 + y;
        //double f_y = -4*y^^3 + x;
        //double f_xy = 1;
        //writefln("For x = %s, y = %s", x, y);
        //writefln("ANALYTICAL :f_x: %s, f_y: %s, f_xy: %s",f_x, f_y, f_xy);
        //writefln("NUMERICAL  :f_x: %s, f_y: %s, f_xy: %s",derivs[0],derivs[1], derivs[2]);

        //---------------------------------------------------------
        myTree.recordDependencies();
        //for(int i = 0; i != 100; i++){
        //      writefln("Dependencies for node %s: %s, splitID: %s, parent: %s", i, myTree.Nodes[i].smallNeighbours, myTree.Nodes[i].splitID,myTree.Nodes[i].bigNeighbours);
        //}
        writeln("making vertices continuous");
        myTree.makeVertexContinuous;
        auto dependencyOrder = myTree.dependencyOrder;
        writeln("making continuous");
        myTree.makeMidsideContinuous(dependencyOrder);
        writeln("finished making it continuous");

}

