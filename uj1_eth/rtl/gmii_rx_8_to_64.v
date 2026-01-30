`resetall
`timescale 1ns/1ps
`default_nettype none
// TODO : 
// 1) add a skid buffer
// 2) replace m_axis_tdata_int_d*_reg and m_axis_tkeep_int_d*_reg with shift reg

// 2026-01-31 by uj1

module gmii_rx_8_to_64 #(
	parameter GMII_DATA_W = 8,
	parameter DATA_WIDTH = 64,
	parameter KEEP_WIDTH = DATA_WIDTH/8
)(
	input wire		gmii_clk,
	input wire		resetn,

	/* GMII input */
	input wire [GMII_DATA_W-1:0]	gmii_rxd,
	input wire						gmii_rx_dv,
	input wire						gmii_rx_er,

	/* AXI output */
	output wire [DATA_WIDTH-1:0]m_axis_tdata,
	output wire [KEEP_WIDTH-1:0]		m_axis_tkeep,
	output wire						m_axis_tvalid,
	input wire						m_axis_tready,
	output wire						m_axis_tlast,
	output wire						m_axis_tuser,

	/* Status output */
	output wire						er_bad_fcs,
	output wire						er_bad_frame
);
parameter PTR_W = 3;// $clog2(8)

localparam [7:0]
	ETH_PREAMBLE = 8'h55,
	ETH_SFD = 8'hD5;

reg [PTR_W-1:0] ptr_reg = {PTR_W{1'b0}}, ptr_next;

reg s_idle_reg = 1'b1, s_idle_next;
reg s_payload_reg = 1'b0, s_payload_next;
reg s_wait_end_reg = 1'b0, s_wait_end_next;

// shift reg
reg [GMII_DATA_W-1:0]	gmii_rxd_reg_d0 = {GMII_DATA_W{1'b0}};
reg [GMII_DATA_W-1:0]	gmii_rxd_reg_d1 = {GMII_DATA_W{1'b0}};
reg [GMII_DATA_W-1:0]	gmii_rxd_reg_d2 = {GMII_DATA_W{1'b0}};
reg [GMII_DATA_W-1:0]	gmii_rxd_reg_d3 = {GMII_DATA_W{1'b0}};
reg [GMII_DATA_W-1:0]	gmii_rxd_reg_d4 = {GMII_DATA_W{1'b0}};

reg gmii_rx_dv_reg_d0 = 1'b0;
reg gmii_rx_dv_reg_d1 = 1'b0;
reg gmii_rx_dv_reg_d2 = 1'b0;
reg gmii_rx_dv_reg_d3 = 1'b0;
reg gmii_rx_dv_reg_d4 = 1'b0;

reg gmii_rx_er_reg_d0 = 1'b0;
reg gmii_rx_er_reg_d1 = 1'b0;
reg gmii_rx_er_reg_d2 = 1'b0;
reg gmii_rx_er_reg_d3 = 1'b0;
reg gmii_rx_er_reg_d4 = 1'b0;

// internal signal
reg [GMII_DATA_W-1:0] m_axis_tdata_int_d0_reg = {GMII_DATA_W{1'b0}}, m_axis_tdata_int_d0_next;
reg [GMII_DATA_W-1:0] m_axis_tdata_int_d1_reg = {GMII_DATA_W{1'b0}}, m_axis_tdata_int_d1_next;
reg [GMII_DATA_W-1:0] m_axis_tdata_int_d2_reg = {GMII_DATA_W{1'b0}}, m_axis_tdata_int_d2_next;
reg [GMII_DATA_W-1:0] m_axis_tdata_int_d3_reg = {GMII_DATA_W{1'b0}}, m_axis_tdata_int_d3_next;
reg [GMII_DATA_W-1:0] m_axis_tdata_int_d4_reg = {GMII_DATA_W{1'b0}}, m_axis_tdata_int_d4_next;
reg [GMII_DATA_W-1:0] m_axis_tdata_int_d5_reg = {GMII_DATA_W{1'b0}}, m_axis_tdata_int_d5_next;
reg [GMII_DATA_W-1:0] m_axis_tdata_int_d6_reg = {GMII_DATA_W{1'b0}}, m_axis_tdata_int_d6_next;
reg [GMII_DATA_W-1:0] m_axis_tdata_int_d7_reg = {GMII_DATA_W{1'b0}}, m_axis_tdata_int_d7_next;

reg m_axis_tkeep_int_d0_reg = 1'b0, m_axis_tkeep_int_d0_next;
reg m_axis_tkeep_int_d1_reg = 1'b0, m_axis_tkeep_int_d1_next;
reg m_axis_tkeep_int_d2_reg = 1'b0, m_axis_tkeep_int_d2_next;
reg m_axis_tkeep_int_d3_reg = 1'b0, m_axis_tkeep_int_d3_next;
reg m_axis_tkeep_int_d4_reg = 1'b0, m_axis_tkeep_int_d4_next;
reg m_axis_tkeep_int_d5_reg = 1'b0, m_axis_tkeep_int_d5_next;
reg m_axis_tkeep_int_d6_reg = 1'b0, m_axis_tkeep_int_d6_next;
reg m_axis_tkeep_int_d7_reg = 1'b0, m_axis_tkeep_int_d7_next;

reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}}, m_axis_tdata_next;
reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg = {KEEP_WIDTH{1'b0}}, m_axis_tkeep_next;
reg m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
reg m_axis_tlast_reg = 1'b0, m_axis_tlast_next;
reg m_axis_tuser_reg = 1'b0, m_axis_tuser_next;

reg er_bad_fcs_reg = 1'b0, er_bad_fcs_next;
reg er_bad_frame_reg = 1'b0, er_bad_frame_next;

assign m_axis_tdata = m_axis_tdata_reg;
assign m_axis_tkeep = m_axis_tkeep_reg;
assign m_axis_tvalid = m_axis_tvalid_reg;
assign m_axis_tlast = m_axis_tlast_reg;
assign m_axis_tuser = m_axis_tuser_reg;
assign er_bad_fcs = er_bad_fcs_reg;

// crc
reg reset_crc;
reg update_crc;

reg [31:0] crc_state = 32'hFFFFFFFF;
wire [31:0] crc_next;

lfsr #(
    .LFSR_WIDTH(32),
    .LFSR_POLY(32'h4c11db7),
    .LFSR_CONFIG("GALOIS"),
    .LFSR_FEED_FORWARD(0),
    .REVERSE(1),
    .DATA_WIDTH(8),
    .STYLE("AUTO")
)
eth_crc_8 (
    .data_in(gmii_rxd_reg_d4),
    .state_in(crc_state),
    .data_out(),
    .state_out(crc_next)
);

// shift logic
always @(posedge gmii_clk) begin
	gmii_rxd_reg_d0 <= gmii_rxd;
	gmii_rxd_reg_d1 <= gmii_rxd_reg_d0;
	gmii_rxd_reg_d2 <= gmii_rxd_reg_d1;
	gmii_rxd_reg_d3 <= gmii_rxd_reg_d2;
	gmii_rxd_reg_d4 <= gmii_rxd_reg_d3;

	gmii_rx_dv_reg_d0 <= gmii_rx_dv;
	gmii_rx_dv_reg_d1 <= gmii_rx_dv_reg_d0 && gmii_rx_dv;
	gmii_rx_dv_reg_d2 <= gmii_rx_dv_reg_d1 && gmii_rx_dv;
	gmii_rx_dv_reg_d3 <= gmii_rx_dv_reg_d2 && gmii_rx_dv;
	gmii_rx_dv_reg_d4 <= gmii_rx_dv_reg_d3 && gmii_rx_dv;

	gmii_rx_er_reg_d0 <= gmii_rx_er;
	gmii_rx_er_reg_d1 <= gmii_rx_er_reg_d0;
	gmii_rx_er_reg_d2 <= gmii_rx_er_reg_d1;
	gmii_rx_er_reg_d3 <= gmii_rx_er_reg_d2;
	gmii_rx_er_reg_d4 <= gmii_rx_er_reg_d3;

	if (!resetn) begin
		gmii_rx_dv_reg_d0 <= 1'b0;
		gmii_rx_dv_reg_d1 <= 1'b0;
		gmii_rx_dv_reg_d2 <= 1'b0;
		gmii_rx_dv_reg_d3 <= 1'b0;
		gmii_rx_dv_reg_d4 <= 1'b0;
	end
end

always @(*) begin
	m_axis_tdata_int_d0_next = m_axis_tdata_int_d0_reg;
	m_axis_tdata_int_d1_next = m_axis_tdata_int_d1_reg;
	m_axis_tdata_int_d2_next = m_axis_tdata_int_d2_reg;
	m_axis_tdata_int_d3_next = m_axis_tdata_int_d3_reg;
	m_axis_tdata_int_d4_next = m_axis_tdata_int_d4_reg;
	m_axis_tdata_int_d5_next = m_axis_tdata_int_d5_reg;
	m_axis_tdata_int_d6_next = m_axis_tdata_int_d6_reg;
	m_axis_tdata_int_d7_next = m_axis_tdata_int_d7_reg;

	m_axis_tkeep_int_d0_next = m_axis_tkeep_int_d0_reg;
	m_axis_tkeep_int_d1_next = m_axis_tkeep_int_d1_reg;
	m_axis_tkeep_int_d2_next = m_axis_tkeep_int_d2_reg;
	m_axis_tkeep_int_d3_next = m_axis_tkeep_int_d3_reg;
	m_axis_tkeep_int_d4_next = m_axis_tkeep_int_d4_reg;
	m_axis_tkeep_int_d5_next = m_axis_tkeep_int_d5_reg;
	m_axis_tkeep_int_d6_next = m_axis_tkeep_int_d6_reg;
	m_axis_tkeep_int_d7_next = m_axis_tkeep_int_d7_reg;
	case (ptr_reg)
			0: m_axis_tdata_int_d0_next = gmii_rxd_reg_d4; 
			1: m_axis_tdata_int_d1_next = gmii_rxd_reg_d4; 
			2: m_axis_tdata_int_d2_next = gmii_rxd_reg_d4; 
			3: m_axis_tdata_int_d3_next = gmii_rxd_reg_d4; 
			4: m_axis_tdata_int_d4_next = gmii_rxd_reg_d4; 
			5: m_axis_tdata_int_d5_next = gmii_rxd_reg_d4;
			6: m_axis_tdata_int_d6_next = gmii_rxd_reg_d4; 
			7: m_axis_tdata_int_d7_next = gmii_rxd_reg_d4; 
	endcase
	case (ptr_reg)
			0: m_axis_tkeep_int_d0_next = gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4;
			1: m_axis_tkeep_int_d1_next = gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4;
			2: m_axis_tkeep_int_d2_next = gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4;
			3: m_axis_tkeep_int_d3_next = gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4;
			4: m_axis_tkeep_int_d4_next = gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4;
			5: m_axis_tkeep_int_d5_next = gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4;
			6: m_axis_tkeep_int_d6_next = gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4;
			7: m_axis_tkeep_int_d7_next = gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4;
	endcase
end

always @(*) begin
	s_idle_next = s_idle_reg;
	s_payload_next = s_payload_reg;
	s_wait_end_next = s_wait_end_reg;

	ptr_next = ptr_reg;

	m_axis_tdata_next = {DATA_WIDTH{1'b0}};
	m_axis_tkeep_next = {KEEP_WIDTH{1'b0}};
	m_axis_tvalid_next = 1'b0;
	m_axis_tlast_next = 1'b0;
	m_axis_tuser_next = 1'b0;

	er_bad_fcs_next = 1'b0;
	er_bad_frame_next = 1'b0;

	reset_crc = 1'b0;
	update_crc = 1'b0;
	
	// payload start
	if (s_idle_reg) begin
		reset_crc = 1'b1;
		if (gmii_rx_dv_reg_d4 && !gmii_rx_er_reg_d4 && (gmii_rxd_reg_d4 == 8'hD5)) begin
			s_idle_next = 1'b0;
			s_payload_next = 1'b1;
		end
	end
	if (s_payload_reg) begin
		s_payload_next = 1'b1;
		s_idle_next = 1'b0;
		update_crc = 1'b1;
		m_axis_tvalid_next = 1'b1;
		ptr_next = ptr_reg + 1;
		if (ptr_reg == 7) begin
			m_axis_tdata_next = {m_axis_tdata_int_d7_reg, m_axis_tdata_int_d6_reg,
								 m_axis_tdata_int_d5_reg, m_axis_tdata_int_d4_reg,
								 m_axis_tdata_int_d3_reg, m_axis_tdata_int_d2_reg,
								 m_axis_tdata_int_d1_reg, m_axis_tdata_int_d0_reg};

			m_axis_tkeep_next = {m_axis_tkeep_int_d7_reg, m_axis_tkeep_int_d6_reg,
								 m_axis_tkeep_int_d5_reg, m_axis_tkeep_int_d4_reg,
								 m_axis_tkeep_int_d3_reg, m_axis_tkeep_int_d2_reg,
								 m_axis_tkeep_int_d1_reg, m_axis_tkeep_int_d0_reg};
			ptr_next = {PTR_W{1'b0}};
		end
		// end of packet
		if (!gmii_rx_dv) begin
			m_axis_tlast_next = 1'b1;
			// bad fcs
			m_axis_tuser_next = 1'b1;
			er_bad_fcs_next = 1'b1;
			s_idle_next = 1'b1;
			s_payload_next = 1'b0;
			// good fcs
			if ({gmii_rxd_reg_d0, gmii_rxd_reg_d1, gmii_rxd_reg_d2, gmii_rxd_reg_d3} == ~crc_next) begin
				m_axis_tuser_next = 1'b0;
				er_bad_fcs_next = 1'b0;
			end
			// error receive in fcs
			if (gmii_rx_er_reg_d0 || gmii_rx_er_reg_d1 || gmii_rx_er_reg_d2 || gmii_rx_er_reg_d3) begin
				m_axis_tuser_next = 1'b1;
				er_bad_frame_next = 1'b1;
			end
			// flush remaining data
			m_axis_tdata_next = {m_axis_tdata_int_d7_reg, m_axis_tdata_int_d6_reg,
								 m_axis_tdata_int_d5_reg, m_axis_tdata_int_d4_reg,
								 m_axis_tdata_int_d3_reg, m_axis_tdata_int_d2_reg,
								 m_axis_tdata_int_d1_reg, m_axis_tdata_int_d0_reg};
			
			m_axis_tkeep_next = {KEEP_WIDTH{1'b1}} >> (8 - ptr_reg);
		end
		
		// transfer error
		if (gmii_rx_dv_reg_d4 && gmii_rx_er_reg_d4) begin
			s_wait_end_next = 1'b1;
			s_payload_next = 1'b0;
			s_idle_next = 1'b0;
			m_axis_tvalid_next = 1'b0;
			m_axis_tuser_next = 1'b0;

		end
	end
	if (s_wait_end_reg) begin
		s_idle_next = 1'b1;
		s_wait_end_next = 1'b0;
		if (!gmii_rx_dv) begin
			s_idle_next = 1'b0;
			s_wait_end_next = 1'b1;
		end
	end
end

always @(posedge gmii_clk) begin
	ptr_reg <= ptr_next;

	m_axis_tdata_int_d0_reg <= m_axis_tdata_int_d0_next;
	m_axis_tdata_int_d1_reg <= m_axis_tdata_int_d1_next;
	m_axis_tdata_int_d2_reg <= m_axis_tdata_int_d2_next;
	m_axis_tdata_int_d3_reg <= m_axis_tdata_int_d3_next;
	m_axis_tdata_int_d4_reg <= m_axis_tdata_int_d4_next;
	m_axis_tdata_int_d5_reg <= m_axis_tdata_int_d5_next;
	m_axis_tdata_int_d6_reg <= m_axis_tdata_int_d6_next;
	m_axis_tdata_int_d7_reg <= m_axis_tdata_int_d7_next;
	
	m_axis_tkeep_int_d0_reg <= m_axis_tkeep_int_d0_next;
	m_axis_tkeep_int_d1_reg <= m_axis_tkeep_int_d1_next;
	m_axis_tkeep_int_d2_reg <= m_axis_tkeep_int_d2_next;
	m_axis_tkeep_int_d3_reg <= m_axis_tkeep_int_d3_next;
	m_axis_tkeep_int_d4_reg <= m_axis_tkeep_int_d4_next;
	m_axis_tkeep_int_d5_reg <= m_axis_tkeep_int_d5_next;
	m_axis_tkeep_int_d6_reg <= m_axis_tkeep_int_d6_next;
	m_axis_tkeep_int_d7_reg <= m_axis_tkeep_int_d7_next;

	m_axis_tdata_reg <= m_axis_tdata_next;
	m_axis_tkeep_reg <= m_axis_tkeep_next;
	m_axis_tvalid_reg <= m_axis_tvalid_next;
	m_axis_tlast_reg <= m_axis_tlast_next;
	m_axis_tuser_reg <= m_axis_tuser_next;

	er_bad_fcs_reg <= er_bad_fcs_next;
	er_bad_frame_reg <= er_bad_frame_next;

	if (reset_crc) begin
        crc_state <= 32'hFFFFFFFF;
    end else if (update_crc) begin
        crc_state <= crc_next;
    end

	if (!resetn) begin
		m_axis_tvalid_reg <= 1'b0;
		m_axis_tkeep_reg <= 1'b0;

		ptr_reg <= {PTR_W{1'b0}};

		er_bad_fcs_reg <= 1'b0;
		er_bad_frame_reg <= 1'b0;
	end
end

endmodule
`resetall
