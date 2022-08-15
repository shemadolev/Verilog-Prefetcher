
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
    // Extra pipeline register on output
    parameter PIPELINE_OUTPUT = 0,
    // Write data FIFO depth (cycles)
    parameter WRITE_FIFO_DEPTH,
    // Read data FIFO depth (cycles)
    parameter READ_FIFO_DEPTH,
    // Hold write address until write data in FIFO, if possible
    parameter WRITE_FIFO_DELAY,
    // Hold read address until space available in FIFO for data, if possible
    parameter READ_FIFO_DELAY

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
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arlock,
    input  wire [3:0]             s_axi_arcache,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready
);



//########### fifo <-> dram ###########//
logic [ID_WIDTH-1:0]      fd_m_awid;
logic [ADDR_WIDTH-1:0]    fd_m_awaddr;
logic [7:0]               fd_m_awlen;
logic [2:0]               fd_m_awsize;
logic [1:0]               fd_m_awburst;
logic                     fd_m_awlock;
logic [3:0]               fd_m_awcache;
logic [2:0]               fd_m_awprot;
logic [3:0]               fd_m_awqos;
logic [3:0]               fd_m_awregion;
logic                     fd_m_awvalid;
logic                     fd_m_awready;
logic [DATA_WIDTH-1:0]    fd_m_wdata;
logic [STRB_WIDTH-1:0]    fd_m_wstrb;
logic                     fd_m_wlast;
logic                     fd_m_wvalid;
logic                     fd_m_wready;
logic [ID_WIDTH-1:0]      fd_m_bid;
logic [1:0]               fd_m_bresp;
logic                     fd_m_bvalid;
logic                     fd_m_bready;
logic [ID_WIDTH-1:0]      fd_m_arid;
logic [ADDR_WIDTH-1:0]    fd_m_araddr;
logic [7:0]               fd_m_arlen;
logic [2:0]               fd_m_arsize;
logic [1:0]               fd_m_arburst;
logic                     fd_m_arlock;
logic [3:0]               fd_m_arcache;
logic [2:0]               fd_m_arprot;
logic [3:0]               fd_m_arqos;
logic [3:0]               fd_m_arregion;
logic                     fd_m_arvalid;
logic                     fd_m_arready;
logic [ID_WIDTH-1:0]      fd_m_rid;
logic [DATA_WIDTH-1:0]    fd_m_rdata;
logic [1:0]               fd_m_rresp;
logic                     fd_m_rlast;
logic                     fd_m_rvalid;
logic                     fd_m_rready;

axi_fifo #
(
    // Width of data bus in bits
    .DATA_WIDTH(DATA_WIDTH),
    // Width of address bus in bits
    .ADDR_WIDTH(ADDR_WIDTH),
    // Width of ID signal
    .ID_WIDTH(ID_WIDTH),
    // Write data FIFO depth (cycles)
    .WRITE_FIFO_DEPTH(WRITE_FIFO_DEPTH),
    // Read data FIFO depth (cycles)
    .READ_FIFO_DEPTH(READ_FIFO_DEPTH),
    // Hold write address until write data in FIFO, if possible
    .WRITE_FIFO_DELAY(WRITE_FIFO_DELAY),
    // Hold read address until space available in FIFO for data, if possible
    .READ_FIFO_DELAY(READ_FIFO_DELAY)
) fifo_dut (
    .clk(clk),
    .rst(rst),

    /*
     * AXI slave interface
     */
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
    .s_axi_arid(s_axi_arid),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arlock(s_axi_arlock),
    .s_axi_arcache(s_axi_arcache),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),

    /*
     * AXI master interface
     */
    .m_axi_awid(fd_m_awid),
    .m_axi_awaddr(fd_m_awaddr),
    .m_axi_awlen(fd_m_awlen),
    .m_axi_awsize(fd_m_awsize),
    .m_axi_awburst(fd_m_awburst),
    .m_axi_awlock(fd_m_awlock),
    .m_axi_awcache(fd_m_awcache),
    .m_axi_awprot(fd_m_awprot),
    .m_axi_awvalid(fd_m_awvalid),
    .m_axi_awready(fd_m_awready),
    .m_axi_wdata(fd_m_wdata),
    .m_axi_wstrb(fd_m_wstrb),
    .m_axi_wlast(fd_m_wlast),
    .m_axi_wvalid(fd_m_wvalid),
    .m_axi_wready(fd_m_wready),
    .m_axi_bid(fd_m_bid),
    .m_axi_bresp(fd_m_bresp),
    .m_axi_bvalid(fd_m_bvalid),
    .m_axi_bready(fd_m_bready),
    .m_axi_arid(fd_m_arid),
    .m_axi_araddr(fd_m_araddr),
    .m_axi_arlen(fd_m_arlen),
    .m_axi_arsize(fd_m_arsize),
    .m_axi_arburst(fd_m_arburst),
    .m_axi_arlock(fd_m_arlock),
    .m_axi_arcache(fd_m_arcache),
    .m_axi_arprot(fd_m_arprot),
    .m_axi_arvalid(fd_m_arvalid),
    .m_axi_arready(fd_m_arready),
    .m_axi_rid(fd_m_rid),
    .m_axi_rdata(fd_m_rdata),
    .m_axi_rresp(fd_m_rresp),
    .m_axi_rlast(fd_m_rlast),
    .m_axi_rvalid(fd_m_rvalid),
    .m_axi_rready(fd_m_rready)
);


axi_ram #
(
    // Width of data bus in bits
    .DATA_WIDTH(DATA_WIDTH),
    // Width of address bus in bits
    .ADDR_WIDTH(ADDR_WIDTH),
    // Width of ID signal
    .ID_WIDTH(ID_WIDTH),
    // Extra pipeline register on output
    .PIPELINE_OUTPUT(PIPELINE_OUTPUT)
) axi_ram_inst (
    .clk(clk),
    .rst(rst),
    .s_axi_awid(fd_m_awid),
    .s_axi_awaddr(fd_m_awaddr),
    .s_axi_awlen(fd_m_awlen),
    .s_axi_awsize(fd_m_awsize),
    .s_axi_awburst(fd_m_awburst),
    .s_axi_awlock(fd_m_awlock),
    .s_axi_awcache(fd_m_awcache),
    .s_axi_awprot(fd_m_awprot),
    .s_axi_awvalid(fd_m_awvalid),
    .s_axi_awready(fd_m_awready),
    .s_axi_wdata(fd_m_wdata),
    .s_axi_wstrb(fd_m_wstrb),
    .s_axi_wlast(fd_m_wlast),
    .s_axi_wvalid(fd_m_wvalid),
    .s_axi_wready(fd_m_wready),
    .s_axi_bid(fd_m_bid),
    .s_axi_bresp(fd_m_bresp),
    .s_axi_bvalid(fd_m_bvalid),
    .s_axi_bready(fd_m_bready),
    .s_axi_arid(fd_m_arid),
    .s_axi_araddr(fd_m_araddr),
    .s_axi_arlen(fd_m_arlen),
    .s_axi_arsize(fd_m_arsize),
    .s_axi_arburst(fd_m_arburst),
    .s_axi_arlock(fd_m_arlock),
    .s_axi_arcache(fd_m_arcache),
    .s_axi_arprot(fd_m_arprot),
    .s_axi_arvalid(fd_m_arvalid),
    .s_axi_arready(fd_m_arready),
    .s_axi_rid(fd_m_rid),
    .s_axi_rdata(fd_m_rdata),
    .s_axi_rresp(fd_m_rresp),
    .s_axi_rlast(fd_m_rlast),
    .s_axi_rvalid(fd_m_rvalid),
    .s_axi_rready(fd_m_rready)
);


//todo: Add a delay to the responses, using the axi_delay module

endmodule

`resetall
