/** main.d
 * Eilmer4 compressible-flow simulation code, top-level function.
 *
 * Author: Peter J. and Rowan G. 
 * First code: 2015-02-05
 */

import core.memory;
import core.stdc.stdlib : exit;
import std.stdio;
import std.string;
import std.file;
import std.path;
import std.getopt;
import std.conv;
import std.parallelism;
import std.algorithm;

import geom;
import gas;
import gas.luagas_model;
import kinetics.luareaction_mechanism;
import kinetics.luachemistry_update;
import nm.luabbla;
import fvcore: FlowSolverException;
import globalconfig;
import simcore;
import util.lua;
import luaglobalconfig;
import luaflowstate;
import luaflowsolution;
import luageom;
import luagpath;
import luasurface;
import luavolume;
import luaunifunction;
import luasgrid;
import luausgrid;
import luasketch;
import luasolidprops;
import postprocess;
import luaflowsolution;
import luaidealgasflow;
import luagasflow;
version(mpi_parallel) {
    import mpi;
    import mpi.util;
}

void moveFileToBackup(string fileName)
{
    if (exists(fileName)) {
	if (exists(fileName~".bak")) { remove(fileName~".bak"); }
	rename(fileName, fileName~".bak");
    }
    return;
}

int main(string[] args)
{
    int exitFlag = 0; // Presume OK in the beginning.
    //
    version(mpi_parallel) {
	// This preamble copied directly from the OpenMPI hello-world example.
	int argc = cast(int)args.length;
	auto argv = args.toArgv();
	int rank;
	int size;
	MPI_Init(&argc, &argv);
	MPI_Comm_rank(MPI_COMM_WORLD, &rank);
	MPI_Comm_size(MPI_COMM_WORLD, &size);
	scope(exit) { MPI_Finalize(); }
    }
    //
    string msg = "Usage:                               Comment:\n";
    msg       ~= "e4shared [--job=<string>]            file names built from this string\n";
    msg       ~= "         [--verbosity=<int>]         defaults to 0\n";
    msg       ~= "\n";
    msg       ~= "         [--prep]                    prepare config, grid and flow files\n";
    msg       ~= "\n";
    msg       ~= "         [--run]                     run the simulation over time\n";
    msg       ~= "         [--tindx-start=<int>|last|9999]  defaults to 0\n";
    msg       ~= "         [--max-cpus=<int>]          defaults to ";
    msg       ~= to!string(totalCPUs) ~" on this machine\n";
    msg       ~= "         [--max-wall-clock=<int>]    in seconds\n";
    msg       ~= "         [--report-residuals]        include residual reporting in console output\n";
    msg       ~= "\n";
    msg       ~= "         [--post]                    post-process simulation data\n";
    msg       ~= "         [--list-info]               report some details of this simulation\n";
    msg       ~= "         [--tindx-plot=<int>|all|last|9999]  default to last\n";
    msg       ~= "         [--add-vars=\"mach,pitot,total-h,total-p,entropy\"]\n";
    msg       ~= "         [--ref-soln=<filename>]     Lua file for reference solution\n";
    msg       ~= "         [--vtk-xml]                 produce XML VTK-format plot files\n";
    msg       ~= "         [--binary-format]           use binary within the VTK-XML\n";
    msg       ~= "         [--tecplot]                 write a binary szplt file in Tecplot format\n";
    msg       ~= "         [--tecplot-ascii]           write an ASCII (text) file in Tecplot format\n";
    msg       ~= "         [--plot-dir=<string>]       defaults to plot\n";
    msg       ~= "         [--output-file=<string>]    defaults to stdout\n";
    msg       ~= "         [--slice-list=\"blk-range,i-range,j-range,k-range;...\"]\n";
    msg       ~= "         [--surface-list=\"blk,surface-id;...\"]\n";
    msg       ~= "         [--extract-streamline=\"x,y,z;...\"]        streamline locus points\n";
    msg       ~= "         [--extract-line=\"x0,y0,z0,x1,y1,z1,n;...\"]    sample along a line in flow blocks\n";
    msg       ~= "         [--extract-solid-line=\"x0,y0,z0,x1,y1,z1,n;...\"]    sample along a line in solid blocks\n";
    msg       ~= "         [--compute-loads-on-group=\"\"]    group tag\n";
    msg       ~= "         [--probe=\"x,y,z;...\"]       locations to sample flow data\n";
    msg       ~= "         [--output-format=<string>]  gnuplot|pretty\n";
    msg       ~= "         [--norms=\"varName,varName,...\"] report L1,L2,Linf norms\n";
    msg       ~= "         [--region=\"x0,y0,z0,x1,y1,z1\"]  limit norms calculation to a box\n";
    msg       ~= "\n";
    msg       ~= "         [--custom-post]             run custom post-processing script\n";
    msg       ~= "         [--script-file=<string>]    defaults to post.lua\n";
    msg       ~= "\n";
    msg       ~= "         [--help]                    writes this message\n";
    if ( args.length < 2 ) {
	writeln("Too few arguments.");
	write(msg);
	exitFlag = 1;
	return exitFlag;
    }
    string jobName = "";
    int verbosityLevel = 1; // default to having a little information
    bool prepFlag = false;
    bool runFlag = false;
    string tindxStartStr = "0";
    int tindxStart = 0;
    int maxCPUs = totalCPUs;
    int maxWallClock = 5*24*3600; // 5 days default
    bool reportResiduals = false;
    bool postFlag = false;
    bool listInfoFlag = false;
    string tindxPlot = "last";
    string addVarsStr = "";
    string luaRefSoln = "";
    bool vtkxmlFlag = false;
    bool binaryFormat = false;
    bool tecplotBinaryFlag = false;
    bool tecplotAsciiFlag = false;
    string plotDir = "plot";
    string outputFileName = "";
    string sliceListStr = "";
    string surfaceListStr = "";
    string extractStreamStr = "";
    string extractLineStr = "";
    string extractSolidLineStr = "";
    string computeLoadsOnGroupStr = "";
    string probeStr = "";
    string outputFormat = "gnuplot";
    string normsStr = "";
    string regionStr = "";
    bool customPostFlag = false;
    string scriptFile = "post.lua";
    bool helpWanted = false;
    try {
	getopt(args,
	       "job", &jobName,
	       "verbosity", &verbosityLevel,
	       "prep", &prepFlag,
	       "run", &runFlag,
	       "tindx-start", &tindxStartStr,
	       "max-cpus", &maxCPUs,
	       "max-wall-clock", &maxWallClock,
	       "report-residuals", &reportResiduals,
	       "post", &postFlag,
	       "list-info", &listInfoFlag,
	       "tindx-plot", &tindxPlot,
	       "add-vars", &addVarsStr,
               "ref-soln", &luaRefSoln,
	       "vtk-xml", &vtkxmlFlag,
	       "binary-format", &binaryFormat,
	       "tecplot", &tecplotBinaryFlag,
	       "tecplot-ascii", &tecplotAsciiFlag,
	       "plot-dir", &plotDir,
	       "output-file", &outputFileName,
	       "slice-list", &sliceListStr,
	       "surface-list", &surfaceListStr,
	       "extract-streamline", &extractStreamStr,
	       "extract-line", &extractLineStr,
	       "extract-solid-line", &extractSolidLineStr,
	       "compute-loads-on-group", &computeLoadsOnGroupStr,
	       "probe", &probeStr,
	       "output-format", &outputFormat,
	       "norms", &normsStr,
	       "region", &regionStr,
	       "custom-post", &customPostFlag,
	       "script-file", &scriptFile,
	       "help", &helpWanted
	       );
    } catch (Exception e) {
	writeln("Problem parsing command-line options.");
	writeln("Arguments not processed: ");
	args = args[1 .. $]; // Dispose of program name in first argument.
	foreach (myarg; args) writeln("    arg: ", myarg);
	write(msg);
	exitFlag = 1;
	return exitFlag;
    }
    if (verbosityLevel > 0) {
	version(mpi_parallel) {
	    if (rank == 0) {
		writeln("Eilmer4 compressible-flow simulation code.");
		writeln("Revision: PUT_REVISION_STRING_HERE");
	    }
	    writefln("MPI rank=%d size=%d", rank, size);
	    MPI_Barrier(MPI_COMM_WORLD);
	} else {
	    writeln("Eilmer4 compressible-flow simulation code.");
	    writeln("Revision: PUT_REVISION_STRING_HERE");
	    writeln("Shared-memory");
	}
    }
    if (helpWanted) {
	write(msg);
	exitFlag = 0;
	return exitFlag;
    }
    //
    if (prepFlag) {
	if (verbosityLevel > 0) { writeln("Begin preparation stage for a simulation."); }
	if (jobName.length == 0) {
	    writeln("Need to specify a job name.");
	    write(msg);
	    exitFlag = 1;
	    return exitFlag;
	}
	if (verbosityLevel > 1) { writeln("Start lua connection."); }
	auto L = luaL_newstate();
	luaL_openlibs(L);
	registerVector3(L);
	registerGlobalConfig(L);
	registerFlowSolution(L);
	registerFlowState(L);
	registerPaths(L);
	registerSurfaces(L);
	registerVolumes(L);
	registerUnivariateFunctions(L);
	registerStructuredGrid(L);
	registerUnstructuredGrid(L);
	registerSketch(L);
	registerSolidProps(L);
	registerGasModel(L, LUA_GLOBALSINDEX);
	registeridealgasflowFunctions(L);
	registergasflowFunctions(L);
	registerBBLA(L);
	// Before processing the Lua input files, move old .config and .control files.
	// This should prevent a subsequent run of the simulation on old config files
	// in the case that the processing of the input script fails.
	moveFileToBackup(jobName~".config");
	moveFileToBackup(jobName~".control");
	if ( luaL_dofile(L, toStringz(dirName(thisExePath())~"/prep.lua")) != 0 ) {
	    writeln("There was a problem in the Eilmer Lua code: prep.lua");
	    string errMsg = to!string(lua_tostring(L, -1));
	    throw new FlowSolverException(errMsg);
	}
	if ( luaL_dofile(L, toStringz(jobName~".lua")) != 0 ) {
	    writeln("There was a problem in the user-supplied input lua script: ", jobName~".lua");
	    string errMsg = to!string(lua_tostring(L, -1));
	    throw new FlowSolverException(errMsg);
	}
	checkGlobalConfig(); // We may not proceed if the config parameters are incompatible.
	if ( luaL_dostring(L, toStringz("build_job_files(\""~jobName~"\")")) != 0 ) {
	    writeln("There was a problem in the Eilmer build function build_job_files() in prep.lua");
	    string errMsg = to!string(lua_tostring(L, -1));
	    throw new FlowSolverException(errMsg);
	}
	if (verbosityLevel > 0) { writeln("Done preparation."); }
    } // end if prepFlag

    if (runFlag) {
	if (jobName.length == 0) {
	    writeln("Need to specify a job name.");
	    write(msg);
	    exitFlag = 1;
	    return exitFlag;
	}
	GlobalConfig.base_file_name = jobName;
	GlobalConfig.verbosity_level = verbosityLevel;
	GlobalConfig.report_residuals = reportResiduals;
	maxCPUs = min(max(maxCPUs, 1), totalCPUs); // don't ask for more than available
	switch (tindxStartStr) {
	case "9999":
	case "last":
	    auto times_dict = readTimesFile(jobName);
            auto tindx_list = times_dict.keys;
	    sort(tindx_list);
	    tindxStart = tindx_list[$-1];
	    break;
	default:
	    // We assume that the command-line argument was an integer.
	    tindxStart = to!int(tindxStartStr);
	} // end switch
	if (verbosityLevel > 0) {
	    writeln("Begin simulation with command-line arguments.");
	    writeln("  jobName: ", jobName);
	    writeln("  tindxStart: ", tindxStart);
	    writeln("  maxWallClock: ", maxWallClock);
	    writeln("  verbosityLevel: ", verbosityLevel);
	    writeln("  maxCPUs: ", maxCPUs);
	}
	
	init_simulation(tindxStart, maxCPUs, maxWallClock);
	if (verbosityLevel > 0) { writeln("starting simulation time= ", simcore.sim_time); }
	if (GlobalConfig.block_marching) {
	    march_over_blocks();
	} else {
	    integrate_in_time(GlobalConfig.max_time);
	}
	finalize_simulation();
	if (verbosityLevel > 0) { writeln("Done simulation."); }
    } // end if runFlag

    if (postFlag) {
	if (jobName.length == 0) {
	    writeln("Need to specify a job name.");
	    write(msg);
	    exitFlag = 1;
	    return exitFlag;
	}
	GlobalConfig.base_file_name = jobName;
	GlobalConfig.verbosity_level = verbosityLevel;
	if (verbosityLevel > 0) {
	    writeln("Begin post-processing with command-line arguments.");
	    writeln("  jobName: ", jobName);
	    writeln("  verbosityLevel: ", verbosityLevel);
	}
	if (verbosityLevel > 1) {
	    writeln("  listInfoFlag: ", listInfoFlag);
	    writeln("  tindxPlot: ", tindxPlot);
	    writeln("  addVarsStr: ", addVarsStr);
	    writeln("  luaRefSoln: ", luaRefSoln);
	    writeln("  vtkxmlFlag: ", vtkxmlFlag);
	    writeln("  binaryFormat: ", binaryFormat);
	    writeln("  tecplotBinaryFlag: ", tecplotBinaryFlag);
	    writeln("  tecplotAsciiFlag: ", tecplotAsciiFlag);
	    writeln("  plotDir: ", plotDir);
	    writeln("  outputFileName: ", outputFileName);
	    writeln("  sliceListStr: ", sliceListStr);
	    writeln("  surfaceListStr: ", surfaceListStr);
	    writeln("  extractStreamStr: ", extractStreamStr);
	    writeln("  extractLineStr: ", extractLineStr);
	    writeln("  extractSolidLineStr: ", extractSolidLineStr);
	    writeln("  computeLoadsOnGroupStr: ", computeLoadsOnGroupStr);
	    writeln("  probeStr: ", probeStr);
	    writeln("  outputFormat: ", outputFormat);
	    writeln("  normsStr: ", normsStr);
	    writeln("  regionStr: ", regionStr);
	}
	post_process(plotDir, listInfoFlag, tindxPlot,
		     addVarsStr, luaRefSoln,
		     vtkxmlFlag, binaryFormat, tecplotBinaryFlag, tecplotAsciiFlag,
		     outputFileName, sliceListStr, surfaceListStr,
		     extractStreamStr, extractLineStr, computeLoadsOnGroupStr,
		     probeStr, outputFormat, normsStr, regionStr, extractSolidLineStr);
	if (verbosityLevel > 0) { writeln("Done postprocessing."); }
    } // end if postFlag

    if (customPostFlag) {
	if (verbosityLevel > 0) { 
	    writeln("Begin custom post-processing using user-supplied script.");
	}
	// For this case, there is very little job context loaded and
	// after loading all of the libraries, we pretty much hand over
	// to a Lua file to do everything.
	if (verbosityLevel > 1) { writeln("Start lua connection."); }
	auto L = luaL_newstate();
	luaL_openlibs(L);
	registerVector3(L);
	registerGlobalConfig(L);
	registerFlowSolution(L);
	registerFlowState(L);
	registerPaths(L);
	registerSurfaces(L);
	registerVolumes(L);
	registerUnivariateFunctions(L);
	registerStructuredGrid(L);
	registerUnstructuredGrid(L);
	registerSketch(L);
	registerSolidProps(L);
	registerGasModel(L, LUA_GLOBALSINDEX);
	registerReactionMechanism(L, LUA_GLOBALSINDEX);
	registerChemistryUpdate(L, LUA_GLOBALSINDEX);
	registeridealgasflowFunctions(L);
	registergasflowFunctions(L);
	if ( luaL_dofile(L, toStringz(scriptFile)) != 0 ) {
	    writeln("There was a problem in the user-supplied Lua script: ", scriptFile);
	    string errMsg = to!string(lua_tostring(L, -1));
	    throw new FlowSolverException(errMsg);
	}
	if (verbosityLevel > 0) { writeln("Done custom postprocessing."); }
    } // end if customPostFlag
    //
    return exitFlag;
} // end main()


