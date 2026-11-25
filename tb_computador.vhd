library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_computador is
end tb_computador;

architecture test of tb_computador is
    signal clk : std_logic := '0';
    signal reset_switch : std_logic := '1';
    signal led : std_logic_vector(7 downto 0);
    signal lcd_e, lcd_rs, lcd_rw, flash_ce : std_logic;
    signal lcd_db : std_logic_vector(3 downto 0);
    signal finished : boolean := false;
begin
    clk <= not clk after 10 ns when not finished else '0';
    reset_switch <= '0' after 100 ns;

    dut : entity work.computador(rtl)
        generic map (INSTRUCTION_CYCLES => 2000000, RESET_RELEASE_CYCLES => 2)
        port map (
            CLK_50MHZ => clk, SW_RESET => reset_switch, LED => led,
            LCD_E => lcd_e, LCD_RS => lcd_rs, LCD_RW => lcd_rw,
            LCD_DB => lcd_db, SF_CE0 => flash_ce
        );

    process
        subtype nibble is std_logic_vector(3 downto 0);
        type init_sequence is array (natural range <>) of nibble;
        constant init : init_sequence := (x"3", x"3", x"3", x"2", x"2", x"8",
                                           x"0", x"6", x"0", x"C", x"0", x"1", x"8", x"0");
        variable value : nibble;
        variable line1, line2 : string(1 to 16);
        variable saw_store : boolean := false;

        procedure receive_nibble(constant rs : in std_logic; variable data : out nibble) is
        begin
            wait until falling_edge(lcd_e);
            assert lcd_rs = rs and lcd_rw = '0' and flash_ce = '1'
                report "Sinais de controle do LCD invalidos" severity failure;
            data := lcd_db;
        end procedure;

        procedure receive_line(constant addr : in nibble; variable data : out string) is
            variable lcd_byte : std_logic_vector(7 downto 0);
        begin
            receive_nibble('0', lcd_byte(7 downto 4));
            receive_nibble('0', lcd_byte(3 downto 0));
            assert lcd_byte = (addr & x"0")
                report "Endereco incorreto da linha do LCD" severity failure;
            for i in data'range loop
                receive_nibble('1', lcd_byte(7 downto 4));
                receive_nibble('1', lcd_byte(3 downto 0));
                data(i) := character'val(to_integer(unsigned(lcd_byte)));
            end loop;
        end procedure;
    begin
        for i in init'range loop
            receive_nibble('0', value);
            assert value = init(i)
                report "Sequencia de inicializacao incorreta" severity failure;
        end loop;

        receive_line(x"8", line1);
        receive_line(x"C", line2);
        assert line1 = "ldi Ra, 0x05    " and line2 = "MEM[255] = 000  "
            report "Primeira instrucao ou valor inicial de MEM[255] incorreto" severity failure;

        loop
            receive_line(x"8", line1);
            receive_line(x"C", line2);
            if line1 = "st Rc, 0xFF     " and line2 = "MEM[255] = 008  " then
                saw_store := true;
            end if;
            exit when line1 = "halt            ";
        end loop;
        assert saw_store and line2 = "MEM[255] = 008  "
            report "LCD nao exibiu a escrita em MEM[255]" severity failure;
        assert led(6 downto 0) = "0110010"
            report "Flags nos pinos dos LEDs incorretas" severity failure;
        report "SUCESSO: inicializacao, duas linhas do LCD e LEDs verificados" severity note;
        finished <= true;
        wait;
    end process;

    process
    begin
        wait until finished for 400 ms;
        assert finished report "Tempo excedido no teste de integracao" severity failure;
        wait;
    end process;
end test;
