
`resetall
`timescale 1ns / 1ps
`default_nettype none
    

module dram #(
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 16,
    // Width of wstrb (width of data bus in words)
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    // Width of ID signal
    parameter ID_WIDTH = 8,
    // the size of the queue [2^x] 
    parameter FIFO_QUEUE_WIDTH = 4'd2,
    // AXI4 supports up to 8 bits
    parameter BURST_LEN_WIDTH = 4'd8,
    
    //Delay paramters for generating delay based on hitting same last page
    parameter PAGE_OFFSET_WIDTH = 6,
    parameter SHORT_DELAY_CYCLES_WIDTH = 2,
    parameter SHORT_DELAY_CYCLES = 5,
    parameter LONG_DELAY_CYCLES_WIDTH = 4,
    parameter LONG_DELAY_CYCLES = 16
) (
    input  wire                   clk,
    input  wire                   rst,
    
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awlock,
    input  wire [3:0]             s_axi_awcache,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize, // assume constants for all requests
    input  wire [1:0]             s_axi_arburst, // assume constants for all requests
    input  wire                   s_axi_arlock, // assume constants for all requests
    input  wire [3:0]             s_axi_arcache, // assume constants for all requests
    input  wire [2:0]             s_axi_arprot, // assume constants for all requests
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready
);

// Hold write address until write data in FIFO, if possible
parameter WRITE_FIFO_DELAY = 1;
// Hold read address until space available in FIFO for data, if possible
parameter READ_FIFO_DELAY = 1;


//########### fifo <-> dram ###########//
logic [ID_WIDTH-1:0]      fd_m_arid;
logic [ADDR_WIDTH-1:0]    fd_m_araddr;
logic [7:0]               fd_m_arlen;
logic                     fd_m_arvalid;
logic                     fd_m_arready;

//Delayed wires for AR channel of fifo->axi_ram
logic fd_m_arvalid_delay, fd_m_arready_delay;

axi_fifo_ar #(
    .LOG_QUEUE_SIZE(FIFO_QUEUE_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .TID_WIDTH(ID_WIDTH),
    .BURST_LEN_WIDTH(BURST_LEN_WIDTH)
) axi_fifo_ar_dut (
    .clk(clk),
    .rst(rst),
    .s_ar_valid(s_axi_arvalid),
    .s_ar_ready(s_axi_arready),
    .s_ar_addr(s_axi_araddr),
    .s_ar_len(s_axi_arlen),
    .s_ar_id(s_axi_arid), 
    .m_ar_valid(fd_m_arvalid),
    .m_ar_ready(fd_m_arready_delay),
    .m_ar_addr(fd_m_araddr),
    .m_ar_len(fd_m_arlen),
    .m_ar_id(fd_m_arid)
);

axi_ram #
(
    // Width of data bus in bits
    .DATA_WIDTH(DATA_WIDTH),
    // Width of address bus in bits
    .ADDR_WIDTH(ADDR_WIDTH),
    // Width of ID signal
    .ID_WIDTH(ID_WIDTH)
) axi_ram_inst (
    .clk(clk),
    .rst(rst),
    .s_axi_awid(s_axi_awid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awlock(s_axi_awlock),
    .s_axi_awcache(s_axi_awcache),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bid(s_axi_bid),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_arid(fd_m_arid),
    .s_axi_araddr(fd_m_araddr),
    .s_axi_arlen(fd_m_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arlock(s_axi_arlock),
    .s_axi_arcache(s_axi_arcache),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(fd_m_arvalid_delay),
    .s_axi_arready(fd_m_arready),
    .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready)
);

axi_delay #
(
    .SHORT_DELAY_CYCLES_WIDTH(SHORT_DELAY_CYCLES_WIDTH),
    .SHORT_DELAY_CYCLES(SHORT_DELAY_CYCLES),
    .LONG_DELAY_CYCLES_WIDTH(LONG_DELAY_CYCLES_WIDTH),
    .LONG_DELAY_CYCLES(LONG_DELAY_CYCLES),
    .PAGE_OFFSET_WIDTH(PAGE_OFFSET_WIDTH)
) axi_ram_ar_delay (
    .clk(clk),
    .rst(rst),
    .in_ready(fd_m_arready),
    .in_valid(fd_m_arvalid),
    .in_addr(fd_m_araddr),

    .out_ready(fd_m_arready_delay),
    .out_valid(fd_m_arvalid_delay)
);

endmodule

`resetall
