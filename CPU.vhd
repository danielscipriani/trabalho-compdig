library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu is
    port (
        CLK       : in  std_logic;
        RESET     : in  std_logic;
        -- Interface com a Memoria RAM (RAM_8x256)
        RAM_DIN   : out std_logic_vector(7 downto 0);
        RAM_DOUT  : in  std_logic_vector(7 downto 0);
        RAM_ADDR  : out std_logic_vector(7 downto 0);
        WE        : out std_logic;
        -- Saidas para interface com usuario (LEDs e LCD)
        FLAGS_OUT : out std_logic_vector(5 downto 0); -- [5]=Z, [4]=N, [3]=OVF, [2]=EQ, [1]=GT, [0]=SM
        IR_OUT    : out std_logic_vector(7 downto 0);
        ARG_OUT   : out std_logic_vector(7 downto 0);
        ARG_VALID : out std_logic;
        RUN_NEXT  : in  std_logic := '1'
    );
end cpu;

architecture Behavioral of cpu is

    -- Banco de 4 registradores de proposito geral (0=Ra, 1=Rb, 2=Rc, 3=Rd)
    type reg_t is array (0 to 3) of std_logic_vector(7 downto 0);
    signal REG : reg_t := (others => (others => '0'));

    -- Registradores especiais (8 bits)
    signal PC  : unsigned(7 downto 0) := (others => '0');
    signal SP  : unsigned(7 downto 0) := x"FE"; -- Inicializado obrigatoriamente em 254 (0xFE)
    signal IR  : std_logic_vector(7 downto 0) := (others => '0');
    signal MAR : unsigned(7 downto 0) := (others => '0');
    signal MBR : unsigned(7 downto 0) := (others => '0');
    signal immediate_valid : std_logic := '0';

    -- Flip-Flops da UC para armazenar as flags da ultima operacao de ALU
    signal FLAGS_REG : std_logic_vector(5 downto 0) := (others => '0');

    -- Estados da Unidade de Controle (UC) sincronizados com a RAM (borda de descida)
    type FSM_CPU is (
        FETCH_ADDR,  -- Coloca PC em MAR para a RAM registrar o endereco
        FETCH_READ,  -- Le a instrucao (RAM_DOUT) para o IR
        DECODE,      -- Decodifica opcode e prepara ALU ou endereco de memoria
        MEM_ACCESS,  -- Le o 2o byte (ldi, st, jmp) ou dado da memoria (ldr, pop)
        EXECUTE,     -- Executa a operacao, atualiza registradores/flags/PC
        WRITE_BACK,  -- Finaliza ciclo de escrita na RAM (WE <= '0')
        HALTED       -- Aguarda reset
    );
    signal STATE : FSM_CPU := FETCH_ADDR;

    -- Sinais de interconexao com a ALU assincrona
    signal ALU_A     : std_logic_vector(7 downto 0) := (others => '0');
    signal ALU_B     : std_logic_vector(7 downto 0) := (others => '0');
    signal ALU_CMD   : std_logic_vector(3 downto 0) := (others => '0');
    signal ALU_S     : std_logic_vector(7 downto 0);
    signal ALU_FLAGS : std_logic_vector(5 downto 0);

    -- Codificacao dos comandos da ALU (identica ao ALU.vhd)
    constant CMD_ADD : std_logic_vector(3 downto 0) := "0000";
    constant CMD_SUB : std_logic_vector(3 downto 0) := "0001";
    constant CMD_INC : std_logic_vector(3 downto 0) := "0010";
    constant CMD_DEC : std_logic_vector(3 downto 0) := "0011";
    constant CMD_AND : std_logic_vector(3 downto 0) := "0100";
    constant CMD_OR  : std_logic_vector(3 downto 0) := "0101";
    constant CMD_NOT : std_logic_vector(3 downto 0) := "0110";
    constant CMD_XOR : std_logic_vector(3 downto 0) := "0111";
    constant CMD_ROL : std_logic_vector(3 downto 0) := "1000";
    constant CMD_ROR : std_logic_vector(3 downto 0) := "1001";
    constant CMD_LSL : std_logic_vector(3 downto 0) := "1010";
    constant CMD_LSR : std_logic_vector(3 downto 0) := "1011";

begin

    -- Instancia da ALU assincrona
    u_alu : entity work.alu(Behavioral)
        port map (
            A     => ALU_A,
            B     => ALU_B,
            CMD   => ALU_CMD,
            S     => ALU_S,
            FLAGS => ALU_FLAGS
        );

    -- Processo principal da Unidade de Controle (borda de subida do CLK)
    p_fsm_cycle : process(CLK)
        variable opcode : std_logic_vector(3 downto 0);
        variable rx_idx : integer range 0 to 3;
        variable ry_idx : integer range 0 to 3;
        variable func   : std_logic_vector(1 downto 0);
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                REG       <= (others => (others => '0'));
                PC        <= (others => '0');
                SP        <= x"FE"; -- 254
                IR        <= (others => '0');
                MAR       <= (others => '0');
                MBR       <= (others => '0');
                immediate_valid <= '0';
                FLAGS_REG <= (others => '0');
                RAM_DIN   <= (others => '0');
                WE        <= '0';
                ALU_A     <= (others => '0');
                ALU_B     <= (others => '0');
                ALU_CMD   <= (others => '0');
                STATE     <= FETCH_ADDR;
            else
                -- Campos da instrucao atual no IR
                opcode := IR(7 downto 4);
                rx_idx := to_integer(unsigned(IR(3 downto 2)));
                ry_idx := to_integer(unsigned(IR(1 downto 0)));
                func   := IR(1 downto 0);

                case STATE is

                    ----------------------------------------------------------------
                    -- 1. FETCH_ADDR: Aplica PC no barramento de enderecos da RAM
                    ----------------------------------------------------------------
                    when FETCH_ADDR =>
                        if RUN_NEXT = '1' then
                            MAR   <= PC;
                            STATE <= FETCH_READ;
                        end if;

                    ----------------------------------------------------------------
                    -- 2. FETCH_READ: Apos borda de descida da RAM, le opcode em IR
                    ----------------------------------------------------------------
                    when FETCH_READ =>
                        immediate_valid <= '0';
                        IR    <= RAM_DOUT;
                        STATE <= DECODE;

                    ----------------------------------------------------------------
                    -- 3. DECODE: Prepara operandos da ALU ou solicita leitura extra
                    ----------------------------------------------------------------
                    when DECODE =>
                        case opcode is
                            -- Operacoes de 2 operandos da ALU
                            when "0000" => -- add Rx, Ry
                                ALU_A   <= REG(rx_idx);
                                ALU_B   <= REG(ry_idx);
                                ALU_CMD <= CMD_ADD;
                                STATE   <= EXECUTE;

                            when "0001" => -- sub Rx, Ry
                                ALU_A   <= REG(rx_idx);
                                ALU_B   <= REG(ry_idx);
                                ALU_CMD <= CMD_SUB;
                                STATE   <= EXECUTE;

                            when "0010" => -- inc Rx (00), dec Rx (01), nao usados (10, 11 -> nop)
                                if func = "00" then
                                    ALU_A   <= REG(rx_idx);
                                    ALU_B   <= x"01";
                                    ALU_CMD <= CMD_INC;
                                elsif func = "01" then
                                    ALU_A   <= REG(rx_idx);
                                    ALU_B   <= x"01";
                                    ALU_CMD <= CMD_DEC;
                                end if;
                                STATE <= EXECUTE;

                            when "0011" => -- and Rx, Ry
                                ALU_A   <= REG(rx_idx);
                                ALU_B   <= REG(ry_idx);
                                ALU_CMD <= CMD_AND;
                                STATE   <= EXECUTE;

                            when "0100" => -- or Rx, Ry
                                ALU_A   <= REG(rx_idx);
                                ALU_B   <= REG(ry_idx);
                                ALU_CMD <= CMD_OR;
                                STATE   <= EXECUTE;

                            when "0101" => -- not Rx (00), demais (01, 10, 11 -> nop)
                                if func = "00" then
                                    ALU_A   <= REG(rx_idx);
                                    ALU_B   <= x"00";
                                    ALU_CMD <= CMD_NOT;
                                end if;
                                STATE <= EXECUTE;

                            when "0110" => -- xor Rx, Ry
                                ALU_A   <= REG(rx_idx);
                                ALU_B   <= REG(ry_idx);
                                ALU_CMD <= CMD_XOR;
                                STATE   <= EXECUTE;

                            when "0111" => -- rol (00), ror (01), lsl (10), lsr (11)
                                ALU_A <= REG(rx_idx);
                                ALU_B <= x"00";
                                case func is
                                    when "00"   => ALU_CMD <= CMD_ROL;
                                    when "01"   => ALU_CMD <= CMD_ROR;
                                    when "10"   => ALU_CMD <= CMD_LSL;
                                    when others => ALU_CMD <= CMD_LSR;
                                end case;
                                STATE <= EXECUTE;

                            -- Pilha e Instrucoes de 2 bytes (st, ldi)
                            when "1000" =>
                                case func is
                                    when "00" => -- push Rx (escreve direto no EXECUTE)
                                        STATE <= EXECUTE;
                                    when "01" => -- pop Rx (incrementa SP e le MEM[SP+1])
                                        SP    <= SP + 1;
                                        MAR   <= SP + 1;
                                        STATE <= MEM_ACCESS;
                                    when "10" | "11" => -- st Rx, 0x-- / ldi Rx, 0x-- (busca 2o byte)
                                        MAR   <= PC + 1;
                                        STATE <= MEM_ACCESS;
                                    when others =>
                                        STATE <= EXECUTE;
                                end case;

                            -- Load indireto: ldr Rx, [Ry]
                            when "1001" =>
                                MAR   <= unsigned(REG(ry_idx));
                                STATE <= MEM_ACCESS;

                            -- Jump absoluto de 2 bytes: jmp 0x-- (somente com Rx = 00)
                            when "1100" =>
                                if func = "00" and IR(3 downto 2) = "00" then
                                    MAR   <= PC + 1;
                                    STATE <= MEM_ACCESS;
                                else
                                    STATE <= EXECUTE;
                                end if;

                            -- Demais instrucoes (str, mov, saltos condicionais, nop, halt, invalidos)
                            when others =>
                                STATE <= EXECUTE;
                        end case;

                    ----------------------------------------------------------------
                    -- 4. MEM_ACCESS: Captura dado da RAM ou 2o byte da instrucao
                    ----------------------------------------------------------------
                    when MEM_ACCESS =>
                        if (opcode = "1000" and func(1) = '1') or IR = x"C0" then
                            immediate_valid <= '1';
                        end if;
                        MBR   <= unsigned(RAM_DOUT);
                        STATE <= EXECUTE;

                    ----------------------------------------------------------------
                    -- 5. EXECUTE: Efetiva resultados, atualiza flags e proximo PC
                    ----------------------------------------------------------------
                    when EXECUTE =>
                        case opcode is
                            -- Instrucoes de ALU (atualizam registrador destino e as 6 flags)
                            when "0000" | "0001" | "0011" | "0100" | "0110" | "0111" =>
                                REG(rx_idx) <= ALU_S;
                                FLAGS_REG   <= ALU_FLAGS;
                                PC          <= PC + 1;
                                STATE       <= FETCH_ADDR;

                            when "0010" => -- inc / dec (func 10 e 11 sao nop)
                                if func = "00" or func = "01" then
                                    REG(rx_idx) <= ALU_S;
                                    FLAGS_REG   <= ALU_FLAGS;
                                end if;
                                PC    <= PC + 1;
                                STATE <= FETCH_ADDR;

                            when "0101" => -- not (func 01, 10, 11 sao nop)
                                if func = "00" then
                                    REG(rx_idx) <= ALU_S;
                                    FLAGS_REG   <= ALU_FLAGS;
                                end if;
                                PC    <= PC + 1;
                                STATE <= FETCH_ADDR;

                            -- Pilha e Memoria imediata/direta
                            when "1000" =>
                                case func is
                                    when "00" => -- push Rx: MEM[SP] <- Rx; SP <- SP - 1; PC <- PC + 1
                                        MAR     <= SP;
                                        RAM_DIN <= REG(rx_idx);
                                        WE      <= '1';
                                        SP      <= SP - 1;
                                        PC      <= PC + 1;
                                        STATE   <= WRITE_BACK;

                                    when "01" => -- pop Rx: Rx <- MEM[SP+1]; PC <- PC + 1
                                        REG(rx_idx) <= std_logic_vector(MBR);
                                        PC          <= PC + 1;
                                        STATE       <= FETCH_ADDR;

                                    when "10" => -- st Rx, ADDR: MEM[MBR] <- Rx; PC <- PC + 2
                                        MAR     <= MBR;
                                        RAM_DIN <= REG(rx_idx);
                                        WE      <= '1';
                                        PC      <= PC + 2;
                                        STATE   <= WRITE_BACK;

                                    when "11" => -- ldi Rx, ADDR: Rx <- MBR; PC <- PC + 2
                                        REG(rx_idx) <= std_logic_vector(MBR);
                                        PC          <= PC + 2;
                                        STATE       <= FETCH_ADDR;

                                    when others =>
                                        PC    <= PC + 1;
                                        STATE <= FETCH_ADDR;
                                end case;

                            when "1001" => -- ldr Rx, [Ry]: Rx <- MEM[Ry]; PC <- PC + 1
                                REG(rx_idx) <= std_logic_vector(MBR);
                                PC          <= PC + 1;
                                STATE       <= FETCH_ADDR;

                            when "1010" => -- str Rx, [Ry]: MEM[Ry] <- Rx; PC <- PC + 1
                                MAR     <= unsigned(REG(ry_idx));
                                RAM_DIN <= REG(rx_idx);
                                WE      <= '1';
                                PC      <= PC + 1;
                                STATE   <= WRITE_BACK;

                            when "1011" => -- mov Rx, Ry: Rx <- Ry; PC <- PC + 1
                                REG(rx_idx) <= REG(ry_idx);
                                PC          <= PC + 1;
                                STATE       <= FETCH_ADDR;

                            -- Saltos incondicionais e por flag ZERO
                            when "1100" =>
                                case func is
                                    when "00" => -- jmp ADDR (se Rx=00) ou nop (se Rx/=00)
                                        if IR(3 downto 2) = "00" then
                                            PC <= MBR;
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when "01" => -- jmpr Rx
                                        PC <= unsigned(REG(rx_idx));
                                    when "10" => -- bz Rx (FLAGS_REG(5) = ZERO)
                                        if FLAGS_REG(5) = '1' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when "11" => -- bnz Rx
                                        if FLAGS_REG(5) = '0' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when others =>
                                        PC <= PC + 1;
                                end case;
                                STATE <= FETCH_ADDR;

                            -- Saltos por OVERFLOW e EQUAL
                            when "1101" =>
                                case func is
                                    when "00" => -- bcs Rx (FLAGS_REG(3) = OVERFLOW)
                                        if FLAGS_REG(3) = '1' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when "01" => -- bcc Rx
                                        if FLAGS_REG(3) = '0' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when "10" => -- beq Rx (FLAGS_REG(2) = EQUAL)
                                        if FLAGS_REG(2) = '1' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when "11" => -- bneq Rx
                                        if FLAGS_REG(2) = '0' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when others =>
                                        PC <= PC + 1;
                                end case;
                                STATE <= FETCH_ADDR;

                            -- Saltos por GREATER, SMALLER e NEGATIVE
                            when "1110" =>
                                case func is
                                    when "00" => -- bgt Rx (FLAGS_REG(1) = GREATER)
                                        if FLAGS_REG(1) = '1' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when "01" => -- blt Rx (FLAGS_REG(0) = SMALLER)
                                        if FLAGS_REG(0) = '1' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when "10" => -- bneg Rx (FLAGS_REG(4) = NEGATIVE)
                                        if FLAGS_REG(4) = '1' then
                                            PC <= unsigned(REG(rx_idx));
                                        else
                                            PC <= PC + 1;
                                        end if;
                                    when others => -- 1110 Rx 11 -> nop
                                        PC <= PC + 1;
                                end case;
                                STATE <= FETCH_ADDR;

                            -- Controle: halt (11111111) e nop / demais invalidos
                            when "1111" =>
                                if IR = "11111111" then
                                    STATE <= HALTED;
                                else
                                    PC <= PC + 1; -- nop e codigos nao usados
                                    STATE <= FETCH_ADDR;
                                end if;

                            when others =>
                                PC    <= PC + 1;
                                STATE <= FETCH_ADDR;
                        end case;

                    ----------------------------------------------------------------
                    -- 6. WRITE_BACK: Garante WE='1' durante a borda de descida da RAM
                    ----------------------------------------------------------------
                    when WRITE_BACK =>
                        WE    <= '0';
                        STATE <= FETCH_ADDR;

                    when HALTED =>
                        null;

                end case;
            end if;
        end if;
    end process;

    -- Saidas continuas da CPU
    RAM_ADDR  <= std_logic_vector(MAR);
    FLAGS_OUT <= FLAGS_REG;
    IR_OUT    <= IR;
    ARG_OUT   <= std_logic_vector(MBR);
    ARG_VALID <= immediate_valid;

end Behavioral;
