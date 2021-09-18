//Notes: On flush, reset the stride FSM; If stride changes, do nothing (if we'll get hit in MOQ, blocks will pop out, else timeout will expire)

module prefetcherCtrl(
    
    input logic     clk,           
    input logic     en,            
    input logic     resetN,        
    input logic     inAddrReqValid, //valid only on read req (given by the top) write reqs aren't relevant for this module
    input logic     [0:ADDR_BITS-1] inAddrReq,
    input logic     [0:ADDR_BITS-1] bar,
    input logic     [0:ADDR_BITS-1] limit,
    input logic     addrReqHit, //data path output logic valid

    output logic    rangeHit, //indicates that the request is the prefetcher range
    output logic    prefetchedAddrValid,
    output logic    [0:ADDR_BITS-1] prefetchedAddr,
    output logic    flushN //control bit to flush the queue
    //TODO add almost max outstanding requests
    //TODO add almost full
);

parameter ADDR_BITS = 64; //64bit address 2^64
parameter LOG_OUTSTAND_REQS = 3'd6; //64bit address 2^64

logic   [0:ADDR_BITS-1] currentStride;
logic   [0:ADDR_BITS-1] storedStride;
logic   [0:ADDR_BITS-1] nxtStride;
logic   [0:ADDR_BITS-1] lastAddr;
logic   strideHit, trigger;

//FSM States
enum logic [1:0] {s_idle=2'b00, s_arm=2'b01, s_active=2'b10} curState, nxtState;

always_ff (posedge clk or negedge resetN) begin
	if(!resetN)	begin
		curState <= s_idle;
        storedStride <= (ADDR_BITS)'d0;
        lastAddr <= (ADDR_BITS)'d0;
        flushN <= 1'b1; 
	end
	else begin
        if(en) begin
            curState <= nxtState;
            lastAddr <= inAddrReq;
            storedStride <= nxtStride;
            flushN <= 1'b1;    
            if(curState == s_active) begin 
                if(!strideHit)
                    flushN <= 1'b0;
            end
        end
    end
end

//Next state comb' logic
always_comb begin
    nxtState = curState;
    nxtStride = storedStride;
    case curState:
        s_idle: begin
            if(trigger) begin
                nxtState = s_arm;
            end
        end
        s_arm: begin
            if((currentStride != (ADDR_BITS)'d0) && inAddrReqValid) begin
                nxtState = s_active;
                nxtStride = currentStride;
            end
        end
        s_active: begin
            if(strideHit || currentStride==(ADDR_BITS)'d0) begin
                nxtState = s_active;
            end
            else begin 
                nxtState = s_arm;
            end
        end
    endcase
end

// signals assignment
assign rangeHit = (inAddrReq >= bar) && (inAddrReq <= limit)
assign currentStride = inAddrReq - lastAddr; //TODO: Check if this FSM handles a case of a negative stride.
assign trigger = inAddrReq != (ADDR_BITS-1)'d0; //first valid address
assign strideHit = (storedStride == currentStride) && inAddrReqValid;

endmodule