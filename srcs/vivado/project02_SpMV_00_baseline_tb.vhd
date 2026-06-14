library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spmv_tb is
-- Nessuna porta esterna per il testbench
end entity spmv_tb;

architecture behavioral of spmv_tb is

    -- 1. Dichiarazione del componente (Deve corrispondere al nome generato da Vivado HLS)
    -- Vengono generate le porte per interfacciamento ap_memory per ogni array
    component spmv_0 is
        port (
            ap_clk : in std_logic;
            ap_rst : in std_logic;
            ap_start : in std_logic;
            ap_done : out std_logic;
            ap_idle : out std_logic;
            ap_ready : out std_logic;

            -- Interfaccia Memoria: values (dim 512, MTX_BIT=8) -> 9 bit address
            values_address0 : out std_logic_vector(8 downto 0);
            values_ce0      : out std_logic;
            values_q0       : in  std_logic_vector(7 downto 0);

            -- Interfaccia Memoria: x (dim 128, VEC_BIT=10) -> 7 bit address
            x_address0      : out std_logic_vector(6 downto 0);
            x_ce0           : out std_logic;
            x_q0            : in  std_logic_vector(9 downto 0);

            -- Interfaccia Memoria: col_idx (dim 512, int=32) -> 9 bit address
            col_idx_address0: out std_logic_vector(8 downto 0);
            col_idx_ce0     : out std_logic;
            col_idx_q0      : in  std_logic_vector(31 downto 0);

            -- Interfaccia Memoria: row_ptr (dim 129, int=32) -> Dual Port
            row_ptr_address0: out std_logic_vector(7 downto 0);
            row_ptr_ce0     : out std_logic;
            row_ptr_q0      : in  std_logic_vector(31 downto 0);

            row_ptr_address1: out std_logic_vector(7 downto 0);
            row_ptr_ce1     : out std_logic;
            row_ptr_q1      : in  std_logic_vector(31 downto 0);

            -- Interfaccia Memoria: y (dim 128, OUT_BIT=32) -> 7 bit address
            y_address0      : out std_logic_vector(6 downto 0);
            y_ce0           : out std_logic;
            y_we0           : out std_logic;
            y_d0            : out std_logic_vector(31 downto 0)
        );
    end component spmv_0;

    -- 2. Definizione dei parametri di simulazione
    constant CLK_PERIOD : time := 10 ns;

    -- Dimensioni
    constant NROWS : integer := 128;
    constant NCOLS : integer := 128;
    constant NNZ   : integer := 512;

    -- Segnali di controllo generali
    signal clk_sig   : std_logic := '0';
    signal rst_sig   : std_logic := '1';
    signal start_sig : std_logic := '0';
    signal done_sig  : std_logic;
    signal idle_sig  : std_logic;
    signal ready_sig : std_logic;

    -- Segnali memorie
    signal values_addr_sig : std_logic_vector(8 downto 0);
    signal values_ce_sig   : std_logic;
    signal values_q_sig    : std_logic_vector(7 downto 0) := (others => '0');

    signal x_addr_sig : std_logic_vector(6 downto 0);
    signal x_ce_sig   : std_logic;
    signal x_q_sig    : std_logic_vector(9 downto 0) := (others => '0');

    signal col_idx_addr_sig : std_logic_vector(8 downto 0);
    signal col_idx_ce_sig   : std_logic;
    signal col_idx_q_sig    : std_logic_vector(31 downto 0) := (others => '0');

    signal row_ptr_addr_sig  : std_logic_vector(7 downto 0);
    signal row_ptr_ce_sig    : std_logic;
    signal row_ptr_q_sig     : std_logic_vector(31 downto 0) := (others => '0');

    signal row_ptr_addr1_sig : std_logic_vector(7 downto 0);
    signal row_ptr_ce1_sig   : std_logic;
    signal row_ptr_q1_sig    : std_logic_vector(31 downto 0) := (others => '0');

    signal y_addr_sig : std_logic_vector(6 downto 0);
    signal y_ce_sig   : std_logic;
    signal y_we_sig   : std_logic;
    signal y_d_sig    : std_logic_vector(31 downto 0);

    signal sim_done : boolean := false;

    -- Tipi per memorie ROM interne
    type mem_values_t  is array (0 to NNZ-1) of std_logic_vector(7 downto 0);
    type mem_x_t       is array (0 to NCOLS-1) of std_logic_vector(9 downto 0);
    type mem_int_nnz_t is array (0 to NNZ-1) of std_logic_vector(31 downto 0);
    type mem_int_nr_t  is array (0 to NROWS) of std_logic_vector(31 downto 0);

    -- Memorie ROM (Dovranno essere popolate in modo analogo alla generazione C++)
    -- I valori qui sono indicativi o da popolare tramite file/script di test se necessario,
    -- in questo esempio le pre-inizializziamo a zero per semplicità strutturale.
    signal rom_values  : mem_values_t := (others => (others => '0'));
    signal rom_x       : mem_x_t := (others => (others => '0'));
    signal rom_col_idx : mem_int_nnz_t := (others => (others => '0'));
    signal rom_row_ptr : mem_int_nr_t := (others => (others => '0'));

begin

    -- Istanziazione dell'Unità Under Test (UUT)
    -- NOTA: La label 'uut_inst' è richiesta dallo script Tcl per generare il file SAIF
    uut_inst: spmv_0
        port map (
            ap_clk   => clk_sig,
            ap_rst   => rst_sig,
            ap_start => start_sig,
            ap_done  => done_sig,
            ap_idle  => idle_sig,
            ap_ready => ready_sig,

            values_address0  => values_addr_sig,
            values_ce0       => values_ce_sig,
            values_q0        => values_q_sig,

            x_address0       => x_addr_sig,
            x_ce0            => x_ce_sig,
            x_q0             => x_q_sig,

            col_idx_address0 => col_idx_addr_sig,
            col_idx_ce0      => col_idx_ce_sig,
            col_idx_q0       => col_idx_q_sig,

            row_ptr_address0 => row_ptr_addr_sig,
            row_ptr_ce0      => row_ptr_ce_sig,
            row_ptr_q0       => row_ptr_q_sig,

            row_ptr_address1 => row_ptr_addr1_sig,
            row_ptr_ce1      => row_ptr_ce1_sig,
            row_ptr_q1       => row_ptr_q1_sig,

            y_address0       => y_addr_sig,
            y_ce0            => y_ce_sig,
            y_we0            => y_we_sig,
            y_d0             => y_d_sig
        );

    -- 4. Generazione del Clock
    clk_process : process
    begin
        while not sim_done loop
            clk_sig <= '0';
            wait for CLK_PERIOD / 2;
            clk_sig <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_process;

    -- 5. Processi per le memorie in lettura (ROM emulate)
    rom_values_proc : process(clk_sig)
    begin
        if rising_edge(clk_sig) then
            if values_ce_sig = '1' then
                values_q_sig <= rom_values(to_integer(unsigned(values_addr_sig)));
            end if;
        end if;
    end process;

    rom_x_proc : process(clk_sig)
    begin
        if rising_edge(clk_sig) then
            if x_ce_sig = '1' then
                x_q_sig <= rom_x(to_integer(unsigned(x_addr_sig)));
            end if;
        end if;
    end process;

    rom_col_idx_proc : process(clk_sig)
    begin
        if rising_edge(clk_sig) then
            if col_idx_ce_sig = '1' then
                col_idx_q_sig <= rom_col_idx(to_integer(unsigned(col_idx_addr_sig)));
            end if;
        end if;
    end process;

    rom_row_ptr_proc : process(clk_sig)
    begin
        if rising_edge(clk_sig) then
            -- Read port 0
            if row_ptr_ce_sig = '1' then
                row_ptr_q_sig <= rom_row_ptr(to_integer(unsigned(row_ptr_addr_sig)));
            end if;
            -- Read port 1
            if row_ptr_ce1_sig = '1' then
                row_ptr_q1_sig <= rom_row_ptr(to_integer(unsigned(row_ptr_addr1_sig)));
            end if;
        end if;
    end process;

    -- 6. Processo di stimolo e controllo
    stimulus_process : process
    begin
        -- Applicazione del reset
        rst_sig <= '1';
        start_sig <= '0';
        wait for CLK_PERIOD * 5;

        -- Rilascio del reset in corrispondenza del fronte di discesa
        wait until falling_edge(clk_sig);
        rst_sig <= '0';
        wait for CLK_PERIOD * 2;

        -- Start dell'elaborazione (Handshake ap_ctrl_hs)
        wait until falling_edge(clk_sig);
        start_sig <= '1';
        wait until falling_edge(clk_sig);
        start_sig <= '0';

        -- Attesa del completamento del modulo
        wait until done_sig = '1';

        -- Termine della simulazione
        wait for CLK_PERIOD * 10;
        sim_done <= true;

        -- Verifica automatica in console (Opzionale nel Tcl/GUI)
        report "SpMV elaborazione conclusa. Simulazione VHDL terminata." severity note;

        wait;
    end process stimulus_process;

end architecture behavioral;
