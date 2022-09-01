`resetall
`timescale 1ns / 1ps
`default_nettype none

//TODO update dram.v to support the updates

/*
 * AXI4 Delay: Mask out the output ready & valid bits bit DELAY_CYCLES after 'valid' is up
 */
module axi_delay #
(
    // Number of cycles to delay 'ready' after 'valid' is up to 2^LONG_DELAY_CYCLES_WIDTH
        // hot page delay 
    parameter SHORT_DELAY_CYCLES_WIDTH = 2,
        // cold page delay
    parameter LONG_DELAY_CYCLES_WIDTH = 4,
    parameter ADDR_WIDTH = 16,
    // Number of bits in the address that stands for the page offset in the ram
    parameter PAGE_OFFSET_WIDTH = 6
) (
    input wire clk,
    input wire rst,
    input wire in_ready,
    input wire in_valid,
    input wire [ADDR_WIDTH-1:0] in_addr,

    output wire out_ready,
    output wire out_valid
);

parameter SHORT_COUNTDOWN_INITIAL = (1<<SHORT_DELAY_CYCLES_WIDTH) - 1;
parameter LONG_COUNTDOWN_INITIAL = (1<<LONG_DELAY_CYCLES_WIDTH) - 1;

localparam PAGE_WIDTH = ADDR_WIDTH-PAGE_OFFSET_WIDTH;

localparam [1:0]
    STATE_IDLE = 2'd0,
    STATE_COUNTDOWN = 2'd1,
    STATE_ACTIVE = 2'd2;

reg [1:0] state_reg = STATE_IDLE, state_next;

reg [LONG_DELAY_CYCLES_WIDTH-1:0] countdown_reg, countdown_next;
// base address of the hot page
reg [PAGE_WIDTH-1:0] page_addr_reg, page_addr_next, in_page_addr;
reg [LONG_DELAY_CYCLES_WIDTH-1:0] countdown_initial;

// in_page_addr selects in_addr without LSB of PAGE_OFFSET_WIDTH
assign in_page_addr = in_addr[ADDR_WIDTH-1:PAGE_OFFSET_WIDTH];
// set the initial countdown timer depend on the address (hot/cold page)
assign countdown_initial = (&(in_page_addr^~page_addr_reg)) ? SHORT_COUNTDOWN_INITIAL : LONG_COUNTDOWN_INITIAL;

// assignment for output signals
assign out_valid = (state_reg == STATE_ACTIVE) ? in_valid : 1'b0;
assign out_ready = (state_reg == STATE_ACTIVE) ? in_ready : 1'b0;

always @* begin
//default next values
state_next = state_reg;
countdown_next = countdown_reg;
page_addr_next = page_addr_reg;

case (state_reg)
        STATE_IDLE: begin
            if(in_valid == 1'b1) begin
                state_next = STATE_COUNTDOWN;
                countdown_next = countdown_initial;
                // set the hot page addr (maybe the same page address)
                page_addr_next = in_page_addr;
            end 
        end
        STATE_COUNTDOWN: begin
            if(countdown_reg == {LONG_DELAY_CYCLES_WIDTH{1'b0}}) begin 
                state_next = STATE_ACTIVE;
            end
            countdown_next = countdown_reg - {{(LONG_DELAY_CYCLES_WIDTH-1){1'b0}},1'b1};
        end
        STATE_ACTIVE: begin
            if(out_ready & out_valid)
                state_next = STATE_IDLE;
        end
endcase
end

always @(posedge clk) begin
    if(rst == 1'b1) begin
        state_reg <= STATE_IDLE;
        countdown_reg <= {(LONG_DELAY_CYCLES_WIDTH){1'b0}};
        page_addr_reg <= {(PAGE_WIDTH){1'b0}};
    end else begin
        state_reg <= state_next;
        countdown_reg <= countdown_next;
        page_addr_reg <= page_addr_next;
    end
end

endmodule;

`resetall
