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

    -- IF signals===================================================================
    signal seqAddr, nextInst, PC : word;
    signal flushInst             : std_logic;

    -- IF/ID pipeline registers=====================================================
    signal IF_ID_PC, IF_ID_inst : word;

    -- ID signals===================================================================
	-- Register File
    signal rs1, rs2, rd     : std_logic_vector(4 downto 0);
    signal rs1Read, rs2Read : word;
    signal rs1_d, rs2_d     : word;

	-- immediate gen
    signal immediate : word;

	-- ID Forwarding Unit
    signal ID_forwardA, ID_forwardB : std_logic;

	-- Branch Detection
    signal taken     : std_logic;
    signal takenAddr : word;

	-- CSR signals
	signal csrAddr : std_logic_vector(11 downto 0);
    signal csrData, maskedCSR, csrWriteData, MTVEC : word;

	-- bubble EX
    signal stall, bubble : std_logic;

    -- Control ID
    signal illegalInst            : std_logic;
    signal format                 : std_logic_vector(2 downto 0);
    signal controlType            : std_logic_vector(1 downto 0);
    signal branchOp               : std_logic_vector(2 downto 0);
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
    signal MEPC, MCAUSE                         : word;
    signal exception, flushIF, flushID, flushEX : std_logic;

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



end architecture Core_ARCH;
