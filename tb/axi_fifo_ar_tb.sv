`resetall
`timescale 1ns / 1ps

`include "print.svh"
`include "utils.svh"

module axi_fifo_ar_tb ();

    localparam LOG_QUEUE_SIZE = 4'd2;  // the size of the queue [2^x] 
    localparam ADDR_WIDTH = 7'd64;  // the size of the address [bits]
    localparam TID_WIDTH = 4'd8;  //AXI4 supports up to 8 bits
    localparam BURST_LEN_WIDTH = 4'd8; //AXI4 supports up to 8 bits

    //input
    logic clk;
    logic rst;
    logic s_ar_valid;
    logic [0:ADDR_WIDTH-1]      s_ar_addr;
    logic [0:BURST_LEN_WIDTH-1] s_ar_len;
    logic [0:TID_WIDTH-1]       s_ar_id;
    logic m_ar_ready;
    //output
    logic s_ar_ready;
    logic m_ar_valid;
    logic [0:ADDR_WIDTH-1]      m_ar_addr;
    logic [0:BURST_LEN_WIDTH-1] m_ar_len;
    logic [0:TID_WIDTH-1]       m_ar_id;

    axi_fifo_ar #(
        .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TID_WIDTH(TID_WIDTH),
        .BURST_LEN_WIDTH(BURST_LEN_WIDTH)
    ) axi_fifo_ar_dut (
        .clk(clk),
        .rst(rst),
        .s_ar_valid(s_ar_valid),
        .s_ar_ready(s_ar_ready),
        .s_ar_addr(s_ar_addr),
        .s_ar_len(s_ar_len),
        .s_ar_id(s_ar_id), 
        .m_ar_valid(m_ar_valid),
        .m_ar_ready(m_ar_ready),
        .m_ar_addr(m_ar_addr),
        .m_ar_len(m_ar_len),
        .m_ar_id(m_ar_id)
    );


    localparam clock_period=20;
    initial begin
        clk <= '0;
        forever begin
            #(clock_period/2) clk = ~clk;
        end
    end

    localparam timeout=100000;
    initial begin
        #(timeout) $finish;
    end

    int i;

    initial begin
        rst=1;
        s_ar_valid = 1'b0;
        m_ar_ready = 1'b0;
        #clock_period;
        i = 0;

        rst=0;

        #clock_period;

        i=0;
        //Fill up the whole FIFO
        while(s_ar_ready) begin
            s_ar_addr = i;
            s_ar_len = i;
            s_ar_id = i;
            i++;            
            `TRANSACTION(s_ar_valid, s_ar_ready);
            #1; //
        end

        // Empty the whole FIFO
        m_ar_ready = 1'b1;
        while(m_ar_valid) #clock_period;

        #clock_period;

        //Fill and clean the FIFO
        while(i<15) begin
            s_ar_addr = i;
            s_ar_len = i;
            s_ar_id = i;
            i++;            
            `TRANSACTION(s_ar_valid,s_ar_ready);
            // @(posedge clk); 
        end

        $stop;
    end
endmodule
`resetall
