`resetall
`timescale 1ns / 1ps

module  clkDivN #(
	parameter WIDTH = 10'd10
)(  
    ////////////////////  Clock Input     ////////////////////  
    input     logic  clk,
    input     logic  resetN,
    input     logic [0:WIDTH-1]  preScaleValue,
    
    output    logic  slowEnPulse, 
    output    logic  slowEnPulse_d // a delayed enalbe to avoid read and write DPRAM at the same time 

);

logic [0:WIDTH-1] counter;

always_ff@(posedge clk or negedge resetN)
begin
    if(!resetN) begin
      counter  <= {WIDTH{1'b0}};
        slowEnPulse      <= 1'b0;
        slowEnPulse_d    <= 1'b0;
    end
    else
    begin
        slowEnPulse_d  <=  slowEnPulse; // 1 clk delay
        if (counter >= preScaleValue) begin
            counter        <= {WIDTH{1'b0}};
            slowEnPulse    <= 1'b1;
        end
        else begin
            counter <= counter + 1'b1;
            slowEnPulse      <= 1'b0;
        end
    end
end
endmodule

`resetall