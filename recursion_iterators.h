////////////////////////////////////////////////////////////////////////////////
//
// Filename:	recursion_iterators.v
//
// Project:	pipeline recursion iterators 
//
// Purpose:	functions used for building pipeline data structures.
//
// Creator:	Ronald Rainwater
// Data: 2024-6-18
////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2024, Ronald Rainwater
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program. If not, see <http://www.gnu.org/licenses/> for a copy.
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////
// Tail Recursion Iteration Functions         //
// f_TailRecursionGetVectorSize           //
// f_TailRecursionGetLastUnitWidth       //
// f_TailRecursionGetUnitWidthForLatency //
// f_TailRecursionGetUnitInputAddress    //
//                                            
// Intended to be used to generate a magnitude comparator result for a staged ripple carry adder 
// By using a overlapping slope structure (name not known), the comparators latency can be controlled
// in order to produce a valid output, 1 clock after the carry chain has completely propagated 
//  LUT width 2                                 LUT width 3                                 LUT width 4
//  base #  0___1   2   3   4   5   6   7   8   9   0___1___2   3   4   5   6   7   8   9   0___1___2___3   4   5   6   7   8   9
//             10___|   |   |   |   |   |   |   |          10___|___|   |   |   |   |   |              10___|___|___|   |   |   |
//                 11___|   |   |   |   |   |   |                  11___|___|   |   |   |                          11___|___|___|
//                     12___|   |   |   |   |   |                          12___|___|   |                                       trigger
//                         13___|   |   |   |   |                                  13___|
//                             14___|   |   |   |                                       trigger
//                                 15___|   |   |
//                                     16___|   |
//                                         17___|
//                                              trigger
// Define a few 'tail recursion iterators' to help build the structure seen above

//  f_TailRecursionGetVectorSize - Returns the number of UNITs needed to build structure
//  base            - Total number of input bits to compare
//  lut_width       - Maximum width of the UNITs input used.
//  current_count   - Set to 0zero when calling this function, used internal, exposed for recursion property's
//
// First Call f_TailRecursionGetVectorSize(CHUNK_COUNT, LUT_WIDTH, 0 );
function automatic integer f_TailRecursionGetVectorSize;
    input integer base, lut_width;         
    f_TailRecursionGetVectorSize=(base > 1 )
        ? iterator_TailRecursionGetVectorSize(base, lut_width, 0)
        : 0;
endfunction
function automatic integer iterator_TailRecursionGetVectorSize;
    input integer base, lut_width, current_count;         
    iterator_TailRecursionGetVectorSize=
        base==0
            ?current_count
            :iterator_TailRecursionGetVectorSize(
                base-(base>=lut_width
                    ?(current_count==0
                        ?lut_width
                        :lut_width-1)
                    :base)
                ,lut_width
                ,current_count+1);
endfunction
    // initial begin:test_TailRecursionGetVectorSize integer idx;$display("f_TailRecursionGetVectorSize()");for(idx=2;idx<=10;idx=idx+1)begin $display("\t\t\t:10 lut_width:%d cmp_width:%d",idx,f_TailRecursionGetVectorSize(10,idx));end end

// f_TailRecursionGetLastUnitWidth - Returns the total number of inputs for the last UNIT of the comparator structure
//  base        - Total number of input bits to compare
//  lut_width   - Maximum width of LUT used.
//  rt          - Set to 0zero when calling this function, used internal, exposed for recursion property's
//
// First Call iterator_TailRecursionGetLastUnitWidth(CHUNK_COUNT, LUT_WIDTH, 0, 0);
function automatic integer f_TailRecursionGetLastUnitWidth;
    input integer base, lut_width;
    f_TailRecursionGetLastUnitWidth=iterator_TailRecursionGetLastUnitWidth(base, lut_width, 0, 0);
endfunction
function automatic integer iterator_TailRecursionGetLastUnitWidth;
    input integer base, lut_width, rt, results;
    iterator_TailRecursionGetLastUnitWidth=
        base==0
            ?results
            :iterator_TailRecursionGetLastUnitWidth(
                base-(base>=lut_width
                    ?(rt==0
                        ?lut_width
                        :lut_width-1)
                    :base),
                lut_width,
                rt+1,
                (base>=lut_width
                    ?lut_width
                    :base+1));
endfunction
    //initial begin:test_TailRecursionGetLastUnitWidth integer idx; for(idx=2;idx<10;idx=idx+1)$display("f_TailRecursionGetLastUnitWidth(.base(10).lut_width(%d)) last_lut_width%d",idx,f_TailRecursionGetLastUnitWidth(10, idx));end   

// f_TailRecursionGetUnitWidthForLatency - Returns the smallest LUT width needed to set the structure's latency to a maximum value.
//                           The actual latency will be less than or equal to the request
//  base        - Total number of input bits to compare
//  latency     - Maximum latency.
//  lut_width   - MUST BE greater than to 1one. Minium size LUT to use for the comparator. Exposed for recursion property's
//
// First Call iterator_TailRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY, 2);
function automatic integer f_TailRecursionGetUnitWidthForLatency;
    input integer base, latency;
    f_TailRecursionGetUnitWidthForLatency=iterator_TailRecursionGetUnitWidthForLatency(base,latency,2);
endfunction
function automatic integer iterator_TailRecursionGetUnitWidthForLatency;
    input integer base, latency, lut_width;
    iterator_TailRecursionGetUnitWidthForLatency=
        (iterator_TailRecursionGetVectorSize(base,lut_width,0)<=latency)
            ?lut_width
            :iterator_TailRecursionGetUnitWidthForLatency(base,latency,lut_width+1);
endfunction
    // initial begin:test_TailRecursionGetUnitWidthForLatency integer idx;$display("f_TailRecursionGetUnitWidthForLatency()");for(idx=1;idx<=10;idx=idx+1)begin $display("\t\t\tbase:10 latency:%d lut_width:%d",idx,f_TailRecursionGetUnitWidthForLatency(10,idx));end end

// f_TailRecursionGetUnitInputAddress - Returns the index for the base bit requested.
//  cmp_width       - width of the comparator
//  lut_width       - width of the lut used in the comparator
//  unit_index      - which LUT index is being requested
//  input_index     - which input of the LUT is being requested
//  base_input_index- Base input address. Exposed for recursion property's
//  past_output_index- Past output address. Exposed for recursion property's
//  current_unit    - current unit_index. Exposed for recursion property's
//
//  First Call iterator_TailRecursionGetUnitInputAddress( CHUNK_COUNT, LUT_WIDTH, LUT_NUMBER, INPUT_NUMBER, 0, ~0, 0);
function automatic integer f_TailRecursionGetUnitInputAddress;
    input integer cmp_width, lut_width, unit_index, input_index;
    f_TailRecursionGetUnitInputAddress = iterator_TailRecursionGetUnitInputAddress(cmp_width, lut_width, unit_index, input_index, 0, ~0, 0);
endfunction
function automatic integer iterator_TailRecursionGetUnitInputAddress;
    input integer cmp_width, lut_width, unit_index, input_index, base_input_index, past_output_index, current_unit;
    iterator_TailRecursionGetUnitInputAddress=
        (current_unit==unit_index)
            ?unit_index==0
                ?input_index
                :input_index==0
                    ?past_output_index+cmp_width
                    :(base_input_index-1)+input_index
            :iterator_TailRecursionGetUnitInputAddress(
                cmp_width,
                lut_width,
                unit_index,
                input_index,
                base_input_index==0
                    ?base_input_index+lut_width
                    :base_input_index+(lut_width-1),
                past_output_index+1,
                current_unit+1);
endfunction
    // initial begin:test_TailRecursionGetUnitInputAddress integer unit_index,input_index;$display("f_TailRecursionGetUnitInputAddress");$display("\t\t\tBase:10 LUT_WIDTH:4 LUT_COUNT:3");for(unit_index=0;unit_index<3;unit_index=unit_index+1)for( input_index=0;input_index<4;input_index=input_index+1)$display("unit:%d input:%d address:%d",unit_index,input_index,f_TailRecursionGetUnitInputAddress(10,4,unit_index,input_index));end

//
    ///////////////////////////////////////////
    // N-ary tree Iteration Functions        //
    // f_NaryRecursionGetVectorSize          //
    // f_NaryRecursionGetUnitWidth           //
    // f_NaryRecursionGetDepth               //
    // f_NaryRecursionUnitDepth              //
    // f_NaryRecursionGetUnitWidthForLatency //
    // f_NaryRecursionGetUnitInputAddress    //
    //                                            
    // Intended to be used to perform a reducing operation on a vector in a pipelined manner 
    // By using a tree structure (N-ary), the operations latency can be controlled
    // in order to produce a valid output, at the specified latency 
    //  LUT width 2 Unit Count 11                       LUT width 3 Unit Count 7                LUT width 4 Unit Count 4
    //  base #  0___1   2___3   4___5   6___7   8___9   0___1___2   3___4___5   6___7___8   9   0___1___2___3   4___5___6___7   8___9
    //              |       |       |       |       |           |           |           |   |               |               |       |
    //             10______11      12______13      14          10__________11__________12  13              10______________11______12
    //                      |               |       |                                   |   |                                       |
    //                     15______________16      17                                  14__15                                      trigger
    //                                      |       |                                       |
    //                                     18______19                                    trigger
    //                                              |
    //                                            trigger

//  f_NaryRecursionGetVectorSize - Returns the number of LUT needed to build structure
//  base        - Total number of input bits to operate on
//  lut_width   - Maximum width of the LUT used.
//  rt          - Set to 0zero when calling this function, used internal, exposed for recursion property's
//
// First Call f_NaryRecursionGetVectorSize(CHUNK_COUNT, LUT_WIDTH );
function automatic integer f_NaryRecursionGetVectorSize;
    input integer base, lut_width;         
    f_NaryRecursionGetVectorSize=iterator_NaryRecursionVectorSize(base, lut_width, 0);
endfunction
function automatic integer iterator_NaryRecursionVectorSize;
    input integer base, lut_width, rt;   
    iterator_NaryRecursionVectorSize=
        base==1
            ?rt
            :iterator_NaryRecursionVectorSize(
                base / lut_width * lut_width == base
                    ? base / lut_width
                    : base / lut_width + 1
                ,lut_width
                ,rt + ((base / lut_width * lut_width == base)
                    ? base / lut_width
                    : (base / lut_width) + 1));
endfunction
    // initial begin:test_NaryRecursionVectorSize integer idx;$display("f_NaryRecursionGetVectorSize()");for(idx=2;idx<=10;idx=idx+1)begin $display("\t\t\t:10 lut_width:%d cmp_width:%d",idx,f_NaryRecursionGetVectorSize(10,idx));end end

// f_NaryRecursionGetUnitWidth - Returns the total number of inputs for unit requested
//  base        - Total number of input bits to compare
//  lut_width   - Maximum width of LUT used.
//  unit        - unit number whom width will be returned
//  rt          - Set to 0zero when calling this function, used internal, exposed for recursion property's
//
// First Call iterator_NaryRecursionGetUnitWidth(CHUNK_COUNT, LUT_WIDTH, unit, 0, 0);
function automatic integer f_NaryRecursionGetUnitWidth;
    input integer base, lut_width, unit;
    f_NaryRecursionGetUnitWidth=iterator_NaryRecursionGetUnitWidth(base, lut_width, unit, 0);
endfunction
// now builds properly in IVerilog, but not using SBY.
// going to try to rewrite this. rewrite worked. code builds in all 3 tools, Gowin, iverilog, Yosys
function automatic integer iterator_NaryRecursionGetUnitWidth;
    input integer base, lut_width, unit, results;
    `define next_level_unit_count (base / lut_width * lut_width == base ? base / lut_width : base / lut_width + 1)
    begin
        // iterator_NaryRecursionGetUnitWidth = 
        //     (base == 1 )
        //         ? 0 // overflow condition, requested unit not in range, width = 0 is a valid answer;
        //         : (results + `next_level_unit_count) <= unit    // requested unit is on a different iteration, proceed to the next iteration
        //             ? iterator_NaryRecursionGetUnitWidth(`next_level_unit_count,lut_width,unit,results + `next_level_unit_count)
        //             // requested unit is on this iteration.
        //             : (unit - results ) == `next_level_unit_count-1 // if this is the last unit in this layer
        //                 ? base % lut_width == 0 ? lut_width : base % lut_width  // calculate its width
        //                 : lut_width;    // its a full unit
        for (iterator_NaryRecursionGetUnitWidth=0; base>0; iterator_NaryRecursionGetUnitWidth=iterator_NaryRecursionGetUnitWidth+1) begin
            if( base == 1 ) begin
                iterator_NaryRecursionGetUnitWidth = 0;
                base = 0;
            end else begin
                if( (results + `next_level_unit_count) <= unit ) begin
                    base = `next_level_unit_count;
                    results = results + `next_level_unit_count;
                end else begin
                    base = 0;
                    if( (unit - results ) == `next_level_unit_count-1 ) begin
                        iterator_NaryRecursionGetUnitWidth = base % lut_width == 0 ? lut_width : base % lut_width;
                    end else begin
                        iterator_NaryRecursionGetUnitWidth = lut_width;
                    end
                end
            end
        end
    end
    `undef next_level_unit_count 
endfunction
    // initial begin:test_NaryRecursionGetLastUnitWidth integer unit_index, test_lut_width;$display("test_NaryRecursionGetLastUnitWidth()");for(test_lut_width=2; test_lut_width < 5; test_lut_width = test_lut_width + 1)for(unit_index=0; unit_index < 11; unit_index = unit_index + 1)$display("rt:%d",f_NaryRecursionGetUnitWidth(10,test_lut_width,unit_index));end

//  f_NaryRecursionGetDepth - Returns the depth of the structure
//  base        - Total number of input bits to operate on
//  lut_width   - Maximum width of the LUT used.
//  rt          - Set to 0zero when calling this function, used internal, exposed for recursion property's
//
// First Call f_NaryRecursionGetDepth(CHUNK_COUNT, LUT_WIDTH, 0 );
function automatic integer f_NaryRecursionGetDepth;
    input integer base, lut_width;         
    f_NaryRecursionGetDepth=iterator_NaryRecursionGetDepth(base, lut_width, 0);
endfunction
function automatic integer iterator_NaryRecursionGetDepth;
    input integer base, lut_width, rt;   
    iterator_NaryRecursionGetDepth=
        base==1
            ?rt
            :iterator_NaryRecursionGetDepth(
                base / lut_width * lut_width == base
                    ? base / lut_width
                    : base / lut_width + 1
                ,lut_width
                ,rt + 1);
endfunction
    //  initial begin:test_NaryRecursionGetDepth integer idx;$display("f_NaryRecursionGetDepth()");for(idx=2;idx<=10;idx=idx+1)begin $display("\t\t\t:10 lut_width:%d cmp_width:%d",idx,f_NaryRecursionGetDepth(10,idx));end end

//  f_NaryRecursionGetUnitDepth - Returns the depth of the structure
//  base        - Total number of input bits to operate on
//  lut_width   - Maximum width of the LUT used.
//  unit_index  - which LUT index is being requested
//  rt          - Set to 0zero when calling this function, used internal, exposed for recursion property's
//
// First Call f_NaryRecursionGetUnitDepth(CHUNK_COUNT, LUT_WIDTH, UNIT, 0 );
function automatic integer f_NaryRecursionGetUnitDepth;
    input integer base, lut_width, unit_index;         
    f_NaryRecursionGetUnitDepth=iterator_NaryRecursionGetUnitDepth(base, lut_width, unit_index, 0);
endfunction
function automatic integer iterator_NaryRecursionGetUnitDepth;
    input integer base, lut_width, unit_index, rt;   
    iterator_NaryRecursionGetUnitDepth=
        base >= unit_index
            ?rt
            :iterator_NaryRecursionGetUnitDepth(
                base / lut_width * lut_width == base
                    ? base / lut_width
                    : base / lut_width + 1
                ,lut_width, 
                unit_index - base,
                rt + 1);
endfunction
    // initial begin:test_NaryRecursionGetUnitDepth integer idx;$display("f_NaryRecursionGetUnitDepth()");for(idx=0;idx<=10+f_NaryRecursionGetVectorSize(10,2);idx=idx+1)begin $display("\t\t\tbase:10 lut_width:2 unit:%d\tdepth:%d",idx,f_NaryRecursionGetUnitDepth(10,2,idx));end end

// f_NaryRecursionGetUnitWidthForLatency - Returns the smallest UNIT width needed to set the structure's latency to a maximum value.
//                           The actual latency will be less than or equal to the request
//  base        - Total number of input bits to compare
//  latency     - Maximum latency.
//  lut_width   - MUST BE greater than to 1one. Minium size UNIT to use for the comparator. Exposed for recursion property's
//
// First Call iterator_NaryRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY, 2);
function automatic integer f_NaryRecursionGetUnitWidthForLatency;
    input integer base, latency;
    f_NaryRecursionGetUnitWidthForLatency=iterator_NaryRecursionGetUnitWidthForLatency(base,latency,2);
endfunction
function automatic integer iterator_NaryRecursionGetUnitWidthForLatency;
    input integer base, latency, lut_width;
    iterator_NaryRecursionGetUnitWidthForLatency=
        (f_NaryRecursionGetDepth(base,lut_width)<=latency)
            ?lut_width
            :iterator_NaryRecursionGetUnitWidthForLatency(base,latency,lut_width+1);
endfunction
    // initial begin:test_NaryRecursionGetLastUnitWidthForLatency integer idx;$display("f_NaryRecursionGetUnitWidthForLatency()");for(idx=1;idx<=10;idx=idx+1)begin $display("\t\t\tbase:10 latency:%d lut_width:%d",idx,f_NaryRecursionGetUnitWidthForLatency(10,idx));end end

// f_NaryRecursionGetUnitInputAddress - Returns the index for the base bit requested. returns ~0 is input is request is invalid
//  cmp_width       - width of the comparator
//  lut_width       - width of the lut used in the comparator
//  unit_index      - which LUT index is being requested
//  input_index     - which input of the LUT is being requested
//  base_input_index- Base input address. Exposed for recursion property's
//  past_output_index- Past output address. Exposed for recursion property's
//  current_unit    - current unit_index. Exposed for recursion property's
//
//  First Call iterator_NaryRecursionGetUnitInputAddress( CHUNK_COUNT, LUT_WIDTH, LUT_NUMBER, INPUT_NUMBER, 0, ~0, 0);
function automatic integer f_NaryRecursionGetUnitInputAddress;
    input integer cmp_width, lut_width, unit_index, input_index;
    f_NaryRecursionGetUnitInputAddress = iterator_NaryRecursionGetUnitInputAddress(cmp_width, lut_width, unit_index, input_index, 0);
endfunction
function automatic integer iterator_NaryRecursionGetUnitInputAddress;
    input integer base_width, unit_width, unit_index, input_index, start_index;
    `define units_on_this_depth (base_width / unit_width * unit_width == base_width ? base_width / unit_width : base_width / unit_width + 1)
    begin
        iterator_NaryRecursionGetUnitInputAddress =
            // if the request is on a deeper recursion
            `units_on_this_depth <= unit_index
                // Goto next recursion 
            ? iterator_NaryRecursionGetUnitInputAddress( `units_on_this_depth, unit_width, unit_index-`units_on_this_depth, input_index, start_index + base_width)
            // else it is on this iteration
                // validate input_index
            : (input_index < f_NaryRecursionGetUnitWidth(base_width, unit_width, unit_index) )
                ? unit_index * unit_width + input_index + start_index // valid input_index
                : ~0;   // invalid input_index
    end
    `undef units_on_this_depth
endfunction
//    initial begin:test_NaryRecursionGetUnitInputAddress integer unit_index,input_index;$display("f_NaryRecursionGetUnitInputAddress");for(unit_index=0;unit_index<=3;unit_index=unit_index+1)for( input_index=0;input_index<4;input_index=input_index+1)$display("unit:%d input:%d address:%d width:%d",unit_index,input_index,f_NaryRecursionGetUnitInputAddress(10,4,unit_index,input_index), f_NaryRecursionGetUnitWidth(10, 4, unit_index));end
