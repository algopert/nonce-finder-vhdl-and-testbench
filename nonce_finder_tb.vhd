library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity nonce_finder_tb is
end nonce_finder_tb;

architecture test of nonce_finder_tb is 

    component nonce_finder is
        port(
        clk          : in std_logic;
        mblock_data  : in std_logic_vector((286*8)-1 downto 0);
        target_hash  : in std_logic_vector((32*8)-1 downto 0);
        reset        : in std_logic;
        golden_nonce : out std_logic_vector((8*8)-1 downto 0);
        found        : out std_logic
        );

    end component;
    
    signal clk          : std_logic;
    signal mblock_data  : std_logic_vector((286*8)-1 downto 0);
    signal target_hash  : std_logic_vector((32*8)-1 downto 0);
    signal reset        : std_logic;
    signal golden_nonce : std_logic_vector((8*8)-1 downto 0);
    signal found        : std_logic;
    constant exp_nonce    : std_logic_vector((8*8)-1 downto 0) := x"4ee84f655ad3ee03";

    constant period : time := 10 ns;

    function ASCII_2_VEC (inchar: in std_logic_vector(7 downto 0))

  	return std_logic_vector is
		variable tmp : std_logic_vector(7 downto 0);

  begin

		if unsigned(inchar) > 96 then
			tmp := std_logic_vector(unsigned(inchar) - 87);
		elsif unsigned(inchar) > 64 then
			tmp := std_logic_vector(unsigned(inchar) - 55);
		else
			tmp := std_logic_vector(unsigned(inchar) - 48);
		end if;

 		return tmp(3 downto 0);

  end;

begin 

dut: nonce_finder port map(
    clk => clk,
    mblock_data => mblock_data,
    target_hash => target_hash,
    reset => reset,
    golden_nonce => golden_nonce,
    found => found
);

clk_process: process

	begin

		clk <= '0';
		wait for period/2;
		clk <= '1';
		wait for period/2;

    end process;
    
    stimuli : process
    file in_file : TEXT open read_mode is "in.txt";
    variable message_line : line;
    variable target_hash_line : line;
    variable i : integer;
    variable current_char : character;
    variable hex0: std_logic_vector(3 downto 0);
    variable hex1: std_logic_vector(3 downto 0);
    variable char_value_1 : std_logic_vector(7 downto 0);
    variable counter : integer;
    begin 
        reset <= '1';
        --Get message from file
        readline(in_file, message_line);
        --Get target hash from file
        readline(in_file, target_hash_line);
        counter := 0;
        --Get message
        for i in 0 to 285 loop
            hread(message_line, hex0);
            hread(message_line, hex1);
            char_value_1 := hex0 & hex1;
            mblock_data(counter * 8 + 7 downto counter * 8) <= char_value_1;
            counter := counter + 1;
        end loop;
        --Get target hash
        counter := 0;
        for i in 0 to 31 loop 
            hread(target_hash_line, hex0);
            hread(target_hash_line, hex1);
            char_value_1 := hex0 & hex1;
            target_hash(counter * 8 + 7 downto counter * 8) <= char_value_1;
            counter := counter + 1;
        end loop;

        wait until RISING_EDGE(clk);
        reset <= '0';
        wait until RISING_EDGE(clk);
        wait until (found = '1');
        if (exp_nonce = golden_nonce) then 
            report "Nonce is correct";
        end if;
        wait for period*15;
        std.env.finish;


    end process;



end test;