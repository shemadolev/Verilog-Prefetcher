`resetall
`timescale 1ns / 1ps

module onesCnt#(
    parameter LOG_VEC_SIZE = 4,
    parameter VEC_SIZE = 1<<LOG_VEC_SIZE
)(
    input logic [0:VEC_SIZE-1] A,
    output logic [0:LOG_VEC_SIZE] ones
    );

integer i;

always@*
begin
    ones = 0;  //initialize count variable.
    for(i=0;i<VEC_SIZE;i=i+1)   //check for all the bits.
        if(A[i] == 1'b1)    //check if the bit is '1'
            ones = ones + 1;    //if its one, increment the count.
end

endmodule
`resetall
