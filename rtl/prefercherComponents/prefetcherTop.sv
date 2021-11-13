//Notes: On flush, reset the stride FSM; If stride changes, do nothing (if we'll get hit in MOQ, blocks will pop out, else timeout will expire)

module prefetcherTop(
    input logic     clk,
    input logic     en, //NOTE: en==1'b1, still need to handle en=1'b0
    input logic     resetN,
    
    //AXI AR (Read Request) slave port
    input logic s_ar_valid,
    output logic s_ar_ready,
    input logic [0:BURST_LEN_WIDTH-1] s_ar_len,
    input logic [0:ADDR_BITS-1] s_ar_addr, 
    input logic [0:TID_WIDTH-1] s_ar_id,

    //AXI AR (Read Request) master port
    output logic m_ar_valid,
    input logic m_ar_ready,
    output logic [0:BURST_LEN_WIDTH-1] m_ar_len,
    output logic [0:ADDR_BITS-1] m_ar_addr,
    output logic [0:TID_WIDTH-1] m_ar_id,

    //AXI R (Read data) slave port
    output logic s_r_valid,
    input logic s_r_ready,
    output logic s_r_last,
    output logic [0:BLOCK_DATA_SIZE_BITS-1] s_r_data,
    output logic [0:TID_WIDTH-1] s_r_id,

    //AXI R (Read data) master port
    input logic m_r_valid,
    output logic m_r_ready,
    input logic m_r_last,
    input logic [0:BLOCK_DATA_SIZE_BITS-1]  m_r_data,
    input logic [0:TID_WIDTH-1] m_r_id, //todo check this always matches the stored tagId

    //AXI AW (Write Request) slave port
    input logic s_aw_valid,
    output logic s_aw_ready,
    input logic [0:BURST_LEN_WIDTH-1]s_aw_len,
    input logic [0:ADDR_BITS-1] s_aw_addr, 
    input logic [0:TID_WIDTH-1] s_aw_id,

    //AXI AW (Write Request) master port
    output logic m_aw_valid,
    input logic m_aw_ready,
    output logic [0:BURST_LEN_WIDTH-1] m_aw_len,
    output logic [0:ADDR_BITS-1] m_aw_addr,
    output logic [0:TID_WIDTH-1] m_aw_id,

    //CR Space
        // Ctrl
    input logic     [0:ADDR_BITS-1] bar,
    input logic     [0:ADDR_BITS-1] limit,
    input logic     [0:LOG_QUEUE_SIZE] windowSize,
    input logic     [0:WATCHDOG_SIZE-1] watchdogCnt, //the size of the counter that is used to divide the clk freq for the watchdog
        // Data
    input logic     [0:LOG_QUEUE_SIZE-1] crs_almostFullSpacer
);
    
logic ctrlFlush;
logic almostFull;
logic [0:LOG_QUEUE_SIZE] prefetchReqCnt;
logic pr_r_valid;
logic pr_r_in_last;
logic [0:BLOCK_DATA_SIZE_BITS-1] pr_r_in_data;
logic pr_addrHit;
logic pr_hasOutstanding;
logic [0:2] pr_opCode;
logic rangeHit;
logic dataFlushN;
logic prDataPath_resetN;
logic [0:BURST_LEN_WIDTH-1] burstLen;
logic [0:TID_WIDTH-1] tagId;
logic pr_r_out_last;
logic [0:BLOCK_DATA_SIZE_BITS-1] pr_r_out_data;
logic [0:ADDR_BITS-1] pr_addr;   
logic cleanup_st;
logic sel_pr; // select 0 - DDR direct, 1 - Prefetcher

logic ctrl_context_valid;
logic ctrl_s_ar_valid;
logic ctrl_s_ar_ready;
logic ctrl_m_ar_valid;
logic ctrl_m_ar_ready;
logic [0:BURST_LEN_WIDTH-1] ctrl_m_ar_len;
logic [0:ADDR_BITS-1] ctrl_m_ar_addr;
logic [0:TID_WIDTH-1] ctrl_m_ar_id;
logic ctrl_s_r_valid;
logic ctrl_s_r_ready;
logic ctrl_s_r_last;
logic [0:BLOCK_DATA_SIZE_BITS-1] ctrl_s_r_data;
logic [0:TID_WIDTH-1] ctrl_s_r_id;
logic ctrl_m_r_valid;
logic ctrl_m_r_ready;

// prefetcher data - queue which stores all the data that is prefetched
  prefetcherData #(
    .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
    .LOG_BLOCK_DATA_BYTES(LOG_BLOCK_DATA_BYTES),
    .ADDR_BITS(ADDR_BITS), 
    .PROMISE_WIDTH(PROMISE_WIDTH),
    .BURST_LEN_WIDTH(BURST_LEN_WIDTH)
  ) prDataPath (
    // inputs
    .clk(clk), 
    .resetN(resetN), 
    .reqAddr(pr_addr), 
    .reqBurstLen(burstLen), 
    .reqData(m_r_data), 
    .reqLast(m_r_last) , 
    .reqOpcode(pr_opCode), 
    .crs_almostFullSpacer(crs_almostFullSpacer),
    // outputs
    .respData(pr_r_out_data), 
    /*.respAddr(),*/ 
    .respLast(pr_r_out_last), 
    .addrHit(pr_addrHit),
    .pr_r_valid(pr_r_valid), 
    .prefetchReqCnt(prefetchReqCnt), 
    .almostFull(almostFull), 
    .errorCode(),
    .hasOutstanding(pr_hasOutstanding)
);

// prefetcher controller

prefetcherCtrl #(
    .ADDR_BITS(ADDR_BITS),
    .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
    .WATCHDOG_SIZE(WATCHDOG_SIZE),
    .LOG_BLOCK_DATA_BYTES(LOG_BLOCK_DATA_BYTES),
    .BURST_LEN_WIDTH(BURST_LEN_WIDTH),
    .TID_WIDTH(TID_WIDTH)
) prCtrlPath (
    .clk(clk), 
    .en(en), 
    .resetN(resetN), 
    .ctrlFlush(ctrlFlush), 
    .almostFull(almostFull), 
    .prefetchReqCnt(prefetchReqCnt), 
    .pr_r_valid(pr_r_valid), 
    .pr_r_in_last(pr_r_in_last), 
    .pr_r_in_data(pr_r_in_data), 
    .pr_addrHit(pr_addrHit), 
    .pr_hasOutstanding(pr_hasOutstanding), 
    .pr_r_out_last(pr_r_out_last), 
    .pr_r_out_data(pr_r_out_data), 
    .pr_addr(pr_addr), 
    .pr_opCode(pr_opCode), 
    .rangeHit(rangeHit), 
    .burstLen(burstLen), 
    .tagId(tagId),
    .dataFlushN(dataFlushN), 
    .isCleanup(cleanup_st),
    .context_valid(ctrl_context_valid),
    .s_ar_valid(ctrl_s_ar_valid),
    .s_ar_ready(ctrl_s_ar_ready), 
    .s_ar_len(s_ar_len),
    .s_ar_addr(s_ar_addr),  
    .s_ar_id(s_ar_id), 
    .m_ar_valid(ctrl_m_ar_valid), 
    .m_ar_ready(ctrl_m_ar_ready), 
    .m_ar_len(ctrl_m_ar_len), 
    .m_ar_addr(ctrl_m_ar_addr), 
    .m_ar_id(ctrl_m_ar_id), 
    .s_r_valid(ctrl_s_r_valid), 
    .s_r_ready(ctrl_s_r_ready), 
    .s_r_last(ctrl_s_r_last), 
    .s_r_data(ctrl_s_r_data), 
    .s_r_id(ctrl_s_r_id), 
    .m_r_valid(ctrl_m_r_valid), 
    .m_r_ready(ctrl_m_r_ready),
    // .m_r_last(), 
    // .m_r_data(), 
    .m_r_id(m_r_id),
    .bar(bar), 
    .limit(limit), 
    .windowSize(windowSize), 
    .watchdogCnt(watchdogCnt)
);

always_comb begin
    prDataPath_resetN = resetN & dataFlushN;
    sel_ar_pr = ~s_ar_valid | cleanup_st | (s_ar_valid & (s_ar_addr >= bar & s_ar_addr <= limit)) | ctrl_m_ar_valid;
    sel_r_pr = ~m_r_valid | (m_r_valid & (ctrl_context_valid & (tagId == m_r_id))) | ctrl_s_r_valid;
    ctrlFlush = (s_ar_valid & (~(s_ar_addr >= bar & s_ar_addr <= limit) & (ctrl_context_valid & tagId == s_ar_id))) //ReadReq outside limits but same tag
                | (s_aw_valid & ((s_ar_addr >= bar & s_ar_addr <= limit) | (ctrl_context_valid & tagId == s_ar_id))); //WriteReq in limits or same tag

    if(sel_ar_pr) begin
        //Path: Master-Prefetcher-Slave
        s_ar_ready = ctrl_s_ar_ready;
        ctrl_s_ar_valid = s_ar_valid & pr_ar_relevant;
        
        ctrl_m_ar_ready = m_ar_ready;
        m_ar_valid = ctrl_m_ar_valid;
        m_ar_len = ctrl_m_ar_len;
        m_ar_addr = ctrl_m_ar_addr;
        m_ar_id = ctrl_m_ar_id;
    end else begin
        //Path: Master-Slave
        ctrl_m_ar_ready = 1'b0;
        ctrl_s_ar_valid = 1'b0;

        s_ar_ready = m_ar_ready;
        m_ar_valid = s_ar_valid;
        m_ar_len = s_ar_len;
        m_ar_addr = s_ar_addr;
        m_ar_id = s_ar_id;
    end

    if(sel_r_pr) begin
        //Path: Master-Prefetcher-Slave
        m_r_ready = ctrl_m_r_ready;
        ctrl_m_r_valid = m_r_valid & pr_r_relevant;

        ctrl_s_r_ready = s_r_ready;
        s_r_valid = ctrl_s_r_valid;
        s_r_last = pr_r_out_last;
        s_r_data = pr_r_out_data;
        s_r_id = ctrl_s_r_id;
    end else begin
        //Path: Master-Slave
        ctrl_s_r_ready = 1'b0;
        ctrl_m_r_valid = 1'b0;

        m_r_ready = s_r_ready;
        s_r_valid = m_r_valid;
        s_r_last = m_r_last;
        s_r_data = m_r_data;
        s_r_id = m_r_id;
    end
end
