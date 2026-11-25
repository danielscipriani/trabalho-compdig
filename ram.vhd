library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity RAM_8x256 is
    port(
        CLK     : in std_logic;
        DIN     : in std_logic_vector(7 downto 0);
        ADDR    : in std_logic_vector(7 downto 0);
        WE      : in std_logic;
        DOUT    : out std_logic_vector(7 downto 0);
        POS_255 : out std_logic_vector(7 downto 0)
    );
end RAM_8x256;

architecture rtl of RAM_8x256 is
    
    type RAM_t is array(0 to 255) of std_logic_vector(7 downto 0);
    -- NASM-20261125/demonstracao.asm
    -- Ra = 00, Rb = 01, Rc = 10, Rd = 11
    -- Cole aqui as entradas do array gerado pelo montador.
    constant RAM_INIT : RAM_t := (
       	 	0  => "10000011", -- ldi Ra, 0x05  (Ra <- 5)
        	1  => "00000101", -- 0x05
        	2  => "10000111", -- ldi Rb, 0x03  (Rb <- 3)
        	3  => "00000011", -- 0x03
        	4  => "00000001", -- add Ra, Rb    (Ra <- 8; Flags: GT=1 -> "000010")
        	5  => "10000000", -- push Ra       (MEM[254] <- 8; SP <- 253)
        	6  => "00010100", -- sub Rb, Ra    (Rb <- 3 - 8 = 0xFB; Flags: N=1, OVF=1, SM=1 -> "011001")
        	7  => "10001001", -- pop Rc        (SP <- 254; Rc <- MEM[254] = 8; Flags mantidas em "011001")
        	8  => "10001111", -- ldi Rd, 0x0C  (Rd <- 12, endereco de destino do salto)
        	9  => "00001100", -- 0x0C
        	10 => "11011100", -- bcs Rd        (Como OVF=1, salta para PC = 12 e pula o endereco 11)
        	11 => "00101000", -- inc Rc        (DEVE SER PULADA! Se executar, Rc vira 9)
        	12 => "10001010", -- st Rc, 0xFF   (MEM[255] <- Rc = 8)
        	13 => "11111111", -- 0xFF (255)
        	14 => "11111111", -- halt          (Trava PC em 14 / 0x0E)
        	others => (others => '0')
    );

    signal ram : RAM_t := RAM_INIT;
    signal display_byte : std_logic_vector(7 downto 0) := RAM_INIT(255);

begin

    -- Uma porta sincrona de RAM, com o dado novo disponivel no ciclo de escrita.
    process(CLK)
        variable address : natural range 0 to 255;
    begin
        if falling_edge(CLK) then
            address := to_integer(unsigned(ADDR));
            if WE = '1' then
                ram(address) <= DIN;
                DOUT <= DIN;
            else
                DOUT <= ram(address);
            end if;
        end if;
    end process;

    -- Espelho de I/O para o LCD, atualizado na mesma borda da escrita na RAM.
    process(CLK)
    begin
        if falling_edge(CLK) then
            if WE = '1' and ADDR = x"FF" then
                display_byte <= DIN;
            end if;
        end if;
    end process;
    POS_255 <= display_byte;

end architecture;
