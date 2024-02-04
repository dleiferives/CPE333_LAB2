`ifndef MEMORY
`define MEMORY

module ParamMemory
#(
    parameter int DELAY_MEM,         // In Cycles
    parameter int DELAY_PAGE_HIT,    // In Cycles
    parameter int BURST_LEN,         // Integer
    parameter int CACHE_LINE_WIDTH,  // In Bits
    parameter int PAGE_SIZE,          // In Bytes
    parameter int USE_STROBE         // Binary
)
(
    mem_itf.device itf
);

localparam int BURST_WIDTH = CACHE_LINE_WIDTH / BURST_LEN;
localparam int ADDRLEN = 32;
localparam int CARELEN = ADDRLEN - $clog2(CACHE_LINE_WIDTH / 8);
localparam logic [ADDRLEN-1:0] mask = {{(CARELEN){1'b1}},
                                       {(ADDRLEN-CARELEN){1'b0}}};
localparam ACTUAL_WIDTH=14;  //32KB     16K x 32

int signed pageno=-1;

logic [CACHE_LINE_WIDTH-1:0] _mem [ACTUAL_WIDTH-1:0];

//Load program into memory

initial begin
    if(USE_STROBE)
        $readmemh("otter_memory.mem", _mem, 0, 2**ACTUAL_WIDTH-1);
    else
        $readmemh("otter_memory_blocks.mem", _mem);
end


enum int unsigned
{ IDLE, DELAY, READ_BURST, WRITE_BURST, DONE } state, next_state;

logic cnt_en,cnt_clr,mread,mwrite,mresp;
logic [7:0] cnt=0;
logic [ADDRLEN-1:0] _addr;
logic [31:0] _read_loc;

always_ff @(posedge itf.clk)    begin
        state <= next_state;
        if(cnt_clr) cnt<=0;
        else if(cnt_en) cnt <= cnt+1;
        if(itf.rst) begin  cnt<=0; state<=IDLE; end
        
        itf.mem_resp <= mresp;
        if(mread) itf.mem_rdata <= _mem[_read_loc][BURST_WIDTH*cnt +: BURST_WIDTH];
        if(mwrite)   begin 
                        if(USE_STROBE) begin
                                for (int j = 0; j < 4; ++j) begin
                                    if (itf.mem_byte_enable[j])
                                        _mem[_read_loc][8*j +: 8] <= itf.mem_wdata[8*j +: 8]; 
                                end
                            end else
                                _mem[_read_loc][BURST_WIDTH*cnt +: BURST_WIDTH] <= itf.mem_wdata;
        end      
end



always_comb begin
            int signed _pageno;
            int delay;
 
            _addr = itf.mem_address & mask;
            _read_loc = _addr / (CACHE_LINE_WIDTH / 8);
            _pageno = itf.mem_address / PAGE_SIZE;
            delay = DELAY_MEM; //_pageno == pageno ? DELAY_PAGE_HIT : DELAY_MEM;
            pageno = _pageno;
            
            cnt_clr=0;
            cnt_en=0;
            mread=0;
            mwrite=0;
            mresp=0;
                
            case(state) 
            IDLE: begin     cnt_clr=1;
                            if(itf.mem_read || itf.mem_write) next_state = DELAY;
                            else next_state = IDLE;
                  end
            DELAY: begin    cnt_en=1;
                            next_state=DELAY;
                            if(cnt == delay && itf.mem_read) begin cnt_clr=1; next_state=READ_BURST; end
                            if(cnt == delay && itf.mem_write) begin cnt_clr=1; next_state=WRITE_BURST; end
                   end
            READ_BURST: begin
                            cnt_en=1;
                            mread=1;
                            if(cnt==BURST_LEN) next_state=DONE;
                            else begin next_state=READ_BURST;
                                       mresp=1;
                            end
                        end
            WRITE_BURST: begin
                            cnt_en=1;
                            mwrite=1;
                            mresp=1;                      
                            if(cnt==BURST_LEN) next_state=DONE;
                            else next_state=WRITE_BURST;
                         end
            DONE: begin     cnt_clr=1;
                            mresp = 1'b0;
                            next_state=IDLE;
                   end
            default: begin  cnt_clr=0; cnt_en=0; next_state=IDLE;
                     end
            endcase;
end             

endmodule

`endif