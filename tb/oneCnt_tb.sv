`resetall
`timescale 1ns / 1ps

module oneCntTb ();

localparam LOG_VEC_SIZE = 2'd3;
localparam VEC_SIZE = 1<<LOG_VEC_SIZE;
  
logic [0:VEC_SIZE-1] vec;
logic [0:LOG_VEC_SIZE-1] outCounter;


onesCnt #(.LOG_VEC_SIZE(LOG_VEC_SIZE)) onesCnt_dut (.A(vec), .ones(outCounter));

initial begin
  vec = 8'b0000_0000;
    #10;
    t0_ones: assert (outCounter==0)
        else $error("Assertion 0_ones failed!");

  vec = 8'b0100_0000;
    #10;
    t1_ones: assert (outCounter==1)
        else $error("Assertion 1_ones failed!");
    
    vec = 8'b1001_1100;
    #10;
    t4_ones: assert (outCounter==4)
        else $error("Assertion 4_ones failed!");

    vec = 8'b1011_1010;
    #10;
    t5_ones: assert (outCounter==5)
        else $error("Assertion 5_ones failed!");

    vec = 8'b1111_1110;
    #10;
    t7_ones: assert (outCounter==7)
        else $error("Assertion 7_ones failed!");
  $display("**** All tests passed ****");
  
    $stop;
end

endmodule
`resetall
