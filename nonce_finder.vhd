library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
--
--------------------------------------------------------------------------------
--
entity nonce_finder is
	port(
	clk          : in std_logic;
	mblock_data  : in std_logic_vector((286*8)-1 downto 0);
	target_hash  : in std_logic_vector((32*8)-1 downto 0);
	reset        : in std_logic;
	golden_nonce : out std_logic_vector((8*8)-1 downto 0);
	found        : out std_logic
	);

end nonce_finder;
--
--------------------------------------------------------------------------------
--
architecture behav of nonce_finder is

	component blake2s is

		port (
			reset          : in  std_logic;
			clk            : in  std_logic;
			message        : in  std_logic_vector(64 * 8 - 1 downto 0);
			hash_len       : in  integer range 1 to 32;
			key_len        : in integer range 0 to 64 * 8;
			valid_in       : in  std_logic;
			message_len    : in  integer range 0 to 2147483647;
			compress_ready : out std_logic;
			last_chunk     : in  std_logic;
			valid_out      : out std_logic;
			hash           : out std_logic_vector(32 * 8 - 1 downto 0)
		);

	end component;

	--Constants
	constant HASH_LEN    : integer range 1 to 32            := 32;
	constant KEY_LEN     : integer range 0 to 64 * 8 		:= 0;
	constant MESSAGE_LEN : integer range 0 to 2147483647    := 286;
	constant NUM_CHUNKS  : integer range 0 to 2147483647    := MESSAGE_LEN / 64;

	type state_s is (IDLE, CAPTURE_DATA, GET_NONCE, NEW_CHUNK, DATA_IN_BLAKE, WAIT_BLAKE, CHECK_BLAKE, INCREMENT_CHUNK, COMPARE_HASH, INCREMENT_NONCE, UPDATE_NONCE, DONE);
	signal state, next_state 		   : state_s;
	type chunk_array_t is array (0 to 285) of std_logic_vector(7 downto 0);
	--Register to store mblock_data
	signal mblock_data_reg 			   : chunk_array_t;
	--Register to store target hash
	signal target_hash_reg 			   : std_logic_vector((32*8)-1 downto 0);
	--Enable mblock_data and target_hash register
	signal en_capture_data 			   : std_logic;
	--Enable data in blake2s
	signal valid_in_blake2s 		   : std_logic;
	--Compress ready blake2s
	signal compress_ready_blake2s 	: std_logic;
	--Last chunk of data
	signal last_chunk_blake2s 		   : std_logic;
	--Valid out
	signal valid_out_blake2s 		   : std_logic;
	--Actual hash
	signal hash_blake2s 			      : std_logic_vector((32*8)-1 downto 0);
	--Actual hash reg
	signal hash_blake2s_reg 		   : std_logic_vector((32*8)-1 downto 0);
	signal hash_blake2s_inv            : std_logic_vector((32*8)-1 downto 0);
	--Data in to blake2s
	signal message_blake2s 			   : std_logic_vector((64*8)-1 downto 0);
	signal en_message_blake2s 		   : std_logic;
	--Counter of chunks
	signal chunk_counter 			   : std_logic_vector(11 downto 0);
	signal chunk_counterx64          : std_logic_vector(17 downto 0);
	signal rst_chunk_counter 		   : std_logic;
	signal en_chunk_counter 		   : std_logic;
	signal done_chunk_counter 		   : std_logic;
	--Compare hash
	signal hash_equal 				   : std_logic;
	--Nonce
	signal nonce 					      : std_logic_vector((8*8)-1 downto 0);
	signal en_nonce 				      : std_logic;
	signal incr_nonce 				   : std_logic;
	signal nonce_inv 				   : std_logic_vector(63 downto 0);
	signal nonce_inv_add1              : std_logic_vector(63 downto 0);

begin

	--blake2s
	valid_in_blake2s  <= '1' when (state = DATA_IN_BLAKE) else '0';
	blake2s_inst: blake2s port map(
		reset 			=> reset,
		clk   			=> clk,
		message 		   => message_blake2s,
		hash_len 		=> HASH_LEN,				--32
		key_len 		   => KEY_LEN,					--0
		valid_in 		=> valid_in_blake2s,
		message_len 	=> MESSAGE_LEN,				--286
		compress_ready => compress_ready_blake2s,
		last_chunk 		=> last_chunk_blake2s,
		valid_out 		=> valid_out_blake2s,
		hash 			   => hash_blake2s

	);

	--FSM
	process (clk, reset) begin 
		if (reset = '1') then 
			state <= IDLE;
		elsif RISING_EDGE(clk) then
			state <= next_state;
		end if;
	end process;

	process(state, valid_out_blake2s, done_chunk_counter, compress_ready_blake2s, hash_equal) begin
		case( state ) is
			when IDLE =>
				next_state <= CAPTURE_DATA;
			when CAPTURE_DATA =>
				next_state <= GET_NONCE;
			when GET_NONCE =>
				next_state <= NEW_CHUNK;
			when NEW_CHUNK =>
				next_state <= DATA_IN_BLAKE;
			when DATA_IN_BLAKE =>
				next_state <= WAIT_BLAKE;
			when WAIT_BLAKE =>
				if (compress_ready_blake2s = '1') then
					next_state <= CHECK_BLAKE;
				else 
					next_state <= WAIT_BLAKE;
				end if;
			when CHECK_BLAKE =>
				if ((valid_out_blake2s = '1') and (done_chunk_counter = '1')) then 
					next_state <= COMPARE_HASH;
				else 
					next_state <= INCREMENT_CHUNK;
				end if;
			when INCREMENT_CHUNK =>
				next_state <= NEW_CHUNK;
			when COMPARE_HASH =>
				if (hash_equal = '1') then 
					next_state <= DONE;
				else 
					next_state <= INCREMENT_NONCE;
				end if;
			when INCREMENT_NONCE =>
				next_state <= UPDATE_NONCE;
			when UPDATE_NONCE =>
				next_state <= NEW_CHUNK;
			when DONE =>
				next_state <= DONE;
			when others =>
				next_state <= IDLE;
		end case ;
	end process;

	en_capture_data <= '1' when (state = CAPTURE_DATA) else '0';

	--Data Path

	--Registers to capture data
	process (clk) is 
	variable i : integer;
	begin
		if RISING_EDGE(clk) then
			if (en_capture_data = '1') then 
				for i in 0 to 285 loop
					mblock_data_reg(i) <= mblock_data(((i+1)*8)-1 downto i*8);
				end loop;
				target_hash_reg <= target_hash;
			elsif (state = UPDATE_NONCE) then 
				for i in 0 to 7 loop
					mblock_data_reg(i+278) <= nonce((i*8)+7 downto i*8);		--Update last 8 bytes with nonce+1
				end loop;
			end if;
		end if;
	end process;



	--Chunk counter
	rst_chunk_counter  <= '1' when ((state = IDLE) or (state = INCREMENT_NONCE)) else '0';
	en_chunk_counter   <= '1' when (state = INCREMENT_CHUNK) else '0';
	done_chunk_counter <= '1' when (chunk_counter = std_logic_vector(to_unsigned(NUM_CHUNKS,chunk_counter'length))) else '0';
	chunk_counterx64   <= (chunk_counter) & "000000";

	process (clk, rst_chunk_counter) begin 
		if (rst_chunk_counter = '1') then 
		    chunk_counter <= (others => '0');
		elsif RISING_EDGE(clk) then 
			if (en_chunk_counter = '1') then 
				chunk_counter <= chunk_counter + 1;
			end if;
		end if;
	end process;

	--Get Chunk
	en_message_blake2s <= '1' when ((state = NEW_CHUNK)) else '0';
	last_chunk_blake2s <= done_chunk_counter;
	process (clk) is
		variable i : integer;
		variable tmp : integer;
		begin 
		if RISING_EDGE(clk) then 
			if (en_message_blake2s = '1') then 
				for i in 0 to 63 loop
					tmp := i + to_integer(unsigned(chunk_counterx64));
					if (tmp < 286) then
						message_blake2s(((i+1)*8)-1 downto i*8) <= mblock_data_reg(tmp);
					else 
						message_blake2s(((i+1)*8)-1 downto i*8) <= (others => '0');
					end if;
				end loop;
			end if;
		end if;
	end process;

	--Get Hash from Blake
	process(hash_blake2s_reg) is 
	variable i: integer;
	begin
		for i in 0 to 31 loop 
			hash_blake2s_inv(255-(8*i) downto 256-(8*(i+1))) <= hash_blake2s_reg((i*8)+7 downto (i*8));
		end loop;
	end process;


	process(clk) begin 
		if RISING_EDGE(clk) then 
			if (valid_out_blake2s = '1') then 
				hash_blake2s_reg <= hash_blake2s;
			end if;
		end if;
	end process;

	hash_equal <= '1' when (hash_blake2s_inv = target_hash_reg) else '0';

	--Nonce
	en_nonce       <= '1' when (state = GET_NONCE )      else '0';
	incr_nonce     <= '1' when (state = INCREMENT_NONCE) else '0';
	nonce_inv      <= nonce (7 downto 0) & nonce (15 downto 8) & nonce (23 downto 16) & nonce (31 downto 24) & nonce (39 downto 32) & nonce (47 downto 40) & nonce (55 downto 48) & nonce (63 downto 56);
	nonce_inv_add1 <= nonce_inv + 1;
	process(clk) 
	variable i : integer;
	begin 
		if RISING_EDGE(clk) then 
			if (en_nonce = '1') then
				for i in 0 to 7 loop
					nonce(((i+1)*8)-1 downto i*8) <= mblock_data_reg(278+i);
				end loop;
			elsif (incr_nonce = '1') then 
				nonce <= nonce_inv_add1 (7 downto 0) & nonce_inv_add1 (15 downto 8) & nonce_inv_add1 (23 downto 16) & nonce_inv_add1 (31 downto 24) & nonce_inv_add1 (39 downto 32) & nonce_inv_add1 (47 downto 40) & nonce_inv_add1 (55 downto 48) & nonce_inv_add1 (63 downto 56);
			end if;
		end if;
	end process;

	--Golden nonce
	process(clk) begin 
		if RISING_EDGE(clk) then 
			if (hash_equal = '1') then 
				golden_nonce <= nonce_inv;
			end if;
		end if;
	end process;

	found <= '1' when (state = DONE) else '0';

end behav;
--
--------------------------------------------------------------------------------
