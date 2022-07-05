
`ifndef UTILS_SVH_
`define UTILS_SVH_

`define TRANSACTION(valid,ready) \
    valid = 1'b1; \
    while(~(valid & ready)) begin \
        @(posedge clk); \
    end \
    @(posedge clk); \
    valid = 1'b0;

`define tick(clk) \
    clk=0; \
    #1; \
    clk=1; \
    #1

`endif