
`ifndef UTILS_SVH_
`define UTILS_SVH_

`define TRANSACTION(valid,ready) \
    valid = 1'b1; \
    while(~(valid & ready)) begin \
        #clock_period; \
    end \
    #clock_period; \
    valid = 1'b0;

`endif