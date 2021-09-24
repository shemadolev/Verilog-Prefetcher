//Notes: On flush, reset the stride FSM; If stride changes, do nothing (if we'll get hit in MOQ, blocks will pop out, else timeout will expire)

module prefetcherTop(
    
    input logic     clk,            //<i
    input logic     en,             //<i
    input logic     resetN,         //<i
    input logic     [0:ADDR_BITS-1] inAddrReq,      //<i
    input logic     inOpcode,       // 1'b0 - read, 1'b1 - write  
    input logic     [0:-] maxOutstandingReqs,
    input logic     [0:ADDR_BITS-1] bar,
    input logic     [0:ADDR_BITS-1] limit,


    output logic    
);

//////////////////////////////////////////////////////////////////////////////////////////////
output  reg   [0:ADDR_BITS-1] currentStride

parameter ADDR_BITS = 64; //64bit address 2^64
reg [0:ADDR_BITS-1] lastAddr, suspectedStride;
wire [0:ADDR_BITS-1] actualStride, nxtSuspectedStride;
wire hit, trigger, stay;

//FSM States
parameter s_idle = 2'b00, s_suspect = 2'b01, s_update = 2'b10;
reg [1:0] curState;
wire [1:0] nxtState;

always @(posedge clk or negedge resetN) begin
	if(!resetN)	begin
		curState <= s_idle;
        currentStride <= 0;
        suspectedStride <= 0;
        lastAddr <= 0;
	end
	else begin
        if(en) begin
            curState <= nxtState;
            lastAddr <= currentAddr;
            suspectedStride <= nxtSuspectedStride;
            if(curState == s_update)
                currentStride <= suspectedStride;
        end
    end
end

assign actualStride = currentAddr - lastAddr; //TODO: Check if this FSM handles a case of a negative stride.
assign stay = (actualStride == 0);
assign hit = (suspectedStride == actualStride);
assign trigger = ((actualStride != currentStride) && (lastAddr != 0)); //(lastAddr != 0), to skip the first mem access (no stride yet)

//Next state comb' logic
always @(curState or trigger or suspectedStride or actualStride or hit) begin    
    nxtSuspectedStride = suspectedStride;
    nxtState = curState;
    case curState:
        s_idle: begin
            if(trigger) begin
                nxtState = s_suspect;
                nxtSuspectedStride = actualStride;
            end
        end
        s_suspect: begin
            if(!stay) begin
                if(hit)
                    nxtState = s_update;
                else
                    nxtState = s_idle;
            end
        end
        s_update: begin
            nxtState = s_idle;
        end
    endcase
end

endmodule