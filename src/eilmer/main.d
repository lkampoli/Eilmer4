/** main.d
 * Eilmer 4.0 compressible-flow simulation code, top-level function.
 *
 * Author: Peter J. and Rowan G. 
 * First code: 2015-02-05
 */

import core.memory;
import core.thread;
import core.stdc.stdlib : exit;
import std.stdio;
import std.string;
import std.file;
import std.path;
import std.getopt;
import std.conv;
import std.parallelism;
import std.algorithm;
import std.math;

import geom;
import gas;
import gas.luagas_model;
import kinetics.luathermochemical_reactor;
import kinetics.luareaction_mechanism;
import kinetics.luachemistry_update;
import kinetics.luatwo_temperature_air_kinetics;
import kinetics.luaelectronically_specific_kinetics;
import nm.luabbla;
import fvcore: FlowSolverException;
import globalconfig;
import simcore;
import util.lua;
import geom.luawrap;
import luaglobalconfig;
import luaflowstate;
import luaflowsolution;
import luasolidprops;
import postprocess;
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
    version(mpi_parallel) {
        // This preamble copied directly from the OpenMPI hello-world example.
        int argc = cast(int)args.length;
        auto argv = args.toArgv();
        MPI_Init(&argc, &argv);
        int rank, size;
        MPI_Comm_rank(MPI_COMM_WORLD, &rank);
        GlobalConfig.mpi_rank_for_local_task = rank;
        MPI_Comm_size(MPI_COMM_WORLD, &size);
        GlobalConfig.mpi_size = size;
        scope(exit) { MPI_Finalize(); }
        // Make note that we are in the context of an MPI task, presumably, one of many.
        GlobalConfig.in_mpi_context = true;
        GlobalConfig.is_master_task = (GlobalConfig.mpi_rank_for_local_task == 0);
    } else {
        // We are NOT in the context of an MPI task.
        GlobalConfig.in_mpi_context = false;
        GlobalConfig.is_master_task = true;
    }
    // We assemble the usage messages as multi-line strings.
    // Be careful when editing them and try to limit the line length
    // to something that is likely to easily fit on a console,
    // say 80 characters.
    string briefUsageMsg = "Usage: e4shared/e4mpi/... [OPTION]...
Top-level arguments include the following.
Argument:                            Comment:
--------------------------------------------------------------------------------
  --job=<string>                     file names built from this string
  --prep                             prepare config, grid and flow files
  --run                              run the simulation over time
  --post                             post-process simulation data
  --custom-script | --custom-post    run custom script
  --help                             writes a longer help message
--------------------------------------------------------------------------------
For a more detailed help message, use --help or view the online help at
http://cfcfd.mechmining.uq.edu.au/eilmer/";
    string longUsageMsg = "Usage: e4shared/e4mpi/... [OPTION]...
Argument:                            Comment:
--------------------------------------------------------------------------------
  --job=<string>                     file names built from this string
  --verbosity=<int>                  defaults to 0

  --prep                             prepare config, grid and flow files
  --only-blocks=\"blk-list\"         only prepare blocks in given list

  --run                              run the simulation over time
  --tindx-start=<int>|last|9999      defaults to 0
  --next-loads-indx=<int>            defaults to (final index + 1) of lines
                                     found in the loads.times file
  --max-cpus=<int>                   (e4shared) defaults to ";
longUsageMsg ~= to!string(totalCPUs) ~" on this machine
  --threads-per-mpi-task=<int>       (e4mpi) defaults to 1
  --max-wall-clock=<int>             in seconds
  --report-residuals                 include residuals in console output

  --post                             post-process simulation data
  --list-info                        report some details of this simulation
  --tindx-plot=<int>|all|last|9999   defaults to last
  --add-vars=\"mach,pitot\"            add variables to the flow solution data
                                     (just for postprocessing)
                                     Other variables include:
                                     total-h, total-p, enthalpy, entropy, molef, conc, 
                                     Tvib (for some gas models)
  --ref-soln=<filename>              Lua file for reference solution
  --vtk-xml                          produce XML VTK-format plot files
  --binary-format                    use binary within the VTK-XML
  --tecplot                          write a binary szplt file for Tecplot
  --tecplot-ascii                    write an ASCII (text) file for Tecplot
  --tecplot-ascii-legacy             write an ASCII (legacy, text) file for Tecplot
  --plot-dir=<string>                defaults to plot
  --output-file=<string>             defaults to stdout
  --slice-list=\"blk-range,i-range,j-range,k-range;...\"
                                     output one or more slices across
                                     a structured-grid solution
  --surface-list=\"blk,surface-id;...\"
                                     output one or more surfaces as subgrids
  --extract-streamline=\"x,y,z;...\"   streamline locus points
  --track-wave=\"x,y,z(,nx,ny,nz);...\"
                                     track wave from given point
                                     in given plane, default is n=(0,0,1)
  --extract-line=\"x0,y0,z0,x1,y1,z1,n;...\"
                                     sample along a line in fluid domain
  --extract-solid-line=\"x0,y0,z0,x1,y1,z1,n;...\"
                                     sample along a line in solid domain
  --compute-loads-on-group=\"\"        group tag
  --probe=\"x,y,z;...\"                locations to sample flow data
  --output-format=<string>           gnuplot|pretty
  --norms=\"varName,varName,...\"      report L1,L2,Linf norms
  --region=\"x0,y0,z0,x1,y1,z1\"       limit norms calculation to a box

  --custom-script | --custom-post    run custom script
  --script-file=<string>             defaults to \"post.lua\"

  --help                             writes this long help message
--------------------------------------------------------------------------------";
    if ( args.length < 2 ) {
        if (GlobalConfig.is_master_task) {
            writeln("Too few arguments.");
            writeln(briefUsageMsg);
            stdout.flush();
        }
        exitFlag = 1;
        return exitFlag;
    }
    string jobName = "";
    int verbosityLevel = 1; // default to having a little information
    bool prepFlag = false;
    string blocksForPrep = "";
    bool runFlag = false;
    string tindxStartStr = "0";
    int tindxStart = 0;
    int nextLoadsIndx = -1;
    int maxCPUs = totalCPUs;
    int threadsPerMPITask = 1;
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
    bool tecplotAsciiLegacyFlag = false;
    string plotDir = "plot";
    string outputFileName = "";
    string sliceListStr = "";
    string surfaceListStr = "";
    string extractStreamStr = "";
    string trackWaveStr = "";
    string extractLineStr = "";
    string extractSolidLineStr = "";
    string computeLoadsOnGroupStr = "";
    string probeStr = "";
    string outputFormat = "gnuplot";
    string normsStr = "";
    string regionStr = "";
    bool customScriptFlag = false;
    string scriptFile = "post.lua";
    bool helpWanted = false;
    try {
        getopt(args,
               "job", &jobName,
               "verbosity", &verbosityLevel,
               "prep", &prepFlag,
               "only-blocks", &blocksForPrep,
               "run", &runFlag,
               "tindx-start", &tindxStartStr,
               "next-loads-indx", &nextLoadsIndx,
               "max-cpus", &maxCPUs,
               "threads-per-mpi-task", &threadsPerMPITask,
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
               "tecplot-ascii-legacy", &tecplotAsciiLegacyFlag,
               "plot-dir", &plotDir,
               "output-file", &outputFileName,
               "slice-list", &sliceListStr,
               "surface-list", &surfaceListStr,
               "extract-streamline", &extractStreamStr,
               "track-wave", &trackWaveStr,
               "extract-line", &extractLineStr,
               "extract-solid-line", &extractSolidLineStr,
               "compute-loads-on-group", &computeLoadsOnGroupStr,
               "probe", &probeStr,
               "output-format", &outputFormat,
               "norms", &normsStr,
               "region", &regionStr,
               "custom-post", &customScriptFlag,
               "custom-script", &customScriptFlag,
               "script-file", &scriptFile,
               "help", &helpWanted
               );
    } catch (Exception e) {
        if (GlobalConfig.is_master_task) {
            writeln("Problem parsing command-line options.");
            writeln("Arguments not processed: ");
            args = args[1 .. $]; // Dispose of program name in first argument.
            foreach (myarg; args) writeln("    arg: ", myarg);
            writeln(briefUsageMsg);
            stdout.flush();
        }
        exitFlag = 1;
        return exitFlag;
    }
    if (verbosityLevel > 0) {
        if (GlobalConfig.is_master_task) {
            writeln("Eilmer 4.0 compressible-flow simulation code.");
            writeln("Revision: PUT_REVISION_STRING_HERE");
            writeln("Compiler-name: PUT_COMPILER_NAME_HERE");
            //
            write("Build-flavour: ");
            version(flavour_debug) { writeln("debug"); }
            version(flavour_profile) { writeln("profile"); }
            version(flavour_fast) { writeln("fast"); }
            //
            write("Capabilities:");
            version(multi_species_gas) {
                write(" multi-species-gas");
            } else {
                write(" single-species-gas");
            }
            version(multi_T_gas) {
                write(" multi-temperature-gas");
            } else {
                write(" single-temperature-gas");
            }
            version(MHD) {
                write(" MHD");
            } else {
                write(" no-MHD");
            }
            version(komega) {
                write(" k-omega-turbulence");
            } else {
                write(" no-k-omega");
            }
            writeln(".");
        }
        version(mpi_parallel) {
            MPI_Barrier(MPI_COMM_WORLD);
            if (GlobalConfig.is_master_task) {
                writefln("Parallelism: MPI-parallel, number of tasks %d", GlobalConfig.mpi_size);
                version(mpi_timeouts) {
                    writeln("With MPI timeouts.");
                } else {
                    writeln("No MPI timeouts.");
                }
            }
            stdout.flush();
            // Give master_task a chance to be seen first.
            Thread.sleep(dur!("msecs")(100));
            MPI_Barrier(MPI_COMM_WORLD);
            // Now, get all tasks to report.
            writefln("MPI-parallel, start task %d", GlobalConfig.mpi_rank_for_local_task);
            stdout.flush();
            Thread.sleep(dur!("msecs")(100));
            MPI_Barrier(MPI_COMM_WORLD);
        } else {
            writeln("Parallelism: Shared-memory");
        }
    }
    if (helpWanted) {
        if (GlobalConfig.is_master_task) { writeln(longUsageMsg); stdout.flush(); }
        exitFlag = 0;
        return exitFlag;
    }
    //
    if (jobName.length > 0) {
        // Clean up the jobName, by removing any extension or path details, if necessary.
        string ext = extension(jobName);
        if (!ext.empty && ext != ".lua") {
            writeln("If you are going to supply an extension for your job name, it needs to be \".lua\"");
            return 1;
        }
        string dir = dirName(jobName);
        if (dir != ".") {
            writeln("You are expected to start with your job script in your working directory.");
            return 1;
        }
        string bn = baseName(jobName);
        if (ext.length > 0) {
            jobName = bn.replace(ext, "");
        } else {
            jobName = bn;
        }
    }
    //
    if (prepFlag) {
        version(mpi_parallel) {
            if (GlobalConfig.is_master_task) {
                writeln("Do not prepare for a simulation using MPI.");
                stdout.flush();
            }
            exitFlag = 1;
            return exitFlag;
        } else { // NOT mpi_parallel
            if (verbosityLevel > 0) { writeln("Begin preparation stage for a simulation."); }
            if (jobName.length == 0) {
                writeln("Need to specify a job name.");
                writeln(briefUsageMsg);
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
            registerGpathUtils(L);
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
            // Determine which fluidBlocks we need to process.
            int[] blockList;
            blocksForPrep = blocksForPrep.strip();
            foreach (blkStr; blocksForPrep.split(",")) {
                blkStr = blkStr.strip();
                auto blkRange = blkStr.split("..<");
                if (blkRange.length == 1) {
                    blockList ~= to!int(blkRange[0]);
                }
                else if (blkRange.length == 2) {
                    auto start = to!int(blkRange[0]);
                    auto end = to!int(blkRange[1]);
                    if (end < start) {
                        writeln("Supplied block list is in error. Range given is not allowed.");
                        writeln("Bad supplied range is: ", blkStr);
                        exitFlag = 1;
                        return exitFlag;
                    }
                    foreach (i; start .. end) {
                        blockList ~= i;
                    }
                }
                else {
                    writeln("Supplied block list is in error. Range given is not allowed.");
                    writeln("Bad supplied range is: ", blkStr);
                    exitFlag = 1;
                    return exitFlag;
                }
            }
            // Let's sort blocks in ascending order
            blockList.sort();
            lua_newtable(L);
            lua_setglobal(L, "fluidBlocksForPrep");
            lua_getglobal(L, "fluidBlocksForPrep");
            // Use uniq so that we remove any duplicates the user might have supplied
            import std.range;
            foreach (i, blkId; blockList.uniq().enumerate(1)) {
                lua_pushinteger(L, blkId);
                lua_rawseti(L, -2, to!int(i));
            }
            lua_pop(L, 1);
            // Set buildMasterFiles as appropriate
            if (blockList.length == 0 || blockList[0] == 0) {
                lua_pushboolean(L, true);
                // Before processing the Lua input files, move old .config and .control files.
                // This should prevent a subsequent run of the simulation on old config files
                // in the case that the processing of the input script fails.
                //
                // RJG, 2019-04-07
                // We only do this if we are processing master files.
                // We'll assume that things proceed ok if we are working on other block ranges.
                moveFileToBackup("config/"~jobName~".config");
                moveFileToBackup("config/"~jobName~".control");
            }
            else {
                lua_pushboolean(L, false);
            }
            lua_setglobal(L, "buildMasterFiles");
            
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
        } // end NOT mpi_parallel
    } // end if prepFlag

    if (runFlag) {
        if (jobName.length == 0) {
            writeln("Need to specify a job name.");
            writeln(briefUsageMsg);
            exitFlag = 1;
            return exitFlag;
        }
        GlobalConfig.base_file_name = jobName;
        GlobalConfig.verbosity_level = verbosityLevel;
        GlobalConfig.report_residuals = reportResiduals;
        // don't ask for more CPUs than available to this process
        maxCPUs = min(max(maxCPUs, 1), totalCPUs);
        threadsPerMPITask = min(threadsPerMPITask, totalCPUs);
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
        if (verbosityLevel > 0 && GlobalConfig.is_master_task) {
            writeln("Begin simulation with command-line arguments.");
            writeln("  jobName: ", jobName);
            writeln("  tindxStart: ", tindxStart);
            writeln("  maxWallClock: ", maxWallClock);
            writeln("  verbosityLevel: ", verbosityLevel);
            version(mpi_parallel) {
                writeln("  threadsPerMPITask: ", threadsPerMPITask);
            } else {
                writeln("  maxCPUs: ", maxCPUs, " for shared memory-parallelism");
            }
        }
        version(mpi_parallel) {
            stdout.flush();
            Thread.sleep(dur!("msecs")(100));
            MPI_Barrier(MPI_COMM_WORLD);
        }        
        init_simulation(tindxStart, nextLoadsIndx, maxCPUs, threadsPerMPITask, maxWallClock);
        if (verbosityLevel > 0 && GlobalConfig.is_master_task) {
            writeln("starting simulation time= ", simcore.SimState.time);
        }
        version(mpi_parallel) {
            stdout.flush();
            Thread.sleep(dur!("msecs")(100));
            MPI_Barrier(MPI_COMM_WORLD);
        }        
        if (GlobalConfig.block_marching) {
            version(mpi_parallel) {
                if (GlobalConfig.is_master_task) {
                    writeln("Do not run a block-marching simulation with MPI parallelism.");
                    stdout.flush();
                }
                exitFlag = 1;
                return exitFlag;
            } else { // NOT mpi_parallel
                march_over_blocks();
                finalize_simulation();
            }
        } else {
            if (integrate_in_time(GlobalConfig.max_time) != 0 && GlobalConfig.is_master_task) {
                writeln("Note that integrate_in_time failed.");
            }
            finalize_simulation();
        }
        if (verbosityLevel > 0 && GlobalConfig.is_master_task) {
            writeln("Done simulation.");
        }
    } // end if runFlag

    if (postFlag) {
        version(mpi_parallel) {
            if (GlobalConfig.is_master_task) {
                writeln("Do not do postprocessing with MPI parallelism.");
                stdout.flush();
            }
            exitFlag = 1;
            return exitFlag;
        } else { // NOT mpi_parallel
            if (jobName.length == 0) {
                writeln("Need to specify a job name.");
                writeln(briefUsageMsg);
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
                writeln("  tecplotAsciiLegacyFlag: ", tecplotAsciiLegacyFlag);
                writeln("  plotDir: ", plotDir);
                writeln("  outputFileName: ", outputFileName);
                writeln("  sliceListStr: ", sliceListStr);
                writeln("  surfaceListStr: ", surfaceListStr);
                writeln("  extractStreamStr: ", extractStreamStr);
                writeln("  trackWaveStr: ", trackWaveStr);
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
                         vtkxmlFlag, binaryFormat,
                         tecplotBinaryFlag, tecplotAsciiFlag, tecplotAsciiLegacyFlag,
                         outputFileName, sliceListStr, surfaceListStr,
                         extractStreamStr, trackWaveStr, extractLineStr, computeLoadsOnGroupStr,
                         probeStr, outputFormat, normsStr, regionStr, extractSolidLineStr);
            if (verbosityLevel > 0) { writeln("Done postprocessing."); }
        } // end NOT mpi_parallel
    } // end if postFlag

    if (customScriptFlag) {
        version(mpi_parallel) {
            if (GlobalConfig.is_master_task) {
                writeln("Do not do custom script processing using MPI.");
                stdout.flush();
            }
            exitFlag = 1;
            return exitFlag;
        } else { // NOT mpi_parallel
            if (verbosityLevel > 0) { 
                writeln("Begin custom script processing using user-supplied script.");
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
            registerGpathUtils(L);
            registerSurfaces(L);
            registerVolumes(L);
            registerUnivariateFunctions(L);
            registerStructuredGrid(L);
            registerUnstructuredGrid(L);
            registerSketch(L);
            registerSolidProps(L);
            registerGasModel(L, LUA_GLOBALSINDEX);
            registerThermochemicalReactor(L, LUA_GLOBALSINDEX);
            registerReactionMechanism(L, LUA_GLOBALSINDEX);
            registerChemistryUpdate(L, LUA_GLOBALSINDEX);
            registerElectronicallySpecificKinetics(L, LUA_GLOBALSINDEX);
            registeridealgasflowFunctions(L);
            registergasflowFunctions(L);
            registerBBLA(L);
            if (luaL_dofile(L, toStringz(scriptFile)) != 0) {
                writeln("There was a problem in the user-supplied Lua script: ", scriptFile);
                string errMsg = to!string(lua_tostring(L, -1));
                throw new FlowSolverException(errMsg);
            }
            if (verbosityLevel > 0) { writeln("Done custom script processing."); }
        } // end NOT mpi_parallel
    } // end if customPostFlag
    //
    return exitFlag;
} // end main()


