module Forwarding (
    input           [0:0]   rf_we_mem,
    input           [0:0]   rf_we_wb,
    input           [4:0]   rf_wa_mem,
    input           [4:0]   rf_wa_wb,
    input           [31:0]  rf_wd_mem,
    input           [31:0]  rf_wd_wb,
    input           [4:0]   rf_ra0_ex,
    input           [4:0]   rf_ra1_ex,
    input           [1:0]   rf_wd_sel_mem,
    
    input           [31:0]  dmem_rd_out_MEM,
    output   reg    [0:0]   f_rf_rd0_fe,
    output   reg    [0:0]   f_rf_rd1_fe,
    output   reg    [31:0]  f_rf_rd0_fd,
    output   reg    [31:0]  f_rf_rd1_fd,
    
    output   reg    [0:0]   rf_rd0_fe,
    output   reg    [0:0]   rf_rd1_fe,
    output   reg    [31:0]  rf_rd0_fd,
    output   reg    [31:0]  rf_rd1_fd


);

always @(*) begin
    case (rf_wd_sel_mem)
        2'b10:begin
            if(rf_we_mem && rf_wa_mem)begin
                if(rf_ra0_ex == rf_wa_mem)begin
                    f_rf_rd0_fe=1'b1;
                    f_rf_rd0_fd=dmem_rd_out_MEM;

                    rf_rd0_fe=1'b0;
                    rf_rd0_fd=32'h00000000;
                end
                else begin
                    f_rf_rd0_fe=1'b0;
                    f_rf_rd0_fd=32'h00000000;

                    rf_rd0_fe=1'b0;
                    rf_rd0_fd=32'h00000000;                    
                end

                if(rf_ra1_ex == rf_wa_mem)begin
                    f_rf_rd1_fe=1'b1;
                    f_rf_rd1_fd=dmem_rd_out_MEM;

                    rf_rd1_fe=1'b0;
                    rf_rd1_fd=32'h00000000;
                end
                else begin
                    f_rf_rd1_fe=1'b0;
                    f_rf_rd1_fd=32'h00000000;

                    rf_rd1_fe=1'b0;
                    rf_rd1_fd=32'h00000000;
                end
            end
            else begin              
                f_rf_rd0_fe=1'b0;
                f_rf_rd1_fe=1'b0;
                f_rf_rd0_fd=32'h00000000;
                f_rf_rd1_fd=32'h00000000;

                rf_rd0_fe=1'b0;
                rf_rd1_fe=1'b0;
                rf_rd0_fd=32'h00000000;
                rf_rd1_fd=32'h00000000;        
            end
        end
    
        default: begin
            if(rf_we_mem && rf_wa_mem)begin
                if(rf_ra0_ex == rf_wa_mem)begin
                    f_rf_rd0_fe=1'b0;
                    f_rf_rd0_fd=32'h00000000;
    
                    rf_rd0_fe=1'b1;
                    rf_rd0_fd=rf_wd_mem;
                end
                else if(rf_ra0_ex == rf_wa_wb)begin
                    f_rf_rd0_fe=1'b0;
                    f_rf_rd0_fd=32'h00000000;
    
                    rf_rd0_fe=1'b1;
                    rf_rd0_fd=rf_wd_wb;
                end
                else begin
                    f_rf_rd0_fe=1'b0;
                    f_rf_rd0_fd=32'h00000000;
    
                    rf_rd0_fe=1'b0;
                    rf_rd0_fd=32'h00000000;
                end

                if(rf_ra1_ex == rf_wa_mem)begin
                    f_rf_rd1_fe=1'b0;
                    f_rf_rd1_fd=32'h00000000;
    
                    rf_rd1_fe=1'b1;
                    rf_rd1_fd=rf_wd_mem;
                end
                else if(rf_ra1_ex == rf_wa_wb)begin
                    f_rf_rd1_fe=1'b0;
                    f_rf_rd1_fd=32'h00000000;
    
                    rf_rd1_fe=1'b1;
                    rf_rd1_fd=rf_wd_wb;
                end
                else begin
                    f_rf_rd1_fe=1'b0;
                    f_rf_rd1_fd=32'h00000000;
    
                    rf_rd1_fe=1'b0;
                    rf_rd1_fd=32'h00000000;
                end
            end
            else begin
                f_rf_rd0_fe=1'b0;
                f_rf_rd1_fe=1'b0;
                f_rf_rd0_fd=32'h00000000;
                f_rf_rd1_fd=32'h00000000;

                rf_rd0_fe=1'b0;
                rf_rd1_fe=1'b0;
                rf_rd0_fd=32'h00000000;
                rf_rd1_fd=32'h00000000;
            end                            
        end
    endcase
end

endmodule  

/*
if(rf_we_mem && rf_wa_mem && (rf_ra0_ex==rf_wa_mem))begin
                f_rf_rd0_fe=1'b0;
                f_rf_rd1_fe=1'b0;
                f_rf_rd0_fd=32'h00000000;
                f_rf_rd1_fd=32'h00000000;

                rf_rd0_fe=1'b1;
                rf_rd1_fe=1'b0;
                rf_rd0_fd=rf_wd_mem;
                rf_rd1_fd=32'h00000000;                                       
            end
            else if(rf_we_mem && rf_wa_mem && (rf_ra1_ex==rf_wa_mem))begin
                f_rf_rd0_fe=1'b0;
                f_rf_rd1_fe=1'b0;
                f_rf_rd0_fd=32'h00000000;
                f_rf_rd1_fd=32'h00000000;

                rf_rd0_fe=1'b0;
                rf_rd1_fe=1'b1;
                rf_rd0_fd=32'h00000000;
                rf_rd1_fd=rf_wd_mem;                                       
                end
            else if(rf_we_wb && rf_wa_wb && (rf_ra0_ex==rf_wa_wb))begin
                f_rf_rd0_fe=1'b0;
                f_rf_rd1_fe=1'b0;
                f_rf_rd0_fd=32'h00000000;
                f_rf_rd1_fd=32'h00000000;

                rf_rd0_fe=1'b1;
                rf_rd1_fe=1'b0;
                rf_rd0_fd=rf_wd_wb;
                rf_rd1_fd=32'h00000000;
            end
            else if(rf_we_wb && rf_wa_wb && (rf_ra1_ex==rf_wa_wb))begin
                f_rf_rd0_fe=1'b0;
                f_rf_rd1_fe=1'b0;
                f_rf_rd0_fd=32'h00000000;
                f_rf_rd1_fd=32'h00000000;

                rf_rd0_fe=1'b0;
                rf_rd1_fe=1'b1;
                rf_rd0_fd=32'h00000000;
                rf_rd1_fd=rf_wd_wb;
            end 
            else begin
                f_rf_rd0_fe=1'b0;
                f_rf_rd1_fe=1'b0;
                f_rf_rd0_fd=32'h00000000;
                f_rf_rd1_fd=32'h00000000;

                rf_rd0_fe=1'b0;
                rf_rd1_fe=1'b0;
                rf_rd0_fd=32'h00000000;
                rf_rd1_fd=32'h00000000;                    
            end
*/