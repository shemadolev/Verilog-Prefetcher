module findValueTb ();

    localparam LOG_VEC_SIZE = 3'd3;
    localparam VEC_SIZE = 1<<LOG_VEC_SIZE;
    localparam TAG_SIZE = 7'd64;

    logic     [0:TAG_SIZE-1] inTag;
    logic     [0:VEC_SIZE-1] valid;
    logic     [0:TAG_SIZE-1] inMat [0:VEC_SIZE-1];

    logic    [0:LOG_VEC_SIZE-1] matchIdx;
    logic    hit;


findValueIdx #(
    .LOG_VEC_SIZE(LOG_VEC_SIZE),
    .TAG_SIZE(TAG_SIZE)
) findValueIdx_dut (
    .inTag(inTag),
    .valid(valid),
    .inMat(inMat),
    .matchIdx(matchIdx),
    .hit(hit)
);

initial begin

    inMat = {
        64'hbeef,
        64'hdead_beef,
        64'haab7271,
        64'h0,
        {64{1'b1}},
        64'h2,
        {64{1'bx}},
        {64{1'bx}}
    };
    valid = 8'b01011100;

    inTag = 64'd5;
    #10;
    not_found: assert (hit=={1'b0})
        else begin
            $error("Assertion not_found failed!");
            $display("hit:%d", hit);
        end

    inTag = 64'hbeef;
    #10;
    found_invalid: assert (hit=={1'b0})
    else begin
            $error("Assertion found_invalid failed!");
            $display("hit:%d",hit);
        end
    
    inTag = 64'hdead_beef;
    #10;
    found_32b: assert (hit=={1'b1} && matchIdx == 3'd1)
    else begin
            $error("Assertion found_32b failed!");
            $display("hit: %d matchIdx: %b",hit,matchIdx);
        end

    inTag = 64'd0;
    #10;
    found_0: assert (hit=={1'b1} && matchIdx == 3'd3)
    else begin
            $error("Assertion found_0 failed!");
            $display("hit: %d matchIdx: %b",hit,matchIdx);
        end 

    inTag = {64{1'b1}};
    #10;
    found_all1: assert (hit=={1'b1} && matchIdx == 3'd4)
        else begin
            $error("Assertion found_all1 failed!");
          $display("hit: %d matchIdx: %b, compareVec: %b",hit,matchIdx,findValueIdx_dut.compareVec);
        end 
  $display("**** All tests passed ****");
  
    $stop;
end

endmodule