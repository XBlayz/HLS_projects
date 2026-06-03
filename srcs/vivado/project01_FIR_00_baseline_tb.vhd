library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fir_tb is
-- Nessuna porta esterna per il testbench
end entity fir_tb;

architecture behavioral of fir_tb is

    -- 1. Dichiarazione del componente (Deve corrispondere al nome generato da Vivado)
    component fir_0 is
        port (
            ap_clk   : in  std_logic;
            ap_rst   : in  std_logic;
            ap_start : in  std_logic;
            ap_done  : out std_logic;
            ap_idle  : out std_logic;
            ap_ready : out std_logic;
            x        : in  std_logic_vector(31 downto 0);
            y        : out std_logic_vector(31 downto 0);
            y_ap_vld : out std_logic
        );
    end component fir_0;

    -- 2. Definizione dei parametri di simulazione
    constant CLK_PERIOD : time := 10 ns;
    constant N_SAMPLES  : integer := 30;

    -- Segnali interni
    signal clk_sig   : std_logic := '0';
    signal rst_sig   : std_logic := '1';
    signal start_sig : std_logic := '0';
    signal done_sig  : std_logic;
    signal idle_sig  : std_logic;
    signal ready_sig : std_logic;
    signal x_sig     : std_logic_vector(31 downto 0) := (others => '0');
    signal y_sig     : std_logic_vector(31 downto 0);
    signal y_vld_sig : std_logic;

    signal sim_done  : boolean := false;

    -- 3. Golden Array: Uscite attese pre-calcolate dal C-Testbench
    type int_array is array (0 to N_SAMPLES - 1) of integer;
    constant EXPECTED_Y : int_array := (
        53, 0, -91, 0, 313, 500, 313, 0, -91, 0, 53, 0, 0, 0, 0,
        106, 0, -182, 0, 626, 1000, 626, 0, -182, 0, 106, 0, 0, 0, 0
    );

begin

    -- Istanziazione dell'Unità Under Test (UUT)
    -- NOTA: La label 'uut_inst' è richiesta dallo script Tcl per generare il file SAIF
    uut_inst: fir_0
        port map (
            ap_clk   => clk_sig,
            ap_rst   => rst_sig,
            ap_start => start_sig,
            ap_done  => done_sig,
            ap_idle  => idle_sig,
            ap_ready => ready_sig,
            x        => x_sig,
            y        => y_sig,
            y_ap_vld => y_vld_sig
        );

    -- Generazione del segnale di Clock
    clk_process : process
    begin
        while not sim_done loop
            clk_sig <= '0';
            wait for CLK_PERIOD / 2;
            clk_sig <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Processo principale di Stimolo e Verifica (Self-Checking)
    stim_process : process
        variable hw_result : integer;
    begin
        -- Sequenza di Reset (HLS usa reset alti attivi di default)
        report "=========================================================";
        report " INIZIO SIMULAZIONE E GENERAZIONE STIMOLI";
        report "=========================================================";
        rst_sig <= '1';
        wait for CLK_PERIOD * 5;

        -- Deasserzione del reset in corrispondenza del fronte di discesa
        -- per evitare problemi di setup/hold in simulazione RTL
        wait until falling_edge(clk_sig);
        rst_sig <= '0';
        wait for CLK_PERIOD * 2;

        -- Ciclo di test: inietta 30 campioni
        for i in 0 to N_SAMPLES - 1 loop

            -- A. Generazione degli stimoli (Impulsi a t=0 e t=15)
            if i = 0 then
                x_sig <= std_logic_vector(to_signed(1, 32));
            elsif i = 15 then
                x_sig <= std_logic_vector(to_signed(2, 32));
            else
                x_sig <= std_logic_vector(to_signed(0, 32));
            end if;

            -- B. Avvio della transazione hardware
            wait until rising_edge(clk_sig);
            start_sig <= '1';

            -- Attesa che l'IP accetti il dato in ingresso
            wait until rising_edge(clk_sig) and ready_sig = '1';
            start_sig <= '0';

            -- C. Attesa del completamento dell'elaborazione (Convoluzione terminata)
            wait until rising_edge(clk_sig) and done_sig = '1';

            -- D. Verifica del dato in uscita rispetto al Golden Model
            -- Campioniamo il segnale solo se la porta dati è valida
            if y_vld_sig = '1' then
                hw_result := to_integer(signed(y_sig));

                if hw_result = EXPECTED_Y(i) then
                    report "Ciclo " & integer'image(i) &
                           " | Input: " & integer'image(to_integer(signed(x_sig))) &
                           " | Out: " & integer'image(hw_result) &
                           " -> PASS";
                else
                    report "Ciclo " & integer'image(i) & " -> FAIL! " &
                           "Atteso: " & integer'image(EXPECTED_Y(i)) &
                           " Ottenuto: " & integer'image(hw_result) severity error;
                end if;
            else
                report "Errore protocollo: ap_done asserito ma y_ap_vld e' basso" severity warning;
            end if;

        end loop;

        report "=========================================================";
        report " SIMULAZIONE COMPLETATA CON SUCCESSO";
        report "=========================================================";

        -- Arresta il clock per chiudere pulitamente la simulazione
        sim_done <= true;
        wait;

    end process;

end architecture behavioral;
