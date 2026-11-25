library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lcd is
    port (
        CLK     : in  std_logic; -- Clock da FPGA (50 MHz)
        RESET   : in  std_logic;
        IR_IN   : in  std_logic_vector(7 downto 0); -- Instrucao atual vinda da CPU
        ARG_IN  : in  std_logic_vector(7 downto 0);
        ARG_VALID : in std_logic;
        POS_255 : in  std_logic_vector(7 downto 0); -- Conteudo de MEM[255] vindo da RAM
        -- Pinos fisicos do display LCD da placa Spartan-3E
        LCD_E   : out std_logic;
        LCD_RS  : out std_logic;
        LCD_RW  : out std_logic;
        LCD_DB  : out std_logic_vector(3 downto 0)  -- Barramento de 4 bits (SF_D<11:8>)
    );
end lcd;

architecture Behavioral of lcd is

    -- Tipo base adaptado de character_to_slv.txt: 16 caracteres = 32 nibbles de 4 bits
    type rom_str is array (0 to 31) of std_logic_vector(3 downto 0);

    -- Converte uma string de exatamente 16 caracteres em 32 nibbles (high nibble primeiro)
    subtype line_text is string(1 to 16);
    function str16_to_rom(a : line_text) return rom_str is
        variable chr2slv : std_logic_vector(7 downto 0);
        variable ret     : rom_str;
    begin
        for i in 1 to 16 loop
            chr2slv              := std_logic_vector(to_unsigned(character'pos(a(i)), 8));
            ret(2 * (i - 1) + 0) := chr2slv(7 downto 4);
            ret(2 * (i - 1) + 1) := chr2slv(3 downto 0);
        end loop;
        return ret;
    end function str16_to_rom;

    -- Converte 8 bits unsigned (0..255) em 3 digitos BCD (Double Dabble)
    function to_bcd_8bit(bin : unsigned(7 downto 0)) return unsigned is
        variable b   : unsigned(7 downto 0)  := bin;
        variable bcd : unsigned(11 downto 0) := (others => '0');
    begin
        for i in 0 to 7 loop
            for d in 0 to 2 loop
                if bcd(d * 4 + 3 downto d * 4) >= 5 then
                    bcd(d * 4 + 3 downto d * 4) := bcd(d * 4 + 3 downto d * 4) + 3;
                end if;
            end loop;
            bcd := bcd(10 downto 0) & b(7);
            b   := b(6 downto 0) & '0';
        end loop;
        return bcd;
    end function to_bcd_8bit;

    -- Retorna o nome do registrador (2 caracteres) a partir de 2 bits
    function reg_name(r : std_logic_vector(1 downto 0)) return string is
    begin
        case r is
            when "00"   => return "Ra";
            when "01"   => return "Rb";
            when "10"   => return "Rc";
            when others => return "Rd";
        end case;
    end function reg_name;

    function hex_digit(nibble : std_logic_vector(3 downto 0)) return character is
        constant digits : string(1 to 16) := "0123456789ABCDEF";
    begin
        return digits(1 + to_integer(unsigned(nibble)));
    end function hex_digit;

    -- Decodifica qualquer byte de IR (0..255) para o mnemonico Assembly de 16 caracteres
    function decode_ir_to_rom(
        ir, arg : std_logic_vector(7 downto 0);
        valid : std_logic
    ) return rom_str is
        variable op   : std_logic_vector(3 downto 0) := ir(7 downto 4);
        variable rx   : string(1 to 2) := reg_name(ir(3 downto 2));
        variable ry   : string(1 to 2) := reg_name(ir(1 downto 0));
        variable func : std_logic_vector(1 downto 0) := ir(1 downto 0);
        variable hex_arg : string(1 to 2) := "--";
    begin
        if valid = '1' then
            hex_arg := hex_digit(arg(7 downto 4)) & hex_digit(arg(3 downto 0));
        end if;
        case op is
            when "0000" => return str16_to_rom("add " & rx & ", " & ry & "      ");
            when "0001" => return str16_to_rom("sub " & rx & ", " & ry & "      ");
            when "0010" =>
                if func = "00" then
                    return str16_to_rom("inc " & rx & "          ");
                elsif func = "01" then
                    return str16_to_rom("dec " & rx & "          ");
                else
                    return str16_to_rom("nop             ");
                end if;
            when "0011" => return str16_to_rom("and " & rx & ", " & ry & "      ");
            when "0100" => return str16_to_rom("or " & rx & ", " & ry & "       ");
            when "0101" =>
                if func = "00" then
                    return str16_to_rom("not " & rx & "          ");
                else
                    return str16_to_rom("nop             ");
                end if;
            when "0110" => return str16_to_rom("xor " & rx & ", " & ry & "      ");
            when "0111" =>
                case func is
                    when "00"   => return str16_to_rom("rol " & rx & "          ");
                    when "01"   => return str16_to_rom("ror " & rx & "          ");
                    when "10"   => return str16_to_rom("lsl " & rx & "          ");
                    when others => return str16_to_rom("lsr " & rx & "          ");
                end case;
            when "1000" =>
                case func is
                    when "00"   => return str16_to_rom("push " & rx & "         ");
                    when "01"   => return str16_to_rom("pop " & rx & "          ");
                    when "10"   => return str16_to_rom("st " & rx & ", 0x" & hex_arg & "     ");
                    when others => return str16_to_rom("ldi " & rx & ", 0x" & hex_arg & "    ");
                end case;
            when "1001" => return str16_to_rom("ldr " & rx & ", [" & ry & "]    ");
            when "1010" => return str16_to_rom("str " & rx & ", [" & ry & "]    ");
            when "1011" => return str16_to_rom("mov " & rx & ", " & ry & "      ");
            when "1100" =>
                case func is
                    when "00" =>
                        if ir(3 downto 2) = "00" then
                            return str16_to_rom("jmp 0x" & hex_arg & "        ");
                        else
                            return str16_to_rom("nop             ");
                        end if;
                    when "01"   => return str16_to_rom("jmpr " & rx & "         ");
                    when "10"   => return str16_to_rom("bz " & rx & "           ");
                    when others => return str16_to_rom("bnz " & rx & "          ");
                end case;
            when "1101" =>
                case func is
                    when "00"   => return str16_to_rom("bcs " & rx & "          ");
                    when "01"   => return str16_to_rom("bcc " & rx & "          ");
                    when "10"   => return str16_to_rom("beq " & rx & "          ");
                    when others => return str16_to_rom("bneq " & rx & "         ");
                end case;
            when "1110" =>
                case func is
                    when "00"   => return str16_to_rom("bgt " & rx & "          ");
                    when "01"   => return str16_to_rom("blt " & rx & "          ");
                    when "10"   => return str16_to_rom("bneg " & rx & "         ");
                    when others => return str16_to_rom("nop             ");
                end case;
            when "1111" =>
                if ir = "11111111" then
                    return str16_to_rom("halt            ");
                else
                    return str16_to_rom("nop             ");
                end if;
            when others =>
                return str16_to_rom("nop             ");
        end case;
    end function decode_ir_to_rom;

    -- Buffers das duas linhas do LCD (32 nibbles cada)
    signal line1_rom : rom_str;
    signal line2_rom : rom_str;
    signal frame_line1, frame_line2 : rom_str := (others => (others => '0'));
    signal bcd_val   : unsigned(11 downto 0);

    -- Sequencia de comandos de inicializacao do controlador HD44780 (modo 4 bits)
    -- Cada comando completo tem 2 nibbles (high, low)
    type init_array_t is array (0 to 13) of std_logic_vector(3 downto 0);
    constant INIT_NIBBLES : init_array_t := (
        x"3", -- 0: Wake-up 1 (apenas 1 nibble)
        x"3", -- 1: Wake-up 2 (apenas 1 nibble)
        x"3", -- 2: Wake-up 3 (apenas 1 nibble)
        x"2", -- 3: Ativa modo 4 bits (apenas 1 nibble)
        x"2", x"8", -- 4,5: Function Set (0x28: 4-bit, 2 linhas, 5x8)
        x"0", x"6", -- 6,7: Entry Mode (0x06: incrementa cursor)
        x"0", x"C", -- 8,9: Display ON, Cursor OFF (0x0C)
        x"0", x"1", -- 10,11: Clear Display (0x01)
        x"8", x"0"  -- 12,13: Posiciona cursor na Linha 1 (0x80)
    );

    -- Maquina de estados do LCD (clock de 50 MHz -> 1 ciclo = 20 ns)
    type lcd_state_t is (
        POWER_ON,
        INIT_LOAD,
        SEND_SETUP,
        SEND_ENABLE,
        SEND_HOLD,
        WAIT_STEP,
        LOOP_PREPARE
    );
    signal state      : lcd_state_t := POWER_ON;
    signal timer      : integer range 0 to 1000000 := 0;
    signal delay_cycles : integer range 0 to 1000000 := 750000; -- 15 ms inicial
    signal init_idx   : integer range 0 to 13 := 0;
    signal char_idx   : integer range 0 to 31 := 0;
    signal phase      : integer range 0 to 3 := 0; -- 0=Cmd L1, 1=Texto L1, 2=Cmd L2, 3=Texto L2
    signal cmd_nib    : std_logic := '0'; -- 0=high nibble, 1=low nibble
    signal cur_nibble : std_logic_vector(3 downto 0) := (others => '0');
    signal cur_rs     : std_logic := '0';

begin

    -- Sempre escrita no LCD
    LCD_RW <= '0';

    -- Atualizacao combinacional da Linha 1 (Instrucao atual no IR)
    line1_rom <= decode_ir_to_rom(IR_IN, ARG_IN, ARG_VALID);

    -- Atualizacao combinacional da Linha 2: "MEM[255] = XXX  "
    bcd_val <= to_bcd_8bit(unsigned(POS_255));
    process(bcd_val)
        variable base : rom_str;
    begin
        base := str16_to_rom("MEM[255] = 000  ");
        -- Substitui os nibbles inferiores dos caracteres 12, 13 e 14 pelos 3 digitos BCD
        -- Como '0'..'9' em ASCII sao 0x30..0x39, o nibble alto ja e x"3"
        base(23) := std_logic_vector(bcd_val(11 downto 8)); -- Centena
        base(25) := std_logic_vector(bcd_val(7 downto 4));  -- Dezena
        base(27) := std_logic_vector(bcd_val(3 downto 0));  -- Unidade
        line2_rom <= base;
    end process;

    -- FSM de controle do barramento fisico do LCD (50 MHz)
    process(CLK)
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                state      <= POWER_ON;
                timer      <= 0;
                delay_cycles <= 750000; -- 15 ms
                init_idx   <= 0;
                char_idx   <= 0;
                phase      <= 0;
                cmd_nib    <= '0';
                LCD_E      <= '0';
                LCD_RS     <= '0';
                LCD_DB     <= (others => '0');
            else
                case state is
                    -- Aguarda 15 ms apos ligar/resetar a placa
                    when POWER_ON =>
                        LCD_E <= '0';
                        if timer < 750000 then
                            timer <= timer + 1;
                        else
                            timer    <= 0;
                            init_idx <= 0;
                            state    <= INIT_LOAD;
                        end if;

                    -- Carrega proximo nibble da sequencia de inicializacao
                    when INIT_LOAD =>
                        cur_rs     <= '0';
                        cur_nibble <= INIT_NIBBLES(init_idx);
                        -- Define tempo de espera apos este nibble
                        case init_idx is
                            when 0      => delay_cycles <= 250000; -- 5 ms (> 4.1 ms)
                            when 1      => delay_cycles <= 10000;  -- 200 us (> 100 us)
                            when 2 | 3  => delay_cycles <= 5000;   -- 100 us (> 40 us)
                            when 11     => delay_cycles <= 100000; -- 2 ms apos Clear Display (0x01)
                            when others =>
                                -- Nibbles altos esperam 1 us (50 ciclos), nibbles baixos esperam 50 us (2500 ciclos)
                                if (init_idx mod 2) = 0 then
                                    delay_cycles <= 50;
                                else
                                    delay_cycles <= 2500;
                                end if;
                        end case;
                        timer <= 0;
                        state <= SEND_SETUP;

                    -- Setup de RS e DB antes da subida de LCD_E (100 ns = 5 ciclos)
                    when SEND_SETUP =>
                        LCD_RS <= cur_rs;
                        LCD_DB <= cur_nibble;
                        LCD_E  <= '0';
                        if timer < 5 then
                            timer <= timer + 1;
                        else
                            timer <= 0;
                            state <= SEND_ENABLE;
                        end if;

                    -- Pulso de Enable ativo por pelo menos 600 ns
                    when SEND_ENABLE =>
                        LCD_E <= '1';
                        if timer < 30 then
                            timer <= timer + 1;
                        else
                            timer <= 0;
                            state <= SEND_HOLD;
                        end if;

                    -- Desce LCD_E e mantem dados estaveis por 100 ns (5 ciclos)
                    when SEND_HOLD =>
                        LCD_E <= '0';
                        if timer < 5 then
                            timer <= timer + 1;
                        else
                            timer <= 0;
                            state <= WAIT_STEP;
                        end if;

                    -- Aguarda o tempo de processamento do controlador LCD
                    when WAIT_STEP =>
                        if timer < delay_cycles then
                            timer <= timer + 1;
                        else
                            timer <= 0;
                            if init_idx < 13 then
                                init_idx <= init_idx + 1;
                                state    <= INIT_LOAD;
                            else
                                -- Inicializacao concluida; inicia loop continuo de atualizacao
                                state <= LOOP_PREPARE;
                            end if;
                        end if;

                    -- Loop continuo: atualiza Linha 1 (IR) e Linha 2 (MEM[255])
                    when LOOP_PREPARE =>
                        case phase is
                            -- Fase 0: Envia comando 0x80 (inicio da Linha 1)
                            when 0 =>
                                cur_rs <= '0';
                                if cmd_nib = '0' then
                                    -- Captura as duas linhas antes de transmitir o quadro.
                                    frame_line1 <= line1_rom;
                                    frame_line2 <= line2_rom;
                                    cur_nibble <= x"8";
                                    delay_cycles <= 50;
                                    cmd_nib    <= '1';
                                else
                                    cur_nibble <= x"0";
                                    delay_cycles <= 2500;
                                    cmd_nib    <= '0';
                                    char_idx   <= 0;
                                    phase      <= 1;
                                end if;

                            -- Fase 1: Envia os 32 nibbles (16 chars) da Linha 1
                            when 1 =>
                                cur_rs     <= '1';
                                cur_nibble <= frame_line1(char_idx);
                                if (char_idx mod 2) = 0 then
                                    delay_cycles <= 50;
                                else
                                    delay_cycles <= 2500;
                                end if;
                                if char_idx < 31 then
                                    char_idx <= char_idx + 1;
                                else
                                    char_idx <= 0;
                                    phase    <= 2;
                                end if;

                            -- Fase 2: Envia comando 0xC0 (inicio da Linha 2)
                            when 2 =>
                                cur_rs <= '0';
                                if cmd_nib = '0' then
                                    cur_nibble <= x"C";
                                    delay_cycles <= 50;
                                    cmd_nib    <= '1';
                                else
                                    cur_nibble <= x"0";
                                    delay_cycles <= 2500;
                                    cmd_nib    <= '0';
                                    char_idx   <= 0;
                                    phase      <= 3;
                                end if;

                            -- Fase 3: Envia os 32 nibbles (16 chars) da Linha 2
                            when 3 =>
                                cur_rs     <= '1';
                                cur_nibble <= frame_line2(char_idx);
                                if (char_idx mod 2) = 0 then
                                    delay_cycles <= 50;
                                else
                                    delay_cycles <= 2500;
                                end if;
                                if char_idx < 31 then
                                    char_idx <= char_idx + 1;
                                else
                                    char_idx <= 0;
                                    phase    <= 0; -- Reinicia refresh continuo
                                end if;
                        end case;
                        timer <= 0;
                        state <= SEND_SETUP;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
