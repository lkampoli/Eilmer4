/**
 * grid.d -- (abstract) grid functions
 *
 * Author: Peter J. and Rowan G.
 * Version: 2014-05-13 factored out of sgrid.d
 */

module grid;

import std.math;
import std.stdio;
import std.conv;
import geom;

//-----------------------------------------------------------------

enum Grid_t {structured_grid, unstructured_grid}

string gridTypeName(Grid_t gt)
{
    final switch (gt) {
    case Grid_t.structured_grid: return "structured_grid";
    case Grid_t.unstructured_grid: return "unstructured_grid";
    }
}

Grid_t gridTypeFromName(string name)
{
    switch (name) {
    case "structured_grid": return Grid_t.structured_grid;
    case "unstructured_grid": return Grid_t.unstructured_grid;
    default: throw new Error("Unknown type of grid: " ~ name);
    }
}

class Grid {
    Grid_t grid_type;
    int dimensions; // 1, 2 or 3
    string label;
    size_t ncells;
    size_t nvertices;
    Vector3[] vertices;
    // For both structured and unstructured grids, we can index vertices with i,j,k indices.
    // For structured grids, the numbers have an obvious significance.
    // For unstructured grids, niv==vertices.length, njv==1, nkv==1
    size_t niv, njv, nkv;
    // The following array can be used to get a list of faces attached to a vertex.
    // We have only filled in its data for unstructured grids, however,
    // we need to access the data via a this base class.
    // I think that my abstractions are leaking.
    size_t[][] faceIndexListPerVertex;
    
    this(Grid_t grid_type, int dimensions, string label="")
    {
	this.grid_type = grid_type;
	this.dimensions = dimensions;
	this.label = label;
    }

    // Unified indexing.
    size_t single_index(size_t i, size_t j, size_t k=0) const
    in {
	assert (i < niv, text("index i=", i, " is invalid, niv=", niv));
	assert (j < njv, text("index j=", j, " is invalid, njv=", njv));
	assert (k < nkv, text("index k=", k, " is invalid, nkv=", nkv));
    }
    body {
	return i + niv*(j + njv*k);
    }

    size_t[] ijk_indices(size_t indx) const
    in {
	assert ( indx < vertices.length );
    }
    body {
	size_t k = indx / (niv*njv);
	indx -= k * (niv * njv);
	size_t j = indx / niv;
	indx -= j * niv;
	return [indx, j, k];
    }
	    
    abstract Vector3* opIndex(size_t i, size_t j, size_t k=0);
    abstract Vector3* opIndex(size_t indx);
    abstract size_t[] get_vtx_id_list_for_cell(size_t i, size_t j, size_t k=0) const; 
    abstract size_t[] get_vtx_id_list_for_cell(size_t indx) const;
    abstract void read_from_gzip_file(string fileName);
    abstract void write_to_gzip_file(string fileName);
    abstract void write_to_vtk_file(string fileName);
    abstract size_t number_of_vertices_for_cell(size_t i);
    abstract int vtk_element_type_for_cell(size_t i);
    abstract Grid get_boundary_grid(size_t boundary_indx);
    abstract size_t[] get_list_of_boundary_cells(size_t boundary_indx);

    void find_enclosing_cell(double x, double y, double z, ref size_t indx, ref bool found)
    {
	found = false;
	indx = 0;
	auto p = Vector3(x, y, z);
	foreach (i; 0 .. ncells) {
	    bool inside_cell = false;
	    auto vtx_id = get_vtx_id_list_for_cell(i);
	    switch (dimensions) {
	    case 1: throw new Exception("cell search not implemented for 1D grids");
	    case 2:
		switch (vtx_id.length) {
		case 3:
		    inside_cell = inside_xy_triangle(vertices[vtx_id[0]], vertices[vtx_id[1]],
						     vertices[vtx_id[2]], p);
		    break;
		case 4:
		    inside_cell = inside_xy_quad(vertices[vtx_id[0]], vertices[vtx_id[1]],
						 vertices[vtx_id[2]], vertices[vtx_id[3]], p);
		    break;
		default:
		    assert(0);
		} // end switch (vtx_id.length)
		break;
	    case 3:
		switch (vtx_id.length) {
		case 4:
		    inside_cell = inside_tetrahedron(vertices[vtx_id[0]], vertices[vtx_id[1]],
						     vertices[vtx_id[2]], vertices[vtx_id[3]], p);
		    break;
		case 8:
		    inside_cell = inside_hexahedron(vertices[vtx_id[0]], vertices[vtx_id[1]],
						    vertices[vtx_id[2]], vertices[vtx_id[3]],
						    vertices[vtx_id[4]], vertices[vtx_id[5]],
						    vertices[vtx_id[6]], vertices[vtx_id[7]], p); 
		    break;
		case 5:
		    throw new Exception("need to implement inside pyramid cell");
		case 6:
		    throw new Exception("need to implement inside wedge cell");
		default:
		    assert(0);
		} // end switch (vtx_id.length)
		break;
	    default: assert(0);
	    } // end switch (dimensions)
	    if (inside_cell) { found = true; indx = i; return; }
	} // foreach i
	return;
    } // end find_enclosing_cell()

    Vector3 cell_barycentre(size_t indx)
    // Returns the "centre-of-mass" of the vertices defining the cell.
    {
	auto cbc = Vector3(0.0, 0.0, 0.0);
	auto vtx_ids = get_vtx_id_list_for_cell(indx);
	foreach(vtx_id; vtx_ids) { cbc += vertices[vtx_id]; }
	double one_over_n_vtx = 1.0 / vtx_ids.length;
	cbc *= one_over_n_vtx;
	return cbc;
    } // end cell_barycentre()

    void find_nearest_cell_centre(double x, double y, double z,
				  ref size_t nearestCell, ref double minDist)
    {
	nearestCell = 0;
	auto p = cell_barycentre(0);
	double dx = x - p.x; double dy = y - p.y; double dz = z - p.z;
	minDist = sqrt(dx*dx + dy*dy + dz*dz);
	foreach (i; 1 .. ncells) {
	    p = cell_barycentre(i);
	    dx = x - p.x; dy = y - p.y; dz = z - p.z;
	    double d = sqrt(dx*dx + dy*dy + dz*dz);
	    if (d < minDist) {
		minDist = d;
		nearestCell = i;
	    }
	} // end foreach i
    } // end find_nearest_cell_centre

} // end class grid
