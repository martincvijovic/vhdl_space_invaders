library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

----------------------------------------------------------------------------------------------------------------------------------
-- UPV Projekat 2020/2021 - SPACE INVADERS - Projekat 19
-- Cvijovic Martin 2017/0558.
-- 24.12.2020. v1.0
--
-- Top Level Entity - space_invaders.vhd. 
-- 
-- Koriscene komponente : diff (diferencijator), vga_sync (sinhronizacija sa monitorom 1024x768@60Hz), Altera IP PLL (50->65MHz), Altera IP ROM
--
-- Na ekranu se nalaze svemirac i stit koji se pomeraju levo/desno. Na ekranu se nalazi top koji se pomocu dugmica kontrolise i ispaljuje projektile.
-- Cilj igre je pogoditi svemirca. Municija je ogranicena i iznosi 8 projektila.
----------------------------------------------------------------------------------------------------------------------------------

entity space_invaders is
	port(
		clk													 : in std_logic; -- 65MHz clock
		reset												 : in std_logic; -- RESET SW
		dir_l, dir_r									 	 : in std_logic; -- Dugmici za pomeranje levo/desno
		fire												 : in std_logic; -- Dugme za pucanje
		VGA_CLK 											 : out std_logic;-- VGA izlaz (izlaz VGA_SYNC)	
		VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N 			 : out std_logic;-- VGA izlazi (VGA_SYNC) 
		VGA_R, VGA_G, VGA_B 							 	 : out std_logic_vector(7 downto 0); -- VGA izlazi (VGA_SYNC)	
		ammunition										 	 : out std_logic_vector(7 downto 0) -- LED za municiju
	);
end space_invaders;

architecture Behavioral of space_invaders is
	-- Komponente
	component diff is -- Diferencijator je potreban za tastere dir_l, dir_r i fire
		port (
			clk : in std_logic;
			reset : in std_logic;
			tast : in std_logic;
			one : out std_logic
		);
	end component;
	component pll is -- PLL 50MHz -> 65MHz (VGA_SYNC)
		port (
			refclk   : in  std_logic := '0'; --  refclk.clk
			rst      : in  std_logic := '0'; --   reset.reset
			outclk_0 : out std_logic         -- outclk0.clk
		);
	end component;
	component vga_sync is
		generic (
			-- Default display mode is 1024x768@60Hz
			-- Horizontal line
			H_SYNC	: integer := 136;		-- sync pulse in pixels
			H_BP		: integer := 160;		-- back porch in pixels
			H_FP		: integer := 24;		-- front porch in pixels
			H_DISPLAY: integer := 1024;	-- visible pixels
			-- Vertical line
			V_SYNC	: integer := 6;		-- sync pulse in pixels
			V_BP		: integer := 29;		-- back porch in pixels
			V_FP		: integer := 3;		-- front porch in pixels
			V_DISPLAY: integer := 768		-- visible pixels
		);
		port (
			clk : in std_logic;
			reset : in std_logic;
			hsync, vsync : out std_logic;
			sync_n, blank_n : out std_logic;
			hpos : out integer range 0 to H_DISPLAY - 1;
			vpos : out integer range 0 to V_DISPLAY - 1;
			Rin, Gin, Bin : in std_logic_vector(7 downto 0);
			Rout, Gout, Bout : out std_logic_vector(7 downto 0);
			ref_tick : out std_logic
		);
	end component;
	component ImgTop IS -- ROM memorija sa slikom topa (cannon)
		PORT
		(
			address		: IN STD_LOGIC_VECTOR (9 DOWNTO 0);
			clock		: IN STD_LOGIC  := '1';
			q		: OUT STD_LOGIC_VECTOR (11 DOWNTO 0)
		);
	END component;
	component ImgAlien IS -- ROM memorija sa slikom vanzemaljca (alien)
		PORT
		(
			address		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
			clock		: IN STD_LOGIC  := '1';
			q		: OUT STD_LOGIC_VECTOR (11 DOWNTO 0)
		);
	END component;
	component ImgIdle IS -- Slika play dugmeta u stanju koje ceka pocetak igre
		PORT
		(
			address		: IN STD_LOGIC_VECTOR (11 DOWNTO 0);
			clock		: IN STD_LOGIC  := '1';
			q		: OUT STD_LOGIC_VECTOR (11 DOWNTO 0)
		);
	END component;
	component ImgDefeat IS -- Slika tuznog smajlija na ekranu nakon poraza
		PORT
		(
			address		: IN STD_LOGIC_VECTOR (11 DOWNTO 0);
			clock		: IN STD_LOGIC  := '1';
			q		: OUT STD_LOGIC_VECTOR (11 DOWNTO 0)
		);
	END component;
	component ImgVictory IS -- Slika srecnog smajlija na ekranu nakon pobede
		PORT
		(
			address		: IN STD_LOGIC_VECTOR (11 DOWNTO 0);
			clock		: IN STD_LOGIC  := '1';
			q		: OUT STD_LOGIC_VECTOR (11 DOWNTO 0)
		);
	END component;
		
	-- Konstante
	constant C_SECOND : integer := 65000000;
	
	-- Granice ekrana
	constant C_XPOS_MIN : integer := 0;
	constant C_XPOS_MAX : integer := 1023;
	constant C_YPOS_MIN : integer := 0;
	constant C_YPOS_MAX : integer := 767;
	
	-- Sve brzine su date u pikselima po frejmu i sinhronizuju se sa signalom reftick
	
	-- Dimenzije i pocetni polozaj svemirca
	constant C_ALIEN_W : integer := 16;
	constant C_ALIEN_H : integer := 16;
	constant C_ALIEN_SPEED : integer := 5; 
	constant C_ALIEN_X_DEFAULT : integer := 1000;
	constant C_ALIEN_Y_DEFAULT : integer := 50;
	
	-- Dimenzije i pocetni polozaj topa
	constant C_CANNON_W : integer := 24;
	constant C_CANNON_H : integer := 24;
	constant C_CANNON_SPEED : integer := 10;
	constant C_CANNON_X_DEFAULT : integer := 500;
	constant C_CANNON_Y_DEFAULT : integer := 700;
	
	-- Dimenzije (bela boja) i pocetni polozaj stita
	constant C_SHIELD_W : integer := 100;
	constant C_SHIELD_H : integer := 15;
	constant C_SHIELD_SPEED : integer := 8; -- bilo 10
	constant C_SHIELD_X_DEFAULT : integer := 60;
	constant C_SHIELD_Y_DEFAULT : integer := 80;
	
	-- Dimenzije i pocetni polozaj projektila (crvena boja)
	constant C_BULLET_W : integer := 4;
	constant C_BULLET_H : integer := 4; -- ne postoji konstanta za polozaj X, zavisi od lokacije topa
	constant C_BULLET_Y_DEFAULT : integer := C_CANNON_Y_DEFAULT;
	constant C_BULLET_SPEED : integer := 5;
	
	-- Dimenzije i pocetni polozaj poruka (interfejsa)
	constant C_MSG_W : integer := 50;
	constant C_MSG_H : integer := 50;
	constant C_MSG_X : integer := (C_XPOS_MAX - C_MSG_W)/2;
	constant C_MSG_Y : integer := (C_YPOS_MAX - C_MSG_H)/2;
	
	-- Signali
	type dir_t is (DIR_LEFT, DIR_RIGHT, DIR_IDLE);
	
	-- Flagovi za horizontalni smer objekata
	signal dir_cannon : dir_t := DIR_IDLE;
	signal dir_shield : dir_t := DIR_LEFT;
	signal dir_alien : dir_t := DIR_RIGHT;
	
	-- Trenutne vrednosti polozaja objekata na mapi
	signal alien_x, alien_y, cannon_x, cannon_y, shield_x, shield_y, bullet_x, bullet_y : integer range 0 to 1023;

	-- Flag koji odredjuje da li je projektil ispaljen (u tom slucaju ne smemo ispaliti novi dok se ne unisti stari)
	signal bullet_fired : std_logic;
	
	-- Trenutna municija
	signal curr_ammo : unsigned(7 downto 0) := "11111111";
	
	-- Potrebni za vga_sync, kao i za trenutni piksel koji se iscrtava
	signal hpos : integer range 0 to 1023;
	signal vpos : integer range 0 to 767;
	signal Rout, Gout, Bout : std_logic_vector(7 downto 0);
	signal ref_tick : std_logic; -- Aktivan jedan takt na pocetku svakog frejma
	signal color : std_logic_vector(23 downto 0);
	
	-- Odredjuju sta se iscrtava na ekranu
	signal on_alien, on_shield, on_bullet, on_cannon, on_msg : std_logic;
	
	-- Potrebni za dohvatanje bitmapa iz ROM-ova.
	signal datamem_alien : std_logic_vector(11 downto 0);
	signal address_alien : unsigned(7 downto 0);
	signal datamem_cannon : std_logic_vector(11 downto 0);
	signal address_cannon : unsigned(9 downto 0);
	
	signal datamem_idle : std_logic_vector(11 downto 0);
	signal address_idle : unsigned(11 downto 0);
	signal datamem_victory : std_logic_vector(11 downto 0);
	signal address_victory : unsigned(11 downto 0);
	signal datamem_defeat : std_logic_vector(11 downto 0);
	signal address_defeat : unsigned(11 downto 0);
	
	-- Nakon zavrsetka igre odbrojavamo 2 sekunde tokom kojih obavestavamo korisnika o ishodu
	signal end_game_counter : integer range 0 to 2 * C_SECOND;
	
	-- Da li smo pogodili vanzemaljca ili stit
	signal hit : std_logic := '0';
	signal hit_shield : std_logic := '0';
	
	-- 65 MHz takt
	signal clk_65 : std_logic;
	
	-- Tasteri
	signal dir_l_diff, dir_r_diff, fire_diff : std_logic;
	
	-- MASINA STANJA : 
		-- IDLE ( PRITISNI BILO KOJE DUGME DA ZAPOCNES IGRU )
		-- GAME ( IGRA TRAJE )
		-- GAMEOVER ( IGRA GOTOVA, SRECAN ILI TUZAN SMAJLI OBAVESTAVAJU KORISNIKA O ISHODU IGRE. NAKON 2s PRELAZI SE U STANJE IDLE )
	
	type state_t is (StIdle, StGame, StGameOver);
	signal state_reg, next_state : state_t;
	
begin
	-- Inicijalizacija
	
	-- Port reset ostaje 'open' kod PLL-a. Resenje je neprakticno (nemoguce je resetovati PLL ukoliko se izgubi njegov 'phase lock').
	-- Medjutim, ukoliko se poveze reset na PLL tada pri aktivnom resetu staje i sam takt, sto nece resetovati komponente/signale koji su drive-ovani od strane sinhronih procesa.
	-- Potencijalno resenje bi bilo staviti i reset u sensitivity listu sinhronih procesa, medjutim autor se kasno setio te ideje :)
	
	PLL0 : pll port map (refclk => clk, rst => open, outclk_0 => clk_65);
	
	VGA0 : vga_sync port map (clk_65, reset, VGA_HS, VGA_VS, VGA_SYNC_N, VGA_BLANK_N, hpos, vpos, Rout, Gout, Bout, VGA_R, VGA_G, VGA_B, ref_tick);
	
	-- Diferencijator nije neophodan. Moguce je koristiti dugmice i bez diferencijatora (dok je pritisnuto dugme, idi levo/desno, inace stoj).
	-- To resenje takodje funkcionise i za dugme za ispaljivanje projektila jer svakako ne mozemo ispaliti novi dok stari ne pogodi/ispadne iz kadra.
	
	D0: diff port map (clk => clk_65, reset => reset, tast => dir_l, one => dir_l_diff);
	D1: diff port map (clk => clk_65, reset => reset, tast => dir_r, one => dir_r_diff);
	D2: diff port map (clk => clk_65, reset => reset, tast => fire, one => fire_diff);
		
	IMG_A0 : ImgAlien port map (std_logic_vector(address_alien), clk_65, datamem_alien);
	IMG_C0 : ImgTop port map (std_logic_vector(address_cannon), clk_65, datamem_cannon);
	IMG_IDLE0 : ImgIdle port map (std_logic_vector(address_idle), clk_65, datamem_idle);
	IMG_VICTORY0 : ImgVictory port map (std_logic_vector(address_victory), clk_65, datamem_victory);
	IMG_DEFEAT0 : ImgDefeat port map (std_logic_vector(address_defeat), clk_65, datamem_defeat);
	
	-- Procesi
	
	STATE_TRANSITION: process(clk_65) is
	-- Proces zaduzen za ispravno funkcionisanje masine stanja
	begin
		if (rising_edge(clk_65)) then
			if (reset = '1') then
				state_reg <= StIdle;
			else
				state_reg <= next_state;
			end if;
		end if;
	end process STATE_TRANSITION;
	
	COUNTER_PROC: process(clk_65) is
	-- Proces koji odbrojava dve sekunde od pocetka stanja GAME_OVER.
	begin
		if (rising_edge(clk_65)) then
			if (reset = '1') then
				end_game_counter <= 2 * C_SECOND;
			else
				if (state_reg = StGameOver) then
					end_game_counter <= end_game_counter - 1;
				else
					end_game_counter <= 2 * C_SECOND;
				end if;
			end if;
		end if;
	end process COUNTER_PROC;
	
	NEXT_STATE_LOGIC: process(state_reg, curr_ammo, bullet_fired, reset, dir_l_diff, dir_r_diff, fire_diff, end_game_counter, hit) is
	-- Proces je zaduzen za odredjivanje sledeceg stanja nase masine stanja.
	begin
		if (reset = '1') then
			next_state <= StIdle;
		else
			if (state_reg = StIdle) then
				-- U stanju pocetka igre smo, treba da pritisnemo bilo koje dugme da zapocnemo igru.
				if (dir_l_diff = '1' or dir_r_diff = '1' or fire_diff = '1') then
					next_state <= StGame;
				else
					next_state <= StIdle;
				end if;
			elsif (state_reg = StGame) then
				-- Ako smo potrosili svu municiju i nas poslednji metak je ispao sa ekrana (ili smo pogodili svemirca) zavrsavamo partiju
				if ((bullet_fired = '0' and curr_ammo = "00000000") or hit = '1') then
					next_state <= StGameOver;
				else
					next_state <= StGame;
				end if;
			else 
				-- Zavrsili smo igru, obavestavamo korisnika o pobedi ili porazu.
				if (end_game_counter = 0) then
					next_state <= StIdle;
				else
					next_state <= StGameOver;
				end if;
			end if;	
		end if;
	end process NEXT_STATE_LOGIC;
	
	MOVING_OBJECTS: process(clk_65) is
	-- Proces je zaduzen za pomeranje objekata po mapi i promenu smera kretanja pri udaru u ivicu (za alien i shield)
	begin
		if (rising_edge(clk_65)) then
			if (reset = '1') then
				alien_x <= C_ALIEN_X_DEFAULT;
				alien_y <= C_ALIEN_Y_DEFAULT;
				
				cannon_x <= C_CANNON_X_DEFAULT;
				cannon_y <= C_CANNON_Y_DEFAULT;
				
				shield_x <= C_SHIELD_X_DEFAULT;
				shield_y <= C_SHIELD_Y_DEFAULT;
				
				bullet_fired <= '0';
				hit <= '0';
				hit_shield <= '0';
				
				curr_ammo <= "11111111";
			else
				if (state_reg = StIdle) then
					alien_x <= C_ALIEN_X_DEFAULT;
					alien_y <= C_ALIEN_Y_DEFAULT;
					
					cannon_x <= C_CANNON_X_DEFAULT;
					cannon_y <= C_CANNON_Y_DEFAULT;
					
					shield_x <= C_SHIELD_X_DEFAULT;
					shield_y <= C_SHIELD_Y_DEFAULT;
					
					bullet_fired <= '0';
					hit <= '0';
					hit_shield <= '0';
					
					curr_ammo <= "11111111";
				end if;
			
				if (dir_l_diff = '1') then
					dir_cannon <= DIR_LEFT;
				elsif (dir_r_diff = '1') then
					dir_cannon <= DIR_RIGHT;
				else
					null;
				end if;
				
				if (state_reg = StGameOver) then
					curr_ammo <= "11111111";
				end if;
				
				if (fire_diff = '1') then
					if (bullet_fired = '0' and state_reg = StGame) then -- Ne zelimo da ispaljujemo dodatne metkove u StGameOver i StIdle
					
						-- bullet_fired je signal koji se aktivira pri pritisku na dugme fire i aktivan je sve dok projektil ne nestane sa ekrana.
					
						bullet_fired <= '1';
						bullet_x <= cannon_x + C_CANNON_W/2;
						bullet_y <= C_CANNON_Y_DEFAULT - 15; -- Postavljamo piksel metka 15px iznad topa.
						curr_ammo <= shift_right(curr_ammo, 1); -- Smanjujemo municiju za 1
					end if;
				end if;
				
				if (ref_tick = '1') then
					-- ref_tick nas obavestava o pocetku novog frejma. Kada je on na '1' apdejtuju se adrese nasih objekata.
					-- Pre ref_ticka registrujemo pritisak na dugme, na ref_tick obradjujemo trenutni pritisak i dozvoljavamo novi.
					if (dir_alien = DIR_LEFT) then
						if (alien_x - C_ALIEN_SPEED > 0) then
							alien_x <= alien_x - C_ALIEN_SPEED;
						else
							alien_x <= 0;
							dir_alien <= DIR_RIGHT;
						end if;
					else
						if (alien_x + C_ALIEN_W + C_ALIEN_SPEED < C_XPOS_MAX) then
							alien_x <= alien_x + C_ALIEN_SPEED;
						else
							alien_x <= C_XPOS_MAX - C_ALIEN_W;
							dir_alien <= DIR_LEFT;
						end if;
					end if;
					
					if (dir_cannon = DIR_LEFT) then 
						if (cannon_x - C_CANNON_SPEED > 0) then
							cannon_x <= cannon_x - C_CANNON_SPEED;
						else
							cannon_x <= 0;
						end if;
					elsif (dir_cannon = DIR_RIGHT) then
						if (cannon_x + C_CANNON_W + C_CANNON_SPEED < C_XPOS_MAX) then
							cannon_x <= cannon_x + C_CANNON_SPEED;
						else
							cannon_x <= C_XPOS_MAX - C_CANNON_W;
						end if;
					else
						null;
					end if;
					
					dir_cannon <= DIR_IDLE; -- Obradili smo kretanje topa.
					
					if (dir_shield = DIR_LEFT) then
						if (shield_x - C_SHIELD_SPEED > 0) then
							shield_x <= shield_x - C_SHIELD_SPEED;
						else
							shield_x <= 0;
							dir_shield <= DIR_RIGHT;
						end if;
					else
						if (shield_x + C_SHIELD_W + C_SHIELD_SPEED < C_XPOS_MAX) then
							shield_x <= shield_x + C_SHIELD_SPEED;
						else
							shield_x <= C_XPOS_MAX - C_SHIELD_W;
							dir_shield <= DIR_LEFT;
						end if;
					end if;
					
					if (bullet_fired = '1') then
						-- Ukoliko smo ispalili metak obradjujemo njegove koordinate.
						if (bullet_y - C_BULLET_SPEED > 0) then
							bullet_y <= bullet_y - C_BULLET_SPEED;
							
							if (bullet_x >= shield_x and bullet_y >= shield_y and bullet_x < shield_x + C_SHIELD_W and bullet_y < shield_y + C_SHIELD_H) then
								hit_shield <= '1';
							end if;
							
							if (bullet_x >= alien_x and bullet_y >= alien_y and bullet_x < alien_x + C_ALIEN_W and bullet_y < alien_y + C_ALIEN_H) then
								hit <= '1';
							end if;
						else
							bullet_fired <= '0';
						end if;
						
						if (hit_shield = '1') then
							bullet_fired <= '0';
							bullet_x <= cannon_x + C_CANNON_W/2;
							bullet_y <= C_CANNON_Y_DEFAULT - 15;
							hit_shield <= '0';
						end if;
						
						-- bullet_fired se vraca na nulu ukoliko ispadnemo sa ivice ekrana po y osi ili pogodimo stit. Ukoliko pogodimo svemirca,
						-- pomocu signala hit cemo preci u stanje GAME_OVER gde cemo prikazati poruku o pobedi, a tada, pri prelasku u stanje IDLE, prebaciti bullet_fired na 0.
						
					else
						null; 
					end if;
				end if;
			end if;
		end if;
	end process MOVING_OBJECTS;	
	
	PIXEL_OBJECT: process(hpos, vpos, on_alien, on_shield, on_bullet, on_cannon, bullet_fired, alien_x, alien_y, shield_x, shield_y, cannon_x, cannon_y, bullet_x, bullet_y) is
	-- Proces je zaduzen za racunanje da li trenutni piksel pripada nekom objektu
	begin
		if (hpos >= alien_x and hpos < alien_x + C_ALIEN_W and vpos >= alien_y and vpos < alien_y + C_ALIEN_H) then
			on_alien <= '1';
		else
			on_alien <= '0';
		end if;
		
		if (hpos >= shield_x and hpos < shield_x + C_SHIELD_W and vpos >= shield_y and vpos < shield_y + C_SHIELD_H) then
			on_shield <= '1';
		else
			on_shield <= '0';
		end if;
		
		if (hpos >= cannon_x and hpos < cannon_x + C_CANNON_W and vpos >= cannon_y and vpos < cannon_y + C_CANNON_H) then
			on_cannon <= '1';
		else
			on_cannon <= '0';
		end if;
		
		if (hpos >= bullet_x and hpos < bullet_x + C_BULLET_W and vpos >= bullet_y and vpos < bullet_y + C_BULLET_H and bullet_fired = '1') then
			on_bullet <= '1';
		else
			on_bullet <= '0';
		end if;
		
		if (hpos >= C_MSG_X and hpos < C_MSG_X + C_MSG_W and vpos >= C_MSG_Y and vpos < C_MSG_Y + C_MSG_H) then
			on_msg <= '1';
		else
			on_msg <= '0';
		end if;
	end process PIXEL_OBJECT;
	
	COLOR_OBJECT: process(hit, on_msg, state_reg, hpos, vpos, reset, on_alien, on_cannon, on_shield, on_bullet, datamem_alien, datamem_cannon, datamem_victory, datamem_defeat, datamem_idle) is
	-- Proces je zaduzen da na osnovu trenutnog stanja i trenutne pozicije objekata i 'kursora za iscrtavanje na ekran' izracuna boju trenutnog piksela.
	begin
		if (reset = '1') then
			color <= (others => '0');
		else
			if (state_reg = StIdle) then
				if (on_msg = '1') then
					color <= datamem_idle(11 downto 8) & x"0" & datamem_idle(7 downto 4) & x"0" & datamem_idle(3 downto 0) & x"0";
				else
					color <= (others => '0');
				end if;
			elsif (state_reg = StGame) then
				if (on_alien = '1') then
					color <= datamem_alien(11 downto 8) & x"0" & datamem_alien(7 downto 4) & x"0" & datamem_alien(3 downto 0) & x"0";
				elsif (on_cannon = '1') then
					color <= datamem_cannon(11 downto 8) & x"0" & datamem_alien(7 downto 4) & x"0" & datamem_alien(3 downto 0) & x"0";
				elsif (on_shield = '1') then
					color <= (others => '1'); 				 -- bela
				elsif (on_bullet = '1') then
					color <= "111111110000000000000000"; -- crvena
				else -- on background
					color <= (others => '0');				 -- crna
				end if;
			else -- StGameOver
				if (hit = '1') then
					if (on_msg = '1') then
						color <= datamem_victory(11 downto 8) & x"0" & datamem_victory(7 downto 4) & x"0" & datamem_victory(3 downto 0) & x"0";
					else
						color <= (others => '0');
					end if;
				else
					if (on_msg = '1') then
						color <= datamem_defeat(11 downto 8) & x"0" & datamem_defeat(7 downto 4) & x"0" & datamem_defeat(3 downto 0) & x"0";
					else
						color <= (others => '0');
					end if;
				end if;
			end if;
			
		end if;
	end process COLOR_OBJECT;
	
	ADDRESS_CALC: process(clk_65) is
	-- Izvlaci podatke iz ROM memorija.
	begin
		if (rising_edge(clk_65)) then
			if (reset = '1') then
				address_alien <= (others => '0');
				address_cannon <= (others => '0');
				address_victory <= (others => '0');
				address_defeat <= (others => '0');
				address_idle <= (others => '0');
			else
				if (on_alien = '1') then
					if (state_reg = StGame) then
						if (address_alien = C_ALIEN_W * C_ALIEN_H - 1) then
							address_alien <= (others => '0');
						else
							address_alien <= address_alien + 1;
						end if;
					else
						address_alien <= (others => '0');
					end if;
					
				elsif (on_cannon = '1') then
					if (state_reg = StGame) then
						if (address_cannon = C_CANNON_W * C_CANNON_H - 1) then
							address_cannon <= (others => '0');
						else
							address_cannon <= address_cannon + 1;
						end if;
					else
						address_cannon <= (others => '0');
					end if;
					
				elsif (on_msg = '1') then	
					address_alien <= (others => '0');
					address_cannon <= (others => '0');
					if (state_reg = StIdle) then
						if (address_idle = C_MSG_W * C_MSG_H - 1) then
							address_idle <= (others => '0');
						else
							address_idle <= address_idle + 1;
						end if;
					elsif (state_reg = StGameOver) then
						if (hit = '1') then
							if (address_victory = C_MSG_W * C_MSG_H - 1) then
								address_victory <= (others => '0');
							else
								address_victory <= address_victory + 1;
							end if;
						else
							if (address_defeat = C_MSG_W * C_MSG_H - 1) then
								address_defeat <= (others => '0');
							else
								address_defeat <= address_defeat + 1;
							end if;
						end if;
					end if;
				else null;
				end if;
			end if;
		end if;
	end process ADDRESS_CALC;
	
	Rout <= color(23 downto 16);
	Gout <= color(15 downto 8);
	Bout <= color(7 downto 0);
	
	ammunition <= std_logic_vector(curr_ammo);
	VGA_CLK <= clk_65;
	
end architecture Behavioral;