library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

entity ledc8x8 is
port ( -- Sem doplnte popis rozhrani obvodu.
	RESET, SMCLK	: in std_logic;
	ROW, LED  : out std_logic_vector  (0 to 7)
	);
end ledc8x8;

architecture main of ledc8x8 is

    -- Sem doplnte definice vnitrnich signalu.
    signal ce_cnt, leds_vector, rows_vector	: std_logic_vector(7 downto 0);
	signal ce, state_signal					: std_logic;
	signal state_vector			: std_logic_vector(3 downto 0);
	signal swich_cnt			: std_logic_vector(20 downto 0);
	


begin

    -- Sem doplnte popis obvodu. Doporuceni: pouzivejte zakladni obvodove prvky
    -- (multiplexory, registry, dekodery,...), jejich funkce popisujte pomoci
    -- procesu VHDL a propojeni techto prvku, tj. komunikaci mezi procesy,
    -- realizujte pomoci vnitrnich signalu deklarovanych vyse.

    -- DODRZUJTE ZASADY PSANI SYNTETIZOVATELNEHO VHDL KODU OBVODOVYCH PRVKU,
    -- JEZ JSOU PROBIRANY ZEJMENA NA UVODNICH CVICENI INP A SHRNUTY NA WEBU:
    -- http://merlin.fit.vutbr.cz/FITkit/docs/navody/synth_templates.html.

    -- Nezapomente take doplnit mapovani signalu rozhrani na piny FPGA
    -- v souboru ledc8x8.ucf.
	 --countre
	cnt: process(SMCLK, RESET)
		begin
			if RESET = '1' then														
				ce_cnt <= "00000000";
			elsif rising_edge(SMCLK) then	
				ce_cnt <= ce_cnt + 1;
			end if;

			if RESET = '1' then
				swich_cnt <= "000000000000000000000";
			elsif rising_edge(SMCLK) then								
				swich_cnt <= swich_cnt + 1;
			end if;

		end process cnt;

		--nastavenie signálov
		ce <= '1' when ce_cnt = "11111111" else '0';
		state_signal <= '1' when (swich_cnt = "111111111111111111111") else '0';
		
		--rotácia vektorov
		rot: process(RESET, ce, SMCLK, state_signal)
		begin
			if RESET = '1' then											
				rows_vector <= "10000000";
				state_vector <= "1000";
			elsif rising_edge(SMCLK) then
				if (state_signal = '1') then
					state_vector <= state_vector(0) & state_vector(3 downto 1);
				end if;
				if (ce = '1') then
					rows_vector <= rows_vector(0) & rows_vector(7 downto 1);	
				end if;

			end if; 
		end process rot;

		-- jednotlivé stavy
		switch: process(rows_vector,state_vector)
		begin

		case( state_vector ) is
		
			when "1000" => case rows_vector is
							when "10000000" => leds_vector <= "11111111";
							when "01000000" => leds_vector <= "11100111";
							when "00100000" => leds_vector <= "11011011";
							when "00010000" => leds_vector <= "11011011";
							when "00001000" => leds_vector <= "11000011";
							when "00000100" => leds_vector <= "11011011";
							when "00000010" => leds_vector <= "11011011";
							when "00000001" => leds_vector <= "11011011";
							when others		=> leds_vector <= "11111111";
							end case;--A
			
			when "0010" => case rows_vector is
						when "10000000" => leds_vector <= "11111111";
						when "01000000" => leds_vector <= "11011011";
						when "00100000" => leds_vector <= "11011011";
						when "00010000" => leds_vector <= "11000011";
						when "00001000" => leds_vector <= "11011011";
						when "00000100" => leds_vector <= "11011011";
						when "00000010" => leds_vector <= "11011011";
						when "00000001" => leds_vector <= "11011011";
						when others		=> leds_vector <= "11111111";
						end case; --H
			when others => leds_vector <= "11111111";

		
		end case ;
			
		end process switch;

		-- rozsvietenie LED
		ROW <= rows_vector;
		LED <= leds_vector;
end main;
