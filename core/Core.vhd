library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Core is
    port (
        reset : in std_logic;
        clock : in std_logic;

        instAddr : out std_logic_vector(31 downto 0);
        inst     : in  std_logic_vector(31 downto 0);

        memEn     : out std_logic;
        writeEn   : out std_logic;
        byteEn    : out std_logic_vector(3 downto 0);
        dataAddr  : out std_logic_vector(31 downto 0);
        dataWrite : out std_logic_vector(31 downto 0);
        dataRead  : in  std_logic_vector(31 downto 0));
end entity Core;

architecture Core_ARCH of Core is

    -- general======================================================================
    constant XLEN : integer := 32;
    subtype word is std_logic_vector(31 downto 0);

    type reg_file_t is array (0 to 31) of word;

    type instr_format_t is record
        r_type : std_logic_vector(2 downto 0);
        i_type : std_logic_vector(2 downto 0);
        s_type : std_logic_vector(2 downto 0);
        b_type : std_logic_vector(2 downto 0);
        u_type : std_logic_vector(2 downto 0);
        j_type : std_logic_vector(2 downto 0);
    end record instr_format_t;
    constant INSTR_FORMAT : instr_format_t := (
                                              r_type => "000",
                                              i_type => "001",
                                              s_type => "010",
                                              b_type => "011",
                                              u_type => "100",
                                              j_type => "101");

    constant CONTROL_NOT_CONTROL : std_logic_vector(1 downto 0) := "00";
    constant CONTROL_BRANCH      : std_logic_vector(1 downto 0) := "01";
    constant CONTROL_JAL         : std_logic_vector(1 downto 0) := "10";
    constant CONTROL_JALR        : std_logic_vector(1 downto 0) := "11";

    constant CSR_MTVEC_ADDR  : std_logic_vector(11 downto 0) := x"305";
    constant CSR_MEPC_ADDR   : std_logic_vector(11 downto 0) := x"341";
    constant CSR_MCAUSE_ADDR : std_logic_vector(11 downto 0) := x"342";
    constant CSR_CYCLE_ADDR  : std_logic_vector(11 downto 0) := x"C00";

    -- IF signals===================================================================
    signal seqAddr, nextInst, PC : word;

    -- IF/ID pipeline registers=====================================================
    signal IF_ID_PC, IF_ID_inst : word;

    -- ID signals===================================================================
    -- Decode instruction
    signal rs1, rs2, rd : std_logic_vector(4 downto 0);
    signal funct3       : std_logic_vector(2 downto 0);

    -- Register File
    signal rs1Read, rs2Read : word;
    signal rs1_d, rs2_d     : word;

    -- immediate gen
    signal immediate : word;

    -- ID Forwarding Unit
    signal ID_forwardB : std_logic;

    -- Branch Detection
    signal taken     : std_logic;
    signal takenAddr : word;

    -- CSR signals
    signal csrAddr                                 : std_logic_vector(11 downto 0);
    signal csrData, maskedCSR, csrWriteData, MTVEC : word;

    -- bubble EX
    signal stall, bubble : std_logic;

    -- Control ID
    signal illegalInst            : std_logic;
    signal format                 : std_logic_vector(2 downto 0);
    signal controlType            : std_logic_vector(1 downto 0);
    signal csrInst, csrWriteOrSet : std_logic;

    -- Control EX
    signal ALUSrc1, ALUSrc2 : std_logic_vector(1 downto 0);
    signal ALUOp            : std_logic_vector(3 downto 0);  -- total of 10 ops

    -- Control MEM
    signal memEn_s, writeEn_s, sign : std_logic;
    signal byteEn_s                 : std_logic_vector(3 downto 0);

    -- Control WB
    signal memToReg, regWrite : std_logic;

    -- ID/EX pipeline registers=====================================================
    signal ID_EX_PC, ID_EX_immediate : word;
    signal ID_EX_rs1_d, ID_EX_rs2_d  : word;
    signal ID_EX_rd                  : std_logic_vector(4 downto 0);

    -- Control EX
    signal ID_EX_ALUSrc1, ID_EX_ALUSrc2 : std_logic_vector(1 downto 0);
    signal ID_EX_ALUOp                  : std_logic_vector(3 downto 0);

    -- Control MEM
    signal ID_EX_memEn_s, ID_EX_writeEn_s, ID_EX_sign : std_logic;
    signal ID_EX_byteEn_s                             : std_logic_vector(3 downto 0);

    -- Control WB
    signal ID_EX_memToReg, ID_EX_regWrite : std_logic;

    -- Exception Detection=========================================================
    signal MEPC, MCAUSE                : word;
    signal exception, flushID, flushEX : std_logic;

    -- EX signals===================================================================
    -- EX Forwarding Unit
    signal EX_forwardA, EX_forwardB : std_logic_vector(1 downto 0);

    -- ALU Operation
    signal ALUArg1, ALUArg2, ALUResult : word;

    -- EX/MEM pipeline registers====================================================
    signal EX_MEM_ALUArg2, EX_MEM_ALUResult : word;
    signal EX_MEM_rd                        : std_logic_vector(4 downto 0);

    -- Control MEM
    signal EX_MEM_memEn_s, EX_MEM_writeEn_s, EX_MEM_sign : std_logic;
    signal EX_MEM_byteEn_s                               : std_logic_vector(3 downto 0);

    -- Control WB
    signal EX_MEM_memToReg, EX_MEM_regWrite : std_logic;

    -- MEM signals==================================================================
    signal extDataRead : word;

    -- MEM/WB pipeline registers====================================================
    signal MEM_WB_ALUResult, MEM_WB_extDataRead : word;
    signal MEM_WB_rd                            : std_logic_vector(4 downto 0);

    -- Control WB
    signal MEM_WB_memToReg, MEM_WB_regWrite : std_logic;

    -- WB signals===================================================================
    signal regWriteData : word;

begin  -- architecture Core_ARCH

    -- IF stage=====================================================================

    -- purpose: Chooses what the next value for the PC is from MTVEC(if
    -- exception), takenAddr(if branch taken), or seqAddr.
    -- type   : combinational
    -- inputs : all
    -- outputs: nextInst
    NEXT_INST_MUX : process (all) is
    begin  -- process NEXT_INST_MUX
        if exception = '1' then
            nextInst <= MTVEC;
        elsif taken = '1' then
            nextInst <= takenAddr;
        else
            nextInst <= seqAddr;
        end if;
    end process NEXT_INST_MUX;

    -- purpose: Program Counter.
    -- type   : sequential
    -- inputs : clock, reset, nextInst, stall
    -- outputs: PC
    PC_32 : process (clock, reset) is
    begin  -- process PC
        if reset = '1' then
            PC <= (others => '0');
        elsif clock'event and clock = '1' then  -- rising clock edge
            if stall = '1' then
                PC <= PC;
            else
                PC <= nextInst;
            end if;
        end if;
    end process PC_32;

    -- Fetch instruction memory with PC
    instAddr <= PC;

    -- Calculate the sequential instruction address
    seqAddr <= std_logic_vector(unsigned(PC) + TO_UNSIGNED(4, XLEN));

    -- purpose: IF/ID pipeline register. It passes PC and inst from IF to ID. It can also be flushed or stalled in exception/branch or hazard situations.
    -- type   : sequential
    -- inputs : clock, reset, PC, inst, taken, exception
    IF_ID : process (clock, reset) is
    begin  -- process IF_ID
        if reset = '1' then
            IF_ID_PC   <= (others => '0');
            IF_ID_inst <= (others => '0');
        elsif clock'event and clock = '1' then  -- rising clock edge
            if (exception = '1') or (taken = '1') then
                IF_ID_PC   <= (others => '0');
                IF_ID_inst <= x"00000013";  	-- NOP: addi x0, x0, 0
            elsif stall = '1' then
                IF_ID_PC   <= IF_ID_PC;
                IF_ID_inst <= IF_ID_inst;
            else
                IF_ID_PC   <= PC;
                IF_ID_inst <= inst;
            end if;
        end if;
    end process IF_ID;

    -- ID stage=====================================================================

    -- decode instruction
    rd      <= inst(11 downto 7);
    rs1     <= inst(19 downto 15);
    rs2     <= inst(24 downto 20);
    funct3  <= inst(14 downto 12);
    csrAddr <= inst(31 downto 20);

    -- purpose: Asynchronous read with Synchronous write on falling edge.
    -- type   : sequential
    -- inputs : clock, reset, rs1, rs2, rd, regWrite, regWriteData
    -- outputs: rs1Read, rs2Read
    REGISTER_FILE : process (clock, reset, rs1, rs2, rd, regWrite, regWriteData) is
        variable regFile : reg_file_t := (others => (others => '0'));
    begin  -- process REGISTER_FILE
        if reset = '1' then
            regFile := (others => (others => '0'));
        elsif clock'event and clock = '0' then  -- falling clock edge
            if (regWrite = '1') and (rd /= "00000") then
                regFile(to_integer(unsigned(rd))) := regWriteData;
            end if;
        end if;

        if rs1 = "00000" then
            rs1Read <= (others => '0');
        else
            rs1Read <= regFile(to_integer(unsigned(rs1)));
        end if;

        if rs2 = "00000" then
            rs2Read <= (others => '0');
        else
            rs2Read <= regFile(to_integer(unsigned(rs2)));
        end if;
    end process REGISTER_FILE;

    -- purpose: Generate immediate based on instruction format.
    -- type   : combinational
    -- inputs : all
    -- outputs: immediate
    IMM_GEN : process (all) is
    begin  -- process IMM_GEN
        if format = INSTR_FORMAT.r_type then
            immediate <= (others => '0');
        elsif format = INSTR_FORMAT.i_type then
            immediate <= (31 downto 12 => inst(31)) & inst(31 downto 20);
        elsif format = INSTR_FORMAT.s_type then
            immediate <= (31 downto 12 => inst(31)) & inst(31 downto 25) & inst(11 downto 7);
        elsif format = INSTR_FORMAT.b_type then
            immediate <= (31 downto 13 => inst(31)) & inst(31) & inst(7) &
                         inst(30 downto 25) & inst(11 downto 8) & '0';
        elsif format = INSTR_FORMAT.u_type then
            immediate <= inst(31 downto 12) & x"000";
        elsif format = INSTR_FORMAT.j_type then
            immediate <= (31 downto 21 => inst(31)) & inst(31) & inst(19 downto 12) &
                         inst(20) & inst(30 downto 21) & '0';
        else
            immediate <= (others => '0');
        end if;
    end process IMM_GEN;

    -- purpose: Forward EX/MEM ALU results to decode consumers (branch, jalr, csr).
    -- type   : combinational
    -- inputs : all
    -- outputs: ID_forwardB, rs1_d, rs2_d
    ID_FORWARDING_UNIT : process (all) is
    begin
        if (EX_MEM_regWrite = '1') and (EX_MEM_memToReg = '0') and
           (EX_MEM_rd /= "00000") and (EX_MEM_rd = rs1) then
            rs1_d <= EX_MEM_ALUResult;
        else
            rs1_d <= rs1Read;
        end if;

        if (EX_MEM_regWrite = '1') and (EX_MEM_memToReg = '0') and
           (EX_MEM_rd /= "00000") and (EX_MEM_rd = rs2) then
            ID_forwardB <= '1';
        else
            ID_forwardB <= '0';
        end if;
    end process ID_FORWARDING_UNIT;

    RS2_MUX : process (all) is
    begin  -- process RS2_MUX
        if (csrInst = '1') then
            rs2_d <= csrData;
        elsif (ID_forwardB = '1') then
            rs2_d <= EX_MEM_ALUResult;
        else
            rs2_d <= rs2Read;
        end if;
    end process RS2_MUX;

    -- feed csrWriteData with mask if set
    maskedCSR <= csrData or rs1_d;
    CSR_DATA_MUX : with csrWriteOrSet select
        csrWriteData <=
        maskedCSR when '1',
        rs1_d     when others;

    -- purpose: CSR file with async read and sync write.
    -- type   : sequential
    -- inputs : clock, reset, csrAddr, csrWriteData, csrInst, exception, MEPC, MCAUSE
    -- outputs: csrData, MTVEC
    CSR_FILE : process (clock, reset, csrAddr, csrInst, csrWriteData, exception, MEPC, MCAUSE) is
        variable csr_mtvec  : word := (others => '0');
        variable csr_mepc   : word := (others => '0');
        variable csr_mcause : word := (others => '0');
        variable csr_cycle  : word := (others => '0');
    begin
        if reset = '1' then
            csr_mtvec  := (others => '0');
            csr_mepc   := (others => '0');
            csr_mcause := (others => '0');
            csr_cycle  := (others => '0');
        elsif clock'event and clock = '1' then
            csr_cycle := std_logic_vector(unsigned(csr_cycle) + to_unsigned(1, XLEN));

            if exception = '1' then
                csr_mepc   := MEPC;
                csr_mcause := MCAUSE;
            elsif csrInst = '1' then
                case csrAddr is
                    when CSR_MTVEC_ADDR =>
                        csr_mtvec := csrWriteData;
                    when CSR_MEPC_ADDR =>
                        csr_mepc := csrWriteData;
                    when CSR_MCAUSE_ADDR =>
                        csr_mcause := csrWriteData;
                    when others =>
                        null;
                end case;
            end if;
        end if;

        case csrAddr is
            when CSR_MTVEC_ADDR =>
                csrData <= csr_mtvec;
            when CSR_MEPC_ADDR =>
                csrData <= csr_mepc;
            when CSR_MCAUSE_ADDR =>
                csrData <= csr_mcause;
            when CSR_CYCLE_ADDR =>
                csrData <= csr_cycle;
            when others =>
                csrData <= (others => '0');
        end case;

        MTVEC <= csr_mtvec;
    end process CSR_FILE;

    -- purpose: Resolve branch/jump direction in decode.
    -- type   : combinational
    -- inputs : all
    -- outputs: taken
    BRANCH_DETECTION : process (all) is
    begin
        taken <= '0';

        if stall = '0' then
            if controlType = CONTROL_BRANCH then
                case funct3 is
                    when "000" =>  		-- BEQ
                        if rs1_d = rs2_d then
                            taken <= '1';
                        end if;
                    when "001" =>  		-- BNE
                        if rs1_d /= rs2_d then
                            taken <= '1';
                        end if;
                    when "100" =>  		-- BLT
                        if signed(rs1_d) < signed(rs2_d) then
                            taken <= '1';
                        end if;
                    when "101" =>  		-- BGE
                        if signed(rs1_d) >= signed(rs2_d) then
                            taken <= '1';
                        end if;
                    when "110" =>  		-- BLTU
                        if unsigned(rs1_d) < unsigned(rs2_d) then
                            taken <= '1';
                        end if;
                    when "111" =>  		-- BGEU
                        if unsigned(rs1_d) >= unsigned(rs2_d) then
                            taken <= '1';
                        end if;
                    when others =>
                        taken <= '0';
                end case;
            elsif (controlType = CONTROL_JAL) or (controlType = CONTROL_JALR) then
                taken <= '1';
            end if;
        end if;
    end process BRANCH_DETECTION;

    -- purpose: Calculate branch/jump target in decode.
    -- type   : combinational
    -- inputs : all
    -- outputs: takenAddr
    ADDRESS_CALCULATION : process (all) is
        variable target : word;
    begin
        target := (others => '0');

        if controlType = CONTROL_JALR then
            -- JALR target: (rs1 + imm) with bit 0 forced to zero.
            target    := std_logic_vector(signed(rs1_d) + signed(immediate));
            target(0) := '0';
        elsif (controlType = CONTROL_JAL) or (controlType = CONTROL_BRANCH) then
            -- JAL and all B-type branches target relative to the ID PC.
            target := std_logic_vector(signed(IF_ID_PC) + signed(immediate));
        end if;

        takenAddr <= target;
    end process ADDRESS_CALCULATION;

    -- purpose: Detect hazards that require stalling fetch/decode.
    -- type   : combinational
    -- inputs : all
    -- outputs: stall
    HAZARD_UNIT : process (all) is
        variable uses_rs1, uses_rs2                     : std_logic;
        variable is_branch, is_jalr, decode_needs_fresh : std_logic;
        variable match_id_ex, match_ex_mem              : std_logic;
    begin
        uses_rs1 := '0';
        uses_rs2 := '0';

        if (format = INSTR_FORMAT.r_type) or
           (format = INSTR_FORMAT.i_type) or
           (format = INSTR_FORMAT.s_type) or
           (format = INSTR_FORMAT.b_type) then
            uses_rs1 := '1';
        end if;

        if (format = INSTR_FORMAT.r_type) or
           (format = INSTR_FORMAT.s_type) or
           (format = INSTR_FORMAT.b_type) then
            uses_rs2 := '1';
        end if;

        is_branch := '0';
        is_jalr   := '0';

        if controlType = CONTROL_BRANCH then
            is_branch := '1';
        elsif controlType = CONTROL_JALR then
            is_jalr := '1';
        end if;

        if (csrInst = '1') or (is_branch = '1') or (is_jalr = '1') then
            decode_needs_fresh := '1';
        else
            decode_needs_fresh := '0';
        end if;

        match_id_ex := '0';
        if (ID_EX_rd /= "00000") and
           (((uses_rs1 = '1') and (ID_EX_rd = rs1)) or
            ((uses_rs2 = '1') and (ID_EX_rd = rs2))) then
            match_id_ex := '1';
        end if;

        match_ex_mem := '0';
        if (EX_MEM_rd /= "00000") and
           (((uses_rs1 = '1') and (EX_MEM_rd = rs1)) or
            ((uses_rs2 = '1') and (EX_MEM_rd = rs2))) then
            match_ex_mem := '1';
        end if;

        -- load-use hazard for all instructions that actually consume the source.
        -- extra decode-stage hazard coverage for branch/jalr/csr consumers.
        if ((ID_EX_memToReg = '1') and (match_id_ex = '1')) or
           ((decode_needs_fresh = '1') and (ID_EX_regWrite = '1') and (match_id_ex = '1')) or
           ((decode_needs_fresh = '1') and (EX_MEM_memToReg = '1') and (match_ex_mem = '1')) then
            stall <= '1';
        else
            stall <= '0';
        end if;
    end process HAZARD_UNIT;

end architecture Core_ARCH;
