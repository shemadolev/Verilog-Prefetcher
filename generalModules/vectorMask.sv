// Creates a mask vector of '1' bits between two given indices.

module vectorMask #(
    parameter LOG_WIDTH = 3'd6,
    parameter WIDTH = 1<<LOG_WIDTH;
) (
    input logic [0:LOG_WIDTH-1] headIdx,
    input logic [0:LOG_WIDTH-1] tailIdx,
    output logic [0:WIDTH-1] outMask
);

logic [0:WIDTH-1] headMaskVec;
logic [0:WIDTH-1] tailMaskVec;
logic [0:WIDTH-1] maskVec;
logic tailIsLeading;

always_comb begin
    headMaskVec = {1'b1, {(WIDTH-1){1'b0}}} >> (headIdx-1'b1);
    tailMaskVec = {1'b1, {(WIDTH-1){1'b0}}} >> tailIdx;
    maskVec = headMaskVec ^ tailMaskVec;
end

assign tailIsLeading = headIdx < tailIdx;
assign outMask = tailIsLeading ? maskVec : ~maskVec

endmodule