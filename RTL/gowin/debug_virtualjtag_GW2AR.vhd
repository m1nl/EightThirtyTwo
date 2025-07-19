library ieee;
use ieee.std_logic_1164.all;

package debug_jtag_plumbing is

type debug_jtag_to_reg is record
	tck : std_logic;
	tdi : std_logic;
	sel : std_logic;
	capture : std_logic;
	shift : std_logic;
	update : std_logic;
end record;

type debug_jtag_to_regs is array (0 to 1) of debug_jtag_to_reg;

type debug_jtag_from_reg is record
	tdo : std_logic;
end record;

type debug_jtag_from_regs is array (0 to 1) of debug_jtag_from_reg;

end package;


library ieee;
use ieee.std_logic_1164.all;

library work;
use work.debug_jtag_plumbing.all;


entity debug_virtualjtag is
port (
	from_regs : in debug_jtag_from_regs;
	to_regs : out debug_jtag_to_regs
);
end entity;

architecture rtl of debug_virtualjtag is
	signal jtck : std_logic;
	signal jtdi,jshift,jupdate,jrstn,jce1,jce2 : std_logic;
	signal jhold : std_logic;

	-- JTAG instance needs to be instantiated from verilog in order to leave the
	-- physical pins unconnected and therefore implicit.
	component gwjtag_wrapper is
	port (
		tck_o : out std_logic;--                //DRCK_IN
		tdi_o : out std_logic;--                //TDI_IN
		test_logic_reset_o : out std_logic;--   //RESET_IN
		run_test_idle_er1_o : out std_logic;--   
		run_test_idle_er2_o : out std_logic;   
		shift_dr_capture_dr_o : out std_logic;--//SHIFT_IN|CAPTURE_IN
		pause_dr_o : out std_logic;     
		update_dr_o : out std_logic;--          //UPDATE_IN
		enable_er1_o : out std_logic;--         //SEL_IN
		enable_er2_o : out std_logic;--         //SEL_IN
		tdo_er1_i : in std_logic;--            //TDO_OUT
		tdo_er2_i : in std_logic--             //TDO_OUT
	);
	end component;

begin

	-- The JTAG instance
	jtg : component gwjtag_wrapper
	port map(
		tck_o => jtck,
		tdi_o => jtdi,
		test_logic_reset_o => jrstn,
		run_test_idle_er1_o => open,
		run_test_idle_er2_o => open,
		shift_dr_capture_dr_o => jshift,
		pause_dr_o => open,
		update_dr_o => jupdate,
		enable_er1_o => jce1,
		enable_er2_o => jce2,
		tdo_er1_i => from_regs(0).tdo,
		tdo_er2_i => from_regs(1).tdo
	);

	to_regs(0).tck <= jtck;
	to_regs(1).tck <= jtck;

	to_regs(0).tdi <= jtdi;
	to_regs(1).tdi <= jtdi;

	to_regs(0).sel <= jce1;
	to_regs(1).sel <= jce2;

	-- The GWJTAG primitive doesn't supply a capture signal, so we
	-- just capture any time we're not shifting or updating.
	-- This works OK provided no action is taken on capture other than
	-- loading the shift register.
	-- Advancing a FIFO or acknowledging a shift should be done on update instead.

	process(jtck) begin
		if rising_edge(jtck) then
			if jshift='1' then
				jhold <= '1';
			elsif jupdate='1' then
				jhold <= '0';
			end if;
		end if;
	end process;

	to_regs(0).capture <= jce1 and (not jshift) and (not jhold);
	to_regs(1).capture <= jce2 and (not jshift) and (not jhold);
	to_regs(0).shift <= jce1 and jshift;
	to_regs(1).shift <= jce2 and jshift;

	to_regs(0).update <= jupdate and jce1;
	to_regs(1).update <= jupdate and jce2;

end architecture;


library ieee;
use ieee.std_logic_1164.all;

library work;
use work.debug_jtag_plumbing.all;

entity vjtag_register is
generic (
	bits : integer := 32
);
port (
	-- JTAG clock domain
	from_jtag : in debug_jtag_to_reg;
	to_jtag : out debug_jtag_from_reg;

	-- System clock domain
	clk : in std_logic;
	d : in std_logic_vector(bits-1 downto 0);
	q : out std_logic_vector(bits-1 downto 0);
	upd_sys : out std_logic
);
end entity;

architecture rtl of vjtag_register is
	signal shiftreg : std_logic_vector(bits-1 downto 0);
	signal tck_inv : std_logic;
	signal toggle : std_logic := '0';
	signal toggle_s : std_logic_vector(2 downto 0) := (others => '0');
begin
	to_jtag.tdo <= shiftreg(0);

	process(from_jtag.tck) begin
		if rising_edge(from_jtag.tck) then
			if from_jtag.shift='1' then
				shiftreg<=from_jtag.tdi & shiftreg(bits-1 downto 1);
			end if;

			if from_jtag.capture='1' then
				shiftreg<=d;
			end if;
		end if;
	end process;

	process(from_jtag.tck) begin
		if rising_edge(from_jtag.tck) then
			if from_jtag.update='1' then
				q<=shiftreg; -- shift_next;
				toggle <= not toggle;
			end if;
		end if;
	end	process;

	-- Move the update pulse into the system clock domain

	process(clk) begin
		if rising_edge(clk) then
			toggle_s <= toggle & toggle_s(toggle_s'high downto 1);
			upd_sys <= toggle_s(1) xor toggle_s(0);
		end if;
	end process;

end architecture;

