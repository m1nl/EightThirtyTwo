-- debug_bridge_bscan.vhd
-- Copyright 2020 by Alastair M. Robinson

-- This file is part of the EightThirtyTwo CPU project.

-- EightThirtyTwo is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- EightThirtyTwo is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with EightThirtyTwo.  If not, see <https://www.gnu.org/licenses/>.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.debug_jtag_plumbing.all;

entity debug_bridge_jtag is
generic (
	id : natural := 16#832D#
);
port (
	clk : in std_logic;
	reset_n : in std_logic;
	d : in std_logic_vector(31 downto 0);
	q : out std_logic_vector(31 downto 0);
	req : in std_logic;
	wr : in std_logic;
	ack : buffer std_logic
);
end entity;

architecture rtl of debug_bridge_jtag is

signal clk_inv : std_logic;

type states is (IDLE, READADDR,GETRESPONSE,STEP);
signal state : states ;
signal counter : unsigned(15 downto 0);
signal data : std_logic_vector(31 downto 0);

-- JTAG signals

constant TX	: std_logic_vector(1 downto 0) := "00";
constant RX	: std_logic_vector(1 downto 0) := "01";
constant STATUS : std_logic_vector(1 downto 0) := "10";
constant BYPASS : std_logic_vector(1 downto 0) := "11";

signal ir : std_logic_vector(1 downto 0);
signal vstate_cdr : std_logic;
signal vstate_sdr : std_logic;
signal vstate_udr : std_logic;
signal vstate_uir : std_logic;

signal from_jtag : debug_jtag_to_regs;
signal to_jtag : debug_jtag_from_regs;

signal tdo : std_logic;
signal tdi : std_logic;
signal tck : std_logic;

signal cdr_d : std_logic;
signal sdr_d : std_logic;

signal shift : std_logic_vector(31 downto 0);
signal bp : std_logic_vector(1 downto 0);

-- FIFO control signals

signal txmt : std_logic;
signal txfl : std_logic;
signal txdata : std_logic_vector(31 downto 0);
signal txwr_req : std_logic;
signal txrd_req : std_logic;

signal rxmt : std_logic;
signal rxfl : std_logic;
signal rxwr_req : std_logic;
signal rxrd_req : std_logic;

begin

clk_inv <= not clk;

to_jtag(1).tdo <= shift(0);

virtualjtag : entity work.debug_virtualjtag
port map(
	to_regs => from_jtag,
	from_regs => to_jtag
);


fifotojtag : entity work.debug_fifo
port map (
	din => d,
	wr_clk => clk_inv,
	wr_en => txwr_req,
	full => txfl,

	rd_clk => tck,
	rd_en => txrd_req,
	dout => txdata,
	empty => txmt
);

txrd_req <= vstate_cdr when ir=TX else '0';


fifofromjtag : entity work.debug_fifo
port map (
	din => shift,
	wr_clk => tck,
	wr_en => rxwr_req,
	full => rxfl,

	rd_clk => clk_inv,
	rd_en => rxrd_req,
	dout => q,
	empty => rxmt
);

rxwr_req <= vstate_udr when ir=RX else '0';


process(clk,reset_n)
begin

	if reset_n='0' then

	elsif rising_edge(clk) then
	
		rxrd_req<='0';
		txwr_req<='0';
		ack<='0';
	
		if req='1' and ack='0' then
			if wr='1' and txfl='0' then
				txwr_req<='1';
				ack<='1';
			elsif wr='0' and rxmt='0' then
				rxrd_req<='1';
				ack<='1';
			end if;
		end if;
		
--		if rxrd_req='1' then
--			ack<='1';
--		end if;
	
	end if;

end process;


cdr_d <= vstate_cdr;
sdr_d <= vstate_sdr;

process (tck)
begin
	if rising_edge(tck) then
		case ir is
			when TX =>
				if cdr_d='1' then
					shift <= txdata;
				elsif sdr_d='1' then
					shift <= tdi&shift(31 downto 1);
				end if;

			when RX =>
				if sdr_d='1' then
					shift <= tdi&shift(31 downto 1);
				end if;

			when STATUS =>
				if cdr_d='1' then
					shift <= std_logic_vector(to_unsigned(id,16))
									&X"000"& rxfl & rxmt & txfl & txmt;
				elsif sdr_d='1' then 
					shift <= tdi&shift(31 downto 1);
				end if;

			when others =>
				if sdr_d='1' then
					bp <= tdi&bp(1);
				end if;
		end case;

	end if;

end process;

end architecture;architecture rtl of debug_bridge_jtag is
	-- JTAG signals
	signal to_regs : debug_jtag_to_regs;
	signal from_regs : debug_jtag_from_regs;

	-- FIFO signals
	-- to JTAG
	signal tjrd,tjwr,tjempty,tjfull : std_logic;
	signal tjd : std_logic_vector(31 downto 0);
	-- from JTAG
	signal fjrd,fjwr,fjempty,fjfull : std_logic;
	signal fjq : std_logic_vector(31 downto 0);	
	
	signal vir : std_logic_vector(31 downto 0);
	signal vir_in : std_logic_vector(31 downto 0);
	signal vir_update : std_logic;
	signal vdr_update : std_logic;

	signal ack_i : std_logic;

begin

	-- Some glue logic to give us separate capture and update signals for the two user registers

	jtagctrl : block
		signal jtdi : std_logic;
		signal jtdo : std_logic_vector(1 downto 0);
	begin

		vjtag : entity work.debug_virtualjtag
		port map (
			from_regs => from_regs,
			to_regs => to_regs
		);
		
		-- Create a pair of registers to be accessed over the JTAG chain

		virtual_ir : entity work.vjtag_register
		generic map (
			bits => 32
		)
		port map (
			from_jtag => to_regs(0),
			to_jtag => from_regs(0),
			clk => clk,
			d => vir_in,
			q => vir,
			upd_sys => vir_update
		);

		virtual_dr : entity work.vjtag_register
		generic map (
			bits => 32
		)
		port map (
			from_jtag => to_regs(1),
			to_jtag => from_regs(1),
			clk => clk,
			d => tjd,
			q => fjq,
			upd_sys => vdr_update
		);
	end block;

	
	-- FIFO to JTAG

	fifotojtag : entity work.debug_fifo
	generic map (
		width => 32,
		depth => 4
	)
	port map(
		reset_n => reset_n,
		rd_clk => clk,
		rd_en => tjrd,
		dout => tjd,
		empty => tjempty,
		
		wr_clk => clk,
		wr_en => tjwr,
		din => d,
		full => tjfull
	);

	process (clk) begin
		if rising_edge(clk) then
			tjrd <= '0';
			fjwr <= '0';
			if vir(1 downto 0) = "00" then
--				tjrd <= capture(1) and not tjempty; -- Lag capture by 1 cycle
				-- Step the FIFO on update rather than delayed capture since Gowin's JTAG primitive doesn't supply a proper capture signal.
				tjrd <= vdr_update and not tjempty;
			end if;
			if vir(1 downto 0) = "01" then
				fjwr <= vdr_update and not fjfull; 
			end if;
		end if;
	end process;


	-- FIFO from JTAG

	fifofromjtag : entity work.debug_fifo
	generic map (
		width => 32,
		depth => 4
	)
	port map(
		reset_n => reset_n,
		rd_clk => clk,
		rd_en => fjrd,
		dout => q,
		empty => fjempty,

		wr_clk => clk,
		wr_en => fjwr,
		din => fjq,
		full => fjfull
	);


	-- Virtual IR, contains fifo state and an ID
	
	vir_in <= std_logic_vector(to_unsigned(id,16)) & req & ack_i & vir(9 downto 0) & fjfull & fjempty & tjfull & tjempty;

	-- Req/ack interface to DR FIFOs

	ack <= ack_i;
	process(clk,reset_n) begin	
		if reset_n='0' then
			tjwr<='0';
			fjrd<='0';
			ack_i<='0';
		elsif rising_edge(clk) then
			tjwr<='0';
			fjrd<='0';
			ack_i<='0';
			if req='1' and ack_i='0' then
				if wr='1' and tjfull='0' then
					tjwr<='1';
					ack_i<='1';
				end if;
				if wr='0' and fjempty='0' then
					fjrd<='1';
					ack_i<='1';
				end if;
			end if;		
		end if;
	end process;

end architecture;



