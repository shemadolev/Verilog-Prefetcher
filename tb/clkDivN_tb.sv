`resetall
`timescale 1ns / 1ps

module clkDivNTb ();

localparam WIDTH = 5;

logic  clk;
logic  resetN;
logic [0:WIDTH-1]  preScaleValue;
logic  slowEnPulse;
logic  slowEnPulse_d;

    logic [0:99] history;
    logic [0:99] history_d;

clkDivN #(
    .WIDTH(WIDTH) 
) clkDivN_dut (
    .clk(clk),
    .resetN(resetN),
    .preScaleValue(preScaleValue),
    .slowEnPulse(slowEnPulse),
    .slowEnPulse_d(slowEnPulse_d)
);

initial begin
    $display("**** test1 preScalerValue==4 ****");
    resetN=0;
    preScaleValue=4;
    #1;
    resetN=1;

    for (int i=1; i<100;i++) begin
        clk = 0;
        #1;
        clk = 1;
        #1;
        history[i]=slowEnPulse;
        history_d[i]=slowEnPulse_d;
    if(i>2) begin
            if(i%5==0) begin //preScaleValue+1
                assert (slowEnPulse==1)
                    else $error("Assertion clk i:%d failed!",i);        
            end
            else begin
                assert (slowEnPulse==0)
                    else $error("Assertion clk i:%d failed!",i);
            end

            if((i-1)%5==0)begin
                assert (slowEnPulse_d==1)
                    else $error("Assertion clk_d i:%d failed!",i);
            end
            else begin
              assert (slowEnPulse_d==0)
                  else $error("Assertion clk_d i:%d failed!",i);
            end
        end
    end

    $display("history is:   %b",history);
    $display("history_d is: %b",history_d);

    $display("**** test2 preScalerValue==7 ****");
    resetN=0;
    preScaleValue=7;
    #1;
    resetN=1;

    for (int i=1; i<100;i++) begin
        clk = 0;
        #1;
        clk = 1;
        #1;
        history[i]=slowEnPulse;
        history_d[i]=slowEnPulse_d;
        if(i>2) begin
            if(i%8==0) begin //preScaleValue+1
                assert (slowEnPulse==1)
                    else $error("Assertion clk i:%d failed!",i);        
            end
            else begin
                assert (slowEnPulse==0)
                    else $error("Assertion clk i:%d failed!",i);
            end

            if((i-1)%8==0)begin
                assert (slowEnPulse_d==1)
                    else $error("Assertion clk_d i:%d failed!",i);
            end
            else begin
            assert (slowEnPulse_d==0)
                else $error("Assertion clk_d i:%d failed!",i);
            end
        end
    end

    $display("history is:   %b",history);
    $display("history_d is: %b",history_d);
    $display("**** test 7 passed ****");

    $display("**** All tests passed ****");
    $stop;
end
endmodule

`resetall
