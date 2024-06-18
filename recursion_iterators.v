////////////////////////////////////////////////
// Tail Recursion Iteration Functions         //
// f_TailRecursionGetVectorSize           //
// f_TailRecursionGetLastUnitWidth       //
// f_TailRecursionGetUnitWidthForLatency //
// f_TailRecursionGetUnitInputAddress    //
//                                            
// Intended to be used to generate a magnitude comparator result for a staged ripple carry adder 
// By using a overlapping slope structure (name not known), the comparators latency can be controlled
// in order to produce a valid output, 1 clock after the carry chain has completly propagated 
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
//  lut_width       - Maxium width of the UNITs input used.
//  current_count   - Set to 0zero when calling this function, used internaly, exposed for recursion propertys
//
// First Call f_TailRecursionGetVectorSize(CHUNK_COUNT, LUT_WIDTH, 0 );
function automatic [7:0] f_TailRecursionGetVectorSize;
    input [7:0] base, lut_width;         
    f_TailRecursionGetVectorSize=iterator_TailRecursionGetVectorSize(base, lut_width, 0);
endfunction
function automatic [7:0] iterator_TailRecursionGetVectorSize;
    input [7:0] base, lut_width, current_count;         
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
//  lut_width   - Maxium width of LUT used.
//  rt          - Set to 0zero when calling this function, used internaly, exposed for recursion propertys
//
// First Call iterator_TailRecursionGetLastUnitWidth(CHUNK_COUNT, LUT_WIDTH, 0, 0);
function automatic [7:0] f_TailRecursionGetLastUnitWidth;
    input [7:0] base, lut_width;
    f_TailRecursionGetLastUnitWidth=iterator_TailRecursionGetLastUnitWidth(base, lut_width, 0, 0);
endfunction
function automatic [7:0] iterator_TailRecursionGetLastUnitWidth;
    input [7:0] base, lut_width, rt, results;
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

// f_TailRecursionGetUnitWidthForLatency - Returns the smalles LUT width needed to set the structure's latency to a maxium value.
//                           The actual latency will be less than or equal to the request
//  base        - Total number of input bits to compare
//  latency     - Maxium latency.
//  lut_width   - MUST BE greater than to 1one. Minium size LUT to use for the comparator. Exposed for recursion propertys
//
// First Call iterator_TailRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY, 2);
function automatic [7:0] f_TailRecursionGetUnitWidthForLatency;
    input [7:0] base, latency;
    f_TailRecursionGetUnitWidthForLatency=iterator_TailRecursionGetUnitWidthForLatency(base,latency,2);
endfunction
function automatic [7:0] iterator_TailRecursionGetUnitWidthForLatency;
    input [7:0] base, latency, lut_width;
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
//  base_input_index- Base input address. Exposed for recursion propertys
//  past_output_index- Past output address. Exposed for recursion propertys
//  current_unit    - current unit_index. Exposed for recursion propertys
//
//  First Call iterator_TailRecursionGetUnitInputAddress( CHUNK_COUNT, LUT_WIDTH, LUT_NUMBER, INPUT_NUMBER, 0, ~0, 0);
function automatic [7:0] f_TailRecursionGetUnitInputAddress;
    input [7:0] cmp_width, lut_width, unit_index, input_index;
    f_TailRecursionGetUnitInputAddress = iterator_TailRecursionGetUnitInputAddress(cmp_width, lut_width, unit_index, input_index, 0, ~0, 0);
endfunction
function automatic [7:0] iterator_TailRecursionGetUnitInputAddress;
    input [7:0] cmp_width, lut_width, unit_index, input_index, base_input_index, past_output_index, current_unit;
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
    // f_NaryRecursionGetVectorSize           //
    // f_NaryRecursionGetLastUnitWidth       //
    // f_NaryRecursionGetDepth               //
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

//  f_NaryRecursionVectorSize - Returns the number of LUT needed to build structure
//  base        - Total number of input bits to operate on
//  lut_width   - Maxium width of the LUT used.
//  rt          - Set to 0zero when calling this function, used internaly, exposed for recursion propertys
//
// First Call f_NaryRecursionVectorSize(CHUNK_COUNT, LUT_WIDTH, 0 );
function automatic [7:0] f_NaryRecursionVectorSize;
    input [7:0] base, lut_width;         
    f_NaryRecursionVectorSize=iterator_NaryRecursionVectorSize(base, lut_width, 0);
endfunction
function automatic [7:0] iterator_NaryRecursionVectorSize;
    input [7:0] base, lut_width, rt;   
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
    // initial begin:test_NaryRecursionVectorSize integer idx;$display("f_NaryRecursionVectorSize()");for(idx=2;idx<=10;idx=idx+1)begin $display("\t\t\t:10 lut_width:%d cmp_width:%d",idx,f_NaryRecursionVectorSize(10,idx));end end

// f_NaryRecursionGetStructureWidth - Returns the total number of inputs for unit requested
//  base        - Total number of input bits to compare
//  lut_width   - Maxium width of LUT used.
//  unit        - unit number whos width will be returned
//  rt          - Set to 0zero when calling this function, used internaly, exposed for recursion propertys
//
// First Call iterator_NaryRecursionGetStructureWidth(CHUNK_COUNT, LUT_WIDTH, unit, 0, 0);
function automatic [7:0] f_NaryRecursionGetStructureWidth;
    input [7:0] base, lut_width, unit;
    f_NaryRecursionGetStructureWidth=iterator_NaryRecursionGetStructureWidth(base, lut_width, unit, 0);
endfunction
function automatic [7:0] iterator_NaryRecursionGetStructureWidth;
    input [7:0] base, lut_width, unit, results;
    integer next_level_unit_count;
    begin : iterator_NaryRecursionGetStructureWidth
        next_level_unit_count = base / lut_width * lut_width == base ? base / lut_width : base / lut_width + 1;
        $display("\tbase:%d lut_width:%d unit:%d results:%d nluc:%d", base, lut_width, unit, results, next_level_unit_count);
        if( base == 1 )
            iterator_NaryRecursionGetStructureWidth = 0;    // overflow condition, requested unit not in range, width = 0 is a valid answer;
        else begin
            if( (results + next_level_unit_count) <= unit) begin
                // requested unit is on a different iteration, procede to the next iteration
                iterator_NaryRecursionGetStructureWidth = iterator_NaryRecursionGetStructureWidth(
                        next_level_unit_count,
                        lut_width,
                        unit,
                        results + next_level_unit_count);
            end else begin
                // requested unit is on this iteration.
                if( (unit - results ) == next_level_unit_count-1 )
                    iterator_NaryRecursionGetStructureWidth = base % lut_width == 0 ? lut_width : base % lut_width;
                else
                    iterator_NaryRecursionGetStructureWidth = lut_width;
            end
        end      
    end
endfunction
    // initial begin:test_NaryRecursionGetStructureWidth integer unit_index, test_lut_width;$display("test_f_NaryRecursionGetStructureWidth()");for(test_lut_width=2; test_lut_width < 5; test_lut_width = test_lut_width + 1)for(unit_index=0; unit_index < 11; unit_index = unit_index + 1)$display("rt:%d",f_NaryRecursionGetStructureWidth(10,test_lut_width,unit_index));end

//  f_NaryRecursionGetDepth - Returns the depth of the structure
//  base        - Total number of input bits to operate on
//  lut_width   - Maxium width of the LUT used.
//  rt          - Set to 0zero when calling this function, used internaly, exposed for recursion propertys
//
// First Call f_NaryRecursionGetDepth(CHUNK_COUNT, LUT_WIDTH, 0 );
function automatic [7:0] f_NaryRecursionGetDepth;
    input [7:0] base, lut_width;         
    f_NaryRecursionGetDepth=iterator_NaryRecursionGetDepth(base, lut_width, 0);
endfunction

function automatic [7:0] iterator_NaryRecursionGetDepth;
    input [7:0] base, lut_width, rt;   
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

// f_NaryRecursionGetUnitWidthForLatency - Returns the smallest UNIT width needed to set the structure's latency to a maxium value.
//                           The actual latency will be less than or equal to the request
//  base        - Total number of input bits to compare
//  latency     - Maxium latency.
//  lut_width   - MUST BE greater than to 1one. Minium size UNIT to use for the comparator. Exposed for recursion propertys
//
// First Call iterator_NaryRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY, 2);
function automatic [7:0] f_NaryRecursionGetUnitWidthForLatency;
    input [7:0] base, latency;
    f_NaryRecursionGetUnitWidthForLatency=iterator_NaryRecursionGetUnitWidthForLatency(base,latency,2);
endfunction
function automatic [7:0] iterator_NaryRecursionGetUnitWidthForLatency;
    input [7:0] base, latency, lut_width;
    iterator_NaryRecursionGetUnitWidthForLatency=
        (f_NaryRecursionGetDepth(base,lut_width)<=latency)
            ?lut_width
            :iterator_NaryRecursionGetUnitWidthForLatency(base,latency,lut_width+1);
endfunction
    // initial begin:test_NaryRecursionGetStructureWidthForLatency integer idx;$display("f_NaryRecursionGetUnitWidthForLatency()");for(idx=1;idx<=10;idx=idx+1)begin $display("\t\t\tbase:10 latency:%d lut_width:%d",idx,f_NaryRecursionGetUnitWidthForLatency(10,idx));end end

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
