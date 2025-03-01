#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift Distributed Actors open source project
##
## Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

# Usage: paste a backtrace (e.g. made using crash_support.h) to this script to get it back with the swift names demangled:
#
# Example input:
#    0   sactPackageTests                 0x000000010b21f81a sact_dump_backtrace + 42
#    1   sactPackageTests                 0x000000010b38147c $S12DistributedActors0B4CellC6myselfAA0B3RefCyxGvg + 108
#    2   sactPackageTests                 0x000000010b39a01f $S12DistributedActors20FaultHandlingDungeonC012installCrashD06reaper4cellyAA0B3RefCyAA13ReaperMessageOG_AA0B4CellCyxGztKlFZySv_s5Int32VAPtcfU_ + 1567
#    3   sactPackageTests                 0x000000010b39a141 $S12DistributedActors20FaultHandlingDungeonC012installCrashD06reaper4cellyAA0B3RefCyAA13ReaperMessageOG_AA0B4CellCyxGztKlFZySv_s5Int32VAPtcfU_TA + 17
#    4   sactPackageTests                 0x000000010b398ce8 $S12DistributedActors22WrappedFailCellClosure33_4C8AA0F401D8341B7F872BBEC8A54C24LLV4fail_3sig6sicodeySv_s5Int32VAItKF + 104
#    5   sactPackageTests                 0x000000010b39c525 $S12DistributedActors20FaultHandlingDungeonC012installCrashD06reaper4cellyAA0B3RefCyAA13ReaperMessageOG_AA0B4CellCyxGztKlFZySvSg_AOs5Int32VAQtcfU0_ + 469
#    6   sactPackageTests                 0x000000010b39c599 $S12DistributedActors20FaultHandlingDungeonC012installCrashD06reaper4cellyAA0B3RefCyAA13ReaperMessageOG_AA0B4CellCyxGztKlFZySvSg_AOs5Int32VAQtcfU0_To + 9
#    7   sactPackageTests                 0x000000010b21fd16 sact_sighandler + 86
#    8   libsystem_platform.dylib            0x00007fff7e040b3d _sigtramp + 29
#
# Example output:
#    0	sactPackageTests	        0x000000010b21f81a	 demangled:sact_dump_backtrace
#    1	sactPackageTests	        0x000000010b38147c	 demangled:DistributedCluster.ActorCell.myself.getter : DistributedCluster._ActorRef<A>
#    2	sactPackageTests	        0x000000010b39a01f	 demangled:closure #1 (Swift.UnsafeMutableRawPointer, Swift.Int32, Swift.Int32) -> () in static DistributedCluster.FaultHandlingDungeon.installCrashHandling<A>(reaper: DistributedCluster._ActorRef<DistributedCluster.ReaperMessage>, cell: inout DistributedCluster.ActorCell<A>) throws -> ()
#    3	sactPackageTests	        0x000000010b39a141	 demangled:partial apply forwarder for closure #1 (Swift.UnsafeMutableRawPointer, Swift.Int32, Swift.Int32) -> () in static DistributedCluster.FaultHandlingDungeon.installCrashHandling<A>(reaper: DistributedCluster._ActorRef<DistributedCluster.ReaperMessage>, cell: inout DistributedCluster.ActorCell<A>) throws -> ()
#    4	sactPackageTests	        0x000000010b398ce8	 demangled:DistributedCluster.(WrappedFailCellClosure in _4C8AA0F401D8341B7F872BBEC8A54C24).fail(_: Swift.UnsafeMutableRawPointer, sig: Swift.Int32, sicode: Swift.Int32) throws -> ()
#    5	sactPackageTests	        0x000000010b39c525	 demangled:closure #2 (Swift.UnsafeMutableRawPointer?, Swift.UnsafeMutableRawPointer?, Swift.Int32, Swift.Int32) -> () in static DistributedCluster.FaultHandlingDungeon.installCrashHandling<A>(reaper: DistributedCluster._ActorRef<DistributedCluster.ReaperMessage>, cell: inout DistributedCluster.ActorCell<A>) throws -> ()
#    6	sactPackageTests	        0x000000010b39c599	 demangled:@objc closure #2 (Swift.UnsafeMutableRawPointer?, Swift.UnsafeMutableRawPointer?, Swift.Int32, Swift.Int32) -> () in static DistributedCluster.FaultHandlingDungeon.installCrashHandling<A>(reaper: DistributedCluster._ActorRef<DistributedCluster.ReaperMessage>, cell: inout DistributedCluster.ActorCell<A>) throws -> ()
#    7	sactPackageTests	        0x000000010b21fd16	 demangled:sact_sighandler
#    8	libsystem_platform.dylib	0x00007fff7e040b3d	 demangled:_sigtramp
# TODO don't drop the pos (+ n)

CYAN='\033[0;36m'
NC='\033[0m' # No Color

while read -r line
do
  mangled=$(echo "$line" | awk '{ print $4 }')
  de_mangled=$(echo "$mangled" | swift demangle)

  echo -n "$line" | awk 'BEGIN{}{ printf "%s\t%s\t%s\t demangled:", $1, $2, $3 }'
  echo -ne "$CYAN$de_mangled + "
  echo -e "$line$NC" | awk '{ print $NF }'
done
