// Creates a mask vector of '1' bits form the index of headIdx, till (and not including) the index of tailIdx.
// The output vector is cyclic, meaning the tail can be smaller than the head.
//Note: If tailPtr == headPtr, a vector of all 1's will be returned (because assuming cyclic vector array)

module vectorMask #(
    parameter LOG_WIDTH = 3'd6,
    parameter WIDTH = 1<<LOG_WIDTH;
) (
    input logic [0:LOG_WIDTH-1] headIdx,
    input logic [0:LOG_WIDTH-1] tailIdx,
    output logic [0:WIDTH-1] outMask
);

parameter logic [2*WIDTH-1:0] maskTemplate = {{WIDTH{1'b0}},{(WIDTH-1){1'b1}}}; //WIDTH=3: 00011

logic [0:WIDTH-1] headMaskVec;
logic [0:WIDTH-1] tailMaskVec;
logic [0:WIDTH-1] maskVec;
logic tailIsLeading;

always_comb begin
    headMaskVec = maskTemplate[headIdx:(headIdx+WIDTH-1)]; // 0: 000, 1: 001, 2: 011
    tailMaskVec = maskTemplate[tailIdx:(tailIdx+WIDTH-1)];
    maskVec = headMaskVec ^ tailMaskVec;
end

assign tailIsLeading = headIdx < tailIdx;
assign outMask = tailIsLeading ? maskVec : ~maskVec

endmodule