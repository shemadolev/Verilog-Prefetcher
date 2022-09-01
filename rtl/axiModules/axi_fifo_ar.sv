
`resetall
`timescale 1ns / 1ps

module	axi_fifo_ar #(
    parameter LOG_QUEUE_SIZE = 4'd8, // the size of the queue [2^x] 
    localparam [0:LOG_QUEUE_SIZE] QUEUE_SIZE = 1<<LOG_QUEUE_SIZE,
    parameter ADDR_WIDTH = 7'd64, // the size of the address [bits]
    parameter TID_WIDTH = 4'd8, //AXI4 supports up to 8 bits
    parameter BURST_LEN_WIDTH = 4'd8 //AXI4 supports up to 8 bits
)(
    input logic	    clk,
    input logic     rst,

    input logic     s_ar_valid,
    output logic    s_ar_ready,
    input logic     [0:ADDR_WIDTH-1]      s_ar_addr,
    input logic	    [0:BURST_LEN_WIDTH-1] s_ar_len,
    input logic	    [0:TID_WIDTH-1]       s_ar_id, 

    output logic    m_ar_valid,
    input  logic    m_ar_ready,
    output logic    [0:ADDR_WIDTH-1]      m_ar_addr,
    output logic	[0:BURST_LEN_WIDTH-1] m_ar_len,
    output logic	[0:TID_WIDTH-1]       m_ar_id
);

logic s_ar_ready_reg, s_ar_ready_next;
logic m_ar_valid_reg, m_ar_valid_next;

assign s_ar_ready = s_ar_ready_reg;
assign m_ar_valid = m_ar_valid_reg;

//queue data
logic [0:QUEUE_SIZE-1] valid_vec_reg, valid_vec_next;
logic [0:ADDR_WIDTH-1] queue_addr_reg [0:QUEUE_SIZE-1];
logic [0:ADDR_WIDTH-1] queue_addr_next [0:QUEUE_SIZE-1];
logic [0:BURST_LEN_WIDTH-1] queue_len_reg [0:QUEUE_SIZE-1];
logic [0:BURST_LEN_WIDTH-1] queue_len_next [0:QUEUE_SIZE-1];
logic [0:TID_WIDTH-1] queue_id_reg [0:QUEUE_SIZE-1];
logic [0:TID_WIDTH-1] queue_id_next [0:QUEUE_SIZE-1];

//queue helpers
logic [0:LOG_QUEUE_SIZE-1] head_reg, tail_reg, head_next, tail_next; 
logic is_next_empty, is_next_full;

assign m_ar_addr = queue_addr_reg[head_reg];
assign m_ar_len  = queue_len_reg [head_reg];
assign m_ar_id   = queue_id_reg  [head_reg];

always_ff @(posedge clk or posedge rst)
begin
	if(rst)	begin 
        valid_vec_reg <= {QUEUE_SIZE{1'b0}}; 
        head_reg <= {LOG_QUEUE_SIZE{1'b0}};
        tail_reg <= {LOG_QUEUE_SIZE{1'b0}};
        s_ar_ready_reg <= 1'b0;
        m_ar_valid_reg <= 1'b0;
    end else begin
        valid_vec_reg <= valid_vec_next; 
        s_ar_ready_reg <= s_ar_ready_next;
        m_ar_valid_reg <= m_ar_valid_next;
        head_reg <= head_next;
        tail_reg <= tail_next;
        queue_addr_reg <= queue_addr_next;
        queue_len_reg <= queue_len_next;
        queue_id_reg <= queue_id_next;
    end
end

always_comb begin
    head_next = head_reg;
    tail_next = tail_reg;
    valid_vec_next = valid_vec_reg;

    queue_addr_next = queue_addr_reg;
    queue_len_next = queue_len_reg;
    queue_id_next = queue_id_reg;

    if(s_ar_valid & s_ar_ready) begin
        valid_vec_next[tail_reg] = 1'b1;
        queue_addr_next[tail_reg] = s_ar_addr;
        queue_len_next[tail_reg] = s_ar_len;
        queue_id_next[tail_reg] = s_ar_id;

        tail_next = tail_reg + {{(LOG_QUEUE_SIZE-1){1'b0}},{1'b1}};
    end

    if(m_ar_valid & m_ar_ready) begin
        valid_vec_next[head_reg] = 1'b0;

        head_next = head_reg + {{(LOG_QUEUE_SIZE-1){1'b0}},{1'b1}};
    end

    is_next_full = &valid_vec_next;
    is_next_empty = ~|valid_vec_next;

    s_ar_ready_next = ~is_next_full;
    m_ar_valid_next = ~is_next_empty;
end

endmodule

`resetall
