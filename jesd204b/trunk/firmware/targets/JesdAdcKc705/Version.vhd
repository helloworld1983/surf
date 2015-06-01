-------------------------------------------------------------------------------
-- Title         : Version Constant File
-- Project       : COB Zynq DTM
-------------------------------------------------------------------------------
-- File          : Version.vhd
-- Author        : Ryan Herbst, rherbst@slac.stanford.edu
-- Created       : 05/18/2014
-------------------------------------------------------------------------------
-- Description:
-- Version Constant Module
-------------------------------------------------------------------------------
-- Copyright (c) 2012 by SLAC. All rights reserved.
-------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;

package Version is

constant FPGA_VERSION_C : std_logic_vector(31 downto 0) := x"00000016"; -- MAKE_VERSION

constant BUILD_STAMP_C : string := "JesdAdcKc705: Vivado v2014.4 (x86_64) Built Fri May 29 15:00:07 PDT 2015 by ulegat";

end Version;
 
-------------------------------------------------------------------------------
-- Revision History:
-------------------------------------------------------------------------------
-- 05/15/2015 - 00000000      - ADC F22 61.44MHz out. 370MHz ref
-- 05/15/2015 - 00000001      - ADC F22 61.44MHz out. 184.32MHz ref 7.3728GHz
-- 05/18/2015 - 00000002      - ADC F22 61.44MHz out. 184.32MHz ref 7.3728GHz. Pol = '1'
-- 05/18/2015 - 00000003      - ADC F22 61.44MHz out. 184.32MHz ref 7.3728GHz. Pol = '1', byte swapped
-- 05/18/2015 - 00000004      - ADC F22 61.44MHz out. 184.32MHz ref 7.3728GHz. Pol = '0', byte swapped
-- 05/18/2015 - 00000005      - Chipscope test
-- 05/19/2015 - 00000006      - ADC F22 368.64MHz out. 184.32MHz ref 7.3728GHz(CS).
-- 05/19/2015 - 00000007      - ADC F22 156.25MHz out. 78.125MHz ref 3.125GHz(CS).
-- 05/19/2015 - 00000008      - (two byte word) ADC F22 156.25MHz out. 156.25MHz ref 3.125GHz(CS).
-- 05/19/2015 - 00000009      - one lane (two byte word) ADC F22 156.25MHz out. 156.25MHz ref 3.125GHz(CS).
-- 05/19/2015 - 0000000A      - dual lane - out clk reset tied to '0'
-- 05/19/2015 - 0000000B      - CPLL 2-byte
-- 05/19/2015 - 0000000C      - CPLL 2-byte - GT parameters as in PGP
-- 05/20/2015 - 0000000D      - CPLL 2-byte - FPGA refclk to ADC
-- 05/20/2015 - 0000000E      - JESD out /2
-- 05/20/2015 - 0000000F      - JESD out /2
-- 05/20/2015 - 00000010      - Recovered clock
-- 05/20/2015 - 00000011      - 2-byte - LMK reference
-- 05/20/2015 - 00000012      - 2-byte - F2 - Dual lane
-- 05/26/2015 - 00000013      - 2-byte - LMK reference - comma alignment parameters fixed
-- 05/26/2015 - 00000014      - 4-byte - LMK reference - AXIS starts on enable and trigger
-- 05/28/2015 - 00000015      - 4-byte - 7.4GHz
-- 05/29/2015 - 00000016      - 4-byte - 7.4GHz - Synced AXIS - Worked over night, Subclass added to registers