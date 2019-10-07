// mapped_cell_copy.d

module bc.ghost_cell_effect.mapped_cell_copy;

import core.memory;
import std.json;
import std.string;
import std.conv;
import std.stdio;
import std.math;
import std.file;
import std.algorithm;
import nm.complex;
import nm.number;
version(mpi_parallel) {
    import mpi;
    import mpi.util;
}

import geom;
import json_helper;
import globalconfig;
import globaldata;
import flowstate;
import fvcore;
import fvinterface;
import fvcell;
import fluidblock;
import sfluidblock;
import gas;
import bc;


struct BlockAndCellId {
    size_t blkId;
    size_t cellId;

    this(size_t bid, size_t cid)
    {
        blkId = bid;
        cellId = cid;
    }
}

class GhostCellMappedCellCopy : GhostCellEffect {
public:
    // Flow data along the boundary is stored in ghost cells.
    FVCell[] ghost_cells;
    size_t[string] ghost_cell_index_from_faceTag;
    // For each ghost-cell associated with the current boundary,
    // we will have a corresponding "mapped cell", also known as "source cell"
    // from which we will copy the flow conditions.
    // In the shared-memory flavour of the code, it is easy to get a direct
    // reference to each such mapped cell and store that for easy access.
    FVCell[] mapped_cells;
    // We may specify which source cell and block from which a particular ghost-cell
    // (a.k.a. destination cell) will copy its flow and geometry data.
    // This mapping information is prepared externally and provided in
    // a single mapped_cells file which has one line per mapped cell.
    // The first item on each line specifies the boundary face associated with
    // with the ghost cell via the faceTag.
    bool cell_mapping_from_file;
    string mapped_cells_filename;
    BlockAndCellId[string][] mapped_cells_list;
    version(mpi_parallel) {
        // In the MPI-parallel code, we do not have such direct access and so
        // we store the integral ids of the source cell and block and send requests
        // to the source blocks to get the relevant geometry and flow data.
        // The particular cells and the order in which they are packed into the
        // data pipes need to be known at the source and destination ends of the pipes.
        // So, we store those cell indices in a matrix of lists with the indices
        // into the matrix being the source and destination block ids.
        size_t[][][] src_cell_ids;
        size_t[][][] ghost_cell_indices;
        //
        size_t n_incoming, n_outgoing;
        size_t[] outgoing_ncells_list, incoming_ncells_list;
        size_t[] outgoing_block_list, incoming_block_list;
        int[] outgoing_rank_list, incoming_rank_list;
        int[] outgoing_geometry_tag_list, incoming_geometry_tag_list;
        MPI_Request[] incoming_geometry_request_list;
        MPI_Status[] incoming_geometry_status_list;
        double[][] outgoing_geometry_buf_list, incoming_geometry_buf_list;
        int[] outgoing_flowstate_tag_list, incoming_flowstate_tag_list;
        MPI_Request[] incoming_flowstate_request_list;
        MPI_Status[] incoming_flowstate_status_list;
        double[][] outgoing_flowstate_buf_list, incoming_flowstate_buf_list;
        int[] outgoing_convective_gradient_tag_list, incoming_convective_gradient_tag_list;
        MPI_Request[] incoming_convective_gradient_request_list;
        MPI_Status[] incoming_convective_gradient_status_list;
        double[][] outgoing_convective_gradient_buf_list, incoming_convective_gradient_buf_list;
    }
    //
    // Parameters for the calculation of the mapped-cell location.
    bool transform_position;
    Vector3 c0 = Vector3(0.0, 0.0, 0.0); // default origin
    Vector3 n = Vector3(0.0, 0.0, 1.0); // z-axis
    double alpha = 0.0; // rotation angle (radians) about specified axis vector
    Vector3 delta = Vector3(0.0, 0.0, 0.0); // default zero translation
    bool list_mapped_cells;
    // Parameters for the optional rotation of copied vector data.
    bool reorient_vector_quantities;
    double[] Rmatrix;

    this(int id, int boundary,
         bool cell_mapping_from_file,
         string mapped_cells_filename,
         bool transform_pos,
         ref const(Vector3) c0, ref const(Vector3) n, double alpha,
         ref const(Vector3) delta,
         bool list_mapped_cells,
         bool reorient_vector_quantities,
         ref const(double[]) Rmatrix)
    {
        super(id, boundary, "MappedCellCopy");
        this.cell_mapping_from_file = cell_mapping_from_file;
        this.mapped_cells_filename = mapped_cells_filename;
        this.transform_position = transform_pos;
        this.c0 = c0;
        this.n = n; this.n.normalize();
        this.alpha = alpha;
        this.delta = delta;
        this.list_mapped_cells = list_mapped_cells;
        this.reorient_vector_quantities = reorient_vector_quantities;
        this.Rmatrix = Rmatrix.dup();
    }

    override string toString() const
    { 
        string str = "MappedCellCopy(" ~
            "cell_mapping_from_file=" ~ to!string(cell_mapping_from_file) ~
            ", mapped_cells_filename=" ~ to!string(mapped_cells_filename) ~
            ", transform_position=" ~ to!string(transform_position) ~
            ", c0=" ~ to!string(c0) ~ 
            ", n=" ~ to!string(n) ~ 
            ", alpha=" ~ to!string(alpha) ~
            ", delta=" ~ to!string(delta) ~
            ", list_mapped_cells=" ~ to!string(list_mapped_cells) ~
            ", reorient_vector_quantities=" ~ to!string(reorient_vector_quantities) ~
            ", Rmatrix=[";
        foreach(i, v; Rmatrix) {
            str ~= to!string(v);
            str ~= (i < Rmatrix.length-1) ? ", " : "]";
        }
        str ~= ")";
        return str;
    }

    // not @nogc
    void set_up_cell_mapping()
    {
        if (cell_mapping_from_file) {
            final switch (blk.grid_type) {
            case Grid_t.unstructured_grid:
                // We set up the ghost-cell reference list to have the same order as
                // the list of faces that were stored in the boundary.
                // We will later confirm that the ghost cells appear in the same order
                // in the mapped_cells file.
                BoundaryCondition bc = blk.bc[which_boundary];
                foreach (i, face; bc.faces) {
                    ghost_cells ~= (bc.outsigns[i] == 1) ? face.right_cell : face.left_cell;
                    size_t[] my_vtx_list; foreach(vtx; face.vtx) { my_vtx_list ~= vtx.id; }
                    string faceTag =  makeFaceTag(my_vtx_list);
                    ghost_cell_index_from_faceTag[faceTag] = i;
                }
                break;
            case Grid_t.structured_grid:
                throw new Error("cell mapping from file is not implemented for structured grids");
            } // end switch grid_type
            //
            // Read the entire mapped_cells file.
            // The single mapped_cell file contains the indices mapped cells
            // for all ghost-cells, for all blocks.
            //
            // They are in sections labelled by the block id.
            // Each boundary face is identified by its "faceTag",
            // which is a string composed of the vertex indices, in ascending order.
            // The order of the ghost-cells is assumed the same as for each
            // grids underlying the FluidBlock.
            //
            // For the shared memory code, we only need the section for the block
            // associated with the current boundary.
            // For the MPI-parallel code, we need the mappings for all blocks,
            // so that we know what requests for data to expect from other blocks.
            //
            size_t nblks = GlobalConfig.nFluidBlocks;
            mapped_cells_list.length = nblks;
            version(mpi_parallel) {
                src_cell_ids.length = nblks;
                ghost_cell_indices.length = nblks;
                foreach (i; 0 .. nblks) {
                    src_cell_ids[i].length = nblks;
                    ghost_cell_indices[i].length = nblks;
                }
            }
            //
            if (!exists(mapped_cells_filename)) {
                string msg = format("mapped_cells file %s does not exist.", mapped_cells_filename);
                throw new FlowSolverException(msg);
            }
            auto f = File(mapped_cells_filename, "r");
            string getHeaderContent(string target)
            {
                // Helper function to proceed through file, line-by-line,
                // looking for a particular header line.
                // Returns the content from the header line and leaves the file
                // at the next line to be read, presumably with expected data.
                while (!f.eof) {
                    auto line = f.readln().strip();
                    if (canFind(line, target)) {
                        auto tokens = line.split("=");
                        return tokens[1].strip();
                    }
                } // end while
                return ""; // didn't find the target
            }
            foreach (dest_blk_id; 0 .. nblks) {
                string txt = getHeaderContent(format("NMappedCells in BLOCK[%d]", dest_blk_id));
                if (!txt.length) {
                    string msg = format("Did not find mapped cells section for destination block id=%d.",
                                        dest_blk_id);
                    throw new FlowSolverException(msg);
                }
                size_t nfaces  = to!size_t(txt);
                foreach(i; 0 .. nfaces) {
                    auto lineContent = f.readln().strip();
                    auto tokens = lineContent.split();
                    string faceTag = tokens[0];
                    size_t src_blk_id = to!size_t(tokens[1]);
                    size_t src_cell_id = to!size_t(tokens[2]);
                    mapped_cells_list[dest_blk_id][faceTag] = BlockAndCellId(src_blk_id, src_cell_id);
                    version(mpi_parallel) {
                        // These lists will be used to direct data when packing and unpacking
                        // the buffers used to send data between the MPI tasks.
                        src_cell_ids[src_blk_id][dest_blk_id] ~= src_cell_id;
                        ghost_cell_indices[src_blk_id][dest_blk_id] ~= i;
                        // If we are presently reading the section for the current block,
                        // we check that the listed faces are in the same order as the
                        // underlying grid.
                        if (blk.id == dest_blk_id) {
                            if (canFind(ghost_cell_index_from_faceTag.keys(), faceTag)) {
                                if (i != ghost_cell_index_from_faceTag[faceTag]) {
                                    throw new Error(format("Oops, ghost-cell indices do not match: %d %d",
                                                           i, ghost_cell_index_from_faceTag[faceTag]));
                                }
                            } else {
                                foreach (ft; ghost_cell_index_from_faceTag.keys()) {
                                    writefln("ghost_cell_index_from_faceTag[\"%s\"] = %d",
                                             ft, ghost_cell_index_from_faceTag[ft]);
                                }
                                throw new Error(format("Oops, cannot find faceTag=\"%s\" for block id=%d", faceTag, blk.id));
                            }
                        }
                    }
                }
            } // end foreach dest_blk_id
            //
            version(mpi_parallel) {
                //
                // No communication needed just now because all MPI tasks have the full mapping,
                // however, we can prepare buffers and the like for communication of the geometry
                // and flowstate data.
                //
                // Incoming messages will carrying data from other block, to be copied into the
                // ghost cells for the current boundary.
                // N.B. We assume that there is only one such boundary per block.
                incoming_ncells_list.length = 0;
                incoming_block_list.length = 0;
                incoming_rank_list.length = 0;
                incoming_geometry_tag_list.length = 0;
                incoming_flowstate_tag_list.length = 0;
                incoming_convective_gradient_tag_list.length = 0;
                foreach (src_blk_id; 0 .. nblks) {
                    size_t nc = src_cell_ids[src_blk_id][blk.id].length;
                    if (nc > 0) {
                        incoming_ncells_list ~= nc;
                        incoming_block_list ~= src_blk_id;
                        incoming_rank_list ~= GlobalConfig.mpi_rank_for_block[src_blk_id];
                        incoming_geometry_tag_list ~= make_mpi_tag(to!int(src_blk_id), 99, 1);
                        incoming_flowstate_tag_list ~= make_mpi_tag(to!int(src_blk_id), 99, 2);
                        incoming_convective_gradient_tag_list ~= make_mpi_tag(to!int(src_blk_id), 99, 3);
                    }
                }
                n_incoming = incoming_block_list.length;
                incoming_geometry_request_list.length = n_incoming;
                incoming_geometry_status_list.length = n_incoming;
                incoming_geometry_buf_list.length = n_incoming;
                incoming_flowstate_request_list.length = n_incoming;
                incoming_flowstate_status_list.length = n_incoming;
                incoming_flowstate_buf_list.length = n_incoming;
                incoming_convective_gradient_request_list.length = n_incoming;
                incoming_convective_gradient_status_list.length = n_incoming;
                incoming_convective_gradient_buf_list.length = n_incoming;
                //
                // Outgoing messages will carry data from source cells in the current block,
                // to be copied into ghost cells in another block.
                outgoing_ncells_list.length = 0;
                outgoing_block_list.length = 0;
                outgoing_rank_list.length = 0;
                outgoing_geometry_tag_list.length = 0;
                outgoing_flowstate_tag_list.length = 0;
                outgoing_convective_gradient_tag_list.length = 0;
                foreach (dest_blk_id; 0 .. nblks) {
                    size_t nc = src_cell_ids[blk.id][dest_blk_id].length;
                    if (nc > 0) {
                        outgoing_ncells_list ~= nc;
                        outgoing_block_list ~= dest_blk_id;
                        outgoing_rank_list ~= GlobalConfig.mpi_rank_for_block[dest_blk_id];
                        outgoing_geometry_tag_list ~= make_mpi_tag(to!int(blk.id), 99, 1);
                        outgoing_flowstate_tag_list ~= make_mpi_tag(to!int(blk.id), 99, 2);
                        outgoing_convective_gradient_tag_list ~= make_mpi_tag(to!int(blk.id), 99, 3);
                    }
                }
                n_outgoing = outgoing_block_list.length;
                outgoing_geometry_buf_list.length = n_outgoing;
                outgoing_flowstate_buf_list.length = n_outgoing;
                outgoing_convective_gradient_buf_list.length = n_outgoing;
                //
                
                //
            } else { // not mpi_parallel
                // For the shared-memory code, get references to the mapped (source) cells
                // that need to be accessed for the current (destination) block.
                final switch (blk.grid_type) {
                case Grid_t.unstructured_grid: 
                    BoundaryCondition bc = blk.bc[which_boundary];
                    foreach (i, face; bc.faces) {
                        size_t[] my_vtx_list; foreach(vtx; face.vtx) { my_vtx_list ~= vtx.id; }
                        string faceTag =  makeFaceTag(my_vtx_list);
                        auto src_blk_id = mapped_cells_list[blk.id][faceTag].blkId;
                        auto src_cell_id = mapped_cells_list[blk.id][faceTag].cellId;
                        if (!find(GlobalConfig.localBlockIds, src_blk_id).empty) {
                            mapped_cells ~= globalFluidBlocks[src_blk_id].cells[src_cell_id];
                        } else {
                            auto msg = format("block id %d is not in localFluidBlocks", src_blk_id);
                            throw new FlowSolverException(msg);
                        }
                    } // end foreach face
                    break;
                case Grid_t.structured_grid:
                    throw new Error("cell mapping from file not implemented for structured grids");
                } // end switch grid_type
            } // end not mpi_parallel
        } else { // !cell_mapping_from_file
            set_up_cell_mapping_via_search();
        } // end if !cell_mapping_from_file
    } // end set_up_cell_mapping()

    // not @nogc
    void set_up_cell_mapping_via_search()
    {
        // For the situation when we haven't been given a file to specify
        // where to find our mapped cells.
        //
        // Needs to be called after the cell geometries have been computed,
        // because the search sifts through the cells in blocks
        // that happen to be in the local process.
        //
        // The search does not extend to cells in blocks in other MPI tasks.
        // If a search for the enclosing cell fails in the MPI context,
        // we will throw an exception rather than continuing the search
        // for the nearest cell.
        //
        final switch (blk.grid_type) {
        case Grid_t.unstructured_grid: 
            BoundaryCondition bc = blk.bc[which_boundary];
            foreach (i, face; bc.faces) {
                ghost_cells ~= (bc.outsigns[i] == 1) ? face.right_cell : face.left_cell;
            }
            break;
        case Grid_t.structured_grid:
            size_t i, j, k;
            auto blk = cast(SFluidBlock) this.blk;
            assert(blk !is null, "Oops, this should be an SFluidBlock object.");
            final switch (which_boundary) {
            case Face.north:
                j = blk.jmax;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (i = blk.imin; i <= blk.imax; ++i) {
                        ghost_cells ~= blk.get_cell(i,j+1,k);
                        ghost_cells ~= blk.get_cell(i,j+2,k);
                        version(nghost3) { ghost_cells ~= blk.get_cell(i,j+3,k); }
                    } // end i loop
                } // for k
                break;
            case Face.east:
                i = blk.imax;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        ghost_cells ~= blk.get_cell(i+1,j,k);
                        ghost_cells ~= blk.get_cell(i+2,j,k);
                        version(nghost3) { ghost_cells ~= blk.get_cell(i+3,j,k); }
                    } // end j loop
                } // for k
                break;
            case Face.south:
                j = blk.jmin;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (i = blk.imin; i <= blk.imax; ++i) {
                        ghost_cells ~= blk.get_cell(i,j-1,k);
                        ghost_cells ~= blk.get_cell(i,j-2,k);
                        version(nghost3) { ghost_cells ~= blk.get_cell(i,j-3,k); }
                    } // end i loop
                } // for k
                break;
            case Face.west:
                i = blk.imin;
                for (k = blk.kmin; k <= blk.kmax; ++k) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        ghost_cells ~= blk.get_cell(i-1,j,k);
                        ghost_cells ~= blk.get_cell(i-2,j,k);
                        version(nghost3) { ghost_cells ~= blk.get_cell(i-3,j,k); }
                    } // end j loop
                } // for k
                break;
            case Face.top:
                k = blk.kmax;
                for (i = blk.imin; i <= blk.imax; ++i) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        ghost_cells ~= blk.get_cell(i,j,k+1);
                        ghost_cells ~= blk.get_cell(i,j,k+2);
                        version(nghost3) { ghost_cells ~= blk.get_cell(i,j,k+3); }
                    } // end j loop
                } // for i
                break;
            case Face.bottom:
                k = blk.kmin;
                for (i = blk.imin; i <= blk.imax; ++i) {
                    for (j = blk.jmin; j <= blk.jmax; ++j) {
                        ghost_cells ~= blk.get_cell(i,j,k-1);
                        ghost_cells ~= blk.get_cell(i,j,k-2);
                        version(nghost3) { ghost_cells ~= blk.get_cell(i,j,k-3); }
                    } // end j loop
                } // for i
                break;
            } // end switch
        } // end switch blk.grid_type
        // Now that we have a collection of the local ghost cells,
        // locate the corresponding active cell so that we can later
        // copy that cell's flow state.
        if (list_mapped_cells) {
            writefln("Mapped cells for block[%d] boundary[%d]:", blk.id, which_boundary);
        }
        foreach (mygc; ghost_cells) {
            Vector3 ghostpos = mygc.pos[0];
            Vector3 mypos = ghostpos;
            if (transform_position) {
                Vector3 del1 = ghostpos - c0;
                Vector3 c1 = c0 + dot(n, del1) * n;
                Vector3 t1 = ghostpos - c1;
                t1.normalize();
                Vector3 t2 = cross(n, t1);
                mypos = c1 + cos(alpha) * t1 + sin(alpha) * t2;
                mypos += delta;
            }
            // Because we need to access all of the gas blocks in the following search,
            // we have to run this set_up_cell_mapping function from a serial loop.
            // In parallel code, threads other than the main thread get uninitialized
            // versions of the localFluidBlocks array.
            //
            // First, attempt to find the enclosing cell at the specified position.
            bool found = false;
            foreach (ib, blk; localFluidBlocks) {
                found = false;
                size_t indx = 0;
                blk.find_enclosing_cell(mypos, indx, found);
                if (found) {
                    mapped_cells ~= blk.cells[indx];
                    break;
                }
            }
            version (mpi_parallel) {
                if (!found && GlobalConfig.in_mpi_context) {
                    string msg = "MappedCellCopy: search for mapped cell did not find an enclosing cell\n";
                    msg ~= "  at position " ~ to!string(mypos) ~ "\n";
                    msg ~= "  This may be because the appropriate cell is not in localFluidBlocks array.\n";
                    throw new FlowSolverException(msg);
                }
            }
            if (!found) {
                // Fall back to nearest cell search.
                FVCell closest_cell = localFluidBlocks[0].cells[0];
                Vector3 cellpos = closest_cell.pos[0];
                double min_distance = distance_between(cellpos, mypos);
                foreach (blk; localFluidBlocks) {
                    foreach (cell; blk.cells) {
                        double distance = distance_between(cell.pos[0], mypos);
                        if (distance < min_distance) {
                            closest_cell = cell;
                            min_distance = distance;
                        }
                    }
                }
                mapped_cells ~= closest_cell;
            }
        } // end foreach mygc
	// TODO: temporarily removing the GC calls below, they are (oddly) computationally expensive - KD 26/03/2019. 
        //GC.collect();
        //GC.minimize();
    } // end set_up_cell_mapping_via_search()

    @nogc
    ref FVCell get_mapped_cell(size_t i)
    {
        if (i < mapped_cells.length) {
            return mapped_cells[i];
        } else {
            throw new FlowSolverException("Reference to requested mapped-cell is not available.");
        }
    }

    // not @nogc
    void exchange_geometry_phase0()
    {
        version(mpi_parallel) {
            // Prepare to exchange geometry data for the boundary cells.
            foreach (i; 0 .. n_incoming) {
                // To match .copy_values_from(mapped_cells[i], CopyDataOption.grid) as defined in fvcell.d.
                size_t ne = incoming_ncells_list[i] * (blk.myConfig.n_grid_time_levels * 5 + 4);
                if (incoming_geometry_buf_list[i].length < ne) { incoming_geometry_buf_list[i].length = ne; }
                // Post non-blocking receive for geometry data that we expect to receive later
                // from the src_blk MPI process.
                MPI_Irecv(incoming_geometry_buf_list[i].ptr, to!int(ne), MPI_DOUBLE, incoming_rank_list[i],
                          incoming_geometry_tag_list[i], MPI_COMM_WORLD, &incoming_geometry_request_list[i]);
            }
        } else { // not mpi_parallel
            // For a single process, nothing to be done because
            // we know that we can just access the data directly
            // in the final phase.
        }
    } // end exchange_geometry_phase0()

    // not @nogc
    void exchange_geometry_phase1()
    {
        version(mpi_parallel) {
            foreach (i; 0 .. n_outgoing) {
                // Blocking send of this block's geometry data
                // to the corresponding non-blocking receive that was posted
                // at in src_blk MPI process.
                size_t ne = outgoing_ncells_list[i] * (blk.myConfig.n_grid_time_levels * 5 + 4);
                if (outgoing_geometry_buf_list[i].length < ne) { outgoing_geometry_buf_list[i].length = ne; }
                auto buf = outgoing_geometry_buf_list[i];
                size_t ii = 0;
                foreach (cid; src_cell_ids[blk.id][outgoing_block_list[i]]) {
                    auto c = blk.cells[cid];
                    foreach (j; 0 .. blk.myConfig.n_grid_time_levels) {
                        buf[ii++] = c.pos[j].x;
                        buf[ii++] = c.pos[j].y;
                        buf[ii++] = c.pos[j].z;
                        buf[ii++] = c.volume[j];
                        buf[ii++] = c.areaxy[j];
                    }
                    buf[ii++] = c.iLength;
                    buf[ii++] = c.jLength;
                    buf[ii++] = c.kLength;
                    buf[ii++] = c.L_min;
                }
                version(mpi_timeouts) {
                    MPI_Request send_request;
                    MPI_Isend(buf.ptr, to!int(ne), MPI_DOUBLE, outgoing_rank_list[i],
                              outgoing_geometry_tag_list[i], MPI_COMM_WORLD, &send_request);
                    MPI_Status send_status;
                    MPI_Wait_a_while(&send_request, &send_status);
                } else {
                    MPI_Send(buf.ptr, to!int(ne), MPI_DOUBLE, outgoing_rank_list[i],
                             outgoing_geometry_tag_list[i], MPI_COMM_WORLD);
                }
            }
        } else { // not mpi_parallel
            // For a single process, nothing to be done because
            // we know that we can just access the data directly
            // in the final phase.
        }
    } // end exchange_geometry_phase1()

    // not @nogc
    void exchange_geometry_phase2()
    {
        version(mpi_parallel) {
            foreach (i; 0 .. n_incoming) {
                // Wait for non-blocking receive to complete.
                // Once complete, copy the data back into the local context.
                version(mpi_timeouts) {
                    MPI_Wait_a_while(&incoming_geometry_request_list[i], &incoming_geometry_status_list[i]);
                } else {
                    MPI_Wait(&incoming_geometry_request_list[i], &incoming_geometry_status_list[i]);
                }
                auto buf = incoming_geometry_buf_list[i];
                size_t ii = 0;
                foreach (gi; ghost_cell_indices[incoming_block_list[i]][blk.id]) {
                    auto c = ghost_cells[gi];
                    foreach (j; 0 .. blk.myConfig.n_grid_time_levels) {
                        c.pos[j].refx = buf[ii++];
                        c.pos[j].refy = buf[ii++];
                        c.pos[j].refz = buf[ii++];
                        c.volume[j] = buf[ii++];
                        c.areaxy[j] = buf[ii++];
                    }
                    c.iLength = buf[ii++];
                    c.jLength = buf[ii++];
                    c.kLength = buf[ii++];
                    c.L_min = buf[ii++];
                }
            }
        } else { // not mpi_parallel
            // For a single process, just access the data directly.
            foreach (i, mygc; ghost_cells) {
                mygc.copy_values_from(mapped_cells[i], CopyDataOption.grid);
            }
        }
    } // end exchange_geometry_phase2()

    // not @nogc
    void exchange_flowstate_phase0(double t, int gtl, int ftl)
    {
        version(mpi_parallel) {
            // Prepare to exchange geometry data for the boundary cells.
            size_t nspecies = blk.myConfig.n_species;
            size_t nmodes = blk.myConfig.n_modes;
            foreach (i; 0 .. n_incoming) {
                // Exchange FlowState data for the boundary cells.
                // To match the function over in flowstate.d
                // void copy_values_from(in FlowState other)
                // and over in gas_state.d
                // @nogc void copy_values_from(ref const(GasState) other) 
                size_t ne = incoming_ncells_list[i] * (nmodes*3 + nspecies + 23);
                if (incoming_flowstate_buf_list[i].length < ne) { incoming_flowstate_buf_list[i].length = ne; }
                // Post non-blocking receive for flowstate data that we expect to receive later
                // from the src_blk MPI process.
                MPI_Irecv(incoming_flowstate_buf_list[i].ptr, to!int(ne), MPI_DOUBLE, incoming_rank_list[i],
                          incoming_flowstate_tag_list[i], MPI_COMM_WORLD, &incoming_flowstate_request_list[i]);
            }
        } else { // not mpi_parallel
            // For a single process, nothing to be done because
            // we know that we can just access the data directly
            // in the final phase.
        }
    } // end exchange_flowstate_phase0()

    // not @nogc
    void exchange_flowstate_phase1(double t, int gtl, int ftl)
    {
        version(mpi_parallel) {
            size_t nspecies = blk.myConfig.n_species;
            size_t nmodes = blk.myConfig.n_modes;
            foreach (i; 0 .. n_outgoing) {
                // Blocking send of this block's flow data
                // to the corresponding non-blocking receive that was posted
                // at in src_blk MPI process.
                size_t nitems = 16;
                version(MHD) { nitems += 5; }
                version(komega) { nitems += 2; }
                size_t ne = outgoing_ncells_list[i] * (nmodes*3 + nspecies + nitems);
                if (outgoing_flowstate_buf_list[i].length < ne) { outgoing_flowstate_buf_list[i].length = ne; }
                auto buf = outgoing_flowstate_buf_list[i];
                size_t ii = 0;
                foreach (cid; src_cell_ids[blk.id][outgoing_block_list[i]]) {
                    auto c = blk.cells[cid];
                    FlowState fs = c.fs;
                    GasState gs = fs.gas;
                    buf[ii++] = gs.rho;
                    buf[ii++] = gs.p;
                    buf[ii++] = gs.T;
                    buf[ii++] = gs.u;
                    buf[ii++] = gs.p_e;
                    buf[ii++] = gs.a;
                    version(multi_T_gas) {
                        foreach (j; 0 .. nmodes) { buf[ii++] = gs.u_modes[j]; }
                        foreach (j; 0 .. nmodes) { buf[ii++] = gs.T_modes[j]; }
                    }
                    buf[ii++] = gs.mu;
                    buf[ii++] = gs.k;
                    version(multi_T_gas) {
                        foreach (j; 0 .. nmodes) { buf[ii++] = gs.k_modes[j]; }
                    }
                    buf[ii++] = gs.sigma;
                    version(multi_species_gas) {
                        foreach (j; 0 .. nspecies) { buf[ii++] = gs.massf[j]; }
                    }
                    buf[ii++] = gs.quality;
                    buf[ii++] = fs.vel.x;
                    buf[ii++] = fs.vel.y;
                    buf[ii++] = fs.vel.z;
                    version(MHD) {
                        buf[ii++] = fs.B.x;
                        buf[ii++] = fs.B.y;
                        buf[ii++] = fs.B.z;
                        buf[ii++] = fs.psi;
                        buf[ii++] = fs.divB;
                    }
                    version(komega) {
                        buf[ii++] = fs.tke;
                        buf[ii++] = fs.omega;
                    }
                    buf[ii++] = fs.mu_t;
                    buf[ii++] = fs.k_t;
                    buf[ii++] = to!double(fs.S);
                }
                version(mpi_timeouts) {
                    MPI_Request send_request;
                    MPI_Isend(buf.ptr, to!int(ne), MPI_DOUBLE, outgoing_rank_list[i],
                              outgoing_flowstate_tag_list[i], MPI_COMM_WORLD, &send_request);
                    MPI_Status send_status;
                    MPI_Wait_a_while(&send_request, &send_status);
                } else {
                    MPI_Send(buf.ptr, to!int(ne), MPI_DOUBLE, outgoing_rank_list[i],
                             outgoing_flowstate_tag_list[i], MPI_COMM_WORLD);
                }
            }
        } else { // not mpi_parallel
            // For a single process, nothing to be done because
            // we know that we can just access the data directly
            // in the final phase.
        }
    } // end exchange_flowstate_phase1()

    // not @nogc
    void exchange_flowstate_phase2(double t, int gtl, int ftl)
    {
        version(mpi_parallel) {
            size_t nspecies = blk.myConfig.n_species;
            size_t nmodes = blk.myConfig.n_modes;
            foreach (i; 0 .. n_incoming) {
                // Wait for non-blocking receive to complete.
                // Once complete, copy the data back into the local context.
                version(mpi_timeouts) {
                    MPI_Wait_a_while(&incoming_flowstate_request_list[i], &incoming_flowstate_status_list[i]);
                } else {
                    MPI_Wait(&incoming_flowstate_request_list[i], &incoming_flowstate_status_list[i]);
                }
                auto buf = incoming_flowstate_buf_list[i];
                size_t ii = 0;
                foreach (gi; ghost_cell_indices[incoming_block_list[i]][blk.id]) {
                    auto c = ghost_cells[gi];
                    FlowState fs = c.fs;
                    GasState gs = fs.gas;
                    gs.rho = buf[ii++];
                    gs.p = buf[ii++];
                    gs.T = buf[ii++];
                    gs.u = buf[ii++];
                    gs.p_e = buf[ii++];
                    gs.a = buf[ii++];
                    version(multi_T_gas) {
                        foreach (j; 0 .. nmodes) { gs.u_modes[j] = buf[ii++]; }
                        foreach (j; 0 .. nmodes) { gs.T_modes[j] = buf[ii++]; }
                    }
                    gs.mu = buf[ii++];
                    gs.k = buf[ii++];
                    version(multi_T_gas) {
                        foreach (j; 0 .. nmodes) { gs.k_modes[j] = buf[ii++]; }
                    }
                    gs.sigma = buf[ii++];
                    version(multi_species_gas) {
                        foreach (j; 0 .. nspecies) { gs.massf[j] = buf[ii++]; }
                    }
                    gs.quality = buf[ii++];
                    fs.vel.refx = buf[ii++];
                    fs.vel.refy = buf[ii++];
                    fs.vel.refz = buf[ii++];
                    version(MHD) {
                        fs.B.refx = buf[ii++];
                        fs.B.refy = buf[ii++];
                        fs.B.refz = buf[ii++];
                        fs.psi = buf[ii++];
                        fs.divB = buf[ii++];
                    }
                    version(komega) {
                        fs.tke = buf[ii++];
                        fs.omega = buf[ii++];
                    }
                    fs.mu_t = buf[ii++];
                    fs.k_t = buf[ii++];
                    fs.S = to!int(buf[ii++]);
                }
            }
        } else { // not mpi_parallel
            // For a single process, just access the data directly.
            foreach (i, mygc; ghost_cells) {
                mygc.fs.copy_values_from(mapped_cells[i].fs);
                mygc.is_interior_to_domain = mapped_cells[i].is_interior_to_domain;
            }
        }
    } // end exchange_flowstate_phase2()

    // not @nogc
    void exchange_convective_gradient_phase0(double t, int gtl, int ftl)
    {
        version(mpi_parallel) {
            // Prepare to exchange geometry data for the boundary cells.
            size_t nspecies = blk.myConfig.n_species;
            size_t nmodes = blk.myConfig.n_modes;
            foreach (i; 0 .. n_incoming) {
                // Exchange cell-centered convective gradients for the boundary cells.
                // the size of the buffer should match up with that of lsqinterp.d
                size_t nitems = 42;
                version(MHD) { nitems += 24; }
                version(komega) { nitems += 12; }
                size_t ne = incoming_ncells_list[i] * (nmodes*12 + nspecies*6 + nitems);
                if (incoming_convective_gradient_buf_list[i].length < ne) { incoming_convective_gradient_buf_list[i].length = ne; }
                // Post non-blocking receive for flowstate data that we expect to receive later
                // from the src_blk MPI process.
                MPI_Irecv(incoming_convective_gradient_buf_list[i].ptr, to!int(ne), MPI_DOUBLE, incoming_rank_list[i],
                          incoming_convective_gradient_tag_list[i], MPI_COMM_WORLD, &incoming_convective_gradient_request_list[i]);
            }
        } else { // not mpi_parallel
            // For a single process, nothing to be done because
            // we know that we can just access the data directly
            // in the final phase.
        }
    } // end exchange_convective_gradient_phase0()

    // not @nogc
    void exchange_convective_gradient_phase1(double t, int gtl, int ftl)
    {
        version(mpi_parallel) {
            size_t nspecies = blk.myConfig.n_species;
            size_t nmodes = blk.myConfig.n_modes;
            foreach (i; 0 .. n_outgoing) {
                // Blocking send of this block's flow data
                // to the corresponding non-blocking receive that was posted
                // at in src_blk MPI process.
                size_t nitems = 42;
                version(MHD) { nitems += 24; }
                version(komega) { nitems += 12; }
                size_t ne = outgoing_ncells_list[i] * (nmodes*12 + nspecies*6 + nitems);
                if (outgoing_convective_gradient_buf_list[i].length < ne) { outgoing_convective_gradient_buf_list[i].length = ne; }
                auto buf = outgoing_convective_gradient_buf_list[i];
                size_t ii = 0;
                foreach (cid; src_cell_ids[blk.id][outgoing_block_list[i]]) {
                    auto c = blk.cells[cid].gradients;
                    // velocity
                    buf[ii++] = c.velx[0];
                    buf[ii++] = c.velx[1];
                    buf[ii++] = c.velx[2];
                    buf[ii++] = c.velxPhi;
                    buf[ii++] = c.velxMin;
                    buf[ii++] = c.velxMax;
                    buf[ii++] = c.vely[0];
                    buf[ii++] = c.vely[1];
                    buf[ii++] = c.vely[2];
                    buf[ii++] = c.velyPhi;
                    buf[ii++] = c.velyMin;
                    buf[ii++] = c.velyMax;
                    buf[ii++] = c.velz[0];
                    buf[ii++] = c.velz[1];
                    buf[ii++] = c.velz[2];
                    buf[ii++] = c.velzPhi;
                    buf[ii++] = c.velzMin;
                    buf[ii++] = c.velzMax;
                    // rho, p, T, u
                    buf[ii++] = c.rho[0];
                    buf[ii++] = c.rho[1];
                    buf[ii++] = c.rho[2];
                    buf[ii++] = c.rhoPhi;
                    buf[ii++] = c.rhoMin;
                    buf[ii++] = c.rhoMax;
                    buf[ii++] = c.p[0];
                    buf[ii++] = c.p[1];
                    buf[ii++] = c.p[2];
                    buf[ii++] = c.pPhi;
                    buf[ii++] = c.pMin;
                    buf[ii++] = c.pMax;
                    buf[ii++] = c.T[0];
                    buf[ii++] = c.T[1];
                    buf[ii++] = c.T[2];
                    buf[ii++] = c.TPhi;
                    buf[ii++] = c.TMin;
                    buf[ii++] = c.TMax;
                    buf[ii++] = c.u[0];
                    buf[ii++] = c.u[1];
                    buf[ii++] = c.u[2];
                    buf[ii++] = c.uPhi;
                    buf[ii++] = c.uMin;
                    buf[ii++] = c.uMax;
                    // tke, omega
                    version(komega) {
                        buf[ii++] = c.tke[0];
                        buf[ii++] = c.tke[1];
                        buf[ii++] = c.tke[2];
                        buf[ii++] = c.tkePhi;
                        buf[ii++] = c.tkeMin;
                        buf[ii++] = c.tkeMax;
                        buf[ii++] = c.omega[0];
                        buf[ii++] = c.omega[1];
                        buf[ii++] = c.omega[2];
                        buf[ii++] = c.omegaPhi;
                        buf[ii++] = c.omegaMin;
                        buf[ii++] = c.omegaMax;
                    }
                    // MHD
                    version(MHD) {
                        buf[ii++] = c.Bx[0];
                        buf[ii++] = c.Bx[1];
                        buf[ii++] = c.Bx[2];
                        buf[ii++] = c.BxPhi;
                        buf[ii++] = c.BxMin;
                        buf[ii++] = c.BxMax;
                        buf[ii++] = c.By[0];
                        buf[ii++] = c.By[1];
                        buf[ii++] = c.By[2];
                        buf[ii++] = c.ByPhi;
                        buf[ii++] = c.ByMin;
                        buf[ii++] = c.ByMax;
                        buf[ii++] = c.Bz[0];
                        buf[ii++] = c.Bz[1];
                        buf[ii++] = c.Bz[2];
                        buf[ii++] = c.BzPhi;
                        buf[ii++] = c.BzMin;
                        buf[ii++] = c.BzMax;
                        buf[ii++] = c.psi[0];
                        buf[ii++] = c.psi[1];
                        buf[ii++] = c.psi[2];
                        buf[ii++] = c.psiPhi;
                        buf[ii++] = c.psiMin;
                        buf[ii++] = c.psiMax;
                    }
                    // multi-species
                    version(multi_species_gas) {
                        foreach (j; 0 .. nspecies) {
                            buf[ii++] = c.massf[j][0];
                            buf[ii++] = c.massf[j][1];
                            buf[ii++] = c.massf[j][2];
                            buf[ii++] = c.massfPhi[j];
                            buf[ii++] = c.massfMin[j];
                            buf[ii++] = c.massfMax[j];
                        }
                    }
                    // multi-T
                    version(multi_T_gas) {
                        foreach (j; 0 .. nmodes) {
                            buf[ii++] = c.T_modes[j][0];
                            buf[ii++] = c.T_modes[j][1];
                            buf[ii++] = c.T_modes[j][2];
                            buf[ii++] = c.T_modesPhi[j];
                            buf[ii++] = c.T_modesMin[j];
                            buf[ii++] = c.T_modesMax[j];
                        }
                        foreach (j; 0 .. nmodes) {
                            buf[ii++] = c.u_modes[j][0];
                            buf[ii++] = c.u_modes[j][1];
                            buf[ii++] = c.u_modes[j][2];
                            buf[ii++] = c.u_modesPhi[j];
                            buf[ii++] = c.u_modesMin[j];
                            buf[ii++] = c.u_modesMax[j];
                        }
                    }
                }
                version(mpi_timeouts) {
                    MPI_Request send_request;
                    MPI_Isend(buf.ptr, to!int(ne), MPI_DOUBLE, outgoing_rank_list[i],
                              outgoing_convective_gradient_tag_list[i], MPI_COMM_WORLD, &send_request);
                    MPI_Status send_status;
                    MPI_Wait_a_while(&send_request, &send_status);
                } else {
                    MPI_Send(buf.ptr, to!int(ne), MPI_DOUBLE, outgoing_rank_list[i],
                             outgoing_convective_gradient_tag_list[i], MPI_COMM_WORLD);
                }
            }
        } else { // not mpi_parallel
            // For a single process, nothing to be done because
            // we know that we can just access the data directly
            // in the final phase.
        }
    } // end exchange_convective_gradient_phase1()

    // not @nogc
    void exchange_convective_gradient_phase2(double t, int gtl, int ftl)
    {
        version(mpi_parallel) {
            size_t nspecies = blk.myConfig.n_species;
            size_t nmodes = blk.myConfig.n_modes;
            foreach (i; 0 .. n_incoming) {
                // Wait for non-blocking receive to complete.
                // Once complete, copy the data back into the local context.
                version(mpi_timeouts) {
                    MPI_Wait_a_while(&incoming_convective_gradient_request_list[i], &incoming_convective_gradient_status_list[i]);
                } else {
                    MPI_Wait(&incoming_convective_gradient_request_list[i], &incoming_convective_gradient_status_list[i]);
                }
                auto buf = incoming_convective_gradient_buf_list[i];
                size_t ii = 0;
                foreach (gi; ghost_cell_indices[incoming_block_list[i]][blk.id]) {
                    auto c = ghost_cells[gi].gradients;
                    // velocity
                    c.velx[0] = buf[ii++];
                    c.velx[1] = buf[ii++];
                    c.velx[2] = buf[ii++];
                    c.velxPhi = buf[ii++];
                    c.velxMin = buf[ii++];
                    c.velxMax = buf[ii++];
                    c.vely[0] = buf[ii++];
                    c.vely[1] = buf[ii++];
                    c.vely[2] = buf[ii++];
                    c.velyPhi = buf[ii++];
                    c.velyMin = buf[ii++];
                    c.velyMax = buf[ii++];
                    c.velz[0] = buf[ii++];
                    c.velz[1] = buf[ii++];
                    c.velz[2] = buf[ii++];
                    c.velzPhi = buf[ii++];
                    c.velzMin = buf[ii++];
                    c.velzMax = buf[ii++];
                    // rho, p, T, u
                    c.rho[0] = buf[ii++];
                    c.rho[1] = buf[ii++];
                    c.rho[2] = buf[ii++];
                    c.rhoPhi = buf[ii++];
                    c.rhoMin = buf[ii++];
                    c.rhoMax = buf[ii++];
                    c.p[0] = buf[ii++];
                    c.p[1] = buf[ii++];
                    c.p[2] = buf[ii++];
                    c.pPhi = buf[ii++];
                    c.pMin = buf[ii++];
                    c.pMax = buf[ii++];
                    c.T[0] = buf[ii++];
                    c.T[1] = buf[ii++];
                    c.T[2] = buf[ii++];
                    c.TPhi = buf[ii++];
                    c.TMin = buf[ii++];
                    c.TMax = buf[ii++];
                    c.u[0] = buf[ii++];
                    c.u[1] = buf[ii++];
                    c.u[2] = buf[ii++];
                    c.uPhi = buf[ii++];
                    c.uMin = buf[ii++];
                    c.uMax = buf[ii++];
                    // tke, omega
                    version(komega) {
                        c.tke[0] = buf[ii++];
                        c.tke[1] = buf[ii++];
                        c.tke[2] = buf[ii++];
                        c.tkePhi = buf[ii++];
                        c.tkeMin = buf[ii++];
                        c.tkeMax = buf[ii++];
                        c.omega[0] = buf[ii++];
                        c.omega[1] = buf[ii++];
                        c.omega[2] = buf[ii++];
                        c.omegaPhi = buf[ii++];
                        c.omegaMin = buf[ii++];
                        c.omegaMax = buf[ii++];
                    }
                    // MHD
                    version(MHD) {
                        c.Bx[0] = buf[ii++];
                        c.Bx[1] = buf[ii++];
                        c.Bx[2] = buf[ii++];
                        c.BxPhi = buf[ii++];
                        c.BxMin = buf[ii++];
                        c.BxMax = buf[ii++];
                        c.By[0] = buf[ii++];
                        c.By[1] = buf[ii++];
                        c.By[2] = buf[ii++];
                        c.ByPhi = buf[ii++];
                        c.ByMin = buf[ii++];
                        c.ByMax = buf[ii++];
                        c.Bz[0] = buf[ii++];
                        c.Bz[1] = buf[ii++];
                        c.Bz[2] = buf[ii++];
                        c.BzPhi = buf[ii++];
                        c.BzMin = buf[ii++];
                        c.BzMax = buf[ii++];
                        c.psi[0] = buf[ii++];
                        c.psi[1] = buf[ii++];
                        c.psi[2] = buf[ii++];
                        c.psiPhi = buf[ii++];
                        c.psiMin = buf[ii++];
                        c.psiMax = buf[ii++];
                    }
                    // multi-species
                    version(multi_species_gas) {
                        foreach (j; 0 .. nspecies) {
                            c.massf[j][0] = buf[ii++];
                            c.massf[j][1] = buf[ii++];
                            c.massf[j][2] = buf[ii++];
                            c.massfPhi[j] = buf[ii++];
                            c.massfMin[j] = buf[ii++];
                            c.massfMax[j] = buf[ii++];
                        }
                    }
                    // multi-T
                    version(multi_T_gas) {
                        foreach (j; 0 .. nmodes) {
                            c.T_modes[j][0] = buf[ii++];
                            c.T_modes[j][1] = buf[ii++];
                            c.T_modes[j][2] = buf[ii++];
                            c.T_modesPhi[j] = buf[ii++];
                            c.T_modesMin[j] = buf[ii++];
                            c.T_modesMax[j] = buf[ii++];
                        }
                        foreach (j; 0 .. nmodes) {
                            c.u_modes[j][0] = buf[ii++];
                            c.u_modes[j][1] = buf[ii++];
                            c.u_modes[j][2] = buf[ii++];
                            c.u_modesPhi[j] = buf[ii++];
                            c.u_modesMin[j] = buf[ii++];
                            c.u_modesMax[j] = buf[ii++];
                        }
                    }
                }
            }
        } else { // not mpi_parallel
            // For a single process, just access the data directly.
            foreach (i, mygc; ghost_cells) {
                mygc.gradients.copy_values_from(mapped_cells[i].gradients);
            }
        }
    } // end exchange_convective_gradient_phase2()

    override void apply_for_interface_unstructured_grid(double t, int gtl, int ftl, FVInterface f)
    {
	assert(0, "apply_for_interface_unstructured_grid not implemented for this BC.");
    }

    @nogc
    override void apply_unstructured_grid(double t, int gtl, int ftl)
    {
        // We presume that all of the exchange of data happened earlier,
        // and that the ghost cells have been filled with flow state data
        // from their respective source cells.
        foreach (i, mygc; ghost_cells) {
            if (reorient_vector_quantities) {
                mygc.fs.reorient_vector_quantities(Rmatrix);
            }
            // [TODO] PJ 2018-01-14 If unstructured blocks ever get used in
            // the block-marching process, we will need a call to encode_conserved
            // at this point.  See the GhostCellFullFaceCopy class.
        }
    } // end apply_unstructured_grid()

    @nogc
    override void apply_structured_grid(double t, int gtl, int ftl)
    {
        foreach (i, mygc; ghost_cells) {
            if (reorient_vector_quantities) {
                mygc.fs.reorient_vector_quantities(Rmatrix);
            }
        }
    } // end apply_unstructured_grid()
} // end class GhostCellMappedCellCopy
