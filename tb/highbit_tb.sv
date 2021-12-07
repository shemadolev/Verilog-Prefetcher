`resetall
`timescale 1ns / 1ps

module highBitTb ();

localparam OUT_WIDTH = 4;
localparam IN_WIDTH = 1<<(OUT_WIDTH-1);

logic [0:IN_WIDTH-1] vec;
logic [0:OUT_WIDTH-1] outIdx;


highbit #(
    .OUT_WIDTH(OUT_WIDTH) 
) highbit_dut (
    .in(vec),
    .out(outIdx)
);

initial begin
    vec = 8'b0001_0110;
    #10;
    t0: assert (outIdx=={{1'b0},{3'd4}})
        else $error("Assertion 0 failed!");

    vec = 8'b0100_0000;
    #10;
    t1: assert (outIdx=={{1'b0},{3'd6}})
        else $error("Assertion 1 failed!");
    
    vec = 8'b1001_1100;
    #10;
    t2: assert (outIdx=={{1'b0},{3'd7}})
        else $error("Assertion 2 failed!");

    vec = 8'd0;
    #10;
    t3: assert (outIdx=={4{1'b1}})
        else $error("Assertion 3 failed!");

    vec = 8'b1111_1111;
    #10;
    t4: assert (outIdx=={{1'b0},{3'd7}})
        else $error("Assertion 4 failed!");
  $display("**** All tests passed ****");
  
    $stop;
end

endmodule
`resetall
