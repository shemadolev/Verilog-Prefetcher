// Searches for a non-zero bit. Outputs '0' in MSB if any non-zero bit found.
// Resource: https://stackoverflow.com/questions/38230450/first-non-zero-element-encoder-in-verilog

`resetall
`timescale 1ns / 1ps

module highbit #(
    parameter OUT_WIDTH = 4, // out uses one extra bit for not-found
    parameter IN_WIDTH = 1<<(OUT_WIDTH-1)
) (
    input [IN_WIDTH-1:0]in,
    output [OUT_WIDTH-1:0]out
);

wire [OUT_WIDTH-1:0]out_stage[0:IN_WIDTH];
assign out_stage[0] = ~0; // desired default output if no bits set
generate genvar i;
    for(i=0; i<IN_WIDTH; i=i+1)
        assign out_stage[i+1] = in[i] ? i : out_stage[i]; 
endgenerate
assign out = out_stage[IN_WIDTH];

endmodule
`resetall
