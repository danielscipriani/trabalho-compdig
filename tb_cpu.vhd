library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_cpu is
end tb_cpu;

architecture Behavioral of tb_cpu is

    -- Sinais de controle e clock
    signal CLK   : std_logic := '0';
    signal RESET : std_logic := '1';

    -- Barramento entre CPU e RAM
    signal ram_din  : std_logic_vector(7 downto 0);
    signal ram_dout : std_logic_vector(7 downto 0);
    signal ram_addr : std_logic_vector(7 downto 0);
    signal ram_we   : std_logic;

    -- Saidas de observacao (LEDs, LCD e MEM[255])
    signal flags_out : std_logic_vector(5 downto 0);
    signal ir_out    : std_logic_vector(7 downto 0);
    signal pos_255   : std_logic_vector(7 downto 0);

    -- Periodo de clock para simulacao (20 ns = 50 MHz)
    constant CLK_PERIOD : time := 20 ns;

begin

    -- Instancia da CPU (que ja instancia a ALU internamente)
    u_cpu : entity work.cpu(Behavioral)
        port map (
            CLK       => CLK,
            RESET     => RESET,
            RAM_DIN   => ram_din,
            RAM_DOUT  => ram_dout,
            RAM_ADDR  => ram_addr,
            WE        => ram_we,
            FLAGS_OUT => flags_out,
            IR_OUT    => ir_out,
            ARG_OUT   => open,
            ARG_VALID => open
        );

    -- Instancia da Memoria RAM fornecida
    u_memory : entity work.RAM_8x256(rtl)
        port map (
            CLK     => CLK,
            DIN     => ram_din,
            ADDR    => ram_addr,
            WE      => ram_we,
            DOUT    => ram_dout,
            POS_255 => pos_255
        );

    -- Gerador de Clock
    p_clk : process
    begin
        CLK <= '0';
        wait for CLK_PERIOD / 2;
        CLK <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Processo de estimulos e verificacao automatica
    p_stim : process
    begin
        -- Libera o reset fora da borda de subida da CPU
        RESET <= '1';
        wait for 60 ns;
        RESET <= '0';

        -- Aguarda tempo suficiente para executar todo o programa de teste (~60 ciclos)
        wait for CLK_PERIOD * 60;

        -- Verificacao automatica do valor final em MEM[255]
        assert pos_255 = x"08"
            report "FALHA NA SIMULACAO: MEM[255] deveria ser 0x08!"
            severity failure;

        assert ir_out = x"FF" and ram_addr = x"0E" and ram_we = '0'
            report "HALT deve manter o endereco e desativar a escrita" severity failure;
        assert flags_out = "011001"
            report "As flags da subtracao devem permanecer ate HALT" severity failure;
        report "SUCESSO: MEM[255] = 8, flags preservadas e CPU em HALT" severity note;

        wait;
    end process;

end Behavioral;
