////////////////////////////////////////////////////////////////////////////////
// Company:        IIS @ ETHZ - Federal Institute of Technology               //
//                 DEI @ UNIBO - University of Bologna                        //
//                                                                            //
// Engineer:       Renzo Andri - andrire@student.ethz.ch                      //
//                                                                            //
// Additional contributions by:                                               //
//                 Igor Loi - igor.loi@unibo.it                               //
//                 Andreas Traber - atraber@student.ethz.ch                   //
//                 Sven Stucki - svstucki@student.ethz.ch                     //
//                                                                            //
//                                                                            //
// Create Date:    19/09/2013                                                 //
// Design Name:    Decode stage                                               //
// Module Name:    id_stage.sv                                                //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Decode stage of the core. It decodes the instructions      //
//                 and hosts the register file.                               //
//                                                                            //
// Revision:                                                                  //
// Revision v0.1 - File Created                                               //
// Revision v0.2 - (July   1st 2014) Pipe splitted in several files           //
// Revision v0.3 - (August 7th 2014) Changed port and signal names, added     //
//                 comments                                                   //
// Revision v0.4 - (December 1th 2014) Merged debug unit                      //
//                                                                            //
//                                                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


`include "defines.sv"

module riscv_id_stage
#(
  parameter N_HWLP      = 2,
  parameter N_HWLP_BITS = $clog2(N_HWLP)
)
(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        test_en_i,

    input  logic        fetch_enable_i,
    output logic        core_busy_o,
    output logic        is_decoding_o,

    // Interface to IF stage
    input  logic [N_HWLP-1:0] hwlp_dec_cnt_i,
    input  logic              is_hwlp_i,
    input  logic              instr_valid_i,
    input  logic       [31:0] instr_rdata_i,      // comes from pipeline of IF stage
    output logic              instr_req_o,


    // Jumps and branches
    output logic        branch_in_ex_o,
    input  logic        branch_decision_i,
    output logic [31:0] jump_target_o,

    // IF and ID stage signals
    output logic        clear_instr_valid_o,
    output logic        pc_set_o,
    output logic [2:0]  pc_mux_o,
    output logic [1:0]  exc_pc_mux_o,
    output logic [4:0]  exc_vec_pc_mux_o,

    input  logic        illegal_c_insn_i,
    input  logic        is_compressed_i,

    input  logic [31:0] current_pc_if_i,
    input  logic [31:0] current_pc_id_i,

    // Stalls
    output logic        halt_if_o,      // controller requests a halt of the IF stage

    output logic        id_ready_o,     // ID stage is ready for the next instruction
    input  logic        ex_ready_i,     // EX stage is ready for the next instruction

    input  logic        if_ready_i,     // IF stage is done
    input  logic        if_valid_i,     // IF stage is done
    output logic        id_valid_o,     // ID stage is done
    input  logic        ex_valid_i,     // EX stage is done
    input  logic        wb_valid_i,     // WB stage is done

    // Pipeline ID/EX
    output logic [31:0] branch_pc_ex_o,

    output logic [31:0] alu_operand_a_ex_o,
    output logic [31:0] alu_operand_b_ex_o,
    output logic [31:0] alu_operand_c_ex_o,

    output logic [4:0]  regfile_waddr_ex_o,
    output logic        regfile_we_ex_o,

    output logic [4:0]  regfile_alu_waddr_ex_o,
    output logic        regfile_alu_we_ex_o,

    // ALU
    output logic [`ALU_OP_WIDTH-1:0] alu_operator_ex_o,

    output logic        vector_mode_ex_o,

    // MUL
    output logic        mult_en_ex_o,
    output logic [1:0]  mult_sel_subword_ex_o,
    output logic [1:0]  mult_signed_mode_ex_o,
    output logic        mult_mac_en_ex_o,

    // CSR ID/EX
    output logic        csr_access_ex_o,
    output logic [1:0]  csr_op_ex_o,

    // hwloop signals
    output logic [N_HWLP-1:0] [31:0] hwlp_start_o,
    output logic [N_HWLP-1:0] [31:0] hwlp_end_o,
    output logic [N_HWLP-1:0] [31:0] hwlp_cnt_o,

    // Interface to load store unit
    output logic        data_req_ex_o,
    output logic        data_we_ex_o,
    output logic [1:0]  data_type_ex_o,
    output logic        data_sign_ext_ex_o,
    output logic [1:0]  data_reg_offset_ex_o,
    output logic        data_misaligned_ex_o,

    output logic        prepost_useincr_ex_o,
    input  logic        data_misaligned_i,

    // Interrupt signals
    input  logic [31:0] irq_i,
    input  logic        irq_enable_i,

    output logic [5:0]  exc_cause_o,
    output logic        save_exc_cause_o,

    output logic        save_pc_if_o,
    output logic        save_pc_id_o,

    input  logic        lsu_load_err_i,
    input  logic        lsu_store_err_i,

    // Debug Unit Signals
    input  logic        dbg_stop_req_i,
    input  logic        dbg_step_en_i,
    input  logic [1:0]  dbg_dsr_i,
    input  logic        dbg_stall_i,
    output logic        dbg_trap_o,
    input  logic        dbg_reg_mux_i,
    input  logic        dbg_reg_we_i,
    input  logic [4:0]  dbg_reg_addr_i,
    input  logic [31:0] dbg_reg_wdata_i,
    output logic [31:0] dbg_reg_rdata_o,
    input  logic        dbg_set_npc_i,

    // Forward Signals
    input  logic [4:0]  regfile_waddr_wb_i,
    input  logic        regfile_we_wb_i,
    input  logic [31:0] regfile_wdata_wb_i, // From wb_stage: selects data from data memory, ex_stage result and sp rdata

    input  logic [4:0]  regfile_alu_waddr_fw_i,
    input  logic        regfile_alu_we_fw_i,
    input  logic [31:0] regfile_alu_wdata_fw_i,

    // Performance Counters
    output logic        perf_jump_o,          // we are executing a jump instruction
    output logic        perf_branch_o,        // we are executing a branch instruction
    output logic        perf_jr_stall_o,      // jump-register-hazard
    output logic        perf_ld_stall_o       // load-use-hazard
);

  logic [31:0] instr;

  // Decoder/Controller ID stage internal signals
  logic        deassert_we;

  logic        illegal_insn_dec;
  logic        trap_insn;
  logic        eret_insn_dec;
  logic        ecall_insn_dec;
  logic        pipe_flush_dec;

  logic        rega_used_dec;
  logic        regb_used_dec;
  logic        regc_used_dec;

  logic        branch_taken_ex;
  logic [1:0]  jump_in_id;
  logic [1:0]  jump_in_dec;

  logic        misaligned_stall;
  logic        jr_stall;
  logic        load_stall;

  logic        halt_id;


  // Immediate decoding and sign extension
  logic [31:0] imm_i_type;
  logic [31:0] imm_iz_type;
  logic [31:0] imm_s_type;
  logic [31:0] imm_sb_type;
  logic [31:0] imm_u_type;
  logic [31:0] imm_uj_type;
  logic [31:0] imm_z_type;

  logic [31:0] immediate_b;       // contains the immediate for operand b

  logic [31:0] jump_target;       // calculated jump target (-> EX -> IF)



  // Signals running between controller and exception controller
  logic        exc_req, exc_ack;  // handshake

  logic        trap_hit;

  // Register file interface
  logic [4:0]  regfile_addr_ra_id;
  logic [4:0]  regfile_addr_rb_id;
  logic [4:0]  regfile_addr_rc_id;

  logic [4:0]  regfile_waddr_id;
  logic [4:0]  regfile_alu_waddr_id;
  logic        regfile_alu_we_id;

  logic [31:0] regfile_data_ra_id;
  logic [31:0] regfile_data_rb_id;
  logic [31:0] regfile_data_rc_id;

  // ALU Control
  logic [`ALU_OP_WIDTH-1:0] alu_operator;
  logic [1:0]  alu_op_a_mux_sel;
  logic [1:0]  alu_op_b_mux_sel;
  logic [1:0]  alu_op_c_mux_sel;

  logic        vector_mode;

  logic [2:0]  immediate_mux_sel;
  logic [1:0]  jump_target_mux_sel;

  // Multiplier Control
  logic        mult_en;          // multiplication is used instead of ALU
  logic [1:0]  mult_sel_subword; // Select a subword when doing multiplications
  logic [1:0]  mult_signed_mode; // Signed mode multiplication at the output of the controller, and before the pipe registers
  logic        mult_mac_en;      // Enables the use of the accumulator

  // Register Write Control
  logic        regfile_we_id;
  logic        regfile_alu_waddr_mux_sel;

  // Data Memory Control
  logic        data_we_id;
  logic [1:0]  data_type_id;
  logic        data_sign_ext_id;
  logic [1:0]  data_reg_offset_id;
  logic        data_req_id;

  // hwloop signals
  logic [N_HWLP_BITS-1:0]   hwloop_regid;
  logic            [2:0]    hwloop_we;
  logic                     hwloop_target_mux_sel;
  logic                     hwloop_start_mux_sel;
  logic                     hwloop_cnt_mux_sel;

  logic           [31:0]    hwloop_target;
  logic           [31:0]    hwloop_start;
  logic           [31:0]    hwloop_end;
  logic           [31:0]    hwloop_cnt;

  // CSR control
  logic        csr_access;
  logic [1:0]  csr_op;

  logic        prepost_useincr;

  // Forwarding
  logic [1:0]  operand_a_fw_mux_sel;
  logic [1:0]  operand_b_fw_mux_sel;
  logic [1:0]  operand_c_fw_mux_sel;
  logic [31:0] operand_a_fw_id;
  logic [31:0] operand_b_fw_id;
  logic [31:0] operand_c_fw_id;

  logic [31:0] alu_operand_a;
  logic [31:0] alu_operand_b;
  logic [31:0] alu_operand_c;


  assign instr         = instr_rdata_i;

  // immediate extraction and sign extension
  assign imm_i_type  = { {20 {instr[31]}}, instr[31:20] };
  assign imm_iz_type = {            20'b0, instr[31:20] };
  assign imm_s_type  = { {20 {instr[31]}}, instr[31:25], instr[11:7] };
  assign imm_sb_type = { {19 {instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0 };
  assign imm_u_type  = { instr[31:12], 12'b0 };
  assign imm_uj_type = { {12 {instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0 };

  // immediate for CSR manipulatin (zero extended)
  assign imm_z_type  = { 27'b0, instr[`REG_S1] };

  // source registers
  assign regfile_addr_ra_id = instr[`REG_S1];
  assign regfile_addr_rb_id = instr[`REG_S2];
  assign regfile_addr_rc_id = instr[`REG_S3];

  // destination registers
  assign regfile_waddr_id = instr[`REG_D];

  // Second Register Write Adress Selection
  // Used for prepost load/store and multiplier
  assign regfile_alu_waddr_id = regfile_alu_waddr_mux_sel ?
                                regfile_waddr_id : regfile_addr_ra_id;


  // kill instruction in the IF/ID stage by setting the instr_valid_id control
  // signal to 0 for instructions that are done
  assign clear_instr_valid_o = id_ready_o | halt_id;

  assign branch_taken_ex = branch_in_ex_o & branch_decision_i;


  ///////////////////////////////////////////////
  //  _   ___        ___     ___   ___  ____   //
  // | | | \ \      / / |   / _ \ / _ \|  _ \  //
  // | |_| |\ \ /\ / /| |  | | | | | | | |_) | //
  // |  _  | \ V  V / | |__| |_| | |_| |  __/  //
  // |_| |_|  \_/\_/  |_____\___/ \___/|_|     //
  //                                           //
  ///////////////////////////////////////////////

  // hwloop register id
  assign hwloop_regid = instr[8:7];   // rd contains hwloop register id

  // hwloop target mux
  always_comb
  begin
    unique case (hwloop_target_mux_sel)
      1'b0: hwloop_target = current_pc_id_i + {imm_iz_type[30:0], 1'b0};
      1'b1: hwloop_target = current_pc_id_i + {imm_z_type[30:0], 1'b0};
    endcase
  end

  // hwloop start mux
  always_comb
  begin
    unique case (hwloop_start_mux_sel)
      1'b0: hwloop_start = hwloop_target;   // for PC + I imm
      1'b1: hwloop_start = current_pc_if_i; // for next PC
    endcase
  end

  // hwloop end mux
  assign hwloop_end = hwloop_target;

  // hwloop cnt mux
  always_comb
  begin : hwloop_cnt_mux
    unique case (hwloop_cnt_mux_sel)
      1'b0: hwloop_cnt = imm_iz_type;
      1'b1: hwloop_cnt = operand_a_fw_id;
    endcase;
  end


  //////////////////////////////////////////////////////////////////
  //      _                         _____                    _    //
  //     | |_   _ _ __ ___  _ __   |_   _|_ _ _ __ __ _  ___| |_  //
  //  _  | | | | | '_ ` _ \| '_ \    | |/ _` | '__/ _` |/ _ \ __| //
  // | |_| | |_| | | | | | | |_) |   | | (_| | | | (_| |  __/ |_  //
  //  \___/ \__,_|_| |_| |_| .__/    |_|\__,_|_|  \__, |\___|\__| //
  //                       |_|                    |___/           //
  //////////////////////////////////////////////////////////////////

  always_comb
  begin : jump_target_mux
    unique case (jump_target_mux_sel)
      `JT_JAL:  jump_target = current_pc_id_i + imm_uj_type;
      `JT_COND: jump_target = current_pc_id_i + imm_sb_type;

      // JALR: Cannot forward RS1, since the path is too long
      `JT_JALR: jump_target = regfile_data_ra_id + imm_i_type;
      default:  jump_target = regfile_data_ra_id + imm_i_type;
    endcase
  end

  assign jump_target_o = jump_target;


  ////////////////////////////////////////////////////////
  //   ___                                 _      _     //
  //  / _ \ _ __   ___ _ __ __ _ _ __   __| |    / \    //
  // | | | | '_ \ / _ \ '__/ _` | '_ \ / _` |   / _ \   //
  // | |_| | |_) |  __/ | | (_| | | | | (_| |  / ___ \  //
  //  \___/| .__/ \___|_|  \__,_|_| |_|\__,_| /_/   \_\ //
  //       |_|                                          //
  ////////////////////////////////////////////////////////

  // ALU_Op_a Mux
  always_comb
  begin : alu_operand_a_mux
    case (alu_op_a_mux_sel)
      `OP_A_REGA_OR_FWD:  alu_operand_a = operand_a_fw_id;
      `OP_A_CURRPC:       alu_operand_a = current_pc_id_i;
      `OP_A_ZIMM:         alu_operand_a = imm_z_type;
      `OP_A_ZERO:         alu_operand_a = 32'b0;
      default:            alu_operand_a = operand_a_fw_id;
    endcase; // case (alu_op_a_mux_sel)
  end

  // Operand a forwarding mux
  always_comb
  begin : operand_a_fw_mux
    case (operand_a_fw_mux_sel)
      `SEL_FW_EX:    operand_a_fw_id = regfile_alu_wdata_fw_i;
      `SEL_FW_WB:    operand_a_fw_id = regfile_wdata_wb_i;
      `SEL_REGFILE:  operand_a_fw_id = regfile_data_ra_id;
      default:       operand_a_fw_id = regfile_data_ra_id;
    endcase; // case (operand_a_fw_mux_sel)
  end

  //////////////////////////////////////////////////////
  //   ___                                 _   ____   //
  //  / _ \ _ __   ___ _ __ __ _ _ __   __| | | __ )  //
  // | | | | '_ \ / _ \ '__/ _` | '_ \ / _` | |  _ \  //
  // | |_| | |_) |  __/ | | (_| | | | | (_| | | |_) | //
  //  \___/| .__/ \___|_|  \__,_|_| |_|\__,_| |____/  //
  //       |_|                                        //
  //////////////////////////////////////////////////////

  // Immediate Mux for operand B
  always_comb
  begin : immediate_mux
    unique case (immediate_mux_sel)
      `IMM_I:      immediate_b = imm_i_type;
      `IMM_S:      immediate_b = imm_s_type;
      `IMM_U:      immediate_b = imm_u_type;
      `IMM_PCINCR: immediate_b = (is_compressed_i && (~data_misaligned_i)) ? 32'h2 : 32'h4;
      default:     immediate_b = imm_i_type;
    endcase; // case (immediate_mux_sel)
  end

  // ALU_Op_b Mux
  always_comb
  begin : alu_operand_b_mux
    case (alu_op_b_mux_sel)
      `OP_B_REGB_OR_FWD:  alu_operand_b = operand_b_fw_id;
      `OP_B_REGC_OR_FWD:  alu_operand_b = operand_c_fw_id;
      `OP_B_IMM:          alu_operand_b = immediate_b;
      default:            alu_operand_b = operand_b_fw_id;
    endcase // case (alu_op_b_mux_sel)
  end

  // Operand b forwarding mux
  always_comb
  begin : operand_b_fw_mux
    case (operand_b_fw_mux_sel)
      `SEL_FW_EX:    operand_b_fw_id = regfile_alu_wdata_fw_i;
      `SEL_FW_WB:    operand_b_fw_id = regfile_wdata_wb_i;
      `SEL_REGFILE:  operand_b_fw_id = regfile_data_rb_id;
      default:       operand_b_fw_id = regfile_data_rb_id;
    endcase; // case (operand_b_fw_mux_sel)
  end


  //////////////////////////////////////////////////////
  //   ___                                 _    ____  //
  //  / _ \ _ __   ___ _ __ __ _ _ __   __| |  / ___| //
  // | | | | '_ \ / _ \ '__/ _` | '_ \ / _` | | |     //
  // | |_| | |_) |  __/ | | (_| | | | | (_| | | |___  //
  //  \___/| .__/ \___|_|  \__,_|_| |_|\__,_|  \____| //
  //       |_|                                        //
  //////////////////////////////////////////////////////

  // ALU OP C Mux
  always_comb
  begin : alu_operand_c_mux
    case (alu_op_c_mux_sel)
      `OP_C_REGC_OR_FWD:  alu_operand_c = operand_c_fw_id;
      `OP_C_REGB_OR_FWD:  alu_operand_c = operand_b_fw_id;
      `OP_C_JT:           alu_operand_c = jump_target;
      default:            alu_operand_c = operand_c_fw_id;
    endcase // case (alu_op_c_mux_sel)
  end

  // Operand c forwarding mux
  always_comb
  begin : operand_c_fw_mux
    case (operand_c_fw_mux_sel)
      `SEL_FW_EX:    operand_c_fw_id = regfile_alu_wdata_fw_i;
      `SEL_FW_WB:    operand_c_fw_id = regfile_wdata_wb_i;
      `SEL_REGFILE:  operand_c_fw_id = regfile_data_rc_id;
      default:       operand_c_fw_id = regfile_data_rc_id;
    endcase; // case (operand_c_fw_mux_sel)
  end


  /////////////////////////////////////////////////////////
  //  ____  _____ ____ ___ ____ _____ _____ ____  ____   //
  // |  _ \| ____/ ___|_ _/ ___|_   _| ____|  _ \/ ___|  //
  // | |_) |  _|| |  _ | |\___ \ | | |  _| | |_) \___ \  //
  // |  _ <| |__| |_| || | ___) || | | |___|  _ < ___) | //
  // |_| \_\_____\____|___|____/ |_| |_____|_| \_\____/  //
  //                                                     //
  /////////////////////////////////////////////////////////
  riscv_register_file  registers_i
  (
    .clk          ( clk                ),
    .rst_n        ( rst_n              ),

    .test_en_i    ( test_en_i          ),

    // Read port a
    .raddr_a_i    ( regfile_addr_ra_id ),
    .rdata_a_o    ( regfile_data_ra_id ),

    // Read port b
    .raddr_b_i    ( regfile_addr_rb_id ),
    .rdata_b_o    ( regfile_data_rb_id ),

    // Read port c
    .raddr_c_i    ( (dbg_reg_mux_i == 1'b0) ? regfile_addr_rc_id : dbg_reg_addr_i ),
    .rdata_c_o    ( regfile_data_rc_id ),

    // Write port a
    .waddr_a_i    ( regfile_waddr_wb_i ),
    .wdata_a_i    ( regfile_wdata_wb_i ),
    .we_a_i       ( regfile_we_wb_i    ),

    // Write port b
    .waddr_b_i    ( (dbg_reg_mux_i == 1'b0) ? regfile_alu_waddr_fw_i : dbg_reg_addr_i  ),
    .wdata_b_i    ( (dbg_reg_mux_i == 1'b0) ? regfile_alu_wdata_fw_i : dbg_reg_wdata_i ),
    .we_b_i       ( (dbg_reg_mux_i == 1'b0) ? regfile_alu_we_fw_i    : dbg_reg_we_i    )
  );

  assign dbg_reg_rdata_o = regfile_data_rc_id;


  ///////////////////////////////////////////////
  //  ____  _____ ____ ___  ____  _____ ____   //
  // |  _ \| ____/ ___/ _ \|  _ \| ____|  _ \  //
  // | | | |  _|| |  | | | | | | |  _| | |_) | //
  // | |_| | |__| |__| |_| | |_| | |___|  _ <  //
  // |____/|_____\____\___/|____/|_____|_| \_\ //
  //                                           //
  ///////////////////////////////////////////////

  riscv_decoder decoder_i
  (
    // controller related signals
    .deassert_we_i                   ( deassert_we               ),
    .data_misaligned_i               ( data_misaligned_i         ),

    .illegal_insn_o                  ( illegal_insn_dec          ),
    .trap_insn_o                     ( trap_insn                 ),
    .eret_insn_o                     ( eret_insn_dec             ),
    .ecall_insn_o                    ( ecall_insn_dec            ),
    .pipe_flush_o                    ( pipe_flush_dec            ),

    .rega_used_o                     ( rega_used_dec             ),
    .regb_used_o                     ( regb_used_dec             ),
    .regc_used_o                     ( regc_used_dec             ),

    // from IF/ID pipeline
    .instr_rdata_i                   ( instr                     ),
    .illegal_c_insn_i                ( illegal_c_insn_i          ),

    // ALU signals
    .alu_operator_o                  ( alu_operator              ),
    .alu_op_a_mux_sel_o              ( alu_op_a_mux_sel          ),
    .alu_op_b_mux_sel_o              ( alu_op_b_mux_sel          ),
    .alu_op_c_mux_sel_o              ( alu_op_c_mux_sel          ),
    .immediate_mux_sel_o             ( immediate_mux_sel         ),

    .vector_mode_o                   ( vector_mode               ),

    // MUL signals
    .mult_en_o                       ( mult_en                   ),
    .mult_sel_subword_o              ( mult_sel_subword          ),
    .mult_signed_mode_o              ( mult_signed_mode          ),
    .mult_mac_en_o                   ( mult_mac_en               ),

    // Register file control signals
    .regfile_mem_we_o                ( regfile_we_id             ),
    .regfile_alu_we_o                ( regfile_alu_we_id         ),
    .regfile_alu_waddr_sel_o         ( regfile_alu_waddr_mux_sel ),

    // CSR control signals
    .csr_access_o                    ( csr_access                ),
    .csr_op_o                        ( csr_op                    ),

    // Data bus interface
    .data_req_o                      ( data_req_id               ),
    .data_we_o                       ( data_we_id                ),
    .prepost_useincr_o               ( prepost_useincr           ),
    .data_type_o                     ( data_type_id              ),
    .data_sign_extension_o           ( data_sign_ext_id          ),
    .data_reg_offset_o               ( data_reg_offset_id        ),

    // hwloop signals
    .hwloop_we_o                     ( hwloop_we                 ),
    .hwloop_target_mux_sel_o         ( hwloop_target_mux_sel     ),
    .hwloop_start_mux_sel_o          ( hwloop_start_mux_sel      ),
    .hwloop_cnt_mux_sel_o            ( hwloop_cnt_mux_sel        ),

    // jump/branches
    .jump_in_dec_o                   ( jump_in_dec               ),
    .jump_in_id_o                    ( jump_in_id                ),
    .jump_target_mux_sel_o           ( jump_target_mux_sel       )

  );

  ////////////////////////////////////////////////////////////////////
  //    ____ ___  _   _ _____ ____   ___  _     _     _____ ____    //
  //   / ___/ _ \| \ | |_   _|  _ \ / _ \| |   | |   | ____|  _ \   //
  //  | |  | | | |  \| | | | | |_) | | | | |   | |   |  _| | |_) |  //
  //  | |__| |_| | |\  | | | |  _ <| |_| | |___| |___| |___|  _ <   //
  //   \____\___/|_| \_| |_| |_| \_\\___/|_____|_____|_____|_| \_\  //
  //                                                                //
  ////////////////////////////////////////////////////////////////////

  riscv_controller controller_i
  (
    .clk                            ( clk                    ),
    .rst_n                          ( rst_n                  ),

    .fetch_enable_i                 ( fetch_enable_i         ),
    .core_busy_o                    ( core_busy_o            ),
    .is_decoding_o                  ( is_decoding_o          ),

    // decoder related signals
    .deassert_we_o                  ( deassert_we            ),
    .illegal_insn_i                 ( illegal_insn_dec       ),
    .eret_insn_i                    ( eret_insn_dec          ),
    .pipe_flush_i                   ( pipe_flush_dec         ),

    .rega_used_i                    ( rega_used_dec          ),
    .regb_used_i                    ( regb_used_dec          ),
    .regc_used_i                    ( regc_used_dec          ),

    // from IF/ID pipeline
    .instr_valid_i                  ( instr_valid_i          ),
    .instr_rdata_i                  ( instr                  ),

    // from prefetcher
    .instr_req_o                    ( instr_req_o            ),

    // to prefetcher
    .pc_set_o                       ( pc_set_o               ),
    .pc_mux_o                       ( pc_mux_o               ),

    // LSU
    .data_req_ex_i                  ( data_req_ex_o          ),
    .data_misaligned_i              ( data_misaligned_i      ),

    // jump/branch control
    .branch_taken_ex_i              ( branch_taken_ex        ),
    .jump_in_id_i                   ( jump_in_id             ),
    .jump_in_dec_i                  ( jump_in_dec            ),

    // Exception Controller Signals
    .exc_req_i                      ( exc_req                ),
    .exc_ack_o                      ( exc_ack                ),
    .trap_hit_i                     ( trap_hit               ),

    .save_pc_id_o                   ( save_pc_id_o           ),
    .save_pc_if_o                   ( save_pc_if_o           ),

    // Debug Unit Signals
    .dbg_stall_i                    ( dbg_stall_i            ),
    .dbg_set_npc_i                  ( dbg_set_npc_i          ),
    .dbg_trap_o                     ( dbg_trap_o             ),

    // Forwarding signals from regfile
    .regfile_waddr_ex_i             ( regfile_waddr_ex_o     ), // Write address for register file from ex-wb- pipeline registers
    .regfile_we_ex_i                ( regfile_we_ex_o        ),
    .regfile_waddr_wb_i             ( regfile_waddr_wb_i     ), // Write address for register file from ex-wb- pipeline registers
    .regfile_we_wb_i                ( regfile_we_wb_i        ),

    // regfile port 2
    .regfile_alu_waddr_fw_i         ( regfile_alu_waddr_fw_i ),
    .regfile_alu_we_fw_i            ( regfile_alu_we_fw_i    ),

    // Forwarding signals
    .operand_a_fw_mux_sel_o         ( operand_a_fw_mux_sel   ),
    .operand_b_fw_mux_sel_o         ( operand_b_fw_mux_sel   ),
    .operand_c_fw_mux_sel_o         ( operand_c_fw_mux_sel   ),

    // Stall signals
    .halt_if_o                      ( halt_if_o              ),
    .halt_id_o                      ( halt_id                ),

    .misaligned_stall_o             ( misaligned_stall       ),
    .jr_stall_o                     ( jr_stall               ),
    .load_stall_o                   ( load_stall             ),

    .if_valid_i                     ( if_valid_i             ),
    .id_valid_i                     ( id_valid_o             ),
    .ex_valid_i                     ( ex_valid_i             ),
    .wb_valid_i                     ( wb_valid_i             ),

    // Performance Counters
    .perf_jump_o                    ( perf_jump_o            ),
    .perf_branch_o                  ( perf_branch_o          ),
    .perf_jr_stall_o                ( perf_jr_stall_o        ),
    .perf_ld_stall_o                ( perf_ld_stall_o        )
  );

  ///////////////////////////////////////////////////////////////////////
  //  _____               ____            _             _ _            //
  // | ____|_  _____     / ___|___  _ __ | |_ _ __ ___ | | | ___ _ __  //
  // |  _| \ \/ / __|   | |   / _ \| '_ \| __| '__/ _ \| | |/ _ \ '__| //
  // | |___ >  < (__ _  | |__| (_) | | | | |_| | | (_) | | |  __/ |    //
  // |_____/_/\_\___(_)  \____\___/|_| |_|\__|_|  \___/|_|_|\___|_|    //
  //                                                                   //
  ///////////////////////////////////////////////////////////////////////

  riscv_exc_controller exc_controller_i
  (
    .clk                  ( clk              ),
    .rst_n                ( rst_n            ),

    // to controller
    .req_o                ( exc_req          ),
    .ack_i                ( exc_ack          ),

    .trap_hit_o           ( trap_hit         ),

    // to IF stage
    .pc_mux_o             ( exc_pc_mux_o     ),
    .vec_pc_mux_o         ( exc_vec_pc_mux_o ),

    // Interrupt signals
    .irq_i                ( irq_i            ),
    .irq_enable_i         ( irq_enable_i     ),

    .trap_insn_i          ( is_decoding_o & trap_insn        ),
    .illegal_insn_i       ( is_decoding_o & illegal_insn_dec ),
    .ecall_insn_i         ( is_decoding_o & ecall_insn_dec   ),
    .eret_insn_i          ( is_decoding_o & eret_insn_dec    ),

    .lsu_load_err_i       ( lsu_load_err_i   ),
    .lsu_store_err_i      ( lsu_store_err_i  ),

    .cause_o              ( exc_cause_o      ),
    .save_cause_o         ( save_exc_cause_o ),

    // Debug Signals
    .dbg_stop_req_i       ( dbg_stop_req_i   ),
    .dbg_step_en_i        ( dbg_step_en_i    ),
    .dbg_dsr_i            ( dbg_dsr_i        )
  );


  //////////////////////////////////////////////////////////////////////////
  //          ____ ___  _   _ _____ ____   ___  _     _     _____ ____    //
  //         / ___/ _ \| \ | |_   _|  _ \ / _ \| |   | |   | ____|  _ \   //
  // HWLOOP-| |  | | | |  \| | | | | |_) | | | | |   | |   |  _| | |_) |  //
  //        | |__| |_| | |\  | | | |  _ <| |_| | |___| |___| |___|  _ <   //
  //         \____\___/|_| \_| |_| |_| \_\\___/|_____|_____|_____|_| \_\  //
  //                                                                      //
  //////////////////////////////////////////////////////////////////////////

  riscv_hwloop_regs
  #(
    .N_REGS ( N_HWLP )
  )
  hwloop_regs_i
  (
    .clk                   ( clk                       ),
    .rst_n                 ( rst_n                     ),

    // from ID
    .hwlp_start_data_i     ( hwloop_start              ),
    .hwlp_end_data_i       ( hwloop_end                ),
    .hwlp_cnt_data_i       ( hwloop_cnt                ),
    .hwlp_we_i             ( hwloop_we                 ),
    .hwlp_regid_i          ( hwloop_regid              ),

    // from controller
    .valid_i               ( instr_valid_i & is_hwlp_i ),

    // to hwloop controller
    .hwlp_start_addr_o     ( hwlp_start_o              ),
    .hwlp_end_addr_o       ( hwlp_end_o                ),
    .hwlp_counter_o        ( hwlp_cnt_o                ),

    // from hwloop controller
    .hwlp_dec_cnt_i        ( hwlp_dec_cnt_i            )
  );


  /////////////////////////////////////////////////////////////////////////////////
  //   ___ ____        _______  __  ____ ___ ____  _____ _     ___ _   _ _____   //
  //  |_ _|  _ \      | ____\ \/ / |  _ \_ _|  _ \| ____| |   |_ _| \ | | ____|  //
  //   | || | | |_____|  _|  \  /  | |_) | || |_) |  _| | |    | ||  \| |  _|    //
  //   | || |_| |_____| |___ /  \  |  __/| ||  __/| |___| |___ | || |\  | |___   //
  //  |___|____/      |_____/_/\_\ |_|  |___|_|   |_____|_____|___|_| \_|_____|  //
  //                                                                             //
  /////////////////////////////////////////////////////////////////////////////////
  always_ff @(posedge clk, negedge rst_n)
  begin
    if (rst_n == 1'b0)
    begin
      branch_pc_ex_o <= '0;
    end
    else begin
      if (jump_in_id == `BRANCH_COND && id_valid_o)
        branch_pc_ex_o <= current_pc_id_i;
    end
  end

  always_ff @(posedge clk, negedge rst_n)
  begin : ID_EX_PIPE_REGISTERS
    if (rst_n == 1'b0)
    begin
      alu_operator_ex_o           <= `ALU_NOP;
      alu_operand_a_ex_o          <= 32'h0000_0000;
      alu_operand_b_ex_o          <= 32'h0000_0000;
      alu_operand_c_ex_o          <= 32'h0000_0000;

      vector_mode_ex_o            <= '0;

      mult_en_ex_o                <= 1'b0;
      mult_sel_subword_ex_o       <= 2'b0;
      mult_signed_mode_ex_o       <= 2'b0;
      mult_mac_en_ex_o            <= 1'b0;

      regfile_waddr_ex_o          <= 5'b0;
      regfile_we_ex_o             <= 1'b0;

      regfile_alu_waddr_ex_o      <= 5'b0;
      regfile_alu_we_ex_o         <= 1'b0;
      prepost_useincr_ex_o        <= 1'b0;

      csr_access_ex_o             <= 1'b0;
      csr_op_ex_o                 <= `CSR_OP_NONE;

      data_we_ex_o                <= 1'b0;
      data_type_ex_o              <= 2'b0;
      data_sign_ext_ex_o          <= 1'b0;
      data_reg_offset_ex_o        <= 2'b0;
      data_req_ex_o               <= 1'b0;

      data_misaligned_ex_o        <= 1'b0;

      branch_in_ex_o              <= 1'b0;

    end
    else if (data_misaligned_i) begin
      // misaligned data access case
      if (ex_ready_i)
      begin // misaligned access case, only unstall alu operands

        // if we are using post increments, then we have to use the
        // original value of the register for the second memory access
        // => keep it stalled
        if (prepost_useincr_ex_o == 1'b1)
        begin
          alu_operand_a_ex_o        <= alu_operand_a;
        end

        alu_operand_b_ex_o          <= alu_operand_b;
        regfile_alu_we_ex_o         <= regfile_alu_we_id;
        prepost_useincr_ex_o        <= prepost_useincr;

        data_misaligned_ex_o        <= 1'b1;
      end
    end
    else if (~data_misaligned_i) begin
      if (id_valid_o)
      begin // unstall the whole pipeline
        alu_operator_ex_o           <= alu_operator;
        alu_operand_a_ex_o          <= alu_operand_a;
        alu_operand_b_ex_o          <= alu_operand_b;
        alu_operand_c_ex_o          <= alu_operand_c;

        vector_mode_ex_o            <= vector_mode;

        mult_en_ex_o                <= mult_en;
        mult_sel_subword_ex_o       <= mult_sel_subword;
        mult_signed_mode_ex_o       <= mult_signed_mode;
        mult_mac_en_ex_o            <= mult_mac_en;

        regfile_waddr_ex_o          <= regfile_waddr_id;
        regfile_we_ex_o             <= regfile_we_id;

        regfile_alu_waddr_ex_o      <= regfile_alu_waddr_id;
        regfile_alu_we_ex_o         <= regfile_alu_we_id;

        prepost_useincr_ex_o        <= prepost_useincr;

        csr_access_ex_o             <= csr_access;
        csr_op_ex_o                 <= csr_op;

        data_we_ex_o                <= data_we_id;
        data_type_ex_o              <= data_type_id;
        data_sign_ext_ex_o          <= data_sign_ext_id;
        data_reg_offset_ex_o        <= data_reg_offset_id;
        data_req_ex_o               <= data_req_id;

        data_misaligned_ex_o        <= 1'b0;

        branch_in_ex_o              <= jump_in_id == `BRANCH_COND;
      end else if(ex_ready_i) begin
        // EX stage is ready but we don't have a new instruction for it,
        // so we set all write enables to 0, but unstall the pipe

        regfile_we_ex_o             <= 1'b0;

        regfile_alu_we_ex_o         <= 1'b0;

        csr_op_ex_o                 <= `CSR_OP_NONE;

        data_req_ex_o               <= 1'b0;

        data_misaligned_ex_o        <= 1'b0;

        branch_in_ex_o              <= 1'b0;
      end
    end
  end


  // stall control
  assign id_ready_o = ((~misaligned_stall) & (~jr_stall) & (~load_stall) & ex_ready_i);
  assign id_valid_o = (~halt_id) & id_ready_o;


  //----------------------------------------------------------------------------
  // Assertions
  //----------------------------------------------------------------------------

  // make sure that branch decision is valid when jumping
  assert property (
    @(posedge clk) (branch_in_ex_o) |-> (branch_decision_i !== 1'bx) );

  // the instruction delivered to the ID stage should always be valid
  assert property (
    @(posedge clk) (instr_valid_i & (~illegal_c_insn_i)) |-> (!$isunknown(instr_rdata_i)) );

endmodule
