/**
 * Eilmer4 cell history writing functions.
 *
 * Author: Rowan G. and Peter J.
 * First code: 2016-01-31
 */

module history;

import std.stdio;
import std.string;
import std.file;
import std.array;
import std.format;

import globalconfig;
import globaldata;
import fvcell;
import fileutil;

string histDir = "hist";

void init_history_cell_files()
{
    ensure_directory_is_present(histDir);
    foreach ( hcell; GlobalConfig.hcells ) {
	auto blkId = hcell[0];
	auto cellId = hcell[1];
	string fname = format("%s/%s-blk-%d-cell-%d.dat", 
			      histDir, GlobalConfig.base_file_name, blkId, cellId);
	auto f = File(fname, "w");
	auto cellVars = variable_list_for_cell(GlobalConfig.gmodel_master);
	f.write("# 1:t ");
	foreach ( i, var; cellVars ) {
	    f.write(format("%d:%s ", i+2, var));
	}
	f.write("\n");
	f.close();
    }    
}

void write_history_cells_to_files(double sim_time)
{
    foreach ( hcell; GlobalConfig.hcells ) {
	auto blkId = hcell[0];
	auto cellId = hcell[1];
	string fname = format("%s/%s-blk-%d-cell-%d.dat", 
			      histDir, GlobalConfig.base_file_name, blkId, cellId);
	auto cell = gasBlocks[blkId].cells[cellId];
	auto writer = appender!string();
	formattedWrite(writer, "%.12e %s\n", sim_time,
		       cell.write_values_to_string());
	append(fname, writer.data);
    }
}
