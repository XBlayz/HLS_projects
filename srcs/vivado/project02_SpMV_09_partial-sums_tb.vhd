library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spmv_tb is
-- Nessuna porta esterna per il testbench
end entity spmv_tb;

architecture behavioral of spmv_tb is

    -- 1. Dichiarazione del componente
    component spmv_0 is
        port (
            ap_clk : in std_logic;
            ap_rst : in std_logic;
            ap_start : in std_logic;
            ap_done : out std_logic;
            ap_idle : out std_logic;
            ap_ready : out std_logic;

            -- Interfaccia Memoria: values (Partizionata in 2 BRAM, entrambe Dual-Port)
            values_0_address0 : out std_logic_vector(7 downto 0);
            values_0_ce0      : out std_logic;
            values_0_q0       : in  std_logic_vector(7 downto 0);
            values_0_address1 : out std_logic_vector(7 downto 0);
            values_0_ce1      : out std_logic;
            values_0_q1       : in  std_logic_vector(7 downto 0);

            values_1_address0 : out std_logic_vector(7 downto 0);
            values_1_ce0      : out std_logic;
            values_1_q0       : in  std_logic_vector(7 downto 0);
            values_1_address1 : out std_logic_vector(7 downto 0);
            values_1_ce1      : out std_logic;
            values_1_q1       : in  std_logic_vector(7 downto 0);

            -- Interfaccia Memoria: col_idx (Partizionata in 2 BRAM, entrambe Dual-Port)
            col_idx_0_address0: out std_logic_vector(7 downto 0);
            col_idx_0_ce0     : out std_logic;
            col_idx_0_q0      : in  std_logic_vector(31 downto 0);
            col_idx_0_address1: out std_logic_vector(7 downto 0);
            col_idx_0_ce1     : out std_logic;
            col_idx_0_q1      : in  std_logic_vector(31 downto 0);

            col_idx_1_address0: out std_logic_vector(7 downto 0);
            col_idx_1_ce0     : out std_logic;
            col_idx_1_q0      : in  std_logic_vector(31 downto 0);
            col_idx_1_address1: out std_logic_vector(7 downto 0);
            col_idx_1_ce1     : out std_logic;
            col_idx_1_q1      : in  std_logic_vector(31 downto 0);

            -- Interfaccia Array X (Completamente partizionato -> 128 porte in ingresso scalari ap_none)
            x_0, x_1, x_2, x_3, x_4, x_5, x_6, x_7,
            x_8, x_9, x_10, x_11, x_12, x_13, x_14, x_15,
            x_16, x_17, x_18, x_19, x_20, x_21, x_22, x_23,
            x_24, x_25, x_26, x_27, x_28, x_29, x_30, x_31,
            x_32, x_33, x_34, x_35, x_36, x_37, x_38, x_39,
            x_40, x_41, x_42, x_43, x_44, x_45, x_46, x_47,
            x_48, x_49, x_50, x_51, x_52, x_53, x_54, x_55,
            x_56, x_57, x_58, x_59, x_60, x_61, x_62, x_63,
            x_64, x_65, x_66, x_67, x_68, x_69, x_70, x_71,
            x_72, x_73, x_74, x_75, x_76, x_77, x_78, x_79,
            x_80, x_81, x_82, x_83, x_84, x_85, x_86, x_87,
            x_88, x_89, x_90, x_91, x_92, x_93, x_94, x_95,
            x_96, x_97, x_98, x_99, x_100, x_101, x_102, x_103,
            x_104, x_105, x_106, x_107, x_108, x_109, x_110, x_111,
            x_112, x_113, x_114, x_115, x_116, x_117, x_118, x_119,
            x_120, x_121, x_122, x_123, x_124, x_125, x_126, x_127 : in std_logic_vector(9 downto 0);

            -- Interfaccia Memoria: row_ptr (Dual-Port nativa)
            row_ptr_address0: out std_logic_vector(7 downto 0);
            row_ptr_ce0     : out std_logic;
            row_ptr_q0      : in  std_logic_vector(31 downto 0);
            row_ptr_address1: out std_logic_vector(7 downto 0);
            row_ptr_ce1     : out std_logic;
            row_ptr_q1      : in  std_logic_vector(31 downto 0);

            -- Interfaccia Memoria: y (Single-Port Write)
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

    -- Segnali array partizionato: values_0 (Dual-Port)
    signal values_0_addr_sig  : std_logic_vector(7 downto 0);
    signal values_0_ce_sig    : std_logic;
    signal values_0_q_sig     : std_logic_vector(7 downto 0) := (others => '0');
    signal values_0_addr1_sig : std_logic_vector(7 downto 0);
    signal values_0_ce1_sig   : std_logic;
    signal values_0_q1_sig    : std_logic_vector(7 downto 0) := (others => '0');

    -- Segnali array partizionato: values_1 (Dual-Port)
    signal values_1_addr_sig  : std_logic_vector(7 downto 0);
    signal values_1_ce_sig    : std_logic;
    signal values_1_q_sig     : std_logic_vector(7 downto 0) := (others => '0');
    signal values_1_addr1_sig : std_logic_vector(7 downto 0);
    signal values_1_ce1_sig   : std_logic;
    signal values_1_q1_sig    : std_logic_vector(7 downto 0) := (others => '0');

    -- Segnali array partizionato: col_idx_0 (Dual-Port)
    signal col_idx_0_addr_sig  : std_logic_vector(7 downto 0);
    signal col_idx_0_ce_sig    : std_logic;
    signal col_idx_0_q_sig     : std_logic_vector(31 downto 0) := (others => '0');
    signal col_idx_0_addr1_sig : std_logic_vector(7 downto 0);
    signal col_idx_0_ce1_sig   : std_logic;
    signal col_idx_0_q1_sig    : std_logic_vector(31 downto 0) := (others => '0');

    -- Segnali array partizionato: col_idx_1 (Dual-Port)
    signal col_idx_1_addr_sig  : std_logic_vector(7 downto 0);
    signal col_idx_1_ce_sig    : std_logic;
    signal col_idx_1_q_sig     : std_logic_vector(31 downto 0) := (others => '0');
    signal col_idx_1_addr1_sig : std_logic_vector(7 downto 0);
    signal col_idx_1_ce1_sig   : std_logic;
    signal col_idx_1_q1_sig    : std_logic_vector(31 downto 0) := (others => '0');

    -- Segnali array row_ptr (Dual-Port)
    signal row_ptr_addr_sig  : std_logic_vector(7 downto 0);
    signal row_ptr_ce_sig    : std_logic;
    signal row_ptr_q_sig     : std_logic_vector(31 downto 0) := (others => '0');
    signal row_ptr_addr1_sig : std_logic_vector(7 downto 0);
    signal row_ptr_ce1_sig   : std_logic;
    signal row_ptr_q1_sig    : std_logic_vector(31 downto 0) := (others => '0');

    -- Segnali per scrittura output Y
    signal y_addr_sig : std_logic_vector(6 downto 0);
    signal y_ce_sig   : std_logic;
    signal y_we_sig   : std_logic;
    signal y_d_sig    : std_logic_vector(31 downto 0);

    signal sim_done : boolean := false;

    -- Tipi per memorie interne
    type mem_values_t  is array (0 to NNZ-1) of std_logic_vector(7 downto 0);
    type mem_x_t       is array (0 to NCOLS-1) of std_logic_vector(9 downto 0);
    type mem_int_nnz_t is array (0 to NNZ-1) of std_logic_vector(31 downto 0);
    type mem_int_nr_t  is array (0 to NROWS) of std_logic_vector(31 downto 0);

    -- Memorie Emulate / Costanti
    signal rom_values  : mem_values_t := (others => (others => '0'));
    signal rom_x       : mem_x_t := (others => (others => '0'));
    signal rom_col_idx : mem_int_nnz_t := (others => (others => '0'));
    signal rom_row_ptr : mem_int_nr_t := (others => (others => '0'));

begin

    -- 3. Istanziazione dell'Unità Under Test (UUT)
    uut_inst: spmv_0
        port map (
            ap_clk   => clk_sig,
            ap_rst   => rst_sig,
            ap_start => start_sig,
            ap_done  => done_sig,
            ap_idle  => idle_sig,
            ap_ready => ready_sig,

            -- Mapping values_0
            values_0_address0 => values_0_addr_sig,
            values_0_ce0      => values_0_ce_sig,
            values_0_q0       => values_0_q_sig,
            values_0_address1 => values_0_addr1_sig,
            values_0_ce1      => values_0_ce1_sig,
            values_0_q1       => values_0_q1_sig,

            -- Mapping values_1
            values_1_address0 => values_1_addr_sig,
            values_1_ce0      => values_1_ce_sig,
            values_1_q0       => values_1_q_sig,
            values_1_address1 => values_1_addr1_sig,
            values_1_ce1      => values_1_ce1_sig,
            values_1_q1       => values_1_q1_sig,

            -- Mapping col_idx_0
            col_idx_0_address0 => col_idx_0_addr_sig,
            col_idx_0_ce0      => col_idx_0_ce_sig,
            col_idx_0_q0       => col_idx_0_q_sig,
            col_idx_0_address1 => col_idx_0_addr1_sig,
            col_idx_0_ce1      => col_idx_0_ce1_sig,
            col_idx_0_q1       => col_idx_0_q1_sig,

            -- Mapping col_idx_1
            col_idx_1_address0 => col_idx_1_addr_sig,
            col_idx_1_ce0      => col_idx_1_ce_sig,
            col_idx_1_q0       => col_idx_1_q_sig,
            col_idx_1_address1 => col_idx_1_addr1_sig,
            col_idx_1_ce1      => col_idx_1_ce1_sig,
            col_idx_1_q1       => col_idx_1_q1_sig,

            -- Mapping completamente partizionato x
            x_0 => rom_x(0), x_1 => rom_x(1), x_2 => rom_x(2), x_3 => rom_x(3),
            x_4 => rom_x(4), x_5 => rom_x(5), x_6 => rom_x(6), x_7 => rom_x(7),
            x_8 => rom_x(8), x_9 => rom_x(9), x_10 => rom_x(10), x_11 => rom_x(11),
            x_12 => rom_x(12), x_13 => rom_x(13), x_14 => rom_x(14), x_15 => rom_x(15),
            x_16 => rom_x(16), x_17 => rom_x(17), x_18 => rom_x(18), x_19 => rom_x(19),
            x_20 => rom_x(20), x_21 => rom_x(21), x_22 => rom_x(22), x_23 => rom_x(23),
            x_24 => rom_x(24), x_25 => rom_x(25), x_26 => rom_x(26), x_27 => rom_x(27),
            x_28 => rom_x(28), x_29 => rom_x(29), x_30 => rom_x(30), x_31 => rom_x(31),
            x_32 => rom_x(32), x_33 => rom_x(33), x_34 => rom_x(34), x_35 => rom_x(35),
            x_36 => rom_x(36), x_37 => rom_x(37), x_38 => rom_x(38), x_39 => rom_x(39),
            x_40 => rom_x(40), x_41 => rom_x(41), x_42 => rom_x(42), x_43 => rom_x(43),
            x_44 => rom_x(44), x_45 => rom_x(45), x_46 => rom_x(46), x_47 => rom_x(47),
            x_48 => rom_x(48), x_49 => rom_x(49), x_50 => rom_x(50), x_51 => rom_x(51),
            x_52 => rom_x(52), x_53 => rom_x(53), x_54 => rom_x(54), x_55 => rom_x(55),
            x_56 => rom_x(56), x_57 => rom_x(57), x_58 => rom_x(58), x_59 => rom_x(59),
            x_60 => rom_x(60), x_61 => rom_x(61), x_62 => rom_x(62), x_63 => rom_x(63),
            x_64 => rom_x(64), x_65 => rom_x(65), x_66 => rom_x(66), x_67 => rom_x(67),
            x_68 => rom_x(68), x_69 => rom_x(69), x_70 => rom_x(70), x_71 => rom_x(71),
            x_72 => rom_x(72), x_73 => rom_x(73), x_74 => rom_x(74), x_75 => rom_x(75),
            x_76 => rom_x(76), x_77 => rom_x(77), x_78 => rom_x(78), x_79 => rom_x(79),
            x_80 => rom_x(80), x_81 => rom_x(81), x_82 => rom_x(82), x_83 => rom_x(83),
            x_84 => rom_x(84), x_85 => rom_x(85), x_86 => rom_x(86), x_87 => rom_x(87),
            x_88 => rom_x(88), x_89 => rom_x(89), x_90 => rom_x(90), x_91 => rom_x(91),
            x_92 => rom_x(92), x_93 => rom_x(93), x_94 => rom_x(94), x_95 => rom_x(95),
            x_96 => rom_x(96), x_97 => rom_x(97), x_98 => rom_x(98), x_99 => rom_x(99),
            x_100 => rom_x(100), x_101 => rom_x(101), x_102 => rom_x(102), x_103 => rom_x(103),
            x_104 => rom_x(104), x_105 => rom_x(105), x_106 => rom_x(106), x_107 => rom_x(107),
            x_108 => rom_x(108), x_109 => rom_x(109), x_110 => rom_x(110), x_111 => rom_x(111),
            x_112 => rom_x(112), x_113 => rom_x(113), x_114 => rom_x(114), x_115 => rom_x(115),
            x_116 => rom_x(116), x_117 => rom_x(117), x_118 => rom_x(118), x_119 => rom_x(119),
            x_120 => rom_x(120), x_121 => rom_x(121), x_122 => rom_x(122), x_123 => rom_x(123),
            x_124 => rom_x(124), x_125 => rom_x(125), x_126 => rom_x(126), x_127 => rom_x(127),

            -- Mapping row_ptr
            row_ptr_address0 => row_ptr_addr_sig,
            row_ptr_ce0      => row_ptr_ce_sig,
            row_ptr_q0       => row_ptr_q_sig,
            row_ptr_address1 => row_ptr_addr1_sig,
            row_ptr_ce1      => row_ptr_ce1_sig,
            row_ptr_q1       => row_ptr_q1_sig,

            -- Mapping y
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

    -- 5. Processi per le memorie in lettura (Dual-Port)

    -- Processo per VALUES (BRAM 0 e BRAM 1, entrambe Dual-Port)
    rom_values_proc : process(clk_sig)
    begin
        if rising_edge(clk_sig) then
            -- BRAM 0 (indici pari)
            if values_0_ce_sig = '1' then
                values_0_q_sig <= rom_values(to_integer(unsigned(values_0_addr_sig)) * 2);
            end if;
            if values_0_ce1_sig = '1' then
                values_0_q1_sig <= rom_values(to_integer(unsigned(values_0_addr1_sig)) * 2);
            end if;

            -- BRAM 1 (indici dispari)
            if values_1_ce_sig = '1' then
                values_1_q_sig <= rom_values(to_integer(unsigned(values_1_addr_sig)) * 2 + 1);
            end if;
            if values_1_ce1_sig = '1' then
                values_1_q1_sig <= rom_values(to_integer(unsigned(values_1_addr1_sig)) * 2 + 1);
            end if;
        end if;
    end process;

    -- Processo per COL_IDX (BRAM 0 e BRAM 1, entrambe Dual-Port)
    rom_col_idx_proc : process(clk_sig)
    begin
        if rising_edge(clk_sig) then
            -- BRAM 0 (indici pari)
            if col_idx_0_ce_sig = '1' then
                col_idx_0_q_sig <= rom_col_idx(to_integer(unsigned(col_idx_0_addr_sig)) * 2);
            end if;
            if col_idx_0_ce1_sig = '1' then
                col_idx_0_q1_sig <= rom_col_idx(to_integer(unsigned(col_idx_0_addr1_sig)) * 2);
            end if;

            -- BRAM 1 (indici dispari)
            if col_idx_1_ce_sig = '1' then
                col_idx_1_q_sig <= rom_col_idx(to_integer(unsigned(col_idx_1_addr_sig)) * 2 + 1);
            end if;
            if col_idx_1_ce1_sig = '1' then
                col_idx_1_q1_sig <= rom_col_idx(to_integer(unsigned(col_idx_1_addr1_sig)) * 2 + 1);
            end if;
        end if;
    end process;

    -- Processo per ROW_PTR (Dual-Port nativa)
    rom_row_ptr_proc : process(clk_sig)
    begin
        if rising_edge(clk_sig) then
            if row_ptr_ce_sig = '1' then
                row_ptr_q_sig <= rom_row_ptr(to_integer(unsigned(row_ptr_addr_sig)));
            end if;
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

        -- Rilascio del reset
        wait until falling_edge(clk_sig);
        rst_sig <= '0';
        wait for CLK_PERIOD * 2;

        -- Start dell'elaborazione
        wait until falling_edge(clk_sig);
        start_sig <= '1';
        wait until falling_edge(clk_sig);
        start_sig <= '0';

        -- Attesa del completamento del modulo
        wait until done_sig = '1';

        -- Termine della simulazione
        wait for CLK_PERIOD * 10;
        sim_done <= true;

        report "SpMV (Manual Unroll, Partizionamento Ciclico e Completo) elaborazione conclusa. Simulazione terminata." severity note;

        wait;
    end process stimulus_process;

end architecture behavioral;
