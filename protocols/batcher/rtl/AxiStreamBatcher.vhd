-------------------------------------------------------------------------------
-- File       : AxiStreamBatcher.vhd
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: The firmware batcher combines sub-frames into a larger super-frame
-- https://confluence.slac.stanford.edu/x/th1SDg
-------------------------------------------------------------------------------
-- This file is part of 'SLAC Firmware Standard Library'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC Firmware Standard Library', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.SsiPkg.all;

entity AxiStreamBatcher is
   generic (
      TPD_G                       : time                := 1 ns;
      MAX_SUPER_FRAME_THRESHOLD_G : positive            := 8192;  -- Units of bytes
      MAX_NUMBER_SUB_FRAME_G      : positive            := 32;  -- Units of sub-frames
      MAX_CLK_GAP_G               : positive            := 256;  -- Units of clock cycles
      AXIS_CONFIG_G               : AxiStreamConfigType := AXI_STREAM_CONFIG_INIT_C;
      INPUT_PIPE_STAGES_G         : natural             := 0;
      OUTPUT_PIPE_STAGES_G        : natural             := 1);
   port (
      -- Clock and Reset
      axisClk      : in  sl;
      axisRst      : in  sl;
      -- External Control Interface
      maxSuperSize : in  slv(31 downto 0) := toSlv(MAX_SUPER_FRAME_THRESHOLD_G, 32);
      maxSubFrame  : in  slv(15 downto 0) := toSlv(MAX_NUMBER_SUB_FRAME_G, 16);
      maxClkGap    : in  slv(11 downto 0) := toSlv(MAX_CLK_GAP_G, 12);
      -- AXIS Interfaces
      sAxisMaster  : in  AxiStreamMasterType;
      sAxisSlave   : out AxiStreamSlaveType;
      mAxisMaster  : out AxiStreamMasterType;
      mAxisSlave   : in  AxiStreamSlaveType);
end entity AxiStreamBatcher;

architecture rtl of AxiStreamBatcher is

   constant AXIS_WRD_C : positive := AXIS_CONFIG_G.TDATA_BYTES_C;  -- Units of bytes

   type StateType is (
      HEADER_S,
      SUB_FRAME_S,
      TAIL_S,
      CHUCK_TAIL_2BYTE_S,
      CHUCK_TAIL_4BYTE_S,
      GAP_S);

   type RegType is record
      maxSuperSize    : slv(31 downto 0);
      superByteCnt    : slv(31 downto 0);
      subByteCnt      : slv(31 downto 0);
      maxSubFrame     : slv(15 downto 0);
      subFrameCnt     : slv(15 downto 0);
      maxClkGap       : slv(11 downto 0);
      clkGapCnt       : slv(11 downto 0);
      maxSuperSizeDet : sl;
      maxSubFrameDet  : sl;
      seqCnt          : slv(7 downto 0);
      tDest           : slv(7 downto 0);
      tUserFirst      : slv(7 downto 0);
      tUserLast       : slv(7 downto 0);
      lastByteCnt     : slv(4 downto 0);
      chuckCnt        : natural range 0 to 3;
      rxSlave         : AxiStreamSlaveType;
      txMaster        : AxiStreamMasterType;
      state           : StateType;
   end record RegType;

   constant REG_INIT_C : RegType := (
      maxSuperSize    => toSlv(MAX_SUPER_FRAME_THRESHOLD_G, 32),
      superByteCnt    => toSlv(AXIS_WRD_C, 32),
      subByteCnt      => (others => '0'),
      maxSubFrame     => toSlv(MAX_NUMBER_SUB_FRAME_G, 16),
      subFrameCnt     => (others => '0'),
      maxClkGap       => toSlv(MAX_CLK_GAP_G, 12),
      clkGapCnt       => (others => '0'),
      maxSuperSizeDet => '0',
      maxSubFrameDet  => '0',
      seqCnt          => (others => '0'),
      tDest           => (others => '0'),
      tUserFirst      => (others => '0'),
      tUserLast       => (others => '0'),
      lastByteCnt     => (others => '0'),
      chuckCnt        => 1,
      rxSlave         => AXI_STREAM_SLAVE_INIT_C,
      txMaster        => AXI_STREAM_MASTER_INIT_C,
      state           => HEADER_S);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal rxMaster : AxiStreamMasterType;
   signal rxSlave  : AxiStreamSlaveType;
   signal txMaster : AxiStreamMasterType;
   signal txSlave  : AxiStreamSlaveType;

begin

   assert (AXIS_WRD_C >= 2)
      report "AXIS_CONFIG_G.TDATA_BYTES_C must be >= 2" severity error;

   -----------------
   -- Input pipeline
   -----------------
   U_Input : entity work.AxiStreamPipeline
      generic map (
         TPD_G         => TPD_G,
         PIPE_STAGES_G => INPUT_PIPE_STAGES_G)
      port map (
         axisClk     => axisClk,
         axisRst     => axisRst,
         sAxisMaster => sAxisMaster,
         sAxisSlave  => sAxisSlave,
         mAxisMaster => rxMaster,
         mAxisSlave  => rxSlave);

   comb : process (axisRst, maxClkGap, maxSubFrame, maxSuperSize, r, rxMaster,
                   txSlave) is
      variable v : RegType;

      procedure doTail is
      begin
         -- Check for end of super-frame condition
         if (v.maxSuperSizeDet = '1') or (v.maxSubFrameDet = '1') then
            -- Move the outbound data
            v.txMaster.tValid := '1';
            -- Terminate the super-frame
            v.txMaster.tLast  := '1';
            -- Indicates super-frame terminated
            if (AXIS_WRD_C = 2) then
               v.txMaster.tData(13) := v.maxSubFrameDet;
               v.txMaster.tData(14) := v.maxSuperSizeDet;
            elsif (AXIS_WRD_C = 4) then
               v.txMaster.tData(29) := v.maxSubFrameDet;
               v.txMaster.tData(30) := v.maxSuperSizeDet;
            else
               v.txMaster.tData(61) := v.maxSubFrameDet;
               v.txMaster.tData(62) := v.maxSuperSizeDet;
            end if;
            -- Next state
            v.state := HEADER_S;
         -- Check if new data to move
         elsif (rxMaster.tValid = '1') then
            -- Move the outbound data
            v.txMaster.tValid := '1';
            -- Next state
            v.state           := SUB_FRAME_S;
         else
            -- Next state
            v.state := GAP_S;
         end if;
      end procedure doTail;

   begin
      -- Latch the current value
      v := r;

      -- Reset the strobes
      v.rxSlave.tReady := '0';
      if (txSlave.tReady = '1') then
         v.txMaster.tValid := '0';
         v.txMaster.tLast  := '0';
         v.txMaster.tUser  := (others => '0');
      end if;

      -- Check for max. super frame
      if(r.superByteCnt = r.maxSuperSize) then
         -- Set the flag
         v.maxSuperSizeDet := '1';
      end if;

      -- Check for max. super frame
      if(r.subFrameCnt = r.maxSubFrame) then
         -- Set the flag
         v.maxSubFrameDet := '1';
      end if;

      -- Main state machine
      case r.state is
         ----------------------------------------------------------------------
         when HEADER_S =>
            -- Reset the flag
            v.maxSuperSizeDet                              := '0';
            v.maxSubFrameDet                               := '0';
            -- Sample external signals
            v.maxSuperSize                                 := maxSuperSize;
            v.maxSubFrame                                  := maxSubFrame;
            v.maxClkGap                                    := maxClkGap;
            -- Floor the maxSuperSize to nearest word increment
            -- This is done to remove the ">" operator in 
            v.maxSuperSize(bitSize(AXIS_WRD_C)-1 downto 0) := (others => '0');
            -- Check for zero byte maxSuperSize case
            if (v.maxSuperSize = 0) then
               -- Prevent zero case
               v.maxSuperSize := toSlv(AXIS_WRD_C, 32);
            end if;
            -- Check for zero maxSubFrame case
            if (v.maxSubFrame = 0) then
               -- Prevent zero case
               v.maxSubFrame := toSlv(1, 16);
            end if;
            -- Check if ready to move data
            if (rxMaster.tValid = '1') and (v.txMaster.tValid = '0') then
               -- Send the super-frame header
               v.txMaster.tValid               := '1';
               v.txMaster.tData(3 downto 0)    := x"1";  -- Version = 0x1
               v.txMaster.tData(7 downto 4)    := toSlv(AXIS_WRD_C-1, 4);
               v.txMaster.tData(15 downto 8)   := r.seqCnt;
               v.txMaster.tData(127 downto 16) := (others => '0');
               ssiSetUserSof(AXIS_CONFIG_G, v.txMaster, '1');
               -- Increment the sequence counter
               v.seqCnt                        := r.seqCnt + 1;
               -- Next state
               v.state                         := SUB_FRAME_S;
            end if;
            -- Reset the sub-frame counter
            v.subFrameCnt  := (others => '0');
            -- Preset the super-frame byte counter
            v.superByteCnt := toSlv(AXIS_WRD_C, 32);
         ----------------------------------------------------------------------
         when SUB_FRAME_S =>
            -- Check if ready to move data
            if (rxMaster.tValid = '1') and (v.txMaster.tValid = '0') then
               -- Accept the inbound data
               v.rxSlave.tReady  := '1';
               -- Move the outbound data
               v.txMaster.tValid := '1';
               v.txMaster.tData  := rxMaster.tData;
               -- Check if first transaction
               if (r.subByteCnt = 0) then
                  -- Sample the first transaction
                  v.tUserFirst(AXIS_CONFIG_G.TUSER_BITS_C-1 downto 0) := axiStreamGetUserField(AXIS_CONFIG_G, rxMaster, 0);
                  -- Increment the sub-frame counter
                  v.subFrameCnt                                       := r.subFrameCnt + 1;
               end if;
               -- Check for last transaction in sub-frame
               if (rxMaster.tLast = '1') then
                  -- Get the number of valid bytes in the last transaction of the sub-frame
                  v.lastByteCnt                                      := toSlv(getTKeep(rxMaster.tKeep), 5);
                  -- Increment the sub-frame byte counter
                  v.subByteCnt                                       := r.subByteCnt + getTKeep(rxMaster.tKeep);
                  -- Sample the meta data
                  v.tUserLast(AXIS_CONFIG_G.TUSER_BITS_C-1 downto 0) := axiStreamGetUserField(AXIS_CONFIG_G, rxMaster);
                  v.tDest(AXIS_CONFIG_G.TDEST_BITS_C-1 downto 0)     := rxMaster.tDest(AXIS_CONFIG_G.TDEST_BITS_C-1 downto 0);
                  -- Next state
                  v.state                                            := TAIL_S;
               else
                  -- Increment the sub-frame byte counter
                  v.subByteCnt := r.subByteCnt + AXIS_WRD_C;
               end if;
               -- Increment the super-frame byte counter
               v.superByteCnt := r.superByteCnt + AXIS_WRD_C;
            end if;
         ----------------------------------------------------------------------
         when TAIL_S =>
            -- Check if ready to move data
            if (v.txMaster.tValid = '0') then
               -- Set the sub-frame tail data field
               v.txMaster.tData(31 downto 0)   := r.subByteCnt;
               v.txMaster.tData(39 downto 32)  := r.tDest;
               v.txMaster.tData(47 downto 40)  := r.tUserFirst;
               v.txMaster.tData(55 downto 48)  := r.tUserLast;
               v.txMaster.tData(60 downto 56)  := r.lastByteCnt;
               v.txMaster.tData(127 downto 61) := (others => '0');
               -- Reset the counter
               v.subByteCnt                    := (others => '0');
               -- Check the AXIS width
               if (AXIS_WRD_C = 2) then
                  -- Move the outbound data
                  v.txMaster.tValid := '1';
                  -- Next state
                  v.state           := CHUCK_TAIL_2BYTE_S;
               elsif (AXIS_WRD_C = 4) then
                  -- Move the outbound data
                  v.txMaster.tValid := '1';
                  -- Next state
                  v.state           := CHUCK_TAIL_4BYTE_S;
               else
                  -- Process the tail
                  doTail;
               end if;
               -- Preset chuck counter
               v.chuckCnt     := 1;
               -- Increment the super-frame byte counter
               v.superByteCnt := r.superByteCnt + AXIS_WRD_C;
            end if;
         ----------------------------------------------------------------------
         when CHUCK_TAIL_2BYTE_S =>
            -- Check if ready to move data
            if (v.txMaster.tValid = '0') then
               -- Shift the data
               v.txMaster.tData := x"0000" & r.txMaster.tData(127 downto 16);
               -- Check the chucking counter
               if r.chuckCnt = 3 then
                  -- Process the tail
                  doTail;
               else
                  -- Move the outbound data
                  v.txMaster.tValid := '1';
                  -- Increment the counter
                  v.chuckCnt        := r.chuckCnt + 1;
               end if;
               -- Increment the super-frame byte counter
               v.superByteCnt := r.superByteCnt + AXIS_WRD_C;
            end if;
         ----------------------------------------------------------------------
         when CHUCK_TAIL_4BYTE_S =>
            -- Check if ready to move data
            if (v.txMaster.tValid = '0') then
               -- Shift the data
               v.txMaster.tData := x"0000_0000" & r.txMaster.tData(127 downto 32);
               -- Check the chucking counter
               if r.chuckCnt = 1 then
                  -- Process the tail
                  doTail;
               else
                  -- Move the outbound data
                  v.txMaster.tValid := '1';
                  -- Increment the counter
                  v.chuckCnt        := r.chuckCnt + 1;
               end if;
               -- Increment the super-frame byte counter
               v.superByteCnt := r.superByteCnt + AXIS_WRD_C;
            end if;
         ----------------------------------------------------------------------
         when GAP_S =>
            -- Check for new sub-frame
            if (rxMaster.tValid = '1') then
               -- Reset the counter
               v.clkGapCnt := (others => '0');
               -- Next state
               v.state     := SUB_FRAME_S;
            -- Check for the clock gap event
            elsif (r.clkGapCnt = r.maxClkGap) then
               -- Check if ready to move data
               if (v.txMaster.tValid = '0') then
                  -- Reset the counter
                  v.clkGapCnt       := (others => '0');
                  -- Move the outbound data
                  v.txMaster.tValid := '1';
                  -- Terminate the super-frame
                  v.txMaster.tLast  := '1';
                  -- Indicates super-frame terminated due to clock gap 
                  if (AXIS_WRD_C = 2) then
                     v.txMaster.tData(15) := '1';
                  elsif (AXIS_WRD_C = 4) then
                     v.txMaster.tData(31) := '1';
                  else
                     v.txMaster.tData(63) := '1';
                  end if;
                  -- Next state
                  v.state := HEADER_S;
               end if;
            else
               -- Increment the counter
               v.clkGapCnt := r.clkGapCnt + 1;
            end if;
      ----------------------------------------------------------------------
      end case;

      -- Always the same outbound AXIS stream width
      v.txMaster.tKeep := genTKeep(AXIS_WRD_C);
      v.txMaster.tStrb := genTKeep(AXIS_WRD_C);

      -- Combinatorial outputs before the reset
      rxSlave <= v.rxSlave;

      -- Reset
      if (axisRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

      -- Registered Outputs
      txMaster <= r.txMaster;

   end process comb;

   seq : process (axisClk) is
   begin
      if (rising_edge(axisClk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   ------------------
   -- Output pipeline
   ------------------
   U_Output : entity work.AxiStreamPipeline
      generic map (
         TPD_G         => TPD_G,
         PIPE_STAGES_G => OUTPUT_PIPE_STAGES_G)
      port map (
         axisClk     => axisClk,
         axisRst     => axisRst,
         sAxisMaster => txMaster,
         sAxisSlave  => txSlave,
         mAxisMaster => mAxisMaster,
         mAxisSlave  => mAxisSlave);

end rtl;
