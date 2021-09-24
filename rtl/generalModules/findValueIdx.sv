module findValueIdx #(
    parameter LOG_VEC_SIZE = 3'd6,
    parameter VEC_SIZE = 1<<LOG_VEC_SIZE,
    parameter TAG_SIZE = 7'd64

)(
    input logic     [0:TAG_SIZE-1] inTag,
    input logic     [0:TAG_SIZE-1] valid,
    input logic     [0:TAG_SIZE-1] inMat [0:VEC_SIZE-1],
    
    output logic    [OUT_WIDTH-1:0] matchIdx,
    output logic    hit
);


logic [0:VEC_SIZE-1] compareVec;
wire [0:LOG_VEC_SIZE] highbitRes;

generate genvar i;
    for(i=0; i<VEC_SIZE; i=i+1)
        assign compareVec[i] = (inTag==inMat[i]) & valid[i] ; 
endgenerate

highbit #(.OUT_WIDTH(LOG_VEC_SIZE+1)) findIdx 
            (.in(compareVec), .out(highbitRes)
            );

assign hit = ~highbitRes[LOG_VEC_SIZE];
assign matchIdx = highbitRes[0:LOG_VEC_SIZE-1];

endmodule