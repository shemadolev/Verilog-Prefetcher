//Notes: On flush, reset the stride FSM; If stride changes, do nothing (if we'll get hit in MOQ, blocks will pop out, else timeout will expire)

//Assumptions:
// * When any _valid is up, the data (and meta-data, such as 'id') doesn't change.

`resetall
`timescale 1ns / 1ps

module prefetcherTop #(
    parameter ADDR_BITS = 64, //64bit address 2^64
    parameter LOG_QUEUE_SIZE = 3'd6, // the size of the queue [2^x] 
    parameter WATCHDOG_SIZE = 10'd10, // number of bits for the watchdog counter
    parameter PRFETCH_FRQ_WIDTH = 3'd6,
    parameter BURST_LEN_WIDTH = 4'd8, //NVDLA max is 3, AXI4 supports up to 8 bits
    parameter TID_WIDTH = 4'd8, //NVDLA max is 3, AXI4 supports up to 8 bits
    parameter LOG_BLOCK_DATA_BYTES = 3'd6, //[Bytes]
    parameter PROMISE_WIDTH = 3'd3, // the log size of the promise's counter
    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3 //shift left by 3 to convert Bytes->bits
)(
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
    input logic [0:TID_WIDTH-1] m_r_id,

    //AXI AW (Write Request) slave port
    input logic s_aw_valid,
    output logic s_aw_ready,
    // input logic [0:BURST_LEN_WIDTH-1] s_aw_len,
    input logic [0:ADDR_BITS-1] s_aw_addr,
    input logic [0:TID_WIDTH-1] s_aw_id,

    //AXI AW (Write Request) master port
    output logic m_aw_valid,
    input logic m_aw_ready,
    // output logic [0:BURST_LEN_WIDTH-1] m_aw_len,
    // output logic [0:ADDR_BITS-1] m_aw_addr,
    // output logic [0:TID_WIDTH-1] m_aw_id,

    //CR Space
        // Ctrl
    input logic     [0:ADDR_BITS-1] crs_bar,
    input logic     [0:ADDR_BITS-1] crs_limit,
    input logic     [0:LOG_QUEUE_SIZE] crs_prOutstandingLimit,
    input logic     [0:WATCHDOG_SIZE-1] crs_watchdogCnt, //the size of the counter that is used to divide the clk freq for the watchdog
    input logic     [0:PRFETCH_FRQ_WIDTH-1] crs_prBandwidthThrottle,
        // Data
    input logic     [0:LOG_QUEUE_SIZE-1] crs_almostFullSpacer,

    output logic    [0:2] errorCode
);
    
logic ctrlFlush;
logic pr_almostFull;
logic [0:LOG_QUEUE_SIZE] prefetchReqCnt;
logic pr_r_valid;
logic pr_addrHit;
logic pr_hasOutstanding;
logic [0:2] pr_opCode;
logic pr_flush;
logic prDataPath_resetN;
logic [0:BURST_LEN_WIDTH-1] pr_m_ar_len;
logic [0:TID_WIDTH-1] pr_m_ar_id;
logic pr_r_out_last;
logic [0:BLOCK_DATA_SIZE_BITS-1] pr_r_out_data;
logic [0:ADDR_BITS-1] pr_m_ar_addr;
logic cleanup_st;
logic sel_r_pr, sel_ar_pr; // select 0 - DDR direct, 1 - Prefetcher

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
logic [0:TID_WIDTH-1] ctrl_s_r_id;
logic ctrl_m_r_valid;
logic ctrl_m_r_ready;

// prefetcher data - queue which stores all the data that is prefetched
  prefetcherData #(
    .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
    .LOG_BLOCK_DATA_BYTES(LOG_BLOCK_DATA_BYTES),
    .ADDR_BITS(ADDR_BITS), 
    .PROMISE_WIDTH(PROMISE_WIDTH)
  ) prDataPath (
    // inputs
    .clk(clk), 
    .resetN(prDataPath_resetN), 
    .reqAddr(pr_m_ar_addr), 
    .reqBurstLen(pr_m_ar_len[(BURST_LEN_WIDTH-LOG_QUEUE_SIZE) +: LOG_QUEUE_SIZE]), 
    .reqData(m_r_data), 
    .reqLast(m_r_last) , 
    .reqOpcode(pr_opCode), 
    .crs_almostFullSpacer(crs_almostFullSpacer),
    // outputs
    .respData(pr_r_out_data),
    .respLast(pr_r_out_last),//fixme
    .addrHit(pr_addrHit),
    .pr_r_valid(pr_r_valid), 
    .prefetchReqCnt(prefetchReqCnt), 
    .almostFull(pr_almostFull), 
    .errorCode(errorCode),
    .hasOutstanding(pr_hasOutstanding)
);

// prefetcher controller

prefetcherCtrl #(
    .ADDR_BITS(ADDR_BITS),
    .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
    .WATCHDOG_SIZE(WATCHDOG_SIZE),
    .BURST_LEN_WIDTH(BURST_LEN_WIDTH),
    .TID_WIDTH(TID_WIDTH)
) prCtrlPath (
    .clk(clk), 
    .en(en), 
    .resetN(resetN), 
    .ctrlFlush(ctrlFlush), 
    .pr_flush(pr_flush), 
    .pr_opCode(pr_opCode), 
    .pr_addrHit(pr_addrHit), 
    .pr_hasOutstanding(pr_hasOutstanding), 
    .pr_reqCnt(prefetchReqCnt), 
    .pr_almostFull(pr_almostFull), 
    .pr_isCleanup(cleanup_st),
    .pr_context_valid(ctrl_context_valid),
    .pr_r_valid(pr_r_valid), 
    .pr_m_ar_addr(pr_m_ar_addr), 
    .pr_m_ar_len(pr_m_ar_len), 
    .pr_m_ar_id(pr_m_ar_id),
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
    .s_r_id(ctrl_s_r_id), 
    .m_r_valid(ctrl_m_r_valid), 
    .m_r_ready(ctrl_m_r_ready),
    .m_r_id(m_r_id),
    .crs_bar(crs_bar), 
    .crs_limit(crs_limit), 
    .crs_prOutstandingLimit(crs_prOutstandingLimit), 
    .crs_watchdogCnt(crs_watchdogCnt),
    .crs_prBandwidthThrottle(crs_prBandwidthThrottle)
);

always_comb begin
    prDataPath_resetN = resetN & ~pr_flush;
    ctrlFlush = (s_ar_valid & (~(s_ar_addr >= crs_bar & s_ar_addr <= crs_limit) & (ctrl_context_valid & pr_m_ar_id == s_ar_id))) //ReadReq outside limits but same tag
                | (s_aw_valid & ((s_aw_addr >= crs_bar & s_aw_addr <= crs_limit) | (ctrl_context_valid & pr_m_ar_id == s_aw_id))); //WriteReq in limits or same tag
    //todo When checking (_addr <= crs_limit), _len should also be considered
    sel_ar_pr = ~s_ar_valid | cleanup_st | ctrlFlush | (s_ar_valid & (s_ar_addr >= crs_bar & s_ar_addr <= crs_limit)) | ctrl_m_ar_valid; //todo consider removing the 'cleanup' condition, to enable req's with other IDs
    sel_r_pr = ~m_r_valid | (m_r_valid & (ctrl_context_valid & (pr_m_ar_id == m_r_id))) | ctrl_s_r_valid;

    if(s_aw_valid && ctrl_context_valid && ((pr_m_ar_id == s_aw_id) || (s_aw_addr >= crs_bar && s_aw_addr <= crs_limit))) begin
        ctrlFlush = 1'b1; //This stops the controller from sending ar_ready=1 to the master
        //Block AW channel until cleanup is done
        s_aw_ready = 1'b0;
        m_aw_valid = 1'b0;
    end else begin
        s_aw_ready = m_aw_ready;
        m_aw_valid = s_aw_valid;
    end

    if(sel_ar_pr) begin
        //Path: Master-Prefetcher-Slave
        s_ar_ready = ctrl_s_ar_ready;
        ctrl_s_ar_valid = s_ar_valid;
        
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
        ctrl_m_r_valid = m_r_valid;

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
endmodule
`resetall
