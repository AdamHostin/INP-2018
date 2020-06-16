-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2018 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): DOPLNIT
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni z pameti (DATA_RDWR='1') / zapis do pameti (DATA_RDWR='0')
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA obsahuje stisknuty znak klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna pokud IN_VLD='1'
   IN_REQ    : out std_logic;                     -- pozadavek na vstup dat z klavesnice
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- pokud OUT_BUSY='1', LCD je zaneprazdnen, nelze zapisovat,  OUT_WE musi byt '0'
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

 -- zde dopiste potrebne deklarace signalu

   -- PC.
   signal pc_reg : std_logic_vector(11 downto 0); -- PC
   signal pc_inc : std_logic; -- inkrementacia
   signal pc_dec : std_logic; -- dekrementacia
   signal pc_init : std_logic; -- vycisti register

   -- PTR.
   signal ptr_reg : std_logic_vector(9 downto 0); -- PTR
   signal ptr_inc : std_logic; -- inkrementacia
   signal ptr_dec : std_logic; -- dekrementacia
   signal ptr_init: std_logic; -- vycisti register

   -- CNT.
   signal cnt_reg : std_logic_vector(11 downto 0); -- cítac poctu závorek
   signal cnt_inc : std_logic; -- inkrementacia
   signal cnt_dec : std_logic; -- dekrementacia
   signal cnt_init : std_logic; -- vycisti register

   -- Vektor pre vyber hodnoty zapisovaných dat.
   -- 00 => zapis z IN_DATA
   -- 01 => zapis z CODE_DATA
   -- 10 => zapis hodnoty aktualnej bunky -1
   -- 11 => zapis hodnoty aktualnej bunky +1
   signal mx_data_wdata_sel : std_logic_vector(1 downto 0) := "00"; --selector
   signal mx_data_wdata : std_logic_vector(7 downto 0);


   -- FSM
   type fsm_state is (
      idle,                    	-- povodny stav
      fetch,                 	-- nacitanie instrukcie
      decode,               	-- dekodovanie instrukcie
      inc_ptr,                 	-- > inkrementacia pointera
      dec_ptr,                 	-- < dekrementacia pointera
      inc_val_0, inc_val_1, inc_val_2, -- + inkrementacia hodnoty aktualnej bunky
      dec_val_0, dec_val_1, dec_val_2, -- - dekrementacia hodnoty aktualnej bunky
      while_start_0, while_start_1, while_start_2, while_start_3, 		-- [ - zaciatok cyklu
      while_end_0, while_end_1, while_end_2, while_end_3, while_end_4, 	-- ] - koniec cyklu
      putchar_0, putchar_1,  -- . print hodnoty aktualnej bunky
      getchar_0, getchar_1,  -- , nacitanie hodnoty do aktualnej bunky
      block_coment_0, block_coment_1,block_coment_2, -- # comentar
      get_val_0, get_val_1, get_val_2, --nacitanie hex hodnoty 0xV0 z kodu
      return_0,                  -- null - zastavenie programu
      others_0                   -- stav pre nezname znaky
   );
   signal fsm_pstate : fsm_state := idle;  -- sucasny stav
   signal fsm_nstate : fsm_state;            -- nasledujuci stav

begin

   -- PC (prog cnt) proces.
   pc_cntr: process (CLK, RESET, pc_inc, pc_dec)
   begin
      if RESET = '1' then
         pc_reg <= (others => '0');
      
      elsif CLK'event and CLK = '1' then
      
         if pc_inc = '1' then
            pc_reg <= pc_reg + 1;
      
         elsif pc_dec = '1' then
            pc_reg <= pc_reg - 1;
      
         elsif pc_init = '1' then
            pc_reg <= (others => '0');
         end if;
      end if;
   end process;

   CODE_ADDR <= pc_reg;

   -- CNT (stupen zanorenia cyklu) proces
   cnt_cntr: process (CLK, RESET, cnt_inc, cnt_dec)
   begin
      if RESET = '1' then
         cnt_reg <= (others => '0');
      elsif CLK'event and CLK = '1' then
         if cnt_inc = '1' then
            cnt_reg <= cnt_reg + 1;
         elsif cnt_dec = '1' then
            cnt_reg <= cnt_reg - 1;
         elsif cnt_init = '1' then
            cnt_reg <= (others => '0');
         end if;
      end if;
   end process;

   -- PTR (addr cnt) proces.
   ptr_cntr: process (CLK, RESET, ptr_inc, ptr_dec)
   begin
      if RESET = '1' then
         ptr_reg <= (others => '0');
      elsif CLK'event and CLK = '1' then
         if ptr_inc = '1' then
         	if ptr_reg = "111111111111" then
         		ptr_reg <= (others => '0');
         	else
         		ptr_reg <= ptr_reg + 1;
         	end if ;
         elsif ptr_dec = '1' then
         	if ptr_reg = "000000000000" then
         		ptr_reg <= (others => '1');
         	else
         		ptr_reg <= ptr_reg - 1;
         	end if ;
         elsif ptr_init = '1' then
            ptr_reg <= (others => '0');
         end if;
      end if;
   end process;

   DATA_ADDR <= ptr_reg;
   --
   -- nastavenie vystupu
   OUT_DATA <= DATA_RDATA;


   -- MX vybera hodnotu zapisovanu do RAM pamate
   mx_data_wdata_proc: process (CLK, RESET, mx_data_wdata_sel)
   begin
      if RESET = '1' then
         mx_data_wdata <= (others => '0');
      elsif CLK'event and CLK = '1' then
         case mx_data_wdata_sel is
            when "00" =>
               -- zapis hodnoty zo vstupu
               mx_data_wdata <= IN_DATA;

            when "01" =>
               -- zapis code data (HEX hodnoty)

               case( CODE_DATA ) is
               
               		when X"30" =>
                  		mx_data_wdata <= X"00";
               		when X"31" =>
                  		mx_data_wdata <= X"10";
               		when X"32" =>
                  		mx_data_wdata <= X"20";
               		when X"33" =>
                  		mx_data_wdata <= X"30";
               		when X"34" =>
                  		mx_data_wdata <= X"40";
               		when X"35" =>
                  		mx_data_wdata <= X"50";
               		when X"36" =>
                  		mx_data_wdata <= X"60";
               		when X"37" =>
                  		mx_data_wdata <= X"70";
               		when X"38" =>
                  		mx_data_wdata <= X"80";
               		when X"39" =>
                  		mx_data_wdata <= X"90";
               		when X"41" =>
                  		mx_data_wdata <= X"A0";
               		when X"42" =>
                 		mx_data_wdata <= X"B0";
               		when X"43" =>
                  		mx_data_wdata <= X"C0";
               		when X"44" =>
                  		mx_data_wdata <= X"D0";
               		when X"45" =>
                  		mx_data_wdata <= X"E0";
               		when X"46" =>
                  		mx_data_wdata <= X"F0";
               		
               
               		when others =>
              			mx_data_wdata <= CODE_DATA;
               		end case ;

            when "10" =>
               -- zapis hodnoty aktualnej bunky -1
               mx_data_wdata <= DATA_RDATA - 1;

            when "11" =>
               -- zapis hodnoty aktualnej bunky +1
               mx_data_wdata <= DATA_RDATA + 1;
            when others =>
            	null;

         end case;
      end if;
   end process;

   DATA_WDATA <= mx_data_wdata;


   -- FSM

   -- logika aktualneho stavu
   fsm_pstate_proc: process (CLK, RESET, EN)
   begin
      if RESET = '1' then
         fsm_pstate <= idle;
      elsif CLK'event and CLK = '1' then
         if EN = '1' then
            fsm_pstate <= fsm_nstate;
         end if;
      end if;
   end process;

   -- logika nasledujuceho stavu
   fsm_nstate_proc: process (fsm_pstate, OUT_BUSY, IN_VLD, CODE_DATA, cnt_reg, DATA_RDATA)
   begin
      -- init
      OUT_WE <= '0';
      IN_REQ <= '0';
      CODE_EN <= '0';
      pc_inc <= '0';
      pc_dec <= '0';
      pc_init <= '0';
      ptr_inc <= '0';
      ptr_dec <= '0';
      ptr_init <= '0';
      cnt_inc <= '0';
      cnt_dec <= '0';
      cnt_init <= '0';
      mx_data_wdata_sel <= "00";
      DATA_EN <= '0';
      DATA_RDWR <= '0';

      case fsm_pstate is
         
         -- reset
         when idle =>
            pc_init <= '1'; -- PC = 0
            ptr_init <= '1'; -- PTR = 0
            cnt_init <= '1'; -- CNT = 0

            fsm_nstate <= fetch;


         -- nacitanie instrukcie
         when fetch =>
            CODE_EN <= '1'; 

            fsm_nstate <= decode;


         -- dekodovanie instrukcie
         when decode =>
            case CODE_DATA is
               when X"3E" =>
                  fsm_nstate <= inc_ptr; -- > - inc pointera (posun v pravo)
               when X"3C" =>
                  fsm_nstate <= dec_ptr; -- < - dec pointera (posun v lavo)
               when X"2B" =>
                  fsm_nstate <= inc_val_0; -- + - inc hodnoty aktualnej bunky
               when X"2D" =>
                  fsm_nstate <= dec_val_0; -- - - dec hodnoty aktualnej bunky
               when X"5B" =>
                  fsm_nstate <= while_start_0; -- [ - zaciatok cyklu
               when X"5D" =>
                  fsm_nstate <= while_end_0; -- ] - koniec cyklu
               when X"2E" =>
                  fsm_nstate <= putchar_0; -- . - vypis hodnoty na FITkit
               when X"2C" =>
                  fsm_nstate <= getchar_0; -- , - nacitanie hodnoty do aktualnej bunky
               when X"23" =>
                  fsm_nstate <= block_coment_0; -- # - blokovy komentar
               when X"00" =>
                  fsm_nstate <= return_0; -- null - koniec programu
               --nacitanie HEX hodnot
               when X"30" =>
                  fsm_nstate <= get_val_0;
               when X"31" =>
                  fsm_nstate <= get_val_0;
               when X"32" =>
                  fsm_nstate <= get_val_0;
               when X"33" =>
                  fsm_nstate <= get_val_0;
               when X"34" =>
                  fsm_nstate <= get_val_0;
               when X"35" =>
                  fsm_nstate <= get_val_0;
               when X"36" =>
                  fsm_nstate <= get_val_0;
               when X"37" =>
                  fsm_nstate <= get_val_0;
               when X"38" =>
                  fsm_nstate <= get_val_0;
               when X"39" =>
                  fsm_nstate <= get_val_0;
               when X"41" =>
                  fsm_nstate <= get_val_0;
               when X"42" =>
                  fsm_nstate <= get_val_0;
               when X"43" =>
                  fsm_nstate <= get_val_0;
               when X"44" =>
                  fsm_nstate <= get_val_0;
               when X"45" =>
                  fsm_nstate <= get_val_0;
               when X"46" =>
                  fsm_nstate <= get_val_0;
               when others =>
                  fsm_nstate <= others_0; -- neznamy znak
            end case;


        -- > - inc pointera (posun vpravo)
         when inc_ptr =>
            ptr_inc <= '1'; -- PTR += 1
            pc_inc <= '1'; -- PC += 1

            fsm_nstate <= fetch;


        -- > - dec pointera (posun vlavo)
         when dec_ptr =>
            ptr_dec <= '1'; -- PTR -= 1
            pc_inc <= '1'; -- PC += 1

            fsm_nstate <= fetch;


         -- + - inc hodnoty aktualnej bunky
         when inc_val_0 =>
            
            DATA_EN <= '1';
            DATA_RDWR <= '1';

            fsm_nstate <= inc_val_1;

         when inc_val_1 =>
            mx_data_wdata_sel <= "11"; -- DATA_WDATA += 1

            fsm_nstate <= inc_val_2;

         when inc_val_2 =>
            
            DATA_EN <= '1';
            DATA_RDWR <= '0';

            pc_inc <= '1'; -- PC += 1

            fsm_nstate <= fetch;


         -- - - dec hodnoty aktualnej bunky
         when dec_val_0 =>
            
            DATA_EN <= '1';
            DATA_RDWR <= '1';

            fsm_nstate <= dec_val_1;

         when dec_val_1 =>
            mx_data_wdata_sel <= "10"; -- DATA_WDATA -= 1

            fsm_nstate <= dec_val_2;

         when dec_val_2 =>
            
            DATA_EN <= '1';
            DATA_RDWR <= '0';

            pc_inc <= '1'; -- PC += 1

            fsm_nstate <= fetch;


        -- [ - zaciatok cyklu
         when while_start_0 =>
            
            pc_inc <= '1'; -- PC += 1
            
            DATA_EN <= '1';
            DATA_RDWR <= '1';

            fsm_nstate <= while_start_1;

         when while_start_1 =>
            
            if DATA_RDATA /= (DATA_RDATA'range => '0') then -- (DATA_RDATA != 0)
               fsm_nstate <= fetch;
            else -- (DATA_RDATA == 0)
               cnt_inc <= '1'; -- CNT += 1
               CODE_EN <= '1'; 

               fsm_nstate <= while_start_2;
            end if;

         
         when while_start_2 =>
            if cnt_reg = (cnt_reg'range => '0') then -- (CNT == 0)
               fsm_nstate <= fetch;
            else -- (CNT != 0)
               if CODE_DATA = X"5B" then -- (CODE_DATA == '[')
                  cnt_inc <= '1'; -- CNT += 1
               elsif CODE_DATA = X"5D" then -- (CODE_DATA == ']')
                  cnt_dec <= '1'; -- CNT -= 1
               end if;

               pc_inc <= '1'; -- PC += 1

               fsm_nstate <= while_start_3;
            end if;

         when while_start_3 =>
            CODE_EN <= '1'; 

            fsm_nstate <= while_start_2;


         -- ] - koniec cyklu
         when while_end_0 =>
            
            DATA_EN <= '1';
            DATA_RDWR <= '1';

            fsm_nstate <= while_end_1;

         when while_end_1 =>
            if DATA_RDATA = (DATA_RDATA'range => '0') then -- (DATA_RDATA == 0)
               pc_inc <= '1'; -- PC += 1

               fsm_nstate <= fetch;
            else -- (DATA_RDATA != 0)
               cnt_inc <= '1'; -- CNT += 1
               pc_dec <= '1'; -- PC -= 1

               fsm_nstate <= while_end_4;
            end if;

         when while_end_2 =>
            if cnt_reg = (cnt_reg'range => '0') then -- (CNT == 0)
               fsm_nstate <= fetch;
            else
               if CODE_DATA = X"5D" then -- (CODE_DATA == ']')
                  cnt_inc <= '1'; -- CNT += 1
               elsif CODE_DATA = X"5B" then -- (CODE_DATA == '[')
                  cnt_dec <= '1'; -- CNT -= 1
               end if;

               fsm_nstate <= while_end_3;
            end if;

         when while_end_3 =>

            if cnt_reg = (cnt_reg'range => '0') then -- (CNT == 0)
               pc_inc <= '1'; -- PC += 1
            else -- (CNT != 0)
               pc_dec <= '1'; -- PC -= 1
            end if;

            fsm_nstate <= while_end_4;

         when while_end_4 =>
            CODE_EN <= '1'; 

            fsm_nstate <= while_end_2;


         -- . - vypis hodnoty na FITkit
         when putchar_0 =>
            
            DATA_EN <= '1';
            DATA_RDWR <= '1';

            fsm_nstate <= putchar_1;

         when putchar_1 =>
            if OUT_BUSY = '1' then
               
               DATA_EN <= '1';
               DATA_RDWR <= '1';

               fsm_nstate <= putchar_1;
            else
               OUT_WE <= '1'; 

               pc_inc <= '1'; -- PC += 1

               fsm_nstate <= fetch;
            end if;


         -- , - nacitanie hodnoty do aktualnej bunky
         when getchar_0 =>
            IN_REQ <= '1';
            mx_data_wdata_sel <= "00"; -- DATA_WDATA = IN_DATA

            fsm_nstate <= getchar_1;

         when getchar_1 =>
            if IN_VLD /= '1' then
               IN_REQ <= '1';
               mx_data_wdata_sel <= "00"; -- DATA_WDATA = IN_DATA

               fsm_nstate <= getchar_1;
            else
               
               DATA_EN <= '1';
               DATA_RDWR <= '0';

               pc_inc <= '1'; -- PC += 1

               fsm_nstate <= fetch;
            end if;

         
         --blokovy komentar   
		when block_coment_0 =>
			
		    pc_inc <= '1'; -- PC += 1
		    fsm_nstate <= block_coment_1;
	

         when block_coment_1 =>
            CODE_EN <= '1'; 

            fsm_nstate <= block_coment_2;

         when block_coment_2 =>

        	pc_inc <= '1'; -- PC += 1
            if CODE_DATA = X"23" then -- (CODE_DATA == '#')
            	
            	fsm_nstate <= fetch;
            
            else 
            
               fsm_nstate <= block_coment_1;
            end if;

         --nacitanie HEX hodnot
         when get_val_0 =>
            
            DATA_EN <= '1';
            DATA_RDWR <= '1';

            fsm_nstate <= get_val_1;

         when get_val_1 =>
            mx_data_wdata_sel <= "01"; -- DATA_WDATA = CODE_DATA


            fsm_nstate <= get_val_2;

         when get_val_2 =>
            
            DATA_EN <= '1';
            DATA_RDWR <= '0';

            pc_inc <= '1'; -- PC += 1

            fsm_nstate <= fetch;


         -- null - koniec programu
         when return_0 =>
            fsm_nstate <= return_0;


         -- neznamy znak
         when others_0 =>
            pc_inc <= '1'; -- PC += 1

            fsm_nstate <= fetch;


         --nedefinovany stav     
         when others =>
            null;

      end case;
   end process;

end behavioral;