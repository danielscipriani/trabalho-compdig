library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alu is
    port (
        A     : in  std_logic_vector(7 downto 0);
        B     : in  std_logic_vector(7 downto 0);
        CMD   : in  std_logic_vector(3 downto 0);
        S     : out std_logic_vector(7 downto 0);
        FLAGS : out std_logic_vector(5 downto 0) -- [5]=Z, [4]=N, [3]=OVF, [2]=EQ, [1]=GT, [0]=SM
    );
end alu;

architecture Behavioral of alu is

    -- Codificacao dos 12 comandos da ALU (4 bits)
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

    -- Sinais internos de 9 bits (unsigned) para capturar carry/borrow no bit 8
    signal a9, b9, r9 : unsigned(8 downto 0);

    -- Sinais individuais das 6 flags
    signal flag_zero     : std_logic;
    signal flag_negative : std_logic;
    signal flag_overflow : std_logic;
    signal flag_equal    : std_logic;
    signal flag_greater  : std_logic;
    signal flag_smaller  : std_logic;

begin

    -- Extensao com zero para 9 bits (0..255)
    a9 <= '0' & unsigned(A);
    b9 <= '0' & unsigned(B);

    -- Selecao assincrona das 12 operacoes
    -- O bit 8 de r9 armazena exatamente o comportamento exigido para OVERFLOW em cada operacao
    with CMD select
        r9 <= (a9 + b9)                             when CMD_ADD | CMD_INC, -- UC envia B = x"01" no inc
              (a9 - b9)                             when CMD_SUB | CMD_DEC, -- UC envia B = x"01" no dec
              unsigned('0' & (A and B))             when CMD_AND,
              unsigned('0' & (A or  B))             when CMD_OR,
              unsigned('0' & (not A))               when CMD_NOT,
              unsigned('0' & (A xor B))             when CMD_XOR,
              unsigned(A(7) & A(6 downto 0) & A(7)) when CMD_ROL, -- bit 7 sai pela esquerda -> OVERFLOW
              unsigned(A(0) & A(0) & A(7 downto 1)) when CMD_ROR, -- bit 0 sai pela direita  -> OVERFLOW
              unsigned(A(7) & A(6 downto 0) & '0')  when CMD_LSL, -- bit 7 sai pela esquerda -> OVERFLOW
              unsigned(A(0) & '0' & A(7 downto 1))  when CMD_LSR, -- bit 0 sai pela direita  -> OVERFLOW
              (others => '0')                       when others;

    -- Resultado final de 8 bits
    S <= std_logic_vector(r9(7 downto 0));

    -- Geracao combinacional das 6 flags
    flag_zero     <= '1' when r9(7 downto 0) = x"00" else '0';
    flag_negative <= r9(7);
    flag_overflow <= r9(8);
    flag_equal    <= '1' when unsigned(A) = unsigned(B) else '0';
    flag_greater  <= '1' when unsigned(A) > unsigned(B) else '0';
    flag_smaller  <= '1' when unsigned(A) < unsigned(B) else '0';

    -- Agrupamento na mesma ordem fisica dos LEDs da placa (LD6 ate LD1)
    FLAGS <= flag_zero & flag_negative & flag_overflow & flag_equal & flag_greater & flag_smaller;

end Behavioral;