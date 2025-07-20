-- Virtual JTAG wrapper for ECP5 JTAGG primitive.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.debug_jtag_plumbing.all;

entity debug_bridge_jtag is
generic (
	id : natural := 16#832d#
);
port(
	clk : in std_logic;
	reset_n : in std_logic;
	-- Design interface
	d : in std_logic_vector(31 downto 0);
	q : out std_logic_vector(31 downto 0);
	req : in std_logic;
	wr : in std_logic;
	ack : out std_logic
);
end entity;

architecture rtl of debug_bridge_jtag is
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

