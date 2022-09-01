
`ifndef UTILS_SVH_
`define UTILS_SVH_

`define TRANSACTION(valid,ready) \
    @(negedge clk); \
    valid = 1'b1; \
    @(posedge clk); \
    while(~(valid & ready)) begin \
        @(posedge clk); \
    end \
    valid = 1'b0;

`define tick(clk) \
    clk=0; \
    #1; \
    clk=1; \
    #1

`endif