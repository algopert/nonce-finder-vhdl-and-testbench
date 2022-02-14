--------------------------------------------------------------------------------
--
-- VHDL implementation of the BLAKE2 Cryptographic Hash and Message
-- Authentication Code as described by Markku-Juhani O. Saarinen and
-- Jean-Philippe Aumasson in https://doi.org/10.17487/RFC7693
--
-- Authors:
--   Benedikt Tutzer
--   Dinka Milovancev
--
-- Supervisors:
--   Christian Krieg
--   Martin Mosbeck
--   Axel Jantsch
--
-- Institute of Computer Technology
-- TU Wien
-- April 2018
--
--------------------------------------------------------------------------------
--
-- Testbench for a Blake2s implementation in VHDL
--
-- Make sure two text-files 'messages.txt' and 'hashes_blake2s.txt' are present
-- in the current working directory. They need to have the following contents:
--
-- 'messages.txt':
--
--   Fill this file with messages to be hashed. Each line shall contain one
--	 message, no newlines are allowed inside of messages.
--
-- 'hashes_blake2s.txt':
--
--   Fill this file with the corresponding blake2s hashes.
--
-- The messages will be sent to the entity and the generated hashes will be
-- compared to the hashes in the hashes_blake2s file.
--
-- ATTENTION: This testbench needs VHDL-2008 due to it's use of std.textio
--
--------------------------------------------------------------------------------
--
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.math_real.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;
USE ieee.numeric_std.ALL;
--
--------------------------------------------------------------------------------
--
ENTITY tb_blake2s IS
END tb_blake2s;
--
--------------------------------------------------------------------------------
--
ARCHITECTURE behav OF tb_blake2s IS

	COMPONENT blake2s IS

		PORT (
			reset : IN STD_LOGIC;
			clk : IN STD_LOGIC;
			message : IN STD_LOGIC_VECTOR(64 * 8 - 1 DOWNTO 0);
			hash_len : IN INTEGER RANGE 1 TO 32;
			key_len : IN INTEGER RANGE 0 TO 64 * 8;
			valid_in : IN STD_LOGIC;
			message_len : IN INTEGER RANGE 0 TO 2147483647;
			compress_ready : OUT STD_LOGIC;
			last_chunk : IN STD_LOGIC;
			valid_out : OUT STD_LOGIC;
			hash : OUT STD_LOGIC_VECTOR(32 * 8 - 1 DOWNTO 0)
		);

	END COMPONENT;

	SIGNAL reset : STD_LOGIC;
	SIGNAL clk : STD_LOGIC;
	SIGNAL message : STD_LOGIC_VECTOR(64 * 8 - 1 DOWNTO 0);
	SIGNAL hash_len : INTEGER RANGE 1 TO 32;
	SIGNAL key_len : INTEGER RANGE 0 TO 64 * 8;
	SIGNAL valid_in : STD_LOGIC;
	SIGNAL message_len : INTEGER RANGE 0 TO 2147483647;
	SIGNAL compress_ready : STD_LOGIC;
	SIGNAL last_chunk : STD_LOGIC;
	SIGNAL valid_out : STD_LOGIC;
	SIGNAL hash : STD_LOGIC_VECTOR(32 * 8 - 1 DOWNTO 0);

	CONSTANT period : TIME := 10 ns;
	SIGNAL ended : STD_LOGIC := '0';

	FUNCTION ASCII_2_VEC (inchar : IN STD_LOGIC_VECTOR(7 DOWNTO 0))

		RETURN STD_LOGIC_VECTOR IS
		VARIABLE tmp : STD_LOGIC_VECTOR(7 DOWNTO 0);

	BEGIN

		IF unsigned(inchar) > 96 THEN
			tmp := STD_LOGIC_VECTOR(unsigned(inchar) - 87);
		ELSIF unsigned(inchar) > 64 THEN
			tmp := STD_LOGIC_VECTOR(unsigned(inchar) - 55);
		ELSE
			tmp := STD_LOGIC_VECTOR(unsigned(inchar) - 48);
		END IF;

		RETURN tmp(3 DOWNTO 0);

	END;
	
	FUNCTION chr_isDigit(chr : CHARACTER) RETURN BOOLEAN IS
	BEGIN
		RETURN (CHARACTER'pos('0') <= CHARACTER'pos(chr)) AND (CHARACTER'pos(chr) <= CHARACTER'pos('9'));
	END FUNCTION;

	FUNCTION chr_isLowerHexDigit(chr : CHARACTER) RETURN BOOLEAN IS
	BEGIN
		RETURN (CHARACTER'pos('a') <= CHARACTER'pos(chr)) AND (CHARACTER'pos(chr) <= CHARACTER'pos('f'));
	END FUNCTION;

	FUNCTION chr_isUpperHexDigit(chr : CHARACTER) RETURN BOOLEAN IS
	BEGIN
		RETURN (CHARACTER'pos('A') <= CHARACTER'pos(chr)) AND (CHARACTER'pos(chr) <= CHARACTER'pos('F'));
	END FUNCTION;

	FUNCTION to_digit_hex(chr : CHARACTER) RETURN INTEGER IS
	BEGIN
		IF chr_isDigit(chr) THEN
			RETURN CHARACTER'pos(chr) - CHARACTER'pos('0');
		ELSIF chr_isLowerHexDigit(chr) THEN
			RETURN CHARACTER'pos(chr) - CHARACTER'pos('a') + 10;
		ELSIF chr_isUpperHexDigit(chr) THEN
			RETURN CHARACTER'pos(chr) - CHARACTER'pos('A') + 10;
		END IF;
		RETURN -1;

	END FUNCTION;
BEGIN

	dut : blake2s

	PORT MAP(
		reset => reset,
		clk => clk,
		message => message,
		valid_in => valid_in,
		message_len => message_len,
		hash_len => hash_len,
		key_len => key_len,
		compress_ready => compress_ready,
		last_chunk => last_chunk,
		valid_out => valid_out,
		hash => hash
	);

	clk_process : PROCESS

	BEGIN

		clk <= '0';
		WAIT FOR period/2;
		clk <= '1';
		WAIT FOR period/2;

		IF ended = '1' THEN
			WAIT;
		END IF;

	END PROCESS;
	stimuli : PROCESS

		TYPE char_file_t IS FILE OF CHARACTER;
		FILE key_file : TEXT OPEN read_mode IS "keys.txt";
		FILE message_file : TEXT OPEN read_mode IS "messages.txt";
		FILE hash_file_2s : TEXT OPEN read_mode IS "hashes_blake2s.txt";
		VARIABLE line_buffer : line;
		VARIABLE line_buffer_keys : line;
		VARIABLE value_in : STD_LOGIC_VECTOR(32 * 8 - 1 DOWNTO 0);
		VARIABLE char_value_1 : STD_LOGIC_VECTOR(7 DOWNTO 0);
		VARIABLE char_value_2 : STD_LOGIC_VECTOR(7 DOWNTO 0);
		VARIABLE read_ok : BOOLEAN;
		VARIABLE current_char : CHARACTER;
		VARIABLE counter : INTEGER;

	BEGIN

		--
		-- Always generate 32-byte hashes
		--
		hash_len <= 32;
		last_chunk <= '0';

		--
		-- Start with reset
		--
		reset <= '1';
		WAIT FOR 10 ns;
		reset <= '0';
		WAIT FOR 5 ns;

		counter := 0;
		message <= (OTHERS => '0');

		WHILE NOT endfile(message_file) LOOP

			counter := 0;
			message <= (OTHERS => '0');
			WAIT FOR period;

			--
			-- Read single line
			--
			readline(message_file, line_buffer);
			readline(key_file, line_buffer_keys);

			--
			-- Message length equals line length
			--
			message_len <= line_buffer'length;
			key_len <= line_buffer_keys'length;

			WAIT FOR period;

			FOR i IN 0 TO line_buffer'length - 1 LOOP
				REPORT "The value of 'a' is " & INTEGER'image(line_buffer'length);
				--
				-- Read one byte of data and write it to 'message'.
				-- If message is filled up, send it to the entity
				-- and start over
				--
				IF counter = 64 THEN

					WAIT FOR period;
					last_chunk <= '0';
					valid_in <= '1';
					WAIT FOR period;
					valid_in <= '0';

					counter := 0;
					message <= (OTHERS => '0');
					WAIT FOR period * 835;

				END IF;

				read(line_buffer, current_char);

				-- for i in str2'range loop
				-- 	--			while ((j >= 0) and str2(j + 1) /= str2(i)) loop
				-- 	--				j		:= PrefixTable(j);
				-- 	--			end loop;
				-- 	--
				-- 	--			j										:= j + 1;
				-- 	--			PrefixTable(i - 1)	:= j + 1;
				-- 	--		end loop;

				char_value_1 := STD_LOGIC_VECTOR(to_unsigned(CHARACTER'pos(current_char), 8));
				message(counter * 8 + 7 DOWNTO counter * 8) <= char_value_1;
				counter := counter + 1;

			END LOOP;

			--
			-- Send the remaining bytes as last chunk
			--
			WAIT FOR period;
			last_chunk <= '1';
			valid_in <= '1';
			WAIT FOR period;
			valid_in <= '0';
			WAIT FOR period * 835;

			-- readline(hash_file_2s, line_buffer);

			--
			-- Read hash file in hex and compare with the output
			-- generated by the entity
			--
			-- counter := 0;
			-- value_in := (others => '0');

			-- for i in 0 to 31 loop

			-- 	read(line_buffer, current_char);
			-- 	char_value_1 := std_logic_vector(to_unsigned(character'pos(current_char),8));
			-- 	read(line_buffer, current_char);
			-- 	char_value_2 := std_logic_vector(to_unsigned(character'pos(current_char),8));
			-- 	value_in(counter * 8 + 7 downto counter * 8) :=	ASCII_2_VEC(char_value_1) &	ASCII_2_VEC(char_value_2);
			-- 	counter := counter + 1;

			-- end loop;
			REPORT "[ OK] HASH correct";
			-- if value_in = hash then
			-- 	report "[ OK] HASH correct";
			-- else
			-- 	report "[NOK] HASH incorrect";
			-- end if;

		END LOOP;

		ended <= '1';

		WAIT;

	END PROCESS;

END behav;
--
--------------------------------------------------------------------------------