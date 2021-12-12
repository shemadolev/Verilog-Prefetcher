
`ifndef PRINT_SVH_
`define PRINT_SVH_

`define printTop(MOD) \
    $display("------- BEGIN Top --------"); \
    $display("  sel_ar_pr %b",MOD.sel_ar_pr); \
    $display("  sel_r_pr %b",MOD.sel_r_pr); \
    $display("  ctrlFlush %b",MOD.ctrlFlush); \
    $display("------- END Top --------")

`define printData(MOD)  \
    $display("------- BEGIN Data --------"); \
    $display("  opCode %d",MOD.reqOpcode); \
    $display("  almostFull %b",MOD.almostFull); \
    $display("  errorCode %d",MOD.errorCode); \
    $display("  prefetchReqCnt %d",MOD.prefetchReqCnt); \
    $display("  head:%d tail:%d validCnt:%d isEmpty:%d isFull:%d",MOD.headPtr, MOD.tailPtr, MOD.validCnt, MOD.isEmpty, MOD.isFull); \
    $display("  hasOutstanding:%b burstOffset:%d readDataPtr:%d",MOD.hasOutstanding, MOD.burstOffset, MOD.readDataPtr); \
    $display(" ** Requset signal **"); \
    $display("   addrHit:%d addrIdx:%d", MOD.addrHit, MOD.addrIdx); \
    for(int i=0;i<MOD.QUEUE_SIZE;i++) begin \
        $display("--Block           %d ",i); \
        if(MOD.headPtr == i) \
            $display(" ^^^ HEAD ^^^"); \
        if(MOD.tailPtr == i) \
            $display(" ^^^ TAIL ^^^"); \
        $display("  valid           %d",MOD.validVec[i]); \
        if(MOD.validVec[i]) begin \
            $display("  addrValid       %b",MOD.addrValid[i]); \
            if(MOD.addrValid[i]) begin \
                $display("  address         0x%h",MOD.blockAddrMat[i]); \
                $display("  prefetchReq     %b",MOD.prefetchReqVec[i]); \
                $display("  promiseCnt      %d",MOD.promiseCnt[i]); \
            end \
            $display("  data valid      %d",MOD.dataValidVec[i]); \
            if(MOD.dataValidVec[i]) begin \
                $display("  data            0x%h",MOD.dataMat[i]); \
                $display("  last            0x%h",MOD.lastVec[i]); \
            end \
        end \
    end \
    $display(" ** Resp data **"); \
    $display(" pr_r_valid:%b respData:0x%h respLast:%b", MOD.pr_r_valid, MOD.respData, MOD.respLast); \
    $display("------- END Data --------")

`define printCtrl(MOD)  \
    $display("------- BEGIN Control --------"); \
    $display("  en %b",MOD.en); \
    $display("  st_pr_cur \t%s",MOD.st_pr_cur.name); \
    $display("  st_exec_cur \t%s",MOD.st_exec_cur.name); \
    $display("  pr_opCode %d",MOD.pr_opCode); \
    $display("  pr_context_valid %b",MOD.pr_context_valid); \
    $display("  stride_sampled 0x%h",MOD.stride_sampled); \
    $display("  valid_burst %b",MOD.valid_burst); \
    if(MOD.stride_learned) \
        $display("  stride_reg 0x%h",MOD.stride_reg); \
        $display("  bar 0x%h, limit 0x%h",MOD.bar, MOD.limit); \
    if(MOD.pr_context_valid == 1) begin \
        $display("  pr_m_ar_len %d",MOD.pr_m_ar_len); \
        $display("  pr_m_ar_id %d",MOD.pr_m_ar_id); \
    end \
    $display("  prefetchAddr_valid %b",MOD.prefetchAddr_valid); \
    if(MOD.prefetchAddr_valid) \
        $display("  prefetchAddr_reg 0x%h",MOD.prefetchAddr_reg); \
    $display("------- END Control --------")


`endif