`resetall
`timescale 1ns / 1ps

`include "print.svh"
`include "utils.svh"

module prefetcherTop_tb();

localparam ADDR_BITS = 64; 
localparam LOG_QUEUE_SIZE = 3'd3; 
localparam WATCHDOG_SIZE = 10'd10; 
localparam BURST_LEN_WIDTH = 4'd8; 
localparam TID_WIDTH = 4'd8; 
localparam LOG_BLOCK_DATA_BYTES = 3'd0;
localparam PROMISE_WIDTH = 3'd3; 
localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3; 

logic     clk;
logic     en; 
logic     resetN;
logic s_ar_valid;
logic s_ar_ready;
logic [0:BURST_LEN_WIDTH-1] s_ar_len;
logic [0:ADDR_BITS-1] s_ar_addr; 
logic [0:TID_WIDTH-1] s_ar_id;
logic m_ar_valid;
logic m_ar_ready;
logic [0:BURST_LEN_WIDTH-1] m_ar_len;
logic [0:ADDR_BITS-1] m_ar_addr;
logic [0:TID_WIDTH-1] m_ar_id;
logic s_r_valid;
logic s_r_ready;
logic s_r_last;
logic [0:BLOCK_DATA_SIZE_BITS-1] s_r_data;
logic [0:TID_WIDTH-1] s_r_id;
logic m_r_valid;
logic m_r_ready;
logic m_r_last;
logic [0:BLOCK_DATA_SIZE_BITS-1]  m_r_data;
logic [0:TID_WIDTH-1] m_r_id;
logic s_aw_valid;
logic s_aw_ready;
logic [0:ADDR_BITS-1] s_aw_addr;
logic [0:TID_WIDTH-1] s_aw_id;
logic m_aw_valid;
logic m_aw_ready;
logic     [0:ADDR_BITS-1] bar;
logic     [0:ADDR_BITS-1] limit;
logic     [0:LOG_QUEUE_SIZE] windowSize;
logic     [0:WATCHDOG_SIZE-1] watchdogCnt; 
logic     [0:LOG_QUEUE_SIZE-1] crs_almostFullSpacer;
logic    [0:2] errorCode;

prefetcherTop #(
.ADDR_BITS(ADDR_BITS),
.LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
.WATCHDOG_SIZE(WATCHDOG_SIZE),
.BURST_LEN_WIDTH(BURST_LEN_WIDTH),
.TID_WIDTH(TID_WIDTH),
.LOG_BLOCK_DATA_BYTES(LOG_BLOCK_DATA_BYTES),
.PROMISE_WIDTH(PROMISE_WIDTH)
) prefetcherTop_dut (
    .clk(clk),
    .en(en), 
    .resetN(resetN),
    .s_ar_valid(s_ar_valid),
    .s_ar_ready(s_ar_ready),
    .s_ar_len(s_ar_len),
    .s_ar_addr(s_ar_addr), 
    .s_ar_id(s_ar_id),
    .m_ar_valid(m_ar_valid),
    .m_ar_ready(m_ar_ready),
    .m_ar_len(m_ar_len),
    .m_ar_addr(m_ar_addr),
    .m_ar_id(m_ar_id),
    .s_r_valid(s_r_valid),
    .s_r_ready(s_r_ready),
    .s_r_last(s_r_last),
    .s_r_data(s_r_data),
    .s_r_id(s_r_id),
    .m_r_valid(m_r_valid),
    .m_r_ready(m_r_ready),
    .m_r_last(m_r_last),
    .m_r_data(m_r_data),
    .m_r_id(m_r_id),
    .s_aw_valid(s_aw_valid),
    .s_aw_ready(s_aw_ready),
    .s_aw_addr(s_aw_addr),
    .s_aw_id(s_aw_id),
    .m_aw_valid(m_aw_valid),
    .m_aw_ready(m_aw_ready),
    .bar(bar),
    .limit(limit),
    .windowSize(windowSize),
    .watchdogCnt(watchdogCnt), 
    .crs_almostFullSpacer(crs_almostFullSpacer),
    .errorCode(errorCode)
);

initial begin
    localparam BASE_ADDR = 64'hdeadbeef;
    resetN=0;
    en = 1;
    // watchdogCnt = 10'd1000;

    `tick(clk);
    resetN=1;
//CR Space
        // Ctrl
    bar = 0;
    limit = BASE_ADDR * 2;
    windowSize= 3;
    watchdogCnt= 10'd1000;
        // Data
    crs_almostFullSpacer=2;

    m_r_valid=0;

    s_ar_len=3;
    s_ar_id=5;

    //NVDLA AR check

    s_ar_valid = 1'b1;
    m_ar_ready = 0;
    s_r_ready = 0;
    m_r_valid = 0;
    s_aw_valid =0;
    m_aw_ready = 0;

    for (int i=0; i<10; i++) begin
        m_ar_ready = 1;
        // s_ar_addr = BASE_ADDR + i*64;
        s_ar_addr = BASE_ADDR;
        `tick(clk);
        $display("\n\n~~~~~~~    Cycle %d",i);
        `printTop(prefetcherTop_dut);
        `printCtrl(prefetcherTop_dut.prCtrlPath);
        `printData(prefetcherTop_dut.prDataPath);
    end
    
    //DDR R check 
    s_ar_valid = 0;
    m_ar_ready = 1;
    s_r_ready = 0;
    m_r_valid = 0;
    s_aw_valid =0;
    m_aw_ready = 0;

    while(~(m_r_ready & m_r_valid)) begin
        m_r_valid = 1;
        m_r_id = 5;
        m_r_last = 1'b1;
        m_r_data = 42;
        $display("\n~~~~ Data read cycle");
        `printTop(prefetcherTop_dut);
        `printCtrl(prefetcherTop_dut.prCtrlPath);
        `printData(prefetcherTop_dut.prDataPath);
        `tick(clk);
    end
    $display("\n~~~~ m_r_ready == 1");
    `printTop(prefetcherTop_dut);
    `printCtrl(prefetcherTop_dut.prCtrlPath);
    `printData(prefetcherTop_dut.prDataPath);
    `tick(clk);
    m_r_valid = 0;
    $display("\n~~~~ opCode == 3");
    `printTop(prefetcherTop_dut);
    `printCtrl(prefetcherTop_dut.prCtrlPath);
    `printData(prefetcherTop_dut.prDataPath);
    `tick(clk);
    $display("\n~~~~ SUCCESS in data read");
    `printTop(prefetcherTop_dut);
    `printCtrl(prefetcherTop_dut.prCtrlPath);
    `printData(prefetcherTop_dut.prDataPath);
    
    $stop;
end

endmodule
`resetall
