/**
 * usgrid.d -- unstructured-grid functions
 *
 * Author: Peter J. and Rowan G.
 * Version: 2014-11-02 First code
 */

module usgrid;

import std.string;
import std.array;
import std.conv;
import std.stdio;
import std.file;
import std.algorithm;
import std.format;
import std.math;
import gzip;

import geom;
import gpath;
import surface;
import volume;
import univariatefunctions;
import grid;
import sgrid;

import paver;

//-----------------------------------------------------------------
// For the USGCell types, we will have only the linear elements,
// with straight-line edges joining the vertices.
// We will use VTK names and vertex ordering to align with su2 file format,
// but we will have different integer tags and thus need a translation array 
// between the tag values.  This is vtk_element_types below.
// 2016-dec-01: Kyle has found that Pointwise writes the su2 file with GMSH
// vertex ordering for the wedge elements.  We retain the VTK ordering. 

enum USGCell_type {
    none = 0,
    // For 2D simulations.
    triangle = 1,
    quad = 2,
    polygon = 3,
    // For 3D simulations.
    tetra = 4,
    wedge = 5,
    hexahedron = 6,
    pyramid = 7,
    // For subsetting the grid, need lines
    line = 8
}
string[] cell_names = ["none", "triangle", "quad", "polygon",
		       "tetra", "wedge", "hexahedron", "pyramid",
		       "line"];

int[] vtk_element_types = [0, VTKElement.triangle, VTKElement.quad, VTKElement.polygon,
			   VTKElement.tetra, VTKElement.wedge, VTKElement.hexahedron,
			   VTKElement.pyramid, VTKElement.line];

USGCell_type convert_cell_type(int vtk_element_type)
{
    switch (vtk_element_type) {
    case VTKElement.triangle: return USGCell_type.triangle;
    case VTKElement.quad: return USGCell_type.quad;
    case VTKElement.tetra: return USGCell_type.tetra;
    case VTKElement.wedge: return USGCell_type.wedge;
    case VTKElement.hexahedron: return USGCell_type.hexahedron;
    case VTKElement.pyramid: return USGCell_type.pyramid;
    case VTKElement.line: return USGCell_type.line;
    default:
	return USGCell_type.none;
    }
}

USGCell_type cell_type_from_name(string name)
{
    switch (name) {
    case "none": return USGCell_type.none;
    case "triangle": return USGCell_type.triangle;
    case "quad": return USGCell_type.quad;
    // case "polygon": return USGCell_type.polygon; // don't allow polygon cells
    case "tetra": return USGCell_type.tetra;
    case "wedge": return USGCell_type.wedge;
    case "hexahedron": return USGCell_type.hexahedron;
    case "pyramid": return USGCell_type.pyramid;
    case "line": return USGCell_type.line;
    default:
	return USGCell_type.none;
    }
}

string makeFaceTag(const size_t[] vtx_id_list)
{
    // We make a tag for this face out of the vertex id numbers
    // sorted in ascending order, to be used as a key in an
    // associative array of indices.  Any cycle of the same vertices
    // should define the same face, so we will use this tag as
    // a way to check if we have made a particular face before.
    // Of course, permutations of the same values that are not
    // correct cycles will produce the same tag, however,
    // we'll not worry about that for now because we should only
    // ever be providing correct cycles.
    size_t[] my_id_list = vtx_id_list.dup();
    sort(my_id_list);
    string tag = "";
    size_t n = my_id_list.length;
    foreach(i; 0 .. n) {
	if (i > 0) { tag ~= "-"; }
	tag ~= format("%d", my_id_list[i]);
    }
    return tag;
}

class USGFace {
public:
    size_t[] vtx_id_list;
    string tag;
    // Note that, when construction a grid from a set of vertices and lists
    // of vertex indices, we will be able to tell if a face in a boundary list
    // is facing in or out by whether it has a right or left cell.
    // This information is filled in when constructing a new mesh but is not copied
    // in the USGFace copy constructor.  Beware.
    USGCell left_cell;
    USGCell right_cell;

    this(const size_t[] vtx_id_list) 
    {
	this.vtx_id_list = vtx_id_list.dup();
    }

    this(const USGFace other)
    {
	vtx_id_list = other.vtx_id_list.dup();
	// The const constraint means that we cannot copy the left_cell and
	// right_cell references.  The compiler cannot be sure that we will
	// honour the const promise once it has allowed us to copy references.
    }

    this(string str)
    // Defines the format for input from a text stream.
    {
	auto tokens = str.strip().split();
	vtx_id_list.length = to!int(tokens[0]);
	foreach(i; 0 .. vtx_id_list.length) { vtx_id_list[i] = to!int(tokens[i+1]); }
    }

    string toIOString()
    // Defines the format for output to a text stream.
    {
	string str = to!string(vtx_id_list.length);
	foreach (vtx_id; vtx_id_list) { str ~= " " ~ to!string(vtx_id); }
	return str;
    }
} // end class USGFace

class USGCell {
public:
    USGCell_type cell_type;
    size_t[] vtx_id_list;
    size_t[] face_id_list;
    int[] outsign_list; // +1 face normal is outward; -1 face normal is inward

    this(USGCell_type cell_type, size_t[] vtx_id_list,
	 size_t[] face_id_list, int[] outsign_list)
    {
	this.cell_type = cell_type;
	this.vtx_id_list = vtx_id_list.dup();
	this.face_id_list = face_id_list.dup();
	this.outsign_list = outsign_list.dup();
    }

    this(const USGCell other)
    {
	cell_type = other.cell_type;
	vtx_id_list = other.vtx_id_list.dup();
	face_id_list = other.face_id_list.dup();
	outsign_list = other.outsign_list.dup();
    }

    this(string str)
    // Defines the format for input from a text stream.
    {
	auto tokens = str.strip().split();
	int itok = 0;
	cell_type = cell_type_from_name(tokens[itok++]);
	if (cell_type == USGCell_type.none) {
	    throw new Exception("Unexpected cell type from line: " ~ str);
	}
        auto junk = tokens[itok++]; // "vtx"
	vtx_id_list.length = to!int(tokens[itok++]);
	foreach(i; 0 .. vtx_id_list.length) {
	    vtx_id_list[i] = to!int(tokens[itok++]);
	}
	junk = tokens[itok++]; // "faces"
	face_id_list.length = to!int(tokens[itok++]);
	foreach(i; 0 .. face_id_list.length) {
	    face_id_list[i] = to!int(tokens[itok++]);
	}
	junk = tokens[itok++]; // "outsigns"
	outsign_list.length = to!int(tokens[itok++]);
	foreach(i; 0 .. outsign_list.length) {
	    outsign_list[i] = to!int(tokens[itok++]);
	}
    }

    string toIOString()
    // Defines the format for output to a text stream.
    {
	string str = cell_names[cell_type];
	str ~= " vtx " ~ to!string(vtx_id_list.length);
	foreach (vtx_id; vtx_id_list) { str ~= " " ~ to!string(vtx_id); }
	str ~= " faces " ~ to!string(face_id_list.length);
	foreach (face_id; face_id_list) { str ~= " " ~ to!string(face_id); }
	str ~= " outsigns " ~ to!string(outsign_list.length);
	foreach (outsign; outsign_list) { str ~= " " ~ to!string(outsign); }
	return str;
    }
} // end class USGCell

class BoundaryFaceSet {
public:
    string tag;
    size_t[] face_id_list;
    int[] outsign_list; // +1 face normal is outward; -1 face normal is inward

    this(string tag, size_t[] face_id_list, int[] outsign_list)
    {
	this.tag = tag;
	this.face_id_list = face_id_list.dup();
	this.outsign_list = outsign_list.dup();
    }
    
    this(string str) 
    // Defines the format for input from a text stream.
    {
	auto tokens = str.strip().split();
	if (tokens.length == 1) {
	    this.tag = tokens[0];
	} else {
	    // We have more information so try to use it.
	    int itok = 0;
	    this.tag = tokens[itok++];
	    auto junk = tokens[itok++]; // "faces"
	    face_id_list.length = to!int(tokens[itok++]);
	    foreach(i; 0 .. face_id_list.length) {
		face_id_list[i] = to!int(tokens[itok++]);
	    }
	    junk = tokens[itok++]; // "outsigns"
	    outsign_list.length = to!int(tokens[itok++]);
	    foreach(i; 0 .. outsign_list.length) {
		outsign_list[i] = to!int(tokens[itok++]);
	    }
	    assert(face_id_list.length == outsign_list.length,
		   "Mismatch in numbers of faces and outsigns");
	}
    }
    
    this(const BoundaryFaceSet other)
    {
	tag = other.tag;
	face_id_list = other.face_id_list.dup();
	outsign_list = other.outsign_list.dup();
    }

    string toIOString()
    // Defines the format for output to a text stream.
    {
	string str = tag;
	str ~= " faces " ~ to!string(face_id_list.length);
	foreach (face_id; face_id_list) { str ~= " " ~ to!string(face_id); }
	str ~= " outsigns " ~ to!string(outsign_list.length);
	foreach (outsign; outsign_list) { str ~= " " ~ to!string(outsign); }
	return str;
    }
} // end class BoundaryFaceSet


class UnstructuredGrid : Grid {
public:
    size_t nfaces, nboundaries;
    USGFace[] faces;
    // The following dictionary of faces, identified by their defining vertices,
    // will enable us to quickly search for an already defined face.
    size_t[string] faceIndices;
    USGCell[] cells;
    BoundaryFaceSet[] boundaries;

    this(int dimensions, string label="")
    // A new empty grid that will have its details filled in later.
    {
	super(Grid_t.unstructured_grid, dimensions, label);
    }

    this(const Vector3[] boundary, BoundaryFaceSet[] in_boundaries, const string new_label="")
    //Paved Grid Constructor by Heather Muir, 2016.
    {
    	double[][] boundary_points;
	foreach(p; boundary){
	    boundary_points ~= [p._p[0], p._p[1], p._p[2]];
	}
	PavedGrid grid = new PavedGrid(boundary_points);
	super(Grid_t.unstructured_grid, grid.dimensions,
	      ((new_label == "")? grid.label : new_label));

	foreach(b; in_boundaries) { boundaries ~= new BoundaryFaceSet(b); }
	this.nvertices = grid.nvertices;
	this.ncells = grid.ncells;
	this.nfaces = grid.nfaces;
	this.nboundaries = grid.nboundaries;
	foreach(p; POINT_LIST){
	    double[] v = [p.x, p.y, p.z];
	    this.vertices ~= Vector3(v);
	}
	foreach(f; FACE_LIST){
	    size_t[] vtx_id_list = f.point_IDs;
	    faceIndices[makeFaceTag(vtx_id_list)] = faces.length;
	    this.faces ~= new USGFace(vtx_id_list);
	}
	foreach(c; CELL_LIST){
	    c.auto_cell_type();
	    if(c.cell_type != "quad"){
		throw new Error(text("paver generated a non-quad cell"));
	    } else {
		USGCell_type cell_type = cell_type_from_name(c.cell_type);
		this.cells ~= new USGCell(cell_type, c.point_IDs, c.face_IDs, c.outsigns);
	    }
	}
	assembleFaceIndexListPerVertex();
	niv = vertices.length; njv = 1; nkv = 1;
    }//end paved grid constructor

    this(const UnstructuredGrid other, const string new_label="")
    {
	super(Grid_t.unstructured_grid, other.dimensions,
	      ((new_label == "")? other.label : new_label));
	nvertices = other.nvertices;
	ncells = other.ncells;
	nfaces = other.nfaces;
	nboundaries = other.nboundaries;
	foreach(v; other.vertices) { vertices ~= Vector3(v); }
	foreach(f; other.faces) {
	    faceIndices[makeFaceTag(f.vtx_id_list)] = faces.length;
	    faces ~= new USGFace(f);
	}
	foreach(c; other.cells) { cells ~= new USGCell(c); }
	foreach(b; other.boundaries) { boundaries ~= new BoundaryFaceSet(b); }
	assembleFaceIndexListPerVertex();
	niv = vertices.length; njv = 1; nkv = 1;
    }

    this(const StructuredGrid sg, const string new_label="")
    {
	super(Grid_t.unstructured_grid, sg.dimensions,
	      ((new_label == "")? sg.label : new_label));
	vertices.length = 0;
	faces.length = 0;
	cells.length = 0;
	boundaries.length = 0;
	if (dimensions == 2) {
	    nvertices = sg.niv * sg.njv;
	    nfaces = (sg.niv)*(sg.njv-1) + (sg.niv-1)*(sg.njv);
	    ncells = (sg.niv-1)*(sg.njv-1);
	    nboundaries = 4;
	    foreach(ib; 0 .. nboundaries) {
		boundaries ~= new BoundaryFaceSet(face_name[ib]);
		// 0=north, 1=east, 2=south, 3=west
	    }
	    // vertex index array
	    size_t[][] vtx_id;
	    vtx_id.length = sg.niv;
	    foreach (i; 0 .. sg.niv) {
		vtx_id[i].length = sg.njv;
	    }
	    // vertex list in standard order, indexed
	    foreach (j; 0 .. sg.njv) {
		foreach (i; 0 .. sg.niv) {
		    vertices ~= Vector3(sg.vertices[sg.single_index(i,j)]);
		    vtx_id[i][j] = vertices.length - 1;
		}
	    }
	    // i-faces
	    size_t[][] iface_id;
	    iface_id.length = sg.niv;
	    foreach (i; 0 .. sg.niv) {
		iface_id[i].length = sg.njv-1;
	    }
	    foreach (j; 0 .. sg.njv-1) {
		foreach (i; 0 .. sg.niv) {
		    size_t[] vtx_id_list = [vtx_id[i][j], vtx_id[i][j+1]];
		    faceIndices[makeFaceTag(vtx_id_list)] = faces.length;
		    faces ~= new USGFace(vtx_id_list);
		    iface_id[i][j] = faces.length - 1;
		    if (i == 0) {
			boundaries[Face.west].face_id_list ~= iface_id[i][j];
			boundaries[Face.west].outsign_list ~= -1;
		    }
		    if (i == sg.niv-1) {
			boundaries[Face.east].face_id_list ~= iface_id[i][j];
			boundaries[Face.east].outsign_list ~= +1;
		    }
		}
	    }
	    // j-faces
	    size_t[][] jface_id;
	    jface_id.length = sg.niv - 1;
	    foreach (i; 0 .. sg.niv-1) {
		jface_id[i].length = sg.njv;
	    }
	    foreach (j; 0 .. sg.njv) {
		foreach (i; 0 .. sg.niv-1) {
		    size_t[] vtx_id_list = [vtx_id[i+1][j], vtx_id[i][j]];
		    faceIndices[makeFaceTag(vtx_id_list)] = faces.length;
		    faces ~= new USGFace(vtx_id_list);
		    jface_id[i][j] = faces.length - 1;
		    if (j == 0) {
			boundaries[Face.south].face_id_list ~= jface_id[i][j];
			boundaries[Face.south].outsign_list ~= -1;
		    }
		    if (j == sg.njv-1) {
			boundaries[Face.north].face_id_list ~= jface_id[i][j];
			boundaries[Face.north].outsign_list ~= +1;
		    }
		}
	    }
	    // cells
	    foreach (j; 0 .. sg.njv-1) {
		foreach (i; 0 .. sg.niv-1) {
		    auto cell_vertices = [vtx_id[i][j], vtx_id[i+1][j],
					  vtx_id[i+1][j+1], vtx_id[i][j+1]];
		    auto cell_faces = [jface_id[i][j+1], // north
				       iface_id[i+1][j], // east
				       jface_id[i][j], // south
				       iface_id[i][j]]; // west
		    auto outsigns = [+1, +1, -1, -1];
		    auto my_cell = new USGCell(USGCell_type.quad, cell_vertices,
					       cell_faces, outsigns);
		    cells ~= my_cell;
		    // Now that we have the new cell, we can make the connections
		    // from the faces back to the cell.
		    faces[jface_id[i][j+1]].left_cell = my_cell;
		    faces[iface_id[i+1][j]].left_cell = my_cell;
		    faces[jface_id[i][j]].right_cell = my_cell;
		    faces[iface_id[i][j]].right_cell = my_cell;
		}
	    }
	} else {
	    // Assume dimensions == 3
	    nvertices = sg.niv * sg.njv * sg.nkv;
	    nfaces = (sg.niv)*(sg.njv-1)*(sg.nkv-1) +
		(sg.niv-1)*(sg.njv)*(sg.nkv-1) +
		(sg.niv-1)*(sg.njv-1)*(sg.nkv);
	    ncells = (sg.niv-1)*(sg.njv-1)*(sg.nkv-1);
	    nboundaries = 6;
	    foreach(ib; 0 .. nboundaries) {
		boundaries ~= new BoundaryFaceSet(face_name[ib]);
		// 0=north, 1=east, 2=south, 3=west, 4=top, 5=bottom
	    }
	    // vertex index array
	    size_t[][][] vtx_id;
	    vtx_id.length = sg.niv;
	    foreach (i; 0 .. sg.niv) {
		vtx_id[i].length = sg.njv;
		foreach (j; 0 .. sg.njv) {
		    vtx_id[i][j].length = sg.nkv;
		}
	    }
	    // vertex list in standard order, indexed
	    foreach (k; 0 .. sg.nkv) {
		foreach (j; 0 .. sg.njv) {
		    foreach (i; 0 .. sg.niv) {
			vertices ~= Vector3(sg.vertices[sg.single_index(i,j,k)]);
			vtx_id[i][j][k] = vertices.length - 1;
		    }
		}
	    }
	    // i-faces
	    size_t[][][] iface_id;
	    iface_id.length = sg.niv;
	    foreach (i; 0 .. sg.niv) {
		iface_id[i].length = sg.njv-1;
		foreach (j; 0 .. sg.njv-1) {
		    iface_id[i][j].length = sg.nkv-1;
		}
	    }
	    foreach (k; 0 .. sg.nkv-1) {
		foreach (j; 0 .. sg.njv-1) {
		    foreach (i; 0 .. sg.niv) {
			size_t[] vtx_id_list = [vtx_id[i][j][k], vtx_id[i][j+1][k],
						vtx_id[i][j+1][k+1], vtx_id[i][j][k+1]];
			faceIndices[makeFaceTag(vtx_id_list)] = faces.length;
			faces ~= new USGFace(vtx_id_list);
			iface_id[i][j][k] = faces.length - 1;
			if (i == 0) {
			    boundaries[Face.west].face_id_list ~= iface_id[i][j][k];
			    boundaries[Face.west].outsign_list ~= -1;
			}
			if (i == sg.niv-1) {
			    boundaries[Face.east].face_id_list ~= iface_id[i][j][k];
			    boundaries[Face.east].outsign_list ~= +1;
			}
		    }
		}
	    }
	    // j-faces
	    size_t[][][] jface_id;
	    jface_id.length = sg.niv-1;
	    foreach (i; 0 .. sg.niv-1) {
		jface_id[i].length = sg.njv;
		foreach (j; 0 .. sg.njv) {
		    jface_id[i][j].length = sg.nkv-1;
		}
	    }
	    foreach (k; 0 .. sg.nkv-1) {
		foreach (j; 0 .. sg.njv) {
		    foreach (i; 0 .. sg.niv-1) {
			size_t[] vtx_id_list = [vtx_id[i][j][k], vtx_id[i+1][j][k],
						vtx_id[i+1][j][k+1], vtx_id[i][j][k+1]];
			faceIndices[makeFaceTag(vtx_id_list)] = faces.length;
			faces ~= new USGFace(vtx_id_list);
			jface_id[i][j][k] = faces.length - 1;
			if (j == 0) {
			    boundaries[Face.south].face_id_list ~= jface_id[i][j][k];
			    boundaries[Face.south].outsign_list ~= +1;
			}
			if (j == sg.njv-1) {
			    boundaries[Face.north].face_id_list ~= jface_id[i][j][k];
			    boundaries[Face.north].outsign_list ~= -1;
			}
		    }
		}
	    }
	    // k-faces
	    size_t[][][] kface_id;
	    kface_id.length = sg.niv-1;
	    foreach (i; 0 .. sg.niv-1) {
		kface_id[i].length = sg.njv-1;
		foreach (j; 0 .. sg.njv-1) {
		    kface_id[i][j].length = sg.nkv;
		}
	    }
	    foreach (k; 0 .. sg.nkv) {
		foreach (j; 0 .. sg.njv-1) {
		    foreach (i; 0 .. sg.niv-1) {
			size_t[] vtx_id_list = [vtx_id[i][j][k], vtx_id[i+1][j][k],
						vtx_id[i+1][j+1][k], vtx_id[i][j+1][k]];
			faceIndices[makeFaceTag(vtx_id_list)] = faces.length;
			faces ~= new USGFace(vtx_id_list);
			kface_id[i][j][k] = faces.length - 1;
			if (k == 0) {
			    boundaries[Face.bottom].face_id_list ~= kface_id[i][j][k];
			    boundaries[Face.bottom].outsign_list ~= -1;
			}
			if (k == sg.nkv-1) {
			    boundaries[Face.top].face_id_list ~= kface_id[i][j][k];
			    boundaries[Face.top].outsign_list ~= +1;
			}
		    }
		}
	    }
	    // cells
	    foreach (k; 0 .. sg.nkv-1) {
		foreach (j; 0 .. sg.njv-1) {
		    foreach (i; 0 .. sg.niv-1) {
			auto cell_vertices = [vtx_id[i][j][k], vtx_id[i+1][j][k],
					      vtx_id[i+1][j+1][k], vtx_id[i][j+1][k],
					      vtx_id[i][j][k+1], vtx_id[i+1][j][k+1],
					      vtx_id[i+1][j+1][k+1], vtx_id[i][j+1][k+1]];
			auto cell_faces = [jface_id[i][j+1][k], // north
					   iface_id[i+1][j][k], // east
					   jface_id[i][j][k], // south
					   iface_id[i][j][k], // west
					   kface_id[i][j][k+1], // top
					   kface_id[i][j][k]]; // bottom
			auto outsigns = [-1, +1, +1, -1, +1, -1];
			auto my_cell = new USGCell(USGCell_type.hexahedron, cell_vertices,
						   cell_faces, outsigns);
			cells ~= my_cell;
			// Now that we have the new cell, we can make the connections
			// from the faces back to the cell.
			faces[jface_id[i][j+1][k]].left_cell = my_cell;
			faces[iface_id[i+1][j][k]].left_cell = my_cell;
			faces[jface_id[i][j][k]].right_cell = my_cell;
			faces[iface_id[i][j][k]].right_cell = my_cell;
			faces[kface_id[i][j][k+1]].left_cell = my_cell;
			faces[kface_id[i][j][k]].right_cell = my_cell;
		    }
		}
	    }
	} // end if dimensions
	assert(nvertices == vertices.length, "mismatch in number of vertices");
	assert(nfaces == faces.length, "mismatch in number of faces");
	assert(ncells == cells.length, "mismatch in number of cells");
	assembleFaceIndexListPerVertex();
	niv = vertices.length; njv = 1; nkv = 1;
    } // end constructor from StructuredGrid object

    // Imported grid.
    this(string fileName, string fmt, double scale=1.0,
	 bool expect_gmsh_order_for_wedges=true, string new_label="")
    {
	super(Grid_t.unstructured_grid, 0, new_label);
	// dimensions will be reset on reading grid
	switch (fmt) {
	case "gziptext": read_from_gzip_file(fileName, scale); break;
	case "su2text": read_from_su2_file(fileName, scale, expect_gmsh_order_for_wedges); break;
	case "vtktext": read_from_vtk_text_file(fileName, scale); break;
	case "vtkxml": throw new Error("Reading from VTK XML format not implemented.");
	default: throw new Error("Import an UnstructuredGrid, unknown format: " ~ fmt);
	}
	if (new_label != "") { label = new_label; }
	assembleFaceIndexListPerVertex();
	niv = vertices.length; njv = 1; nkv = 1;
    }

    UnstructuredGrid dup() const
    {
	return new UnstructuredGrid(this);
    }

    // ---------------------------------
    // Helper functions for constructors.
    // ---------------------------------
    
    void assembleFaceIndexListPerVertex()
    // Work through the collection of faces and record, for each vertex,
    // that this face is attached to the vertex.
    {
	assert(nvertices == vertices.length, "Inconsistent record of vertices.");
	faceIndexListPerVertex.length = vertices.length;
	foreach (i, f; faces) {
	    foreach (vtxid; f.vtx_id_list) { faceIndexListPerVertex[vtxid] ~= i; }
	}
    }

    
    // -----------------------------
    // Indexing and location methods.
    // -----------------------------
    
    override Vector3* opIndex(size_t i, size_t j, size_t k=0)
    in {
	assert (i < nvertices, text("index i=", i, " is invalid, nvertices=", nvertices));
	assert (j == 0, text("index j=", j, " is invalid for unstructured grid"));
	assert (k == 0, text("index k=", k, " is invalid for unstructured grid"));
    }
    body {
	return &(vertices[i]);
    }

    override Vector3* opIndex(size_t indx)
    in {
	assert (indx < nvertices,
		text("index indx=", indx, " is invalid, nvertices=", nvertices));
    }
    body {
	return &(vertices[indx]);
    }

    override size_t number_of_vertices_for_cell(size_t i)
    {
	return cells[i].vtx_id_list.length;
    }

    override int vtk_element_type_for_cell(size_t i)
    {
	return vtk_element_types[cells[i].cell_type];
    }

    override int get_cell_type(size_t i)
    {
	return cells[i].cell_type;
    }

    override size_t[] get_vtx_id_list_for_cell(size_t i, size_t j, size_t k=0) const
    in {
	assert (i < ncells, text("index i=", i, " is invalid, ncells=", ncells));
	assert (j == 0, text("index j=", j, " is invalid for unstructured grid"));
	assert (k == 0, text("index k=", k, " is invalid for unstructured grid"));
    }
    body {
	return cells[i].vtx_id_list.dup();
    }

    override size_t[] get_vtx_id_list_for_cell(size_t indx) const
    in {
	assert (indx < ncells,
		text("index indx=", indx, " is invalid, ncells=", ncells));
    }
    body {
	return cells[indx].vtx_id_list.dup();
    }

    override Grid get_boundary_grid(size_t boundary_indx)
    // Returns the grid defining a particular boundary of the original grid.
    // For an 3D block, a 2D surface grid will be returned, with index directions
    // as defined on the debugging cube.
    // This new grid is intended for use just in the output of a subset 
    // of the simulation data and not for actual simulation.
    // It does not carry all of the information required for flow simulation.
    {
	int new_dimensions = dimensions - 1;
	if (new_dimensions < 1 || new_dimensions > 2) {
	    throw new Exception(format("Invalid new_dimensions=%d", new_dimensions));
	}
	BoundaryFaceSet bfs = boundaries[boundary_indx];
	UnstructuredGrid new_grid = new UnstructuredGrid(new_dimensions, bfs.tag);
	// We'll make a full copy of the original grid's vertices
	// so that we don't have to renumber them.
	new_grid.nvertices = nvertices;
	new_grid.vertices.length = nvertices;
	foreach (i; 0 .. nvertices) { new_grid.vertices[i].set(vertices[i]); }
	foreach (fid; bfs.face_id_list) {
	    // fid is the face in the original grid.
	    // It will become the cell in the new grid.
	    USGCell_type new_cell_type = USGCell_type.none;
	    switch (faces[fid].vtx_id_list.length) {
	    case 2:
		assert(dimensions == 2, "Assumed 2D but it was not so.");
		new_cell_type = USGCell_type.line;
		break;
	    case 3:
		assert(dimensions == 3, "Assumed 3D but it was not so.");
		new_cell_type = USGCell_type.triangle;
		break;
	    case 4:
		assert(dimensions == 3, "Assumed 3D but it was not so.");
		new_cell_type = USGCell_type.quad;
		break;
	    default:
		throw new Exception("Did not know what to do with this number of vertices.");
	    }
	    size_t[] newCell_face_id_list; // empty
	    int[] newCell_outsign_list; // empty
	    new_grid.cells ~= new USGCell(new_cell_type, faces[fid].vtx_id_list,
					  newCell_face_id_list, newCell_outsign_list);
	}
	return new_grid;
    } // end get_boundary_grid()

    override size_t[] get_list_of_boundary_cells(size_t boundary_indx)
    // Prepares list of cells indicies that match the boundary grid selected by
    // the function get_boundary_grid().  See above.
    {
	size_t new_nic, new_njc, new_nkc;
	size_t[] cellList;
	// Make a dictionary of cell indices, so that we may look them up
	// when building the list of indices.
	size_t[USGCell] cell_indx;
	foreach (i, c; cells) { cell_indx[c] = i; }
	// Work through the set of boundary faces and identify the inside cell
	// as being the one we want to associate with the boundary face.
	BoundaryFaceSet bfs = boundaries[boundary_indx];
	foreach (i, fid; bfs.face_id_list) {
	    USGCell insideCell = (bfs.outsign_list[i] == 1) ? 
		faces[fid].left_cell : faces[fid].right_cell;
	    cellList ~= cell_indx[insideCell];
	}
	return cellList;
    } // end get_list_of_boundary_cells()
    
    override double cell_volume(size_t indx)
    {
	Vector3 centroid;
	double vol, iLen, jLen, kLen, Lmin;
	size_t[] vtx_ids = get_vtx_id_list_for_cell(indx);

	if (dimensions == 2) {
	    switch (vtx_ids.length) {
	    case 3:
		xyplane_triangle_cell_properties(vertices[vtx_ids[0]], vertices[vtx_ids[1]], vertices[vtx_ids[2]],
						  centroid, vol, iLen, jLen, Lmin);
		return vol;
	    case 4:
		xyplane_quad_cell_properties(vertices[vtx_ids[0]], vertices[vtx_ids[1]],
					     vertices[vtx_ids[2]], vertices[vtx_ids[3]],
					     centroid, vol, iLen, jLen, Lmin);
		return vol;
	    default:
		string msg = "usgrid.cell_volume(): ";
		msg ~= format("Unhandled number of vertices: %d", vtx_ids.length);
		throw new Error(msg);
	    } // end switch
	} // end: if 2D
	// else, 3D
	switch (vtx_ids.length) {
	case 4:
	    tetrahedron_properties(vertices[vtx_ids[0]], vertices[vtx_ids[1]], 
				   vertices[vtx_ids[2]], vertices[vtx_ids[3]],
				   centroid, vol);
	    return vol;
	case 8:
	    hex_cell_properties(vertices[vtx_ids[0]], vertices[vtx_ids[1]], 
				vertices[vtx_ids[2]], vertices[vtx_ids[3]],
				vertices[vtx_ids[4]], vertices[vtx_ids[5]],
				vertices[vtx_ids[6]], vertices[vtx_ids[7]],
				centroid, vol, iLen, jLen, kLen);
	    return vol;
	case 5:
	    pyramid_properties(vertices[vtx_ids[0]], vertices[vtx_ids[1]], 
			       vertices[vtx_ids[2]], vertices[vtx_ids[3]],
			       vertices[vtx_ids[4]], 
			       centroid, vol);
	    return vol;
	case 6:
	    wedge_properties(vertices[vtx_ids[0]], vertices[vtx_ids[1]],
			     vertices[vtx_ids[2]], vertices[vtx_ids[3]],
			     vertices[vtx_ids[4]], vertices[vtx_ids[5]],
			     centroid, vol);
	    return vol;
	default:
	    string msg = "usgrid.cell_volume(): ";
	    msg ~= format("Unhandled number of vertices: %d", vtx_ids.length);
	    throw new Error(msg);
	} // end switch
    } // end cell_volume()
    
    // ------------------------
    // Import-from-file methods.
    // ------------------------
    
    override void read_from_gzip_file(string fileName, double scale=1.0)
    // This function, together with the constructors (from strings) for
    // the classes USGFace, USGCell and BoundaryFaceSet (above),
    // define the Eilmer4 native format.
    // For output, there is the matching write_to_gzip_file() below.
    // scale = unit length in metres
    {
	auto byLine = new GzipByLine(fileName);
	auto line = byLine.front; byLine.popFront();
	string format_version;
	formattedRead(line, "unstructured_grid %s", &format_version);
	if (format_version != "1.0") {
	    throw new Error("UnstructuredGrid.read_from_gzip_file(): " ~
			    "format version found: " ~ format_version); 
	}
	line = byLine.front; byLine.popFront();
	formattedRead(line, "label: %s", &label);
	line = byLine.front; byLine.popFront();
	formattedRead(line, "dimensions: %d", &dimensions);
	line = byLine.front; byLine.popFront();
	formattedRead(line, "vertices: %d", &nvertices);
	double x, y, z;
	vertices.length = 0;
	foreach (i; 0 .. nvertices) {
	    line = byLine.front; byLine.popFront();
	    // Note that the line starts with whitespace.
	    formattedRead(line, " %g %g %g", &x, &y, &z);
	    vertices ~= Vector3(scale*x, scale*y, scale*z);
	}
	line = byLine.front; byLine.popFront();
	formattedRead(line, "faces: %d", &nfaces);
	faces.length = 0;
	foreach (i; 0 .. nfaces) {
	    line = byLine.front; byLine.popFront();
	    auto myFace = new USGFace(line);
	    faceIndices[makeFaceTag(myFace.vtx_id_list)] = faces.length;
	    faces ~= myFace;
	}
	line = byLine.front; byLine.popFront();
	formattedRead(line, "cells: %d", &ncells);
	cells.length = 0;
	foreach (i; 0 .. ncells) {
	    line = byLine.front; byLine.popFront();
	    cells ~= new USGCell(line);
	}
	line = byLine.front; byLine.popFront();
	formattedRead(line, "boundaries: %d", &nboundaries);
	boundaries.length = 0;
	foreach (i; 0 .. nboundaries) {
	    line = byLine.front; byLine.popFront();
	    boundaries ~= new BoundaryFaceSet(line);
	}
    } // end read_from_gzip_file()

    void read_from_su2_file(string fileName, double scale=1.0,
			    bool expect_gmsh_order_for_wedges=true)
    // Information on the su2 file format from
    // https://github.com/su2code/SU2/wiki/Mesh-File
    // scale = unit length in metres
    {
	auto f = File(fileName, "r");
	string getHeaderContent(string target)
	// Helper function to proceed through file, line-by-line,
	// looking for a particular header line.
	// Returns the content from the header line and leaves the file
	// at the next line to be read, presumably with expected data.
	{
	    while (!f.eof) {
		auto line = f.readln().strip();
		if (canFind(line, target)) {
		    auto tokens = line.split("=");
		    return tokens[1].strip();
		}
	    } // end while
	    return ""; // didn't find the target
	}
	dimensions = to!int(getHeaderContent("NDIME"));
	writeln("dimensions=", dimensions);
	ncells = to!size_t(getHeaderContent("NELEM"));
	writeln("ncells=", ncells);
	cells.length = ncells;
	foreach(i; 0 .. ncells) {
	    auto lineContent = f.readln().strip();
	    auto tokens = lineContent.split();
	    int vtk_element_type = to!int(tokens[0]);
	    size_t indx = to!size_t(tokens[$-1]);
	    size_t[] vtx_id_list;
	    foreach(j; 1 .. tokens.length-1) { vtx_id_list ~= to!size_t(tokens[j]); }
	    USGCell_type cell_type = convert_cell_type(vtk_element_type);
	    if (cell_type == USGCell_type.none) {
		throw new Exception("unknown element type for line: "~to!string(lineContent));
	    }
	    if (cell_type == USGCell_type.wedge && expect_gmsh_order_for_wedges) {
		// We assume that we have picked up the vertex indices for a wedge
		// in GMSH order but we need to store them in VTK order.
		vtx_id_list = [vtx_id_list[1], vtx_id_list[0], vtx_id_list[2],
			       vtx_id_list[4], vtx_id_list[3], vtx_id_list[5]];
	    }
	    size_t[] face_id_list; // empty, so far
	    int[] outsign_list; // empty, so far
	    // Once we have created the full list of vertices, we will be able to make
	    // the set of faces and then come back to filling in the face_id_list and
	    // outsign_list for each cell.
	    cells[indx] = new USGCell(cell_type, vtx_id_list, face_id_list, outsign_list);
	} // end foreach i .. ncells
	foreach(i; 0 .. cells.length) {
	    if (!cells[i]) { writeln("Warning: uninitialized cell at index: ", i); }
	    // [TODO] if we have any uninitialized cells,
	    // we should compress the array to eliminate empty elements.
	}
	nvertices = to!size_t(getHeaderContent("NPOIN"));
	writeln("nvertices=", nvertices);
	vertices.length = nvertices;
	foreach(i; 0 .. nvertices) {
	    auto tokens = f.readln().strip().split();
	    double x=0.0; double y=0.0; double z = 0.0; size_t indx = 0;
	    if (dimensions == 2) {
		x = scale * to!double(tokens[0]);
		y = scale * to!double(tokens[1]);
		indx = to!size_t(tokens[2]);
	    } else {
		assert(dimensions == 3, "invalid dimensions");
		x = scale * to!double(tokens[0]);
		y = scale * to!double(tokens[1]);
		z = scale * to!double(tokens[2]);
		indx = to!size_t(tokens[3]);
	    }
	    vertices[indx].set(x, y, z);
	} // end foreach i .. nvertices
	//
	if (dimensions == 2) {
	    // In 2D, the flow solver code assumes that the cycle of vertices
	    // defining the cell is counterclockwise, looking down the negative z-axis,
	    // toward the x,y-plane.
	    // If any of the cells that have been read from the file presently have
	    // their normal vector pointing in the negative z-direction,
	    // we should reverse the order of their vertex list.
	    foreach(c; cells) {
		switch (c.cell_type) {
		case USGCell_type.triangle:
		    Vector3 a = Vector3(vertices[c.vtx_id_list[1]]);
		    a -= vertices[c.vtx_id_list[0]];
		    Vector3 b = Vector3(vertices[c.vtx_id_list[2]]);
		    b -= vertices[c.vtx_id_list[0]];
		    Vector3 n;
		    cross(n,a,b);
		    if (n.z < 0.0) { reverse(c.vtx_id_list); }
		    break;
		case USGCell_type.quad:
		    Vector3 a = Vector3(vertices[c.vtx_id_list[1]]);
		    a -= vertices[c.vtx_id_list[0]];
		    a += vertices[c.vtx_id_list[2]];
		    a -= vertices[c.vtx_id_list[3]];
		    Vector3 b = Vector3(vertices[c.vtx_id_list[3]]);
		    b -= vertices[c.vtx_id_list[0]];
		    b += vertices[c.vtx_id_list[2]];
		    b -= vertices[c.vtx_id_list[1]];
		    Vector3 n;
		    cross(n,a,b);
		    if (n.z < 0.0) { reverse(c.vtx_id_list); }
		    break;
		default:
		    throw new Exception("invalid cell type for 2D grid");
		} // end switch
	    } // end foreach c
	} // end if (dimensions == 2)
	//
	// Now that we have the full list of cells and vertices assigned to each cell,
	// we can construct the faces between cells and along the boundaries.
	//
	void add_face_to_cell(ref USGCell cell, size_t[] corners)
	{
	    // If the face is new, we add it to the list, else we use the face
	    // already stored within the list, so that it may no longer be
	    // outward pointing for this cell.
	    //
	    size_t[] my_vtx_id_list;
	    foreach(i; corners) { my_vtx_id_list ~= cell.vtx_id_list[i]; }
	    size_t face_indx = 0;
	    string faceTag = makeFaceTag(my_vtx_id_list);
	    if (faceTag in faceIndices) {
		// Use the face already present.
		face_indx = faceIndices[faceTag];
	    } else {
		// Since we didn't find the face already, construct it.
		face_indx = faces.length;
		faces ~= new USGFace(my_vtx_id_list);
		faceIndices[faceTag] = face_indx;
	    }
	    cell.face_id_list ~= face_indx;
	    //
	    // Note that, from this point, we work with the face from the collection
	    // which, if it was an existing face, will not have the same orientation
	    // as indicated by the cycle of vertices passed in to this function call.
	    //
	    // Pointers to all vertices on face.
	    Vector3*[] v;
	    foreach (i; 0 .. corners.length) {
		v ~= &vertices[faces[face_indx].vtx_id_list[i]];
	    }
	    // Location of mid-point of cell.
	    Vector3 cell_mid = Vector3(vertices[cell.vtx_id_list[0]]);
	    foreach(i; 1 .. cell.vtx_id_list.length) {
		cell_mid += vertices[cell.vtx_id_list[i]];
	    }
	    cell_mid /= cell.vtx_id_list.length;
	    //
	    // Determine if cell is on left- or right-side of face.
	    //
	    bool onLeft;
	    switch (corners.length) {
	    case 2:
		// Two-dimensional simulation:
		// The face is a line in the xy-plane.
		onLeft = on_left_of_xy_line(*(v[0]), *(v[1]), cell_mid);
		break;
	    case 3:
		// Three-dimensional simulation:
		// The face has been defined with the vertices being in
		// a counter-clockwise cycle when viewed from outside of the cell.
		// We expect negative volumes for the pyramid having the cell's
		// midpoint as its apex.
		onLeft = (tetrahedron_volume(*(v[0]), *(v[1]), *(v[2]), cell_mid) < 0.0);
		break;
	    case 4:
		// Three-dimensional simulation:
		// The face has been defined with the vertices being in
		// a counter-clockwise cycle when viewed from outside of the cell.
		// We expect negative volumes for the pyramid having the cell's
		// midpoint as its apex.
		Vector3 vmid = 0.25*( *(v[0]) + *(v[1]) + *(v[2]) + *(v[3]) );
		onLeft = (tetragonal_dipyramid_volume(*(v[0]), *(v[1]), *(v[2]), *(v[3]),
						      vmid, cell_mid) < 0.0);
		break;
	    default:
		throw new Exception("invalid number of corners on face.");
	    }
	    if (onLeft) {
		if (faces[face_indx].left_cell) {
		    throw new Exception("face already has a left cell");
		}
		faces[face_indx].left_cell = cell;
		cell.outsign_list ~=  1;
	    } else {
		if (faces[face_indx].right_cell) {
		    throw new Exception("face already has a right cell");
		}
		faces[face_indx].right_cell = cell;
		cell.outsign_list ~= -1;
	    }
	    return;
	} // end add_face_to_cell()
	//
	foreach(cell; cells) {
	    if (!cell) continue;
	    // Attach the faces to each cell. In 2D, faces are defined as lines.
	    // As we progress along the line the face normal is pointing to the right.
	    // In 3D, a counter-clockwise cycles of points plus the right-hand rule
	    // define the face normal. Whether a face points out of or into a cell
	    // will be determined and remembered when we add the face to the cell.
	    if (dimensions == 2) {
		switch(cell.cell_type) {
		case USGCell_type.triangle:
		    add_face_to_cell(cell, [0,1]);
		    add_face_to_cell(cell, [1,2]);
		    add_face_to_cell(cell, [2,0]);
		    break;
		case USGCell_type.quad:
		    add_face_to_cell(cell, [2,3]); // north
		    add_face_to_cell(cell, [1,2]); // east
		    add_face_to_cell(cell, [0,1]); // south
		    add_face_to_cell(cell, [3,0]); // west
		    break;
		default:
		    throw new Exception("invalid cell type in 2D");
		}
	    } else {
		assert(dimensions == 3, "invalid dimensions");
		switch(cell.cell_type) {
		case USGCell_type.tetra:
		    add_face_to_cell(cell, [0,1,2]);
		    add_face_to_cell(cell, [0,1,3]);
		    add_face_to_cell(cell, [1,2,3]);
		    add_face_to_cell(cell, [2,0,3]);
		    break;
		case USGCell_type.hexahedron:
		    add_face_to_cell(cell, [2,3,7,6]); // north
		    add_face_to_cell(cell, [1,2,6,5]); // east
		    add_face_to_cell(cell, [1,0,4,5]); // south
		    add_face_to_cell(cell, [0,3,7,4]); // west
		    add_face_to_cell(cell, [4,5,6,7]); // top
		    add_face_to_cell(cell, [0,1,2,3]); // bottom
		    break;
		case USGCell_type.wedge:
		    add_face_to_cell(cell, [0,1,2]);
		    add_face_to_cell(cell, [3,4,5]);
		    add_face_to_cell(cell, [0,2,5,3]);
		    add_face_to_cell(cell, [0,3,4,1]);
		    add_face_to_cell(cell, [1,4,5,2]);
		    break;
		case USGCell_type.pyramid:
		    add_face_to_cell(cell, [0,1,2,3]);
		    add_face_to_cell(cell, [0,1,4]);
		    add_face_to_cell(cell, [1,2,4]);
		    add_face_to_cell(cell, [2,3,4]);
		    add_face_to_cell(cell, [3,0,4]);
		    break;
		default:
		    throw new Exception("invalid cell type in 3D");
		}
	    }
	} // end foreach cell
	nfaces = faces.length;
	//
	// Now that we have a full set of cells and faces,
	// make lists of the boundary faces.
	//
	nboundaries = to!size_t(getHeaderContent("NMARK"));
	foreach(i; 0 .. nboundaries) {
	    string tag = getHeaderContent("MARKER_TAG");
	    writeln("boundary i=", i, " tag=", tag);
	    size_t[] face_id_list;
	    int[] outsign_list;
	    size_t nelem = to!size_t(getHeaderContent("MARKER_ELEMS"));
	    // writeln("nelem=", nelem);
	    foreach(j; 0 .. nelem) {
		auto tokens = f.readln().strip().split();
		int vtk_type = to!int(tokens[0]);
		size_t[] my_vtx_id_list;
		foreach(k; 1 .. tokens.length) { my_vtx_id_list ~= to!size_t(tokens[k]); }
		string faceTag = makeFaceTag(my_vtx_id_list);
		if (faceTag in faceIndices) {
		    size_t face_indx = faceIndices[faceTag];
		    USGFace my_face = faces[face_indx];
		    assert(my_face.left_cell || my_face.right_cell,
			   "face is not properly connected");
		    if (my_face.left_cell && !(my_face.right_cell)) {
			outsign_list ~= 1;
		    } else if ((!my_face.left_cell) && my_face.right_cell) {
			outsign_list ~= -1;
		    } else {
			throw new Exception("appears to be an interior face");
		    }
		    face_id_list ~= face_indx;
		} else {
		    throw new Exception("cannot find face in collection");
		}
	    } // end foreach j
	    boundaries ~= new BoundaryFaceSet(tag, face_id_list, outsign_list);
	} // end foreach i
    } // end read_from_su2_text_file()

    void read_from_vtk_text_file(string fileName, double scale=1.0)
    // scale = unit length in metres
    {
	string[] tokens;
	auto f = File(fileName, "r");
	read_VTK_header_line("vtk", f);
	label = f.readln().strip();
	read_VTK_header_line("ASCII", f);
	read_VTK_header_line("USTRUCTURED_GRID", f);
	tokens = f.readln().strip().split();
	throw new Error("read_from_vtk_text_file() is not finished, yet.");
	// For VTK files, we need to work out how to extract 
	// the topological details for the incoming grid.
    } // end read_from_vtk_text_file()

    override void write_to_gzip_file(string fileName)
    // This function, together with the toIOstring methods for
    // the classes USGFace, USGCell and BoundaryFaceSet (way above)
    // define the Eilmer4 native format.
    // For input, there is the matching read_from_gzip_file(), above.
    {
	auto fout = new GzipOut(fileName);
	fout.compress("unstructured_grid 1.0\n");
	fout.compress(format("label: %s\n", label));
	fout.compress(format("dimensions: %d\n", dimensions));
	fout.compress(format("vertices: %d\n", nvertices));
	foreach (v; vertices) {
	    fout.compress(format("%.18e %.18e %.18e\n", v.x, v.y, v.z));
	}
	fout.compress(format("faces: %d\n", nfaces));
	foreach (f; faces) { fout.compress(f.toIOString ~ "\n"); }
	fout.compress(format("cells: %d\n", ncells));
	foreach (c; cells) { fout.compress(c.toIOString ~ "\n"); }
	fout.compress(format("boundaries: %d\n", boundaries.length));
	foreach (b; boundaries) { fout.compress(b.toIOString ~ "\n"); }
	fout.finish();
    } // end write_to_gzip_file()

    override void write_to_vtk_file(string fileName)
    {
	auto f = File(fileName, "w");
	f.writeln("# vtk DataFile Version 2.0");
	f.writeln(label);
	f.writeln("ASCII");
	f.writeln("");
	f.writeln("DATASET UNSTRUCTURED_GRID");
	f.writefln("POINTS %d float", nvertices);
	foreach (v; vertices) { f.writefln("%.18e %.18e %.18e", v.x, v.y, v.z); }
	f.writeln("");
	int n_ints = 0; // number of integers to describe connections
	foreach (c; cells) { n_ints += 1 + c.vtx_id_list.length; }
	f.writefln("CELLS %d %d", ncells, n_ints);
	foreach (c; cells) {
	    f.write(c.vtx_id_list.length);
	    foreach (vtx_id; c.vtx_id_list) { f.write(" ", vtx_id); }
	    f.writeln();
	}
	f.writefln("CELL_TYPES %d", ncells);
	foreach (c; cells) {
	    f.writeln(vtk_element_types[c.cell_type]);
	}
	f.close();
    } // end write_to_vtk_file()

    override void write_to_su2_file(string fileName, double scale=1.0,
				    bool use_gmsh_order_for_wedges=true)
    {
	auto f = File(fileName, "w");
	f.writefln("NDIME= %d", dimensions);
	f.writeln("");
	f.writefln("NELEM= %d", ncells);
	foreach (i, c; cells) {
	    f.write(vtk_element_types[c.cell_type]);
	    if (c.cell_type == USGCell_type.wedge && use_gmsh_order_for_wedges) {
		size_t[] vtx_id_list = c.vtx_id_list.dup();
		// We have the vertex indices for a wedge stored in VTK order
		// but we are requested to output them in GMSH order.
		vtx_id_list = [vtx_id_list[1], vtx_id_list[0], vtx_id_list[2],
			       vtx_id_list[4], vtx_id_list[3], vtx_id_list[5]];
		foreach (vtx_id; vtx_id_list) { f.write(" ", vtx_id); }
	    } else {
		foreach (vtx_id; c.vtx_id_list) { f.write(" ", vtx_id); }
	    }
	    f.writefln(" %d", i); // cell index
	}
	f.writeln("");
	f.writefln("NPOIN= %d", nvertices);
	foreach (i, v; vertices) {
	    if (dimensions == 3) {
		f.writefln("%.18e %.18e %.18e %d", v.x/scale, v.y/scale, v.z/scale, i);
	    } else {
		f.writefln("%.18e %.18e %d", v.x/scale, v.y/scale, i);
	    }
	}
	f.writeln("");
	f.writefln("NMARK= %d", nboundaries);
	foreach (b; boundaries) {
	    f.writefln("MARKER_TAG= %s", b.tag);
	    f.writefln("MARKER_ELEMS= %d", b.face_id_list.length);
	    foreach (faceIndx; b.face_id_list) {
		auto vtx_id_list = faces[faceIndx].vtx_id_list;
		if (dimensions == 3) {
		    switch (vtx_id_list.length) {
		    case 3: f.writef("%d", VTKElement.triangle); break;
		    case 4: f.writef("%d", VTKElement.quad); break;
		    default: f.write("oops, should not have this number of vertices");
		    }
		} else {
		    // In 2D, we have only lines as the boundary elements.
		    f.writef("%d", VTKElement.line);
		}
		foreach (vtx_id; vtx_id_list) { f.writef(" %d", vtx_id); }
		f.writeln();
	    }
	}
	f.close();
    } // end write_to_su2_file()

    void write_openFoam_polyMesh(string topLevelDir)
    // The OpenFoam mesh format is defined primarily in terms of the face polygons.
    // There is a required order for the faces in which all internal faces appear first,
    // followed by the boundary sets of faces.  This order is required so that each
    // boundary set can be simply identified as a starting face and a number of faces.
    // There is also a constraint that each face's unit normal points out of its
    // "owning" cell.  For an internal cell, between two cells, the owning cell is
    // the one with the smaller index.
    //
    // Files that will be written:
    // <topLevelDir>/polyMesh/points
    //                       /faces
    //                       /owner
    //                       /neighbour
    //                       /boundary
    {
	// First, we will construct a description of the unstructured mesh
	// in terms of quantities that OpenFOAM uses.
	//
	// Construct dictionary of cell indices so that we can look up
	// the indices of the left and right cells.
	//
	int[USGCell] cellId; foreach (i, c; cells) { cellId[c] = to!int(i); }
	//
	// Set up the list of internal-face ids and a list of outsign values,
	// indicating whether the internal face is point out of its owning cell.
	//
	size_t[] internal_face_id_list; // limited to internal faces only
	int[] owner_cell_id_list; // an entry for all faces
	int[] neighbour_cell_id_list; // an entry for all faces
	int[] outsign_list; // an entry for all faces
	foreach (i, face; faces) {
	    int owner_id = -1;
	    int neighbour_id = -1;
	    int outsign = 1;
	    if (face.left_cell is null) {
		owner_id = cellId[face.right_cell];
		outsign = -1;
	    } else if (face.right_cell is null) {
		owner_id = cellId[face.left_cell];
	    } else {
		internal_face_id_list ~= i;
		if (cellId[face.left_cell] < cellId[face.right_cell]) {
		    owner_id = cellId[face.left_cell];
		    neighbour_id = cellId[face.right_cell];
		} else {
		    owner_id = cellId[face.right_cell];
		    neighbour_id = cellId[face.left_cell];
		    outsign = -1;
		}
	    }
	    assert(owner_id >= 0, "face seems to be not owned by a cell"); // [TODO] more info
	    owner_cell_id_list ~= owner_id;
	    neighbour_cell_id_list ~= neighbour_id;
	    outsign_list ~= outsign;
	}
	size_t face_tally = internal_face_id_list.length;
	foreach (b; boundaries) { face_tally += b.face_id_list.length; }
	assert(face_tally == faces.length, "mismatch in number of faces in boundary sets");
	//
	// Now, we are ready to write the files.
	//
	string polyMeshDir = topLevelDir ~ "/polyMesh";
	if (!exists(polyMeshDir)) { mkdirRecurse(polyMeshDir); }
	//
	auto f = File(polyMeshDir~"/points", "w");
	f.writeln("FoamFile\n{");
	f.writeln(" version   2.0;");
	f.writeln(" format    ascii;");
	f.writeln(" class     vectorField;");
	f.writeln(" location  \"constant/polyMesh\";");
	f.writeln(" object    points;");
	f.writeln("}");
	f.writefln("%d\n(", vertices.length);
	foreach (i,v; vertices) { f.writefln(" (%.18e %.18e %.18e)", v.x, v.y, v.z); }
	f.writeln(")");
	f.close();
	//
	f = File(polyMeshDir~"/faces", "w");
	f.writeln("FoamFile\n{");
	f.writeln(" version   2.0;");
	f.writeln(" format    ascii;");
	f.writeln(" class     faceList;");
	f.writeln(" location  \"constant/polyMesh\";");
	f.writeln(" object    faces;");
	f.writeln("}");
	string index_str(const ref USGFace f, int outsign)
	{
	    string str = " " ~ to!string(f.vtx_id_list.length) ~ "(";
	    auto my_vtx_id_list = f.vtx_id_list.dup();
	    if (outsign < 0) { reverse(my_vtx_id_list); }
	    foreach (j, vtx_id; my_vtx_id_list) {
		if (j > 0) { str ~= " "; }
		str ~= to!string(vtx_id);
	    }
	    str ~= ")";
	    return str;
	}
	f.writefln("%d\n(", faces.length);
	foreach (i; internal_face_id_list) { f.writeln(index_str(faces[i], outsign_list[i])); }
	foreach (b; boundaries) {
	    foreach (i; b.face_id_list) { f.writeln(index_str(faces[i], outsign_list[i])); }
	}
	f.writeln(")");
	f.close();
	//
	f = File(polyMeshDir~"/owner", "w");
	f.writeln("FoamFile\n{");
	f.writeln(" version   2.0;");
	f.writeln(" format    ascii;");
	f.writeln(" class     labelList;");
	f.writeln(" location  \"constant/polyMesh\";");
	f.writeln(" object    owner;");
	f.writeln("}");
	f.writefln("%d\n(", faces.length);
	foreach (i; internal_face_id_list) { f.writefln(" %d", owner_cell_id_list[i]); }
	foreach (b; boundaries) {
	    foreach (i; b.face_id_list) { f.writefln(" %d", owner_cell_id_list[i]); }
	}
	f.writeln(")");
	f.close();
	//
	f = File(polyMeshDir~"/neighbour", "w");
	f.writeln("FoamFile\n{");
	f.writeln(" version   2.0;");
	f.writeln(" format    ascii;");
	f.writeln(" class     labelList;");
	f.writeln(" location  \"constant/polyMesh\";");
	f.writeln(" object    neighbour;");
	f.writeln("}");
	f.writefln("%d\n(", internal_face_id_list.length);
	foreach (i; internal_face_id_list) { f.writefln(" %d", owner_cell_id_list[i]); }
	f.writeln(")");
	f.close();
	//
	f = File(polyMeshDir~"/boundary", "w");
	f.writeln("FoamFile\n{");
	f.writeln(" version   2.0;");
	f.writeln(" format    ascii;");
	f.writeln(" class     polyBoundaryMesh;");
	f.writeln(" location  \"constant/polyMesh\";");
	f.writeln(" object    boundary;");
	f.writeln("}");
	f.writefln("%d\n(", boundaries.length);
	size_t startFace = internal_face_id_list.length;
	foreach (i, b; boundaries) {
	    f.writefln(" boundary%04d\n {", i);
	    f.writefln("  type      %s;", "patch");
	    f.writefln("  nFaces    %d;", b.face_id_list.length);
	    f.writefln("  startFace %d;", startFace);
	    f.writeln(" }");
	    startFace += b.face_id_list.length; // for the next boundary
	}
	f.writeln(")");
	f.close();
    } // end write_openFoam_polyMesh()

} // end class UnstructuredGrid



