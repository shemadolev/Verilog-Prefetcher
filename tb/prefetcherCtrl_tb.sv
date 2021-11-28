`define tick(clk) \
clk=0; \
#1; \
clk=1; \
#1

`define printContext(MOD) \
$display("------- BEGIN Prefetcher Context --------"); \
$display("  st_pr_cur \t%s",MOD.st_pr_cur.name); \
$display("  st_pr_next \t%s",MOD.st_pr_next.name); \
$display("  st_exec_cur \t%s",MOD.st_exec_cur.name); \
$display("  st_exec_next \t%s",MOD.st_exec_next.name); \
$display("  pr_context_valid %b",MOD.pr_context_valid); \
$display("  stride_sampled 0x%h",MOD.stride_sampled); \
$display("  stride_learned %b",MOD.stride_learned); \
if(MOD.stride_learned) \
    $display("  stride_reg 0x%h",MOD.stride_reg); \
    $display("  bar 0x%h, limit 0x%h",MOD.bar, MOD.limit); \
if(pr_context_valid == 1) begin \
    $display("  pr_m_ar_len %d",MOD.pr_m_ar_len); \
    $display("  pr_m_ar_id %d",MOD.pr_m_ar_id); \
end \
$display("  prefetchAddr_valid %b",MOD.prefetchAddr_valid); \
if(MOD.prefetchAddr_valid) \
    $display("  prefetchAddr_reg 0x%h",MOD.prefetchAddr_reg); \
$display("------- END Prefetcher Context --------")


module prefetcherCtrl_tb();
    localparam ADDR_BITS = 64; //64bit address 2^64
    localparam LOG_QUEUE_SIZE = 3'd6; // the size of the queue [2^x] 
    localparam WATCHDOG_SIZE = 10'd10; // number of bits for the watchdog counter
    localparam BURST_LEN_WIDTH = 4'd8; //NVDLA max is 3; AXI4 supports up to 8 bits
    localparam TID_WIDTH = 4'd8; //NVDLA max is 3; AXI4 supports up to 8 bits

    
    logic     clk;
    logic     en;
    logic     resetN;
    logic     ctrlFlush;

    // Prefetch Data Path
        // Control bits
    logic    pr_flush; //control bit to flush the queue
    logic    [0:2] pr_opCode;
    logic     pr_addrHit;
    logic     pr_hasOutstanding;
    logic     [0:LOG_QUEUE_SIZE] pr_reqCnt;
    logic     pr_almostFull;
    logic    pr_isCleanup; // indicates that the prefecher is in cleaning
    logic    pr_context_valid; // burst & tag were learned
       // Read channel
     logic     pr_r_valid;
     logic     pr_r_in_last;
        //Read Req Channel
     logic    [0:ADDR_BITS-1] pr_m_ar_addr;
     logic    [0:BURST_LEN_WIDTH-1] pr_m_ar_len;
     logic    [0:TID_WIDTH-1] pr_m_ar_id;

    // Slave AXI ports (PR <-> NVDLA)
        //AR (Read Request)
     logic s_ar_valid;
     logic s_ar_ready;
     logic [0:BURST_LEN_WIDTH-1]s_ar_len;
     logic [0:ADDR_BITS-1] s_ar_addr; 
     logic [0:TID_WIDTH-1] s_ar_id;
        //R (Read data)
     logic s_r_valid;
     logic s_r_ready;
     logic s_r_last;
     logic [0:TID_WIDTH-1] s_r_id;

    // Master AXI ports (PR <-> DDR)
        //AR (Read Request)
     logic m_ar_valid;
     logic m_ar_ready;
     logic [0:BURST_LEN_WIDTH-1] m_ar_len;
     logic [0:ADDR_BITS-1] m_ar_addr;
     logic [0:TID_WIDTH-1] m_ar_id;
        //R (Read data)
     logic m_r_valid;
     logic m_r_ready;
     logic [0:TID_WIDTH-1] m_r_id;

    //CR Space
     logic     [0:ADDR_BITS-1] bar;
     logic     [0:ADDR_BITS-1] limit;
     logic     [0:LOG_QUEUE_SIZE] windowSize;
     logic     [0:WATCHDOG_SIZE-1] watchdogCnt; //the size of the counter that is used to divide the clk freq for the watchdog


    prefetcherCtrl #(
        .ADDR_BITS(ADDR_BITS),
        .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
        .WATCHDOG_SIZE(WATCHDOG_SIZE),
        .BURST_LEN_WIDTH(BURST_LEN_WIDTH),
        .TID_WIDTH(TID_WIDTH)
    ) prefetcherCtrl_dut (
        .clk(clk),
        .en(en),
        .resetN(resetN),
        .ctrlFlush(ctrlFlush),
        .pr_flush(pr_flush), //control bit to flush the queue
        .pr_opCode(pr_opCode),
        .pr_addrHit(pr_addrHit),
        .pr_hasOutstanding(pr_hasOutstanding),
        .pr_reqCnt(pr_reqCnt),
        .pr_almostFull(pr_almostFull),
        .pr_isCleanup(pr_isCleanup), // indicates that the prefecher is in cleaning
        .pr_context_valid(pr_context_valid), // burst & tag were learned
        .pr_r_valid(pr_r_valid),
        .pr_r_in_last(pr_r_in_last),
        .pr_m_ar_addr(pr_m_ar_addr),
        .pr_m_ar_len(pr_m_ar_len),
        .pr_m_ar_id(pr_m_ar_id),
        .s_ar_valid(s_ar_valid),
        .s_ar_ready(s_ar_ready),
        .s_ar_len(s_ar_len),
        .s_ar_addr(s_ar_addr), 
        .s_ar_id(s_ar_id),
        .s_r_valid(s_r_valid),
        .s_r_ready(s_r_ready),
        .s_r_last(s_r_last),
        .s_r_id(s_r_id),
        .m_ar_valid(m_ar_valid),
        .m_ar_ready(m_ar_ready),
        .m_ar_len(m_ar_len),
        .m_ar_addr(m_ar_addr),
        .m_ar_id(m_ar_id),
        .m_r_valid(m_r_valid),
        .m_r_ready(m_r_ready),
        .m_r_id(m_r_id),
        .bar(bar),
        .limit(limit),
        .windowSize(windowSize),
        .watchdogCnt(watchdogCnt) //the size of the counter that is used to divide the clk freq for the watchdog
    );

    initial begin
        localparam BASE_ADDR = 64'hdeadbeef;
        resetN=0;
        ctrlFlush=0;

        `tick(clk);
        `printContext(prefetcherCtrl_dut);
        resetN=1;
        en=1;
        bar = 0;
        limit = BASE_ADDR * 2;
        $display("###### Reseted prefetcher");

        s_ar_len = 4;
        s_ar_id = 3;
        pr_almostFull = 0;
        m_ar_ready = 1;
        windowSize=3;
        pr_reqCnt = 0;

        $display("~~~~~~~~~~~~~~~~~~~ Requests burst ~~~~~~~~~~~~~~~~~~~");
        pr_addrHit = 0;
        for (int i=0; i<3; i++) begin
            s_ar_valid = 1'b1;
            s_ar_addr = BASE_ADDR + i*64;
            `tick(clk); //ST_EXEC_IDLE (raise ready)
            $display("@@@@@@@   Master Read Req No.%d   @@@@@@@", i);

            $display("###### %d.1", i);
            `printContext(prefetcherCtrl_dut);
            assert(prefetcherCtrl_dut.shouldCleanup==1'b0);
            assert(s_ar_ready == 1);
            `tick(clk); //ST_EXEC_IDLE -> ST_EXEC_S_AR_PR_ACCESS
            s_ar_valid = 0;

            $display("###### %d.2", i);
            `printContext(prefetcherCtrl_dut);
            assert(prefetcherCtrl_dut.shouldCleanup==1'b0);
            assert(pr_opCode == 2); //read req to data path
            assert(s_ar_ready == 0);
            `tick(clk); //ST_EXEC_S_AR_PR_ACCESS -> ST_EXEC_S_AR_POLLING

            $display("###### %d.3", i);
            `printContext(prefetcherCtrl_dut);
            assert(prefetcherCtrl_dut.shouldCleanup==1'b0);
            assert(m_ar_valid == 1);
            `tick(clk); // ST_EXEC_S_AR_POLLING -> ST_EXEC_IDLE
            assert(m_ar_valid == 0);
            assert(prefetcherCtrl_dut.shouldCleanup==1'b0);

            $display("###### %d.4", i);
            `printContext(prefetcherCtrl_dut);
        end

        $display("~~~~~~~~~~~~~~~~~~~ Read data burst ~~~~~~~~~~~~~~~~~~~");
        m_r_valid = 1'b1;
        #1; // essential for the TB to absorb m_r_valid
        m_r_id = 3;
        for (int i=0; i<3; i++) begin //ST_EXEC_IDLE always 
            `tick(clk);
            assert(m_r_ready == 1);
            assert(pr_opCode == 0); //NOP, pr_opCode_next == readDataSlave 
            `tick(clk);
            assert(m_r_ready == 0);
            assert(pr_opCode == 3); //readDataSlave, pr_opCode_next == NOP  
        end
        `printContext(prefetcherCtrl_dut);
        
    $display("**** All tests passed ****");
    
        $stop;
    end

endmodule