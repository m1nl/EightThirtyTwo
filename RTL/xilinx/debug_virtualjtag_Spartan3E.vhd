library ieee;
use ieee.std_logic_1164.all;

package debug_jtag_plumbing is

type debug_jtag_to_reg is record
	tck : std_logic;
	tdi : std_logic;
	sel : std_logic;
	rst : std_logic;
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
use ieee.numeric_std.all;

Library UNISIM;
use UNISIM.vcomponents.all;

library work;
use work.debug_jtag_plumbing.all;

entity debug_virtualjtag is
port (
	from_regs : in debug_jtag_from_regs;
	to_regs : out debug_jtag_to_regs
);
end entity;

architecture rtl of debug_virtualjtag is
	signal tck1, tck2 : std_logic;
	signal tdi,shift,update,capture,rst,jce1,jce2 : std_logic;
begin

to_regs(0).tck <= tck1;
to_regs(0).sel <= jce1;
to_regs(0).tdi <= tdi;
to_regs(0).sel <= jce1;
to_regs(0).rst <= rst;
to_regs(0).capture <= capture;
to_regs(0).shift <= shift;
to_regs(0).update <= update;

to_regs(1).tck <= tck2;
to_regs(1).sel <= jce2;
to_regs(1).tdi <= tdi;
to_regs(1).sel <= jce2;
to_regs(1).rst <= rst;
to_regs(1).capture <= capture;
to_regs(1).shift <= shift;
to_regs(1).update <= update;

irscan : BSCAN_SPARTAN3
port map (
	CAPTURE => capture,       -- 1-bit output: CAPTURE output from TAP controller.
	DRCK1 => tck1,            -- 1-bit output: Gated TCK output. When SEL is asserted, DRCK toggles when CAPTURE or
                              -- SHIFT are asserted.
	DRCK2 => tck2,            
	RESET=> rst,              -- 1-bit output: Reset output for TAP controller.
	SEL1 => jce1,             -- 1-bit output: USER instruction active output.
	SEL2 => jce2,             -- 1-bit output: USER instruction active output.
	SHIFT => shift,           -- 1-bit output: SHIFT output from TAP controller.
	TDI => tdi,               -- 1-bit output: Test Data Input (TDI) output from TAP controller.
	UPDATE => update,         -- 1-bit output: UPDATE output from TAP controller
	TDO1 => from_regs(0).tdo, -- 1-bit input: Test Data Output (TDO) input for USER function.
	TDO2 => from_regs(1).tdo  -- 1-bit input: Test Data Output (TDO) input for USER function.
);

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

	process(from_jtag.tck,from_jtag.rst) begin
		if from_jtag.rst='1' then
			shiftreg<=(others => '0');
		elsif rising_edge(from_jtag.tck) then
			if from_jtag.shift='1' then
				shiftreg <= from_jtag.tdi & shiftreg(shiftreg'high downto 1);
			end if;
			if from_jtag.capture='1' then
				shiftreg<=d;
			end if;
		end if;
	end process;

	process(from_jtag.update) begin
		if rising_edge(from_jtag.update) then
			if from_jtag.sel='1' then
				q<=shiftreg;
				toggle<=not toggle;
			end if;
		end if;
	end process;

	process(clk) begin
		if rising_edge(clk) then
			toggle_s <= toggle & toggle_s(toggle_s'high downto 1);
			upd_sys <= toggle_s(1) xor toggle_s(0);
		end if;
	end process;
end architecture;

