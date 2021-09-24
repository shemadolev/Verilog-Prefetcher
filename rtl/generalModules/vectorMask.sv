// Creates a mask vector of '1' bits form the index of headIdx, till (and not including) the index of tailIdx.
// The output vector is cyclic, meaning the tail can be smaller than the head.
//Note: If tailPtr == headPtr, a vector of all 1's will be returned (because assuming cyclic vector array)

module vectorMask #(
    parameter LOG_WIDTH = 3'd6,
    parameter WIDTH = 1<<LOG_WIDTH
) (
    input logic [LOG_WIDTH-1:0] headIdx,
    input logic [LOG_WIDTH-1:0] tailIdx,
    output logic [WIDTH-1:0] outMask
);

  parameter logic [2*WIDTH-1:0] maskTemplate = {{(WIDTH-1){1'b1}},{WIDTH{1'b0}}}; //WIDTH=3: 00011

    logic [WIDTH-1:0] headMaskVec;
    logic [WIDTH-1:0] tailMaskVec;
    logic [WIDTH-1:0] maskVec;
    logic tailIsLeading;

    logic [WIDTH-1:0] maskTemplateArr [WIDTH-1:0];

    generate genvar i;
        for(i=0; i<WIDTH; i=i+1)
            assign maskTemplateArr[i] = maskTemplate[(i+WIDTH-1):i];
    endgenerate

    always_comb begin
        headMaskVec = maskTemplateArr[headIdx]; // 0: 000, 1: 001, 2: 011
        tailMaskVec = maskTemplateArr[tailIdx];
        maskVec = headMaskVec ^ tailMaskVec;
    end

    assign tailIsLeading = headIdx < tailIdx;
    assign outMask = tailIsLeading ? maskVec : ~maskVec;

endmodule