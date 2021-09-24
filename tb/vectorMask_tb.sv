module vectorMaskTb ();

    localparam LOG_WIDTH = 3'd3;
    localparam WIDTH = 1<<LOG_WIDTH;

    logic [0:LOG_WIDTH-1] headIdx;
    logic [0:LOG_WIDTH-1] tailIdx;
    logic [0:WIDTH-1] outMask;

    vectorMask #(
        .LOG_WIDTH(LOG_WIDTH)
    ) vectorMask_dut (
        .headIdx(headIdx),
        .tailIdx(tailIdx),
        .outMask(outMask)
    );

    initial begin

        headIdx = 3'd2;
        tailIdx = 3'd6;

        #10;
        tail_lead: assert (outMask=={8'b00111100})
            else begin
                $error("Assertion tail_lead failed!");
                $display("outMask:%b", outMask);
            end

        headIdx = 3'd6;
        tailIdx = 3'd2;
        #10;
        head_lead: assert (outMask=={8'b11000011})
        else begin
                $error("Assertion head_lead failed!");
                $display("outMask:%b", outMask);
            end
        
        headIdx = 3'd0;
        tailIdx = 3'd0;
        #10;
        empty_full: assert (outMask=={8'b11111111})
        else begin
                $error("Assertion empty_full failed!");
                $display("outMask:%b", outMask);
            end

        headIdx = 3'd0;
        tailIdx = 3'd7;
        #10;
        almostFull: assert (outMask=={8'b1111_1110})
        else begin
                $error("Assertion almostFull failed!");
                $display("outMask:%b", outMask);
            end 

        headIdx = 3'd3;
        tailIdx = 3'd3;
        #10;
        empty_full2: assert (outMask=={8'b11111111})
            else begin
                $error("Assertion empty_full2 failed!");
                $display("outMask:%b", outMask);
            end 

        headIdx = 3'd3;
        tailIdx = 3'd4;
        #10;
        one_bit: assert (outMask=={8'b0001_0000})
            else begin
                $error("Assertion one_bit failed!");
                $display("outMask:%b", outMask);
            end 

        $display("**** All tests passed ****");
    
        $stop;
    end

endmodule