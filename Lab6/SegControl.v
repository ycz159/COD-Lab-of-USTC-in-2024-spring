module SegCtrl (
    input   [0:0]   rf_we_ex,
    input   [1:0]   rf_wd_sel_ex,
    input   [4:0]   rf_wa_ex,
    input   [4:0]   rf_ra0_id,
    input   [4:0]   rf_ra1_id,
    input   [1:0]   npc_sel_ex,

    output  reg [0:0]   stall_pc,
    output  reg [0:0]   stall_if_id,
    output  reg [0:0]   flush_if_id,
    output  reg [0:0]   flush_id_ex
);
    
always @(*) begin
    if(npc_sel_ex==2'b00)begin//Load-Use Hazard
        if(rf_wd_sel_ex==2'b10 && rf_we_ex && rf_wa_ex && (rf_ra0_id==rf_wa_ex || rf_ra1_id==rf_wa_ex))begin
            stall_pc    =1'b1;
            stall_if_id =1'b1;
            flush_if_id =1'b0;
            flush_id_ex =1'b1;
        end
        else begin
            stall_pc    =1'b0;
            stall_if_id =1'b0;
            flush_if_id =1'b0;
            flush_id_ex =1'b0;
        end
    end
    else begin              //Control Hazard
        stall_pc    =1'b0;
        stall_if_id =1'b0;
        flush_if_id =1'b1;
        flush_id_ex =1'b1;
    end
end



endmodule