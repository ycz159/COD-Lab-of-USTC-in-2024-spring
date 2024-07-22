module Interval_Reg (
    input                  [ 0 : 0]            rst,
    input                  [ 0 : 0]            en,
    input                  [ 0 : 0]            flush,
    input                  [ 0 : 0]            stall,
    input                  [ 0 : 0]            clk,
    //pc
    input                  [31 : 0]            i_pc_out,
    input                  [31 : 0]            i_pc_out_add4,
    input                  [31 : 0]            i_inst,
    //decoder
    input                  [ 4 : 0]            i_rf_ra0,
    input                  [ 4 : 0]            i_rf_ra1,
    input                  [ 4 : 0]            i_alu_op,
    input                  [ 3 : 0]            i_dmem_access,
    input                  [31 : 0]            i_imm,
    input                  [ 4 : 0]            i_rf_wa,
    input                  [ 0 : 0]            i_rf_we,
    input                  [ 1 : 0]            i_rf_wd_sel,
    input                  [ 0 : 0]            i_alu_src0_sel,
    input                  [ 0 : 0]            i_alu_src1_sel,
    input                  [ 3 : 0]            i_br_type,
    //RegFile
    input                   [31 : 0]           i_rf_rd0,
    input                   [31 : 0]           i_rf_rd1,
    input                   [ 4 : 0]           i_dbg_reg_ra,
    input                   [31 : 0]           i_dbg_reg_rd,
    //ALU
    input                   [31 : 0]           i_alu_res,
    //SLU
    input                   [31 : 0]           i_dmem_rd_out,
    //commit
    input                   [ 0 : 0]           i_commit,



    output                  [31 : 0]           o_pc_out,
    output                  [31 : 0]           o_pc_out_add4,
    output                  [31 : 0]           o_inst,
    //decoder
    output                  [ 4 : 0]           o_rf_ra0,
    output                  [ 4 : 0]           o_rf_ra1,    
    output                  [ 4 : 0]           o_alu_op,
    output                  [ 3 : 0]           o_dmem_access,
    output                  [31 : 0]           o_imm,
    output                  [ 4 : 0]           o_rf_wa,
    output                  [ 0 : 0]           o_rf_we,
    output                  [ 1 : 0]           o_rf_wd_sel,
    output                  [ 0 : 0]           o_alu_src0_sel,
    output                  [ 0 : 0]           o_alu_src1_sel,
    output                  [ 3 : 0]           o_br_type,
    //RegFile
    output                   [31 : 0]          o_rf_rd0,
    output                   [31 : 0]          o_rf_rd1,
    output                   [ 4 : 0]          o_dbg_reg_ra,
    output                   [31 : 0]          o_dbg_reg_rd,
    //ALU
    output                   [31 : 0]          o_alu_res,
    //SLU
    output                   [31 : 0]          o_dmem_rd_out,
    //commit
    output                   [ 0 : 0]          o_commit
);

    reg                  [31 : 0]            pc_out;
    reg                  [31 : 0]            pc_out_add4;
    reg                  [31 : 0]            inst;
    //decoder
    reg                  [ 4 : 0]            rf_ra0;
    reg                  [ 4 : 0]            rf_ra1;    
    reg                  [ 4 : 0]            alu_op;
    reg                  [ 3 : 0]            dmem_access;
    reg                  [31 : 0]            imm;
    reg                  [ 4 : 0]            rf_wa;
    reg                  [ 0 : 0]            rf_we;
    reg                  [ 1 : 0]            rf_wd_sel;
    reg                  [ 0 : 0]            alu_src0_sel;
    reg                  [ 0 : 0]            alu_src1_sel;
    reg                  [ 3 : 0]            br_type;
    //RegFile
    reg                   [31 : 0]           rf_rd0;
    reg                   [31 : 0]           rf_rd1;
    reg                   [ 4 : 0]           dbg_reg_ra;
    reg                   [31 : 0]           dbg_reg_rd;
    //ALU
    reg                   [31 : 0]           alu_res;
    //SLU
    reg                   [31 : 0]           dmem_rd_out;
    //commit
    reg                   [ 0 : 0]           commit;

    assign o_pc_out=pc_out;
    assign o_pc_out_add4=pc_out_add4;
    assign o_inst=inst;

    assign o_rf_ra0=rf_ra0;
    assign o_rf_ra1=rf_ra1;
    assign o_alu_op=alu_op;
    assign o_dmem_access=dmem_access;
    assign o_imm=imm;
    assign o_rf_wa=rf_wa;
    assign o_rf_we=rf_we;
    assign o_rf_wd_sel=rf_wd_sel;
    assign o_alu_src0_sel=alu_src0_sel;
    assign o_alu_src1_sel=alu_src1_sel;
    assign o_br_type=br_type;

    assign o_rf_rd0=rf_rd0;
    assign o_rf_rd1=rf_rd1;
    assign o_dbg_reg_ra=dbg_reg_ra;
    assign o_dbg_reg_rd=dbg_reg_rd;

    assign o_alu_res=alu_res;
    assign o_dmem_rd_out=dmem_rd_out;

    assign o_commit=commit;

always @(posedge clk) begin
    if (rst) begin
        // rst 操作的逻辑
        pc_out<=32'h00000000;
        pc_out_add4<=32'h00000000;
        inst<=32'h00000000;
        //decoder
        rf_ra0<=5'b00000;
        rf_ra1<=5'b00000;
        alu_op<=5'b00000;
        dmem_access<=4'hf;
        imm<=32'h00000000;
        rf_wa<=5'b00000;
        rf_we<=1'b0;
        rf_wd_sel<=2'b00;
        alu_src0_sel<=1'b0;
        alu_src1_sel<=1'b0;
        br_type<=4'b0000;
        //RegFile
        rf_rd0<=32'h00000000;
        rf_rd1<=32'h00000000;
        dbg_reg_ra<=5'b00000;
        dbg_reg_rd<=32'h00000000;
        //ALU
        alu_res<=5'b00000;
        //SLU
        dmem_rd_out<=32'h00000000;
        //commit
        commit<=1'b0;
    end
    else if (en) begin
        // flush 和 stall 操作的逻辑, flush 的优先级更高
        if(flush)begin
            pc_out<=32'h00000000;
            pc_out_add4<=32'h00000000;
            inst<=32'h00000000;
            //decoder
            rf_ra0<=5'b00000;
            rf_ra1<=5'b00000;            
            alu_op<=5'b00000;
            dmem_access<=4'hf;
            imm<=32'h00000000;
            rf_wa<=5'b00000;
            rf_we<=1'b0;
            rf_wd_sel<=2'b00;
            alu_src0_sel<=1'b0;
            alu_src1_sel<=1'b0;
            br_type<=4'b0000;
            //RegFile
            rf_rd0<=32'h00000000;
            rf_rd1<=32'h00000000;
            dbg_reg_ra<=5'b00000;
            dbg_reg_rd<=32'h00000000;
            //ALU
            alu_res<=5'b00000;
            //SLU
            dmem_rd_out<=32'h00000000;
            //commit
            commit<=1'b0;
        end
        else if(stall)begin
            pc_out<=pc_out;
            pc_out_add4<=pc_out_add4;
            inst<=inst;
            //decoder
            rf_ra0<=rf_ra0;
            rf_ra1<=rf_ra1;            
            alu_op<=alu_op;
            dmem_access<=dmem_access;
            imm<=imm;
            rf_wa<=rf_wa;
            rf_we<=rf_we;
            rf_wd_sel<=rf_wd_sel;
            alu_src0_sel<=alu_src0_sel;
            alu_src1_sel<=alu_src1_sel;
            br_type<=br_type;
            //RegFile
            rf_rd0<=rf_rd0;
            rf_rd1<=rf_rd1;
            dbg_reg_ra<=dbg_reg_ra;
            dbg_reg_rd<=dbg_reg_rd;
            //ALU
            alu_res<=alu_res;
            //SLU
            dmem_rd_out<=dmem_rd_out;
            //commit
            commit<=commit;
        end
        else begin
            pc_out<=i_pc_out;
            pc_out_add4<=i_pc_out_add4;
            inst<=i_inst;
            //decoder
            rf_ra0<=i_rf_ra0;
            rf_ra1<=i_rf_ra1;            
            alu_op<=i_alu_op;
            dmem_access<=i_dmem_access;
            imm<=i_imm;
            rf_wa<=i_rf_wa;
            rf_we<=i_rf_we;
            rf_wd_sel<=i_rf_wd_sel;
            alu_src0_sel<=i_alu_src0_sel;
            alu_src1_sel<=i_alu_src1_sel;
            br_type<=i_br_type;
            //RegFile
            rf_rd0<=i_rf_rd0;
            rf_rd1<=i_rf_rd1;
            dbg_reg_ra<=i_dbg_reg_ra;
            dbg_reg_rd<=i_dbg_reg_rd;
            //ALU
            alu_res<=i_alu_res;
            //SLU
            dmem_rd_out<=i_dmem_rd_out;
            //commit
            commit<=i_commit;
        end
    end
end

endmodule