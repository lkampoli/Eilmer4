// sgrid_demo.d

import std.stdio;
import std.conv;
import geom;
import gpath;
import surface;
import volume;
import univariatefunctions;
import sgrid;

void main()
{
    writeln("Begin structured-grid demo...");
    auto p00 = Vector3(0.0, 0.1);
    auto p10 = Vector3(1.0, 0.4);
    auto p11 = Vector3(1.0, 1.1);
    auto p01 = Vector3(0.0, 1.1);
    auto my_patch = new AOPatch(p00, p10, p11, p01);
    auto cf = [new LinearFunction(), new LinearFunction(), 
	       new LinearFunction(), new LinearFunction()];
    auto my_grid = new StructuredGrid(my_patch, 11, 21, cf);
    writeln("grid point 5 5 at x=", my_grid[5,5].x, " y=", my_grid[5,5].y);
    my_grid.write_to_vtk_file("test_grid-2D.vtk");
    my_grid.write_to_gzip_file("test_grid-2D.gz");
    auto my_grid2 = new StructuredGrid("test_grid.gz", "gziptext");
    my_grid2.write_to_vtk_file("test_grid2-2D.vtk");

    writeln("SlabGrid");
    auto my_grid3 = my_grid.makeSlabGrid(0.2);
    my_grid3.write_to_vtk_file("test_grid3-slab.vtk");
    writeln("WedgeGrid");
    auto my_grid4 = my_grid.makeWedgeGrid(0.2);
    my_grid4.write_to_vtk_file("test_grid4-wedge.vtk");
    
    writeln("3D grid from the start");
    Vector3[8] p;
    p[0] = Vector3(0.0, 0.1, 0.0);
    p[1] = Vector3(1.0, 0.1, 0.0);
    p[2] = Vector3(1.0, 1.1, 0.0);
    p[3] = Vector3(0.0, 1.1, 0.0);
    //
    p[4] = Vector3(0.0, 0.1, 3.0);
    p[5] = Vector3(1.0, 0.1, 3.0);
    p[6] = Vector3(1.0, 1.1, 3.0);
    p[7] = Vector3(0.0, 1.1, 3.0);
    //
    auto simple_box = new TFIVolume(p);
    auto my_3Dgrid = new StructuredGrid(simple_box, 11, 21, 11, cf);
    writeln("grid point 5 5 5 at p=", *my_3Dgrid[5,5,5]);
    my_3Dgrid.write_to_vtk_file("test_grid-3D.vtk");
    my_3Dgrid.sort_cells_into_bins(10, 10, 10);
    Vector3 my_point = 0.5*(p[0] + p[7]);
    size_t cell_indx = 0; bool found = false;
    my_3Dgrid.find_enclosing_cell(my_point, cell_indx, found);
    writeln("Search for cell enclosing my_point= ", my_point);
    if (found) {
	writeln("    cell found, index= ", cell_indx);
	writeln("    cell barycentre= ", my_3Dgrid.cell_barycentre(cell_indx));
    } else {
	writeln("    cell not found");
    }
    //
    writeln("2D surface from the 3D grid");
    auto north_grid = my_3Dgrid.get_boundary_grid(Face.north);
    writeln("grid point 5 5 at p=", *north_grid[5,5]);
    
    writeln("Import GridPro grid...");
    auto gpgrid = import_gridpro_grid("../../examples/eilmer/3D/gridpro-import/blk.tmp");
    foreach (i; 0 .. gpgrid.length) {
	gpgrid[i].write_to_vtk_file("gpgrid-"~to!string(i)~".vtk");
    }
    writeln("Done.");
}
