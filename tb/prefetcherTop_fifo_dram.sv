`resetall
`timescale 1ns / 1ps //This is <time_unit>/<time_precision>. If higher freq' is needed, decrease <time_unit>

`include "print.svh"
`include "utils.svh"

module prefetcherTop_fifo_dram();

localparam ADDR_SIZE_ENCODE = 4;
localparam ADDR_WIDTH = 1<<ADDR_SIZE_ENCODE; 
localparam QUEUE_WIDTH = 3'd5; 
localparam WATCHDOG_WIDTH = 10'd10; 
localparam BURST_LEN_WIDTH = 4'd8; 
localparam ID_WIDTH = 4'd8; 
localparam DATA_SIZE_ENCODE = 3'd0;
localparam DATA_WIDTH = (1<<DATA_SIZE_ENCODE)<<3;
localparam STRB_WIDTH = (DATA_WIDTH/8);
localparam PROMISE_WIDTH = 3'd3;
localparam PRFETCH_FRQ_WIDTH = 3'd1;
localparam FIFO_DEPTH = 5'd16;
localparam PAGE_OFFSET_WIDTH = 8;
localparam SHORT_DELAY_CYCLES_WIDTH = 2;
localparam LONG_DELAY_CYCLES_WIDTH = 5;

//########### prefetcherTop ###########//
    // + axi signals (prefetcher<->DDR)
logic                       clk;
logic                       en; 
logic                       resetN;
logic                       s_ar_valid;
logic                       s_ar_ready;
logic [0:BURST_LEN_WIDTH-1] s_ar_len;
logic [0:ADDR_WIDTH-1]       s_ar_addr; 
logic [0:ID_WIDTH-1]       s_ar_id;
logic                       m_ar_valid;
logic                       m_ar_ready;
logic [0:BURST_LEN_WIDTH-1] m_ar_len;
logic [0:ADDR_WIDTH-1]       m_ar_addr;
logic [0:ID_WIDTH-1]       m_ar_id;
logic                       s_r_valid;
logic                       s_r_ready;
logic                       s_r_last;
logic [0:DATA_WIDTH-1]      s_r_data;
logic [0:ID_WIDTH-1]       s_r_id;
logic                       m_r_valid;
logic                       m_r_ready;
logic                       m_r_last;
logic [0:DATA_WIDTH-1]      m_r_data;
logic [0:ID_WIDTH-1]       m_r_id;
logic                       s_aw_valid;
logic                       s_aw_ready;
logic [0:ADDR_WIDTH-1]       s_aw_addr;
logic [0:ID_WIDTH-1]       s_aw_id;
logic                       m_aw_valid;
logic                       m_aw_ready;
logic [0:ADDR_WIDTH-1]       crs_bar;
logic [0:ADDR_WIDTH-1]       crs_limit;
logic [0:QUEUE_WIDTH]       crs_prOutstandingLimit;
logic [0:WATCHDOG_WIDTH-1]   crs_watchdogCnt; 
logic [0:PRFETCH_FRQ_WIDTH-1] crs_prBandwidthThrottle;
logic [0:QUEUE_WIDTH-1]     crs_almostFullSpacer;
logic [0:2]                 errorCode;

//########### axi-dram ###########//
logic                   rst;

//These are not checked, assign some contants for valid/ready
logic [ADDR_WIDTH-1:0]  s_axi_awaddr;
logic [7:0]             s_axi_awlen;
logic [DATA_WIDTH-1:0]  s_axi_wdata;
logic [STRB_WIDTH-1:0]  s_axi_wstrb;
logic                   s_axi_wlast;
logic                   s_axi_wvalid;
logic                   s_axi_wready;

logic [ID_WIDTH-1:0]    s_axi_bid;
logic [1:0]             s_axi_bresp; //dram's output - always 2'b00, no error can be sent
logic                   s_axi_bvalid;
logic                   s_axi_bready;

logic [1:0]             s_axi_rresp;

prefetcherTop #(
    .ADDR_BITS(ADDR_WIDTH),
    .LOG_QUEUE_SIZE(QUEUE_WIDTH),
    .WATCHDOG_WIDTH(WATCHDOG_WIDTH),
    .BURST_LEN_WIDTH(BURST_LEN_WIDTH),
    .TID_WIDTH(ID_WIDTH),
    .LOG_BLOCK_DATA_BYTES(DATA_SIZE_ENCODE),
    .PROMISE_WIDTH(PROMISE_WIDTH),
    .PRFETCH_FRQ_WIDTH(PRFETCH_FRQ_WIDTH)
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
    .crs_bar(crs_bar),
    .crs_limit(crs_limit),
    .crs_prOutstandingLimit(crs_prOutstandingLimit),
    .crs_watchdogCnt(crs_watchdogCnt), 
    .crs_almostFullSpacer(crs_almostFullSpacer),
    .crs_prBandwidthThrottle(crs_prBandwidthThrottle),
    .errorCode(errorCode)
);

dram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ID_WIDTH(ID_WIDTH),
    .WRITE_FIFO_DEPTH(FIFO_DEPTH),
    .READ_FIFO_DEPTH(FIFO_DEPTH),
    .PAGE_OFFSET_WIDTH(PAGE_OFFSET_WIDTH),
    .SHORT_DELAY_CYCLES_WIDTH(SHORT_DELAY_CYCLES_WIDTH),
    .LONG_DELAY_CYCLES_WIDTH(LONG_DELAY_CYCLES_WIDTH)
) dram_dut (
    .clk(clk),
    .rst(rst),
    .s_axi_awid(s_aw_id),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(DATA_SIZE_ENCODE),
    .s_axi_awburst(2'b01),
    .s_axi_awlock(1'b0), //Irrelevant when accessing a single port
    .s_axi_awcache(4'b0000),
    .s_axi_awprot(3'b000),
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
    .s_axi_arid(m_ar_id),
    .s_axi_araddr(m_ar_addr),
    .s_axi_arlen(m_ar_len),
    .s_axi_arsize(DATA_SIZE_ENCODE),
    .s_axi_arburst(2'b01), //INC burst type, the only type supported by NVDLA
    .s_axi_arlock(1'b0), //Irrelevant when accessing a single port
    .s_axi_arcache(4'b0000), // Irrelevant, used for caching attributes
    .s_axi_arprot(3'b000), // Irrelevant, used for access premissions 
    .s_axi_arvalid(m_ar_valid),
    .s_axi_arready(m_ar_ready),
    .s_axi_rid(m_r_id),
    .s_axi_rdata(m_r_data),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(m_r_last),
    .s_axi_rvalid(m_r_valid),
    .s_axi_rready(m_r_ready)
);



assign rst = ~resetN;

assign s_axi_awaddr = s_aw_addr;
assign s_axi_wstrb = {STRB_WIDTH{1'b1}};
assign s_axi_bready = 1'b1;


localparam clock_period=20;
localparam gpu_period = clock_period * 10;
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

// Tracer's vars
int 	 fd; 			    // file descriptor handle
int 	 trace_mem_addr;    // var for address extraction from the file
int reqs_count;
realtime log_req []; //log of $realtime of each AR of MASTER->Prefetcher
realtime log_res []; //log of $realtime, so the i'th element is the R response of the AR executed at log_req[i]
realtime log_diff []; //log_res[i] - log_req[i]
int log_req_idx, log_res_idx;
realtime diff_sum, diff_avg;

localparam file_name = "/users/epiddo/Workshop/projectB/traces/one_slice.trace";

localparam use_prefetcher = 0; //1 to use prefetcher, 0 for direct GPU<->RAM

initial begin
    localparam BASE_ADDR = 16'h5940 * use_prefetcher;
    localparam SLICE_RANGE = 16'h5940 * use_prefetcher;
    localparam RD_LEN = 0;
    localparam TRANS_ID = 5;    
    resetN = 1'b0;
    en = 1'b1;

//CR Space
        // Ctrl
    crs_watchdogCnt = 10'd1000;
    crs_bar = 0;
    crs_limit = BASE_ADDR + SLICE_RANGE;
    crs_prOutstandingLimit = {{(QUEUE_WIDTH-3){1'b0}}, 3'd7};
    crs_prBandwidthThrottle = 4;
        // Data
    crs_almostFullSpacer={{(QUEUE_WIDTH-2){1'b0}}, 2'd2};

    s_aw_valid = 1'b0;
    s_axi_wvalid = 1'b0;
    s_ar_valid = 1'b0;
    s_r_ready = 1'b1;

    #clock_period;
    resetN=1'b1;


    //Count number of lines
    fd = $fopen (file_name, "r");
    reqs_count = 0;
    while ($fscanf (fd, "%h,", trace_mem_addr) == 1) begin
        reqs_count++;
    end
    $fclose(fd);
    log_req = new [reqs_count];
    log_res = new [reqs_count];
    log_diff = new [reqs_count];
    log_req_idx = 0;
    log_res_idx = 0;

    $display("lines=%d",reqs_count);

    fd = $fopen (file_name, "r");
    // fscanf - scan line after line in the trace's file
    while ($fscanf (fd, "%h,", trace_mem_addr) == 1) begin
        // Extract only the relevant address width from the trace addresses
        s_ar_addr = trace_mem_addr[ADDR_WIDTH-1:0];
        // Set AXI signals to commit transaction to the prefetcher
        s_ar_len = RD_LEN;
        s_ar_id = TRANS_ID;
        `TRANSACTION(s_ar_valid,s_ar_ready)
        #gpu_period;
    end
	
    // Close the file handle
    $fclose(fd);

    //calculate diff of res and req
    diff_sum = 0;
    for(int i=0;i<reqs_count;i++) begin
        log_diff[i] = log_res[i] - log_req[i];
        diff_sum += log_diff[i];
    end
    diff_avg = diff_sum / reqs_count;

    //print results
    for(int i=0;i<reqs_count;i++)
        $display("%0.0t\t%0.0t\t%0.0t",log_req[i],log_res[i],log_diff[i]);


    $display("diff avg = %0.0t",diff_avg);

    $finish;
end

//Log times of AR (read requests)
initial begin
    forever begin
        @(posedge s_ar_valid);
        log_req[log_req_idx] = $realtime;
        log_req_idx++;
    end
end

//Log times of R (read response)
initial begin
    forever begin
        @(posedge clk);
        if(s_r_ready & s_r_valid) begin
            log_res[log_res_idx] = $realtime;
            log_res_idx++;
        end
    end
end


endmodule
`resetall
