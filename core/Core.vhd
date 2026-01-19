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

begin  -- architecture Core_ARCH



end architecture Core_ARCH;
