---
title: "Command Help"
date: 2019-02-06T15:49:24+10:00
draft: false
menu:
   main:
      weight: 25
---

This page serves as the command reference for using eilmer and its utilities.

The overall process of simulation of a gas flow is divided into 
three stages: 
(1) preparation of the defining data, 
(2) running the main simulation program, and 
(3) postprocessing of the output data from the simulation.
Information is passed from one stage to the next in data files.

## Pre-processing stage: commands and options
To start a simulation, we need a gas model, 
maybe a chemical-kinetics model for reacting flow,
simulation configuration and control files, and
the initial grid and flow state.
Generation of all of these data is the activity of 
the pre-processing (or preparation) stage.

### `prep-gas` : gas model preparation
The `prep-gas` program is used to take a brief description of
the desired gas model used in the flow simulation and produce
a detailed configuration gas model configuration file for
use by eilmer at pre-processing and simulation stages.
Its usage is shown here. Generally, one uses prep-gas
in the first mode shown: with two arguments.
The second mode simply lists available species in the
eilmer database and exits.

```
Usage:
 > prep-gas input output

   input    : a gas input file with user selections
   output   : detailed gas file in format ready for Eilmer4.

 > prep-gas --list-available-species
```

### `prep-chem` : chemistry scheme preparation
`prep-chem` is used to take user created description of a chemistry
scheme written in Lua and generate a detailed configuration file
for eilmer to use at run-time. The use of `prep-chem` is shown here. 
```
Usage:
 > prep-chem [--compact] gmodelfile cheminput output

   gmodelfile  : a gas model file is required as input for context
   cheminput   : input chemistry file in Lua format.
   output      : output file in format ready for Eilmer4.

Options:
   --compact   : produce a text file called 'chem-compact-notation.inp'
                 which is used to configure a GPU chemistry kernel.
```

### `e4shared --prep` : pre-processing for flow simulation
Once the gas and chemistry files are prepared,
the flow simulation process in divided into three stages,
with preparation of the configuration, grid and initial flow-state files
being the first.
```
 > e4shared --prep --job=name [--verbosity=<int>]
```
will start with the user-supplied description of the simulation in the 
file `name.lua` and produce the set of data files that are needed 
to run a simulation.
The integer value for `verbosity` defaults to 0, for minimum commentary
as the preparation calculations are done.
If things are going badly, setting a higher value may give more information
during the calculations, however, it is more likely that increased verbosity
is more useful during the simulation (run-time) stage.

## Run-time stage: commands and options
Now that the initial flow and grid files exist, it is time to run the main
transient flow simulation process. 
The transient-flow simulation program comes in two main flavours.
`e4shared` is for using one or more cores on your workstation for calculation
using shared-memory parallelism.
`e4mpi` is for running a distributed-memory calculation using the 
Message-Passing Interface (MPI).
When getting started with small-scale simulations, `e4shared` is the simpler program to use.
Once you have graduated to running large, many-block simulations, it may be good to start
using `e4mpi` across the nodes of a cluster computer.

### Run a simulation, shared-memory
```
 > e4shared --run --job=name [OPTIONS]
```
with the relevant options being
```
  --tindx-start=<int>|last|9999      defaults to 0
  --next-loads-indx=<int>            defaults to (final index + 1) of lines
                                     found in the loads.times file
  --max-cpus=<int>                   (e4shared) defaults to 8 on this machine
  --max-wall-clock=<int>             in seconds
  --report-residuals                 include residuals in console output
```

### Run a simulation, MPI
```
 > mpirun -np <ntask> e4mpi --run --job=name [OPTIONS]
```
with the relevant options being
```
  --tindx-start=<int>|last|9999      defaults to 0
  --next-loads-indx=<int>            defaults to (final index + 1) of lines
                                     found in the loads.times file
  --threads-per-mpi-task=<int>       (e4mpi) defaults to 1
  --max-wall-clock=<int>             in seconds
  --report-residuals                 include residuals in console output
```

## Post-processing stage: commands and options
Once you have a large collection of numbers defining the flow field
at various instances in its history, it will be stored in files with
a format specific to Eilmer and mostly unknown to many data visualization tools.
To make your data more accessible, you may rewrite it into formats 
known by the visualization tools or you may slice it into various subsets.

### Post-processing using predefined actions
```
 > e4shared --post --job=name [OPTIONS]
```
with the relevant options being
```
  --list-info                        report some details of this simulation
  --tindx-plot=<int>|all|last|9999   defaults to last
  --add-vars="mach,pitot"            add variables to the flow solution data
                                     (just for postprocessing)
                                     Other variables include:
                                     total-h, total-p, enthalpy, entropy, molef, conc, 
                                     Tvib (for some gas models)
  --ref-soln=<filename>              Lua file for reference solution
  --vtk-xml                          produce XML VTK-format plot files
  --binary-format                    use binary within the VTK-XML
  --tecplot                          write a binary szplt file for Tecplot
  --tecplot-ascii                    write an ASCII (text) file for Tecplot
  --plot-dir=<string>                defaults to plot
  --output-file=<string>             defaults to stdout
  --slice-list="blk-range,i-range,j-range,k-range;..."
                                     output one or more slices across
                                     a structured-grid solution
  --surface-list="blk,surface-id;..."
                                     output one or more surfaces as subgrids
  --extract-streamline="x,y,z;..."   streamline locus points
  --track-wave="x,y,z(,nx,ny,nz);..."
                                     track wave from given point
                                     in given plane, default is n=(0,0,1)
  --extract-line="x0,y0,z0,x1,y1,z1,n;..."
                                     sample along a line in fluid domain
  --extract-solid-line="x0,y0,z0,x1,y1,z1,n;..."
                                     sample along a line in solid domain
  --compute-loads-on-group=""        group tag
  --probe="x,y,z;..."                locations to sample flow data
  --output-format=<string>           gnuplot|pretty
  --norms="varName,varName,..."      report L1,L2,Linf norms
  --region="x0,y0,z0,x1,y1,z1"       limit norms calculation to a box
```

### Post-processing using a user-supplied script
When none of the predefined post-processing operations are suitable,
you may define your own, in Lua.
The Eilmer4 program provides a number of service functions to the Lua interpreter
for loading grid and flow files and accessing the data 
within the loaded grids and flow blocks.
This is probably the least-well-defined activity associated with a simulation,
so an interest in experimentation could be rewarding.
```
 > e4shared --custom-post --script-file=name.lua
```

