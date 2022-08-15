`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 Delay: Mask out the output ready & valid bits bit DELAY_CYCLES after 'valid' is up
 */
module axi_delay #
(
    // Number of cycles to delay 'ready' after 'valid' is up is 2^DELAY_CYCLES_WIDTH
    parameter DELAY_CYCLES_WIDTH = 3
) (
    input wire clk,
    input wire rst,
    input wire in_ready,
    input wire in_valid,

    output wire out_ready,
    output wire out_valid
);

parameter COUNTDOWN_INITIAL = 1<<DELAY_CYCLES_WIDTH - 1;

localparam [1:0]
    STATE_IDLE = 2'd0,
    STATE_COUNTDOWN = 2'd1;
    STATE_ACTIVE = 2'd2;

reg [1:0] state_reg = STATE_IDLE;
wire [1:0] state_next;

reg [DELAY_CYCLES_WIDTH-1:0] countdown_reg;
wire [DELAY_CYCLES_WIDTH-1:0] countdown_next;

assign out_valid = (state_reg == STATE_ACTIVE) ? in_valid : 1'b0;
assign out_ready = (state_reg == STATE_ACTIVE) ? in_ready : 1'b0;

always @* begin
//default next values
state_next = state_reg;
countdown_next = countdown_reg;

case (state_reg)
        STATE_IDLE: begin
            if(in_valid == 1'b1) begin
                state_next = STATE_COUNTDOWN;
                countdown_next = DELAY_CYCLES;
            end 
        end
        STATE_COUNTDOWN: begin
            if(count_reg == {DELAY_CYCLES_WIDTH{1'b0}}) begin 
                state_next = STATE_COUNTDOWN;
            end
            countdown_next = count_reg - {{(DELAY_CYCLES_WIDTH-1){1'b0}},1'b1};
        end
        STATE_ACTIVE: begin
            if(out_ready & out_valid)
                state_next = STATE_IDLE;
        end
endcase
end

always @(posedge clk) begin
    if(rst == 1'b1)
        state_reg <= STATE_IDLE;
    else begin
        state_reg <= state_next;
        countdown_reg <= countdown_next;
    end
end

endmodule;

`resetall
