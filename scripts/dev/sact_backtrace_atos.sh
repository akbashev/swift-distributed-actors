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
# 1   SampleLetItCrash             0x000000010a4aee28 sact_segfault_sighandler + 56
# 2   libsystem_platform.dylib            0x00007fff7e040b3d _sigtramp + 29
# 3   libsystem_c.dylib                   0x00007fffb0c3b6b8 __global_locale + 0
# 4   SampleLetItCrash             0x000000010a62678d $S12DistributedActors20FaultHandlingDungeonC012installCrashD06reaper4cellyAA0B3RefCyAA13ReaperMessageOG_AA0B4CellCyxGztKlFZySv_s5Int32VAPtcfU_ + 429
# 5   SampleLetItCrash             0x000000010a626c65 $S12DistributedActors20FaultHandlingDungeonC012installCrashD06reaper4cellyAA0B3RefCyAA13ReaperMessageOG_AA0B4CellCyxGztKlFZySv_s5Int32VAPtcfU_TA + 21
# 6   SampleLetItCrash             0x000000010a6258e8 $S12DistributedActors22WrappedFailCellClosure33_4C8AA0F401D8341B7F872BBEC8A54C24LLV4fail_3sig6sicodeySv_s5Int32VAItKF + 104
# 7   SampleLetItCrash             0x000000010a628fb0 $S12DistributedActors20FaultHandlingDungeonC012installCrashD06reaper4cellyAA0B3RefCyAA13ReaperMessageOG_AA0B4CellCyxGztKlFZySvSg_AOs5Int32VAQtcfU0_ + 320
# 8   SampleLetItCrash             0x000000010a629129 $S12DistributedActors20FaultHandlingDungeonC012installCrashD06reaper4cellyAA0B3RefCyAA13ReaperMessageOG_AA0B4CellCyxGztKlFZySvSg_AOs5Int32VAQtcfU0_To + 9
# 9   SampleLetItCrash             0x000000010a4af312 sact_sighandler + 146
# 10  libsystem_platform.dylib            0x00007fff7e040b3d _sigtramp + 29
# 11  ???                                 0x0000000000000000 0x0 + 0
# 12  libswiftCore.dylib                  0x000000010a9a6c23 $Ss18_fatalErrorMessage__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF + 19
# ...
#
# Example output:
# 1	 SampleLetItCrash    0x000000010a4aee28	 atos:sact_segfault_sighandler (in SampleLetItCrash) (/Users/ktoso/code/sact/Sources/CMailbox/survive_crash_support.c:31)
# 2	 libsystem_platform.dylib   0x00007fff7e040b3d	 atos:_sigtramp (in libsystem_platform.dylib) + 29
# 3	 libsystem_c.dylib          0x00007fffb0c3b6b8	 atos:__global_locale (in libsystem_c.dylib) + 0
# 4	 SampleLetItCrash    0x000000010a62678d	 atos:closure #1 in static FaultHandlingDungeon.installCrashHandling<A>(reaper:cell:) (in SampleLetItCrash) (/Users/ktoso/code/sact/Sources/DistributedCluster/FaultHandling.swift:73)
# 5	 SampleLetItCrash    0x000000010a626c65	 atos:partial apply for closure #1 in static FaultHandlingDungeon.installCrashHandling<A>(reaper:cell:) (in SampleLetItCrash) (/Users/ktoso/code/sact/<compiler-generated>:0)
# 6	 SampleLetItCrash    0x000000010a6258e8	 atos:WrappedFailCellClosure.fail(_:sig:sicode:) (in SampleLetItCrash) (/Users/ktoso/code/sact/Sources/DistributedCluster/FaultHandling.swift:34)
# 7	 SampleLetItCrash    0x000000010a628fb0	 atos:closure #2 in static FaultHandlingDungeon.installCrashHandling<A>(reaper:cell:) (in SampleLetItCrash) (/Users/ktoso/code/sact/Sources/DistributedCluster/FaultHandling.swift:92)
# 8	 SampleLetItCrash    0x000000010a629129	 atos:@objc closure #2 in static FaultHandlingDungeon.installCrashHandling<A>(reaper:cell:) (in SampleLetItCrash) (/Users/ktoso/code/sact/<compiler-generated>:0)
# 9	 SampleLetItCrash    0x000000010a4af312	 atos:sact_sighandler (in SampleLetItCrash) (/Users/ktoso/code/sact/Sources/CMailbox/survive_crash_support.c:52)
# 10 libsystem_platform.dylib   0x00007fff7e040b3d	 atos:_sigtramp (in libsystem_platform.dylib) + 29
# 11 ???	                    0x0000000000000000	 atos:0x0000000000000000
# 12 libswiftCore.dylib	        0x000000010a9a6c23	 atos:_fatalErrorMessage(_:_:file:line:flags:) (in libswiftCore.dylib) + 19
# 13 SampleLetItCrash	0x000000010a64f1db	 atos:closure #1 in faultyWorkerBehavior() (in SampleLetItCrash) (/Users/ktoso/code/sact/Sources/SampleLetItCrash/main.swift:0)
#
# Example usage snippet:
#       clear; pbpaste | bash ./scripts/sact_backtrace_atos.sh
CYAN='\033[0;36m'
NC='\033[0m' # No Color

BIN=$1
# BIN=".build/x86_64-apple-macosx10.10/debug/SampleLetItCrash"
PID=$2
# PID=$(ps aux | grep "SampleLetItCrash" | grep -v "grep" | awk '{print $2}')

while read -r line
do
  address="$(echo "$line" | awk '{ print $3 }')"
  source_pos=$(atos -p "$PID" -o "$BIN" -fullPath "$address" 2> /dev/null)

  echo -n "$line" | awk 'BEGIN{} { printf "%s\t%s\t%s\t atos:", $1, $2, $3 }'
  echo -e "$CYAN$source_pos$NC"
done
