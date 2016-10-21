/** postprocess.d
 * Eilmer4 compressible-flow simulation code, postprocessing functions.
 *
 * The role of the post-processing functions is just to pick up data
 * from a previously-run simulation and either write plotting files
 * or extract interesting pieces of data.
 *
 * Author: Peter J. and Rowan G. 
 * First code: 2015-06-09
 */

module postprocess;

import std.math;
import std.stdio;
import std.conv;
import std.format;
import std.string;
import std.algorithm;
import std.bitmanip;
import std.stdint;
import gzip;
import fvcore;
import fileutil;
import geom;
import sgrid;
import grid;
import gas;
import globalconfig;
import flowsolution;
import solidsolution;


void post_process(string plotDir, bool listInfoFlag, string tindxPlot,
		  string addVarsStr, string luaRefSoln,
		  bool vtkxmlFlag, bool binary_format, bool tecplotFlag,
		  string outputFileName, string sliceListStr,
		  string surfaceListStr, string extractStreamStr,
		  string extractLineStr, string probeStr,
		  string normsStr, string regionStr)
{
    read_config_file();
    string jobName = GlobalConfig.base_file_name;
    //
    string[] addVarsList;
    addVarsStr = addVarsStr.strip();
    addVarsStr = removechars(addVarsStr, "\"");
    if (addVarsStr.length > 0) {
	addVarsList = addVarsStr.split(",");
    }
    //
    auto times_dict = readTimesFile(jobName);
    auto tindx_list = times_dict.keys;
    sort(tindx_list);
    int[] tindx_list_to_plot;
    switch (tindxPlot) {
    case "all":
	tindx_list_to_plot = tindx_list.dup;
	break;
    case "9999":
    case "last":
	tindx_list_to_plot ~= tindx_list[$-1];
        break;
    default:
	// We assume that the command-line argument was an integer.
        tindx_list_to_plot ~= to!int(tindxPlot);
    } // end switch
    //
    if (listInfoFlag) {
	writeln("Some information about this simulation.");
	writeln("  nBlocks= ", GlobalConfig.nBlocks);
	writeln("  nSolidBlocks= ", GlobalConfig.nSolidBlocks);
	writeln("  last tindx= ", tindx_list[$-1]);
	writeln("  Flow Variables:");
	// Dip into the top of a solution file that is likely to be present
	// to get the variable names, as saved by the simulation.
	string fileName = make_file_name!"flow"(jobName, to!int(0), 0);
	auto byLine = new GzipByLine(fileName);
	auto line = byLine.front; byLine.popFront();
	double sim_time;
	formattedRead(line, " %g", &sim_time);
	line = byLine.front; byLine.popFront();
	auto variableNames = line.strip().split();
	foreach (ref var; variableNames) { var = removechars(var, "\""); }
	foreach (i; 0 .. variableNames.length) {
	    writeln(format("%4d %s", i, variableNames[i]));
	}
	if ( GlobalConfig.nSolidBlocks > 0 ) {
	    writeln("  Solid Variables:");
	    // Dip into the top of a solid solution file that is
	    // likely to be present to get the variable names
	    // as saved by the simulation.
	    fileName = make_file_name!"solid"(jobName, 0, 0);
	    byLine = new GzipByLine(fileName);
	    line = byLine.front; byLine.popFront();
	    formattedRead(line, " %g", &sim_time);
	    line = byLine.front; byLine.popFront();
	    variableNames = line.strip().split();
	    foreach (ref var; variableNames) { var = removechars(var, "\""); }
	    foreach (i; 0 .. variableNames.length) {
		writeln(format("%4d %s", i, variableNames[i]));
	    }
	} // end if nSolidBlocks > 0
    } // end if listInfoFlag
    //
    if (vtkxmlFlag) {
	writeln("writing VTK-XML files to directory \"", plotDir, "\"");
	begin_Visit_file(jobName, plotDir, GlobalConfig.nBlocks);
	begin_PVD_file(jobName, plotDir);
	foreach (tindx; tindx_list_to_plot) {
	    writeln("  tindx= ", tindx);
	    auto soln = new FlowSolution(jobName, ".", tindx, GlobalConfig.nBlocks);
	    soln.add_aux_variables(addVarsList);
	    if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
	    write_VTK_XML_files(jobName, plotDir, soln, tindx, binary_format);
	} // foreach tindx
	finish_PVD_file(jobName, plotDir);
	if ( GlobalConfig.nSolidBlocks > 0 ) {
	    writeln("writing solid VTK-XML files to directory \"", plotDir, "\"");
	    begin_Visit_file(jobName~"-solid", plotDir, GlobalConfig.nSolidBlocks);
	    begin_PVD_file(jobName~"-solid", plotDir);
	    foreach (tindx; tindx_list_to_plot) {
		writeln("  tindx= ", tindx);
		auto soln = new SolidSolution(jobName, ".", tindx, GlobalConfig.nSolidBlocks);
		if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
		write_VTK_XML_files(jobName, plotDir, soln, tindx, binary_format);
	    } // foreach tindx
	    finish_PVD_file(jobName~"-solid", plotDir);
	} // end if nSolidBlocks > 0
    } // end if vtkxml
    //
    if (tecplotFlag) {
	throw new FlowSolverException("Tecplot output not currently available.");
	// writeln("writing Tecplot file(s) to directory \"", plotDir, "\"");
	// foreach (tindx; tindx_list_to_plot) {
	//     writeln("  tindx= ", tindx);
	//     auto soln = new FlowSolution(jobName, ".", tindx, GlobalConfig.nBlocks);
	//     soln.add_aux_variables(addVarsList);
	//     if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
	//     write_Tecplot_file(jobName, plotDir, soln, tindx);
	// } // foreach tindx
	// if ( GlobalConfig.nSolidBlocks > 0 ) {
	//     writeln("writing solid Tecplot file(s) to directory \"", plotDir, "\"");
	//     foreach (tindx; tindx_list_to_plot) {
	// 	writeln("  tindx= ", tindx);
	// 	auto soln = new SolidSolution(jobName, ".", tindx, GlobalConfig.nSolidBlocks);
	// 	if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
	// 	write_Tecplot_file(jobName, plotDir, soln, tindx);
	//     } // foreach tindx
	// } // end if nSolidBlocks > 0
    } // end if tecplot
    //
    if (probeStr.length > 0) {
	writeln("Probing flow solution at specified points.");
	// The output may go to a user-specified file, or stdout.
	File outFile;
	if (outputFileName.length > 0) {
	    outFile = File(outputFileName, "w");
	    writeln("Output will be sent to File: ", outputFileName);
	} else {
	    outFile = stdout;
	}
	probeStr = probeStr.strip();
	probeStr = removechars(probeStr, "\"");
	double[] xp, yp, zp;
	foreach(triple; probeStr.split(";")) {
	    auto items = triple.split(",");
	    xp ~= to!double(items[0]);
	    yp ~= to!double(items[1]);
	    zp ~= to!double(items[2]);
	}
	foreach (tindx; tindx_list_to_plot) {
	    writeln("  tindx= ", tindx);
	    auto soln = new FlowSolution(jobName, ".", tindx, GlobalConfig.nBlocks);
	    soln.add_aux_variables(addVarsList);
	    if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
	    outFile.writeln(soln.flowBlocks[0].variable_names_as_string());
	    foreach (ip; 0 .. xp.length) {
		auto nearest = soln.find_nearest_cell_centre(xp[ip], yp[ip], zp[ip]);
		size_t ib = nearest[0]; size_t i = nearest[1];
		outFile.writeln(soln.flowBlocks[ib].values_as_string(i));
	    }
	} // end foreach tindx
    } // end if probeStr
    //
    if (sliceListStr.length > 0) {
	writeln("Extracting slices of the flow solution.");
	// The output may go to a user-specified file, or stdout.
	File outFile;
	if (outputFileName.length > 0) {
	    outFile = File(outputFileName, "w");
	    writeln("Output will be sent to File: ", outputFileName);
	} else {
	    outFile = stdout;
	}
	foreach (tindx; tindx_list_to_plot) {
	    writeln("  tindx= ", tindx);
	    auto soln = new FlowSolution(jobName, ".", tindx, GlobalConfig.nBlocks);
	    soln.add_aux_variables(addVarsList);
	    if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
	    //
	    outFile.writeln(soln.flowBlocks[0].variable_names_as_string());
	    foreach (sliceStr; sliceListStr.split(";")) {
		auto rangeStrings = sliceStr.split(",");
		auto blk_range = decode_range_indices(rangeStrings[0], 0, soln.nBlocks);
		foreach (ib; blk_range[0] .. blk_range[1]) {
		    auto blk = soln.flowBlocks[ib];
		    // We need to do the decode in the context of each block because
		    // the upper limits to the indices are specific to the block.
		    auto i_range = decode_range_indices(rangeStrings[1], 0, blk.nic);
		    auto j_range = decode_range_indices(rangeStrings[2], 0, blk.njc);
		    auto k_range = decode_range_indices(rangeStrings[3], 0, blk.nkc);
		    foreach (k; k_range[0] .. k_range[1]) {
			foreach (j; j_range[0] .. j_range[1]) {
			    foreach (i; i_range[0] .. i_range[1]) {
				outFile.writeln(blk.values_as_string(i,j,k));
			    }
			}
		    }
		} // end foreach ib
	    } // end foreach sliceStr
	} // end foreach tindx
    } // end if sliceListStr
    //
    if (surfaceListStr.length > 0) {
	writeln("Extracting named surfaces of the flow solution.");
	foreach (tindx; tindx_list_to_plot) {
	    writeln("  tindx= ", tindx);
	    auto soln = new FlowSolution(jobName, ".", tindx, GlobalConfig.nBlocks);
	    soln.add_aux_variables(addVarsList);
	    foreach (surfaceStr; surfaceListStr.split(";")) {
		auto itemStrings = surfaceStr.split(",");
		size_t blk_indx = to!size_t(itemStrings[0]);
		string boundary_id = itemStrings[1];
		size_t boundary_indx;
		if (canFind(face_name, boundary_id)) {
		    boundary_indx = face_index(boundary_id);
		} else {
		    boundary_indx = to!size_t(boundary_id);
		}
		string fileName = format("%s-t%04d-blk-%04d-surface-%s.vtu",
					 jobName, tindx, blk_indx, boundary_id);
		writeln("fileName=", fileName); // DEBUG
		auto surf_grid = soln.gridBlocks[blk_indx].get_boundary_grid(boundary_indx);
		auto surf_cells = soln.gridBlocks[blk_indx].get_list_of_boundary_cells(boundary_indx);
		size_t new_dimensions = surf_grid.dimensions;
		size_t new_nic = surf_cells.length;
		size_t new_njc = 0;
		size_t new_nkc = 0;
		auto surf_flow = new BlockFlow(soln.flowBlocks[blk_indx], surf_cells,
					       new_dimensions, new_nic, new_njc, new_nkc);
		write_VTK_XML_unstructured_file(surf_flow, surf_grid, fileName, binary_format);
	    } // end foreach surfaceStr
	} // end foreach tindx
    } // end if surfaceListStr
    //
    if (extractStreamStr.length > 0) {
	writeln("Extracting data along a streamline of the flow solution.");
	// The output may go to a user-specified file, or stdout.
	File outFile;
	if (outputFileName.length > 0) {
	    outFile = File(outputFileName, "w");
	    writeln("Output will be sent to File: ", outputFileName);
	} else {
	    outFile = stdout;
	}
	extractStreamStr = extractStreamStr.strip();
	extractStreamStr = removechars(extractStreamStr, "\"");
	double[] xp, yp, zp;
	foreach(triple; extractStreamStr.split(";")) {
	    auto items = triple.split(",");
	    xp ~= to!double(items[0]);
	    yp ~= to!double(items[1]);
	    zp ~= to!double(items[2]);
	}
	double stepSize = 1e-06; // set a temporal step size
	double xInit, yInit, zInit;
	double xOld, yOld, zOld;
	double xNew, yNew, zNew;
	foreach (tindx; tindx_list_to_plot) {
	    writeln("  tindx= ", tindx);
	    auto soln = new FlowSolution(jobName, ".", tindx, GlobalConfig.nBlocks);
	    soln.add_aux_variables(addVarsList);
	    if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
	    outFile.writeln("xStreamPos ", "yStreamPos ", "zStreamPos ",
			    soln.flowBlocks[0].variable_names_as_string());
	    foreach (ip; 0 .. xp.length) {
	        outFile.writeln("# streamline locus point: ", xp[ip], ", ", yp[ip], ", ", zp[ip]);
	        auto identity = soln.find_enclosing_cell(xp[ip], yp[ip], zp[ip]);
		size_t ib = identity[0]; size_t idx = identity[1]; size_t found = identity[2];
		if (found == 0) { // out of domain bounds
		    writeln("User defined point not in solution domain bounds");
		    break;
		}
		else { // store initial cell data
		    xInit = soln.flowBlocks[ib]["pos.x", idx];
		    yInit = soln.flowBlocks[ib]["pos.y", idx];
		    zInit = soln.flowBlocks[ib]["pos.z", idx];
		    outFile.writeln(xInit, " ", yInit, " ", zInit, " ",
				    soln.flowBlocks[ib].values_as_string(idx));
		}
		// we need to travel both forward (direction = 1) and backward (direction = -1)
		int[] direction = [-1, 1];
		double min = 1e-6;
		foreach (direct; direction) {
		    found = 1;
		    xOld = xInit; yOld = yInit; zOld = zInit; 
		    while (found == 1) { // while we have a cell in the domain
		        double vx = soln.flowBlocks[ib]["vel.x", idx];
			double vy = soln.flowBlocks[ib]["vel.y", idx];
			double vz = soln.flowBlocks[ib]["vel.z", idx];
			double dx = direct*vx*stepSize;
			double dy = direct*vy*stepSize;
			double dz = direct*vz*stepSize;
			xNew = xOld + dx; yNew = yOld + dy; zNew = zOld + dz;
			identity = soln.find_enclosing_cell(xNew, yNew, zNew);
			if (identity[0] == ib && identity[1] == idx) {
			    // did not step outside current cell
			    stepSize = stepSize*2.0; found = identity[2];
			} else {
			    ib = identity[0]; idx = identity[1]; found = identity[2];
			    if (found == 1) {
				outFile.writeln(xNew, " ", yNew, " ", zNew, " ",
						soln.flowBlocks[ib].values_as_string(idx));
			    }
			    xOld = xNew; yOld = yNew; zOld = zNew;
			    stepSize = 1e-06;
			} // end else
		    } // end while
		} // end foreach direction
	    } // end for each xp.length
	} // end foreach tindx
    } // end if streamlineStr
    //
    if (extractLineStr.length > 0) {
	writeln("Extracting data along a straight line between end points.");
	// The output may go to a user-specified file, or stdout.
	File outFile;
	if (outputFileName.length > 0) {
	    outFile = File(outputFileName, "w");
	    writeln("Output will be sent to File: ", outputFileName);
	} else {
	    outFile = stdout;
	}
	extractLineStr = extractLineStr.strip();
	extractLineStr = removechars(extractLineStr, "\"");
	foreach (tindx; tindx_list_to_plot) {
	    writeln("  tindx= ", tindx);
	    auto soln = new FlowSolution(jobName, ".", tindx, GlobalConfig.nBlocks);
	    soln.add_aux_variables(addVarsList);
	    if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
	    outFile.writeln(soln.flowBlocks[0].variable_names_as_string());
	    size_t[2][] cells_found; // accumulate the identies of the cells found here
	    // I think that it will be convenient to omit repeated cells so that we can
	    // specify really tiny steps and be sure of sampling all cells and also
	    // be able to specify multiple lines that get concatenated, again without
	    // repeated cells in the output stream.
	    foreach(lineStr; extractLineStr.split(";")) {
		auto items = lineStr.split(",");
		double x0 = to!double(items[0]);
		double y0 = to!double(items[1]);
		double z0 = to!double(items[2]);
		double x1 = to!double(items[3]);
		double y1 = to!double(items[4]);
		double z1 = to!double(items[5]);
		size_t n = to!size_t(items[6]);
		foreach (ip; 0 .. n) {
		    double frac = double(ip) / double(n-1);
		    double x = x0*(1.0-frac) + x1*frac;
		    double y = y0*(1.0-frac) + y1*frac;
		    double z = z0*(1.0-frac) + z1*frac;
		    // outFile.writeln("# point: ", x, ", ", y, ", ", z);
		    auto identity = soln.find_enclosing_cell(x, y, z);
		    size_t ib = identity[0]; size_t idx = identity[1];
		    size_t found = identity[2];
		    if (found == 0) { // out of domain bounds
			writefln("Point %g,%g,%g not in solution domain bounds", x, y, z);
			continue;
		    } else { // store cell data
			if ((cells_found.length == 0) ||
			    (cells_found[$-1][0] != ib) ||
			    (cells_found[$-1][1] != idx)) {
			    // Add only "new" cells.
			    cells_found ~= [ib, idx];
			}
		    }
		} // end foreach ip
	    } // end foreach lineStr
	    foreach(i; 0 .. cells_found.length) {
		size_t ib = cells_found[i][0]; size_t idx = cells_found[i][1];
		outFile.writeln(soln.flowBlocks[ib].values_as_string(idx));
	    }
	} // end foreach tindx
    } // end if extractLineStr
    //
    if (normsStr.length > 0) {
	writeln("Norms for variables.");
	normsStr = normsStr.strip();
	normsStr = removechars(normsStr, "\"");
	foreach (tindx; tindx_list_to_plot) {
	    writeln("  tindx= ", tindx);
	    auto soln = new FlowSolution(jobName, ".", tindx, GlobalConfig.nBlocks);
	    soln.add_aux_variables(addVarsList);
	    if (luaRefSoln.length > 0) soln.subtract_ref_soln(luaRefSoln);
	    //
	    SolidSolution solidSoln;
	    if ( GlobalConfig.nSolidBlocks > 0 ) {
		solidSoln = new SolidSolution(jobName, ".", tindx, GlobalConfig.nSolidBlocks);
		if (luaRefSoln.length > 0) solidSoln.subtract_ref_soln(luaRefSoln);
	    }
	    //
	    // Work on flow blocks first
	    writeln("normsStr= ", normsStr);
	    foreach (varName; normsStr.split(",")) {
		writeln("flow: varName= ", varName);
		if (!canFind(soln.flowBlocks[0].variableNames, varName)) {
		    writeln(format("Requested variable name \"%s\" not in list of flow variables.", varName));
		    continue;
		}
		auto norms = soln.compute_volume_weighted_norms(varName, regionStr);
		write("    variable= ", varName, "\n");
		write(format(" L1= %.18e L2= %.18e Linf= %.18e\n",
			     norms[0], norms[1], norms[2]));
		write(" x= ", norms[3], " y= ", norms[4], " z= ", norms[5]);
		write("\n");
	    } // end foreach varName
	    // Then work on solid blocks
	    if ( GlobalConfig.nSolidBlocks > 0 ) {
		writeln("normsStr= ", normsStr);
		foreach (varName; normsStr.split(",")) {
		    writeln("solid: varName= ", varName);
		    if (!canFind(solidSoln.solidBlocks[0].variableNames, varName)) {
			writeln(format("Requested variable name \"%s\" not in list of solid variables.", varName));
			continue;
		    }
		    auto norms = solidSoln.compute_volume_weighted_norms(varName, regionStr);
		    write("    variable= ", varName, "\n");
		    write(format(" L1= %.18e L2= %.18e Linf= %.18e\n",
				 norms[0], norms[1], norms[2]));
		    write(" x= ", norms[3], " y= ", norms[4], " z= ", norms[5]);
		    write("\n");
		} // end foreach varName
	    } // end if nSolidBlocks > 0
	} // end foreach tindx
    } // end if normsStr
    //
} // end post_process()

//-----------------------------------------------------------------------

size_t[] decode_range_indices(string rangeStr, size_t first, size_t endplus1)
// Decode strings such as "0:$", ":", "0:3", "$"
// On input, first and endplus1 represent the largest, available range.
// Return the pair of numbers that can be used in a foreach loop range.
{
    if (rangeStr == ":") {
	return [first, endplus1];
    }
    if (canFind(rangeStr, ":")) {
	// We have a range specification to pull apart.
	auto items = rangeStr.split(":");
	first = to!size_t(items[0]);
	if (items.length > 1 && items[1] != "$") {
	    // Presume that we have a second integer.
	    size_t new_endplus1 = to!size_t(items[1]);
	    if (new_endplus1 < endplus1) endplus1 = new_endplus1; 
	}
    } else if (rangeStr == "$") {
	// Wit just a single "$" specified, we want only the last index.
	first = endplus1 - 1;
    }else {
	// Presume that we have a single integer.
	first = to!size_t(rangeStr);
	if (first < endplus1) endplus1 = first+1;
    }
    return [first, endplus1];
} // end decode_range_indices()

double[int] readTimesFile(string jobName)
{
    double[int] times_dict;
    // Read the times file for all tindx values.
    auto timesFile = File(jobName ~ ".times");
    auto line = timesFile.readln().strip();
    while (line.length > 0) {
	if (line[0] != '#') {
	    // Process a non-comment line.
	    auto tokens = line.split();
	    times_dict[to!int(tokens[0])] = to!double(tokens[1]);
	}
	line = timesFile.readln().strip();
    }
    timesFile.close();
    return times_dict;
} // end readTimesFile()

//-----------------------------------------------------------------------

void begin_Visit_file(string jobName, string plotDir, int nBlocks)
{
    // Will be handy to have a Visit file, also.
    // For each time index, this justs lists the names of the files for individual blocks.
    ensure_directory_is_present(plotDir);
    string fileName = plotDir ~ "/" ~ jobName ~ ".visit";
    auto visitFile = File(fileName, "w");
    visitFile.writef("!NBLOCKS %d\n", nBlocks);
    visitFile.close();
    return;
} // end begin_Visit_file()

void begin_PVD_file(string jobName, string plotDir)
{
    // Will be handy to have a Paraview collection file, also.
    // For each time index, this justs lists the name of the top-level .pvtu file.
    ensure_directory_is_present(plotDir);
    string fileName = plotDir ~ "/" ~ jobName ~ ".pvd";
    auto pvdFile = File(fileName, "w");
    pvdFile.write("<?xml version=\"1.0\"?>\n");
    pvdFile.write("<VTKFile type=\"Collection\" version=\"0.1\" byte_order=\"LittleEndian\">\n");
    pvdFile.write("<Collection>\n");
    pvdFile.close();
    return;
} // end begin_PVD_file()

void finish_PVD_file(string jobName, string plotDir)
{
    ensure_directory_is_present(plotDir);
    string fileName = plotDir ~ "/" ~ jobName ~ ".pvd";
    auto pvdFile = File(fileName, "a");
    pvdFile.write("</Collection>\n");
    pvdFile.write("</VTKFile>\n");
    pvdFile.close();
    return;
} // end finish_PVD_file()

void write_VTK_XML_files(string jobName, string plotDir,
			 FlowSolution soln, int tindx,
			 bool binary_format=false)
{
    ensure_directory_is_present(plotDir);
    string fileName = plotDir~"/"~jobName~format(".t%04d", tindx)~".pvtu";
    auto pvtuFile = File(fileName, "w");
    pvtuFile.write("<VTKFile type=\"PUnstructuredGrid\">\n");
    pvtuFile.write("<PUnstructuredGrid GhostLevel=\"0\">");
    pvtuFile.write("<PPoints>\n");
    pvtuFile.write(" <PDataArray type=\"Float32\" NumberOfComponents=\"3\"/>\n");
    pvtuFile.write("</PPoints>\n");
    pvtuFile.write("<PCellData>\n");
    foreach (var; soln.flowBlocks[0].variableNames) {
        pvtuFile.writef(" <DataArray Name=\"%s\" type=\"Float32\" NumberOfComponents=\"1\"/>\n", var);
    }
    pvtuFile.write(" <PDataArray Name=\"vel.vector\" type=\"Float32\" NumberOfComponents=\"3\"/>\n");
    if (canFind(soln.flowBlocks[0].variableNames,"c.x")) {
	pvtuFile.write(" <PDataArray Name=\"c.vector\" type=\"Float32\" NumberOfComponents=\"3\"/>\n");
    }
    if (canFind(soln.flowBlocks[0].variableNames,"B.x")) {
	pvtuFile.write(" <PDataArray Name=\"B.vector\" type=\"Float32\" NumberOfComponents=\"3\"/>\n");
    }
    pvtuFile.write("</PCellData>\n");
    foreach (jb; 0 .. soln.nBlocks) {
        fileName = jobName ~ format(".b%04d.t%04d.vtu", jb, tindx);
        // We write the short version of the fileName into the pvtu file.
        pvtuFile.writef("<Piece Source=\"%s\"/>\n", fileName);
        // but use the long version to actually open it.
        fileName = plotDir ~ "/" ~ fileName;
        write_VTK_XML_unstructured_file(soln.flowBlocks[jb], soln.gridBlocks[jb], fileName, binary_format);
    }
    pvtuFile.write("</PUnstructuredGrid>\n");
    pvtuFile.write("</VTKFile>\n");
    pvtuFile.close();
    // Will be handy to have a Visit file, also.
    // This justs lists the names of the files for individual blocks.
    fileName = plotDir ~ "/" ~ jobName ~ ".visit";
    // Note that we append to the visit file for each tindx.
    auto visitFile = File(fileName, "a");
    foreach (jb; 0 .. soln.nBlocks) {
        fileName = jobName ~ format(".b%04d.t%04d.vtu", jb, tindx);
        visitFile.writef("%s\n", fileName);
    }
    visitFile.close();
    // Will be handy to have a Paraview PVD file, also.
    // This justs lists the top-level .pvtu files.
    fileName = plotDir ~ "/" ~ jobName ~ ".pvd";
    // Note that we append to the .pvd file for each tindx.
    auto pvdFile = File(fileName, "a");
    fileName = jobName ~ format(".t%04d.pvtu", tindx);
    pvdFile.writef("<DataSet timestep=\"%.18e\" group=\"\" part=\"0\" file=\"%s\"/>\n",
		   soln.sim_time, fileName);
    pvdFile.close();
    return;
} // end write_VTK_XML_files()

// This version is for writing out solid domain files
void write_VTK_XML_files(string jobName, string plotDir,
			 SolidSolution soln, int tindx,
			 bool binary_format=false)
{
    ensure_directory_is_present(plotDir);
    string fileName = plotDir~"/"~jobName~format("-solid.t%04d", tindx)~".pvtu";
    auto pvtuFile = File(fileName, "w");
    pvtuFile.write("<VTKFile type=\"PUnstructuredGrid\">\n");
    pvtuFile.write("<PUnstructuredGrid GhostLevel=\"0\">");
    pvtuFile.write("<PPoints>\n");
    pvtuFile.write(" <PDataArray type=\"Float32\" NumberOfComponents=\"3\"/>\n");
    pvtuFile.write("</PPoints>\n");
    pvtuFile.write("<PCellData>\n");
    foreach (var; soln.solidBlocks[0].variableNames) {
        pvtuFile.writef(" <DataArray Name=\"%s\" type=\"Float32\" NumberOfComponents=\"1\"/>\n", var);
    }
    pvtuFile.write("</PCellData>\n");
    foreach (jb; 0 .. soln.nBlocks) {
        fileName = jobName~format("-solid.b%04d.t%04d.vtu", jb, tindx);
        // We write the short version of the fileName into the pvtu file.
        pvtuFile.writef("<Piece Source=\"%s\"/>\n", fileName);
        // but use the long version to actually open it.
        fileName = plotDir ~ "/" ~ fileName;
        write_VTK_XML_unstructured_file(soln, jb, fileName, binary_format);
    }
    pvtuFile.write("</PUnstructuredGrid>\n");
    pvtuFile.write("</VTKFile>\n");
    pvtuFile.close();
    // Will be handy to have a Visit file, also.
    // This justs lists the names of the files for individual blocks.
    fileName = plotDir ~ "/" ~ jobName ~ "-solid.visit";
    // Note that we append to the visit file for each tindx.
    auto visitFile = File(fileName, "a");
    foreach (jb; 0 .. soln.nBlocks) {
        fileName = jobName ~ format("-solid.b%04d.t%04d.vtu", jb, tindx);
        visitFile.writef("%s\n", fileName);
    }
    visitFile.close();
    // Will be handy to have a Paraview PVD file, also.
    // This justs lists the top-level .pvtu files.
    fileName = plotDir ~ "/" ~ jobName ~ "-solid.pvd";
    // Note that we append to the .pvd file for each tindx.
    auto pvdFile = File(fileName, "a");
    fileName = jobName ~ format("-solid.t%04d.pvtu", tindx);
    pvdFile.writef("<DataSet timestep=\"%.18e\" group=\"\" part=\"0\" file=\"%s\"/>\n",
		   soln.sim_time, fileName);
    pvdFile.close();
    return;
} // end write_VTK_XML_files()

void write_VTK_XML_unstructured_file(BlockFlow flow, Grid grid, 
				     string fileName, bool binary_format)
// Write the cell-centred flow data from a single block (index jb)
// as an unstructured grid of finite-volume cells.
{
    auto fp = File(fileName, "wb"); // We may be writing some binary data.
    // auto flow = soln.flowBlocks[jb];
    // auto grid = soln.gridBlocks[jb];
    ubyte[] binary_data_string;
    ubyte[] binary_data;
    int binary_data_offset = 0;
    bool two_D = (grid.dimensions == 2);
    size_t NumberOfPoints = grid.nvertices;
    if (flow.ncells != grid.ncells) {
	string msg = text("Mismatch between grid and flow grid.ncells=",
			  grid.ncells, " flow.ncells=", flow.ncells);
	throw new FlowSolverException(msg);
    }
    size_t NumberOfCells = flow.ncells;
    fp.write("<VTKFile type=\"UnstructuredGrid\" byte_order=\"BigEndian\">\n");
    fp.write("<UnstructuredGrid>");
    fp.writef("<Piece NumberOfPoints=\"%d\" NumberOfCells=\"%d\">\n",
	      NumberOfPoints, NumberOfCells);
    //
    fp.write("<Points>\n");
    fp.write(" <DataArray type=\"Float32\" NumberOfComponents=\"3\"");
    if (binary_format) {
	fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	binary_data.length=0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    foreach (i; 0 .. grid.nvertices) {
	float x = uflowz(grid[i].x);
	float y = uflowz(grid[i].y);
	float z = uflowz(grid[i].z);
	if (binary_format) {
	    binary_data ~= nativeToBigEndian(x);
	    binary_data ~= nativeToBigEndian(y);
	    binary_data ~= nativeToBigEndian(z);
	} else {
	    fp.writef(" %.18e %.18e %.18e\n", x,y,z);
	}
    }
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    fp.write("</Points>\n");
    //
    fp.write("<Cells>\n");
    fp.write(" <DataArray type=\"Int32\" Name=\"connectivity\"");
    if (binary_format) {
	fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	binary_data.length = 0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    foreach (i; 0 .. grid.ncells) {
	auto ids = grid.get_vtx_id_list_for_cell(i);
	if (binary_format) {
	    foreach (id; ids) { binary_data ~= nativeToBigEndian(to!int32_t(id)); }
	} else {
	    foreach (id; ids) { fp.writef(" %d", id); }
	    fp.write("\n");
	}
    } // end foreach i
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    //
    fp.write(" <DataArray type=\"Int32\" Name=\"offsets\"");
    if (binary_format) {
	fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	binary_data.length = 0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    // Since all of the point-lists are concatenated, these offsets into the connectivity
    // array specify the end of each cell.
    size_t conn_offset = 0;
    foreach (i; 0 .. grid.ncells) {
	conn_offset += grid.number_of_vertices_for_cell(i);
	if (binary_format) {
	    binary_data ~= nativeToBigEndian(to!int32_t(conn_offset));
	} else {
	    fp.writef(" %d\n", conn_offset);
	}
    } // end foreach i
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    //
    fp.write(" <DataArray type=\"UInt8\" Name=\"types\"");
    if (binary_format) {
        fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
        binary_data.length = 0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    foreach (i; 0 .. grid.ncells) {
	int type_value = grid.vtk_element_type_for_cell(i);
	if (binary_format) {
	    binary_data ~= nativeToBigEndian(to!uint8_t(type_value));
	} else {
	    fp.writef(" %d\n", type_value);
	}
    } // end foreach i
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    fp.write("</Cells>\n");
    //
    fp.write("<CellData>\n");
    // Write variables from the dictionary.
    foreach (var; flow.variableNames) {
        fp.writef(" <DataArray Name=\"%s\" type=\"Float32\" NumberOfComponents=\"1\"", var);
        if (binary_format) {
	    fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	    binary_data.length = 0;
        } else {
            fp.write(" format=\"ascii\">\n");
	}
	foreach (i; 0 .. flow.ncells) {
	    if (binary_format) {
		binary_data ~= nativeToBigEndian(to!float(uflowz(flow[var,i])));
	    } else {
		fp.writef(" %.18e\n", uflowz(flow[var,i]));
	    }
	} // end foreach i
	fp.write(" </DataArray>\n");
        if (binary_format) {
	    uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
	    binary_data_string ~= nativeToBigEndian(binary_data_count);
	    binary_data_string ~= binary_data;
	    binary_data_offset += 4 + binary_data.length;
	}
    } // end foreach var
    //
    // Write the special variables:
    // i.e. variables constructed from those in the dictionary.
    fp.write(" <DataArray Name=\"vel.vector\" type=\"Float32\" NumberOfComponents=\"3\"");
    if (binary_format) {
        fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
        binary_data.length = 0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    foreach (i; 0 .. flow.ncells) {
	float x = uflowz(flow["vel.x",i]);
	float y = uflowz(flow["vel.y",i]);
	float z = uflowz(flow["vel.z",i]);
	if (binary_format) {
	    binary_data ~= nativeToBigEndian(x);
	    binary_data ~= nativeToBigEndian(y);
	    binary_data ~= nativeToBigEndian(z);
	} else {
	    fp.writef(" %.18e %.18e %.18e\n", x, y, z);
	}
    } // end foreach i
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    //
    if (canFind(flow.variableNames, "c.x")) {
	fp.write(" <DataArray Name=\"c.vector\" type=\"Float32\" NumberOfComponents=\"3\"");
        if (binary_format) {
	    fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	    binary_data.length = 0;
        } else {
            fp.write(" format=\"ascii\">\n");
	}
	foreach (i; 0 .. flow.ncells) {
	    float x = uflowz(flow["c.x",i]);
	    float y = uflowz(flow["c.y",i]);
	    float z = uflowz(flow["c.z",i]);
	    if (binary_format) {
		binary_data ~= nativeToBigEndian(x);
		binary_data ~= nativeToBigEndian(y);
		binary_data ~= nativeToBigEndian(z);
	    } else {
		fp.writef(" %.18e %.18e %.18e\n", x, y, z);
	    }
	} // end foreach i
	fp.write(" </DataArray>\n");
	if (binary_format) {
	    uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
	    binary_data_string ~= nativeToBigEndian(binary_data_count);
	    binary_data_string ~= binary_data;
	    binary_data_offset += 4 + binary_data.length;
	}
    } // if canFind c.x
    //
    if (canFind(flow.variableNames, "B.x")) {
	fp.write(" <DataArray Name=\"B.vector\" type=\"Float32\" NumberOfComponents=\"3\"");
        if (binary_format) {
	    fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	    binary_data.length = 0;
        } else {
            fp.write(" format=\"ascii\">\n");
	}
	foreach (i; 0 .. flow.ncells) {
	    float x = uflowz(flow["B.x",i]);
	    float y = uflowz(flow["B.y",i]);
	    float z = uflowz(flow["B.z",i]);
	    if (binary_format) {
		binary_data ~= nativeToBigEndian(x);
		binary_data ~= nativeToBigEndian(y);
		binary_data ~= nativeToBigEndian(z);
	    } else {
		fp.writef(" %.18e %.18e %.18e\n", x, y, z);
	    }
	} // end foreach i
	fp.write(" </DataArray>\n");
	if (binary_format) {
	    uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
	    binary_data_string ~= nativeToBigEndian(binary_data_count);
	    binary_data_string ~= binary_data;
	    binary_data_offset += 4 + binary_data.length;
	}
    } // if canFind B.x
    //
    fp.write("</CellData>\n");
    fp.write("</Piece>\n");
    fp.write("</UnstructuredGrid>\n");
    if (binary_format) {
        fp.write("<AppendedData encoding=\"raw\">\n");
        fp.write('_');
        fp.rawWrite(binary_data_string);
        fp.write("</AppendedData>\n");
    }
    fp.write("</VTKFile>\n");
    fp.close();
    return;
} // end write_VTK_XML_unstructured_file()


// This version is for the solid domain.
void write_VTK_XML_unstructured_file(SolidSolution soln, size_t jb, 
				     string fileName, bool binary_format)
// Write the cell-centred flow data from a single block (index jb)
// as an unstructured grid of finite-volume cells.
{
    auto fp = File(fileName, "wb"); // We may be writing some binary data.
    auto solid = soln.solidBlocks[jb];
    auto grid = soln.gridBlocks[jb];
    ubyte[] binary_data_string;
    ubyte[] binary_data;
    int binary_data_offset = 0;
    size_t niv = grid.niv; size_t njv = grid.njv; size_t nkv = grid.nkv;
    size_t nic = solid.nic; size_t njc = solid.njc; size_t nkc = solid.nkc;
    bool two_D = (nkv == 1);
    size_t NumberOfPoints = niv * njv * nkv;
    size_t NumberOfCells = nic * njc * nkc;
    fp.write("<VTKFile type=\"UnstructuredGrid\" byte_order=\"BigEndian\">\n");
    fp.write("<UnstructuredGrid>");
    fp.writef("<Piece NumberOfPoints=\"%d\" NumberOfCells=\"%d\">\n",
	      NumberOfPoints, NumberOfCells);
    //
    fp.write("<Points>\n");
    fp.write(" <DataArray type=\"Float32\" NumberOfComponents=\"3\"");
    if (binary_format) {
	fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	binary_data.length=0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    size_t vtx_number = 0;
    size_t[][][] vtx_id;
    vtx_id.length = niv;
    foreach (i; 0 .. niv) {
	vtx_id[i].length = njv;
	foreach (j; 0 .. njv) {
	    vtx_id[i][j].length = nkv;
	}
    }
    foreach (k; 0 .. nkv) {
        foreach (j; 0 .. njv) {
            foreach (i; 0 .. niv) {
                vtx_id[i][j][k] = vtx_number;
                float x = uflowz(grid[i,j,k].x);
		float y = uflowz(grid[i,j,k].y);
		float z = uflowz(grid[i,j,k].z);
                if (binary_format) {
		    binary_data ~= nativeToBigEndian(x);
		    binary_data ~= nativeToBigEndian(y);
		    binary_data ~= nativeToBigEndian(z);
                } else {
                    fp.writef(" %.18e %.18e %.18e\n", x,y,z);
		}
                vtx_number += 1;
	    }
	}
    }
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    fp.write("</Points>\n");
    //
    fp.write("<Cells>\n");
    fp.write(" <DataArray type=\"Int32\" Name=\"connectivity\"");
    if (binary_format) {
	fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	binary_data.length = 0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    foreach (k; 0 .. nkc) {
        foreach (j; 0 .. njc) {
            foreach (i; 0 .. nic) {
                if (two_D) {
                    auto ids = [vtx_id[i][j][k], vtx_id[i+1][j][k],
				vtx_id[i+1][j+1][k], vtx_id[i][j+1][k]];
                    if (binary_format) {
			foreach (id; ids) { binary_data ~= nativeToBigEndian(to!int32_t(id)); }
                    } else {
                        fp.writef(" %d %d %d %d\n", ids[0], ids[1], ids[2], ids[3]);
		    }
                } else {
                    auto ids = [vtx_id[i][j][k], vtx_id[i+1][j][k], 
				vtx_id[i+1][j+1][k], vtx_id[i][j+1][k],
				vtx_id[i][j][k+1], vtx_id[i+1][j][k+1], 
				vtx_id[i+1][j+1][k+1], vtx_id[i][j+1][k+1]];
                    if (binary_format) {
			foreach (id; ids) { binary_data ~= nativeToBigEndian(to!int32_t(id)); }
                    } else {
                        fp.writef(" %d %d %d %d %d %d %d %d\n", ids[0], ids[1], ids[2],
				  ids[3], ids[4], ids[5], ids[6], ids[7]);
		    }
		}
	    } // end foreach i
	} // end foreach j
    } // end foreach k
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    //
    fp.write(" <DataArray type=\"Int32\" Name=\"offsets\"");
    if (binary_format) {
	fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	binary_data.length = 0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    // Since all of the point-lists are concatenated, these offsets into the connectivity
    // array specify the end of each cell.
    foreach (k; 0 .. nkc) {
        foreach (j; 0 .. njc) {
            foreach (i; 0 .. nic) {
		size_t conn_offset;
                if (two_D) {
                    conn_offset = 4*(1+i+j*nic);
                } else {
                    conn_offset = 8*(1+i+j*nic+k*(nic*njc));
		}
		if (binary_format) {
                    binary_data ~= nativeToBigEndian(to!int32_t(conn_offset));
                } else {
                    fp.writef(" %d\n", conn_offset);
		}
	    } // end foreach i
	} // end foreach j
    } // end foreach k
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    //
    fp.write(" <DataArray type=\"UInt8\" Name=\"types\"");
    if (binary_format) {
        fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
        binary_data.length = 0;
    } else {
        fp.write(" format=\"ascii\">\n");
    }
    int type_value;
    if (two_D) {
        type_value = 9; // VTK_QUAD
    } else {
        type_value = 12; // VTK_HEXAHEDRON
    }
    foreach (k; 0 .. nkc) {
        foreach (j; 0 .. njc) {
            foreach (i; 0 .. nic) {
                if (binary_format) {
                    binary_data ~= nativeToBigEndian(to!uint8_t(type_value));
                } else {
                    fp.writef(" %d\n", type_value);
		}
	    } // end foreach i
	} // end foreach j
    } // end foreach k
    fp.write(" </DataArray>\n");
    if (binary_format) {
        uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
        binary_data_string ~= nativeToBigEndian(binary_data_count);
        binary_data_string ~= binary_data;
        binary_data_offset += 4 + binary_data.length;
    }
    fp.write("</Cells>\n");
    //
    fp.write("<CellData>\n");
    // Write variables from the dictionary.
    foreach (var; solid.variableNames) {
        fp.writef(" <DataArray Name=\"%s\" type=\"Float32\" NumberOfComponents=\"1\"", var);
        if (binary_format) {
	    fp.writef(" format=\"appended\" offset=\"%d\">", binary_data_offset);
	    binary_data.length = 0;
        } else {
            fp.write(" format=\"ascii\">\n");
	}
        foreach (k; 0 .. nkc) {
            foreach (j; 0 .. njc) {
                foreach (i; 0 .. nic) {
                    if (binary_format) {
                        binary_data ~= nativeToBigEndian(to!float(uflowz(solid[var,i,j,k])));
                    } else {
                        fp.writef(" %.18e\n", uflowz(solid[var,i,j,k]));
		    }
		} // end foreach i
	    } // end foreach j
	} // end foreach k
	fp.write(" </DataArray>\n");
        if (binary_format) {
	    uint32_t binary_data_count = to!uint32_t(binary_data.length); // 4-byte count of bytes
	    binary_data_string ~= nativeToBigEndian(binary_data_count);
	    binary_data_string ~= binary_data;
	    binary_data_offset += 4 + binary_data.length;
	}
    } // end foreach var
    //
    fp.write("</CellData>\n");
    fp.write("</Piece>\n");
    fp.write("</UnstructuredGrid>\n");
    if (binary_format) {
        fp.write("<AppendedData encoding=\"raw\">\n");
        fp.write('_');
        fp.rawWrite(binary_data_string);
        fp.write("</AppendedData>\n");
    }
    fp.write("</VTKFile>\n");
    fp.close();
    return;
} // end write_VTK_XML_unstructured_file()
