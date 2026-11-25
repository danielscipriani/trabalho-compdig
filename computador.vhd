library ieee;
use ieee.std_logic_1164.all;

entity computador is
    generic (
        INSTRUCTION_CYCLES : positive := 100000000;
        RESET_RELEASE_CYCLES : positive := 250000
    );
    port (
        CLK_50MHZ : in  std_logic;
        SW_RESET  : in  std_logic;
        LED       : out std_logic_vector(7 downto 0);
        LCD_E     : out std_logic;
        LCD_RS    : out std_logic;
        LCD_RW    : out std_logic;
        LCD_DB    : out std_logic_vector(3 downto 0);
        SF_CE0    : out std_logic
    );
end computador;

architecture rtl of computador is
    signal reset_meta, reset_sync : std_logic := '1';
    signal reset_cpu : std_logic := '1';
    signal reset_timer : natural range 0 to RESET_RELEASE_CYCLES - 1 := 0;
    signal instruction_timer : natural range 0 to INSTRUCTION_CYCLES - 1 := 0;
    signal run_next : std_logic;
    signal ram_din, ram_dout, ram_addr, pos_255 : std_logic_vector(7 downto 0);
    signal ram_we : std_logic;
    signal flags : std_logic_vector(5 downto 0);
    signal instruction, argument : std_logic_vector(7 downto 0);
    signal argument_valid : std_logic;
begin
    process(CLK_50MHZ)
    begin
        if rising_edge(CLK_50MHZ) then
            reset_meta <= SW_RESET;
            reset_sync <= reset_meta;

            -- A chave deve ficar em zero por 5 ms para liberar o reset.
            if reset_sync = '1' then
                reset_timer <= 0;
                reset_cpu <= '1';
            elsif reset_timer = RESET_RELEASE_CYCLES - 1 then
                reset_cpu <= '0';
            else
                reset_timer <= reset_timer + 1;
            end if;

            if reset_cpu = '1' or instruction_timer = INSTRUCTION_CYCLES - 1 then
                instruction_timer <= 0;
            else
                instruction_timer <= instruction_timer + 1;
            end if;
        end if;
    end process;

    -- Libera um fetch por periodo. Os estados internos usam o clock da placa.
    run_next <= '1' when instruction_timer = 0 else '0';
    LED(7) <= '1' when reset_cpu = '0' and
                       instruction_timer < INSTRUCTION_CYCLES / 2 else '0';
    LED(6 downto 1) <= flags;
    LED(0) <= '0';
    SF_CE0 <= '1'; -- Desabilita a flash, que compartilha pinos com o LCD.

    u_cpu : entity work.cpu(Behavioral)
        port map (
            CLK => CLK_50MHZ, RESET => reset_cpu, RUN_NEXT => run_next,
            RAM_DIN => ram_din, RAM_DOUT => ram_dout, RAM_ADDR => ram_addr,
            WE => ram_we, FLAGS_OUT => flags, IR_OUT => instruction,
            ARG_OUT => argument, ARG_VALID => argument_valid
        );

    u_ram : entity work.RAM_8x256(rtl)
        port map (
            CLK => CLK_50MHZ, DIN => ram_din, ADDR => ram_addr, WE => ram_we,
            DOUT => ram_dout, POS_255 => pos_255
        );

    u_lcd : entity work.lcd(Behavioral)
        port map (
            CLK => CLK_50MHZ, RESET => reset_cpu, IR_IN => instruction,
            ARG_IN => argument, ARG_VALID => argument_valid, POS_255 => pos_255,
            LCD_E => LCD_E, LCD_RS => LCD_RS, LCD_RW => LCD_RW, LCD_DB => LCD_DB
        );
end rtl;
