`resetall
`timescale 1ns / 1ps

module findValueIdx #(
    parameter LOG_VEC_SIZE = 4'd8,
    parameter VEC_SIZE = 1<<LOG_VEC_SIZE,
    parameter TAG_SIZE = 7'd64

)(
    input logic     [0:TAG_SIZE-1] inTag,
    input logic     [0:VEC_SIZE-1] valid,
    input logic     [0:TAG_SIZE-1] inMat [0:VEC_SIZE-1],
    
    output logic    [LOG_VEC_SIZE-1:0] matchIdx,
    output logic    hit
);

    logic [VEC_SIZE-1:0] compareVec;
    wire [LOG_VEC_SIZE:0] highbitRes;

    generate genvar i;
        for(i=0; i<VEC_SIZE; i=i+1)
            assign compareVec[i] = (inTag==inMat[i]) & valid[i] ; 
    endgenerate

    highbit #(.OUT_WIDTH(LOG_VEC_SIZE+1)) findIdx 
            (.in(compareVec), .out(highbitRes)
            );

    assign hit = ~highbitRes[LOG_VEC_SIZE];
    assign matchIdx = highbitRes[LOG_VEC_SIZE-1:0];

endmodule
`resetall
