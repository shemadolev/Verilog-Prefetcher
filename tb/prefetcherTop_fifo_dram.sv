`resetall
`timescale 10ps / 1ps //This is <time_unit>/<time_precision>. If higher freq' is needed, decrease <time_unit>

`include "print.svh"
`include "utils.svh"

`define USE_PREFETCHER 0 //1 to use prefetcher, 0 for direct GPU<->RAM
`define LOG_PR_QUEUE_SIZE 5 //32 blocks
`define LOG_BLOCK_SIZE 8 //Cacheline
`define CRS_OUTSTAND_LIM 1 //0 = No prefetching, caching only
`define CRS_BW_THROTTLE 1
`define CRS_ALMOST_FULL 2
`define TRACES_FILENAME "/users/epiddo/Workshop/projectB/traces/final_traces/nw_256_16_1.csv"
// `define TRACES_FILENAME "/users/epiddo/Workshop/projectB/traces/final_traces/ispass-2009-NN.csv"


module prefetcherTop_fifo_dram();

localparam ADDR_SIZE_ENCODE = 4; // 16 bits 
localparam ADDR_WIDTH = 1<<ADDR_SIZE_ENCODE; 
localparam PR_QUEUE_WIDTH = `LOG_PR_QUEUE_SIZE; 
localparam WATCHDOG_WIDTH = 10'd30; 
localparam BURST_LEN_WIDTH = 4'd8; 
localparam ID_WIDTH = 4'd8; 
localparam DATA_SIZE_ENCODE = `LOG_BLOCK_SIZE;
localparam CACHELINE_SIZE = (1<<DATA_SIZE_ENCODE); // [Bytes]
localparam DATA_WIDTH = CACHELINE_SIZE<<3;
localparam STRB_WIDTH = (DATA_WIDTH/8);
localparam PROMISE_WIDTH = 3'd5;
localparam PRFETCH_FRQ_WIDTH = 3'd7;
localparam DRAM_QUEUE_WIDTH = 4'd5; //2^5 = 32 requests
localparam PAGE_OFFSET_WIDTH = 11; // lpddr5 - page size: 2KB
localparam SHORT_DELAY_CYCLES_WIDTH = 7;
localparam LONG_DELAY_CYCLES_WIDTH = 7;
localparam SHORT_DELAY_CYCLES = 80; // 120[ns]
localparam LONG_DELAY_CYCLES = 100; // 150[ns]

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
logic [0:PR_QUEUE_WIDTH]       crs_prOutstandingLimit;
logic [0:WATCHDOG_WIDTH-1]   crs_watchdogCnt; 
logic [0:PRFETCH_FRQ_WIDTH-1] crs_prBandwidthThrottle;
logic [0:PR_QUEUE_WIDTH-1]     crs_almostFullSpacer;
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
    .LOG_QUEUE_SIZE(PR_QUEUE_WIDTH),
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
    .FIFO_QUEUE_WIDTH(DRAM_QUEUE_WIDTH),
    .PAGE_OFFSET_WIDTH(PAGE_OFFSET_WIDTH),
    .SHORT_DELAY_CYCLES_WIDTH(SHORT_DELAY_CYCLES_WIDTH),
    .SHORT_DELAY_CYCLES(SHORT_DELAY_CYCLES),
    .LONG_DELAY_CYCLES_WIDTH(LONG_DELAY_CYCLES_WIDTH),
    .LONG_DELAY_CYCLES(LONG_DELAY_CYCLES)
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


localparam clock_period = 150; // Prefetcher freq 666Mhz => 1.5[ns]
// localparam gpu_period = (clock_period / 2) * 4; //GPU freq 1.2GHz, divided to 4 banks ~ 300MHz => 6[ns]
localparam gpu_period = (clock_period / 2) * 8; //GPU freq 1.2GHz, divided to 8 banks = 153MHz => 6[ns]
// localparam gpu_period = clock_period ; //GPU freq 666Mhz => 1.5[ns]
// localparam gpu_period = clock_period / 2; //GPU freq 1.2GHz => 0.83[ns]
initial begin
    clk <= '0;
    forever begin
        #(clock_period/2) clk = ~clk;
    end
end

localparam timeout=10000000000;
initial begin
    #(timeout) $finish;
end

// Tracer's vars
int 	 fd_input, fd_output; 			    // file descriptors handle
longint  trace_mem_addr;    // var for address extraction from the file
int      gpu_reqs_count;    // counts the reqs towards the from the GPU
int      dram_reqs_count;   // counts the reqs towards the dram
int      prefetcher_resps_count;   // counts the responses of prefetcher towards the GPU
int      prefetcher_reqs_count;   // counts the reqs towards the prefetcher
int      dram_total_bytes;   // counts the reqs towards the dram
time log_req []; //log of $realtime of each AR of MASTER->Prefetcher
time log_res []; //log of $realtime, so the i'th element is the R response of the AR executed at log_req[i]
time log_diff []; //log_res[i] - log_req[i]
int log_req_idx, s_ar_count;
longint lat_sum, lat_avg;
int gpu_cycle_prev, gpu_cycle_cur;
string str_temp;

initial begin
    // NOTE: need to be update according to the usecase
    localparam BASE_ADDR = 32'hc0010540; //for NW
    localparam LIMIT_ADDR = 32'hc0014500;
    // localparam BASE_ADDR = 32'hc003e440;//fow NN
    // localparam LIMIT_ADDR = 32'hc003f3a0;
    // static parameters
    localparam RD_LEN = 0;
    localparam TRANS_ID = 5;
    resetN = 1'b0;
    en = 1'b1;

//CR Space
        // Ctrl
    crs_watchdogCnt = 30'd100000;
    crs_bar = BASE_ADDR * `USE_PREFETCHER;
    crs_limit = LIMIT_ADDR * `USE_PREFETCHER;
    crs_prOutstandingLimit = `CRS_OUTSTAND_LIM;
    crs_prBandwidthThrottle = `CRS_BW_THROTTLE;
        // Data
    crs_almostFullSpacer = `CRS_ALMOST_FULL;

    s_aw_valid = 1'b0;
    s_axi_wvalid = 1'b0;
    s_ar_valid = 1'b0;
    s_r_ready = 1'b1;
    s_ar_id = TRANS_ID;
    s_ar_len = RD_LEN;

    #clock_period;
    resetN=1'b1;


    //Count number of lines
    fd_input = $fopen (`TRACES_FILENAME, "r");
    assert (fd_input != 0); //File opened successfully
    gpu_reqs_count = 0;
    prefetcher_reqs_count = 0;
    dram_reqs_count = 0;
    prefetcher_resps_count = 0;
    s_ar_count = 0;
    while(!$feof(fd_input)) begin
        $fgets(str_temp,fd_input);
        gpu_reqs_count++;
    end

    $fclose(fd_input);
    gpu_reqs_count--; //drop header line
    log_req = new [gpu_reqs_count];
    log_res = new [gpu_reqs_count];
    log_diff = new [gpu_reqs_count];

    $display("lines=%d",gpu_reqs_count);

    fd_input = $fopen (`TRACES_FILENAME, "r");
    // fscanf - scan line after line in the trace's file
    gpu_cycle_prev = 0;
    $fgets (str_temp,fd_input); //read header row

    // $fscanf (fd_input, "%s", str_temp); //read header row
    while ($fscanf (fd_input, "%d,%h,", gpu_cycle_cur, trace_mem_addr) > 0) begin
        if(trace_mem_addr >= BASE_ADDR && trace_mem_addr <= LIMIT_ADDR) begin
            // Extract only the relevant address width from the trace addresses
            s_ar_addr = trace_mem_addr[ADDR_WIDTH-1:0];
            //Wait GPU cycles, relative to previous transaction
            #(gpu_cycle_prev == 0 ? 0 : gpu_period * (gpu_cycle_cur - gpu_cycle_prev)); //wait the diff of cycles, unless this is the first transaction
            prefetcher_reqs_count++;
            `TRANSACTION(s_ar_valid,s_ar_ready)
            gpu_cycle_prev = gpu_cycle_cur;
        end
    end
	
    //Busy wait for all requests to be served by the prefetcher back to GPU
    while(prefetcher_reqs_count != prefetcher_resps_count)
        #clock_period;

    // Close the file handle
    $fclose(fd_input);

    //calculate diff of res and req
    lat_sum = 0;
    for(int i=0;i<prefetcher_reqs_count;i++) begin
        log_diff[i] = log_res[i] - log_req[i];
        lat_sum += log_diff[i];
    end
    lat_avg = lat_sum / prefetcher_reqs_count;
    
    dram_total_bytes = dram_reqs_count * CACHELINE_SIZE;
    //print stats results

    fd_output = $fopen("./output.csv","w");
    $fwrite(fd_output,"request time,response time,delta\n");

    for(int i=0;i<prefetcher_reqs_count;i++)
        // $display("%0.0t\t%0.0t\t%0.0t",log_req[i],log_res[i],log_diff[i]);
        $fwrite(fd_output,"%0.0t,%0.0t,%0.0t\n",log_req[i],log_res[i],log_diff[i]);
    $fclose(fd_output);

    $display("##### Prefetcher Simulation Summary #####");

    $display("USE_PREFETCHER\n=%d",`USE_PREFETCHER);
    $display("LOG_PR_QUEUE_SIZE\n=%d",`LOG_PR_QUEUE_SIZE);
    $display("LOG_BLOCK_SIZE\n=%d",`LOG_BLOCK_SIZE);
    $display("CRS_OUTSTAND_LIM\n=%d",`CRS_OUTSTAND_LIM);
    $display("CRS_BW_THROTTLE\n=%d",`CRS_BW_THROTTLE);
    $display("CRS_ALMOST_FULL\n=%d",`CRS_ALMOST_FULL);

    $display("latency avg\n=%0.0t",lat_avg);
    $display("total bytes towards ddr (reqs)\n=%d",dram_total_bytes);
    
    $display("ddr bus throughput [B/ns]\n=%.5f",dram_total_bytes / $realtime);
    $display("ddr bus utilization [%d/%.2f]\n=%.5f",dram_reqs_count,($realtime / clock_period),dram_reqs_count / ($realtime / clock_period));
    
    $display("Total simulation time\n=%0.0t",$realtime);
    $display("Slice range reqs count\n=%d",prefetcher_reqs_count);

    $finish;
end
/*
 * GPU -> Prefetcher stats *******************
 */
//Log times of AR (read requests)
initial begin
    forever begin
        @(posedge s_ar_valid);
        log_req[log_req_idx] = $time;
        log_req_idx++;
    end
end

//Log times of R (read response)
initial begin
    forever begin
        @(posedge clk);
        if(s_r_ready & s_r_valid & s_r_last) begin
            log_res[prefetcher_resps_count] = $time;
            prefetcher_resps_count++;
        end
        if(m_r_valid & m_r_ready) begin
            dram_reqs_count++;
        end
        if(s_ar_ready & s_ar_valid) begin
            s_ar_count++;
        end
    end
end

endmodule
`resetall
