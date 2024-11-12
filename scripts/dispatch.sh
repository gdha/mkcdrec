#!/bin/bash
echo "Checking architure..." | tee -a ${LOG}
. ./Config.sh 2>/dev/null

# check architecture is supported:
GetBootArch
if [ "${barch}" = "Unsupported" ]; then
   echo "Fatal: Architecture NOT supported by mkCDrec." | tee -a ${LOG}
   exit 1
fi
if [ "${BOOTARCH}" != "${barch}" ]; then
   echo "Warning: Edit Config.sh and set BOOTARCH to ${barch}" | tee -a ${LOG}
   exit 1
fi
echo "Supported architecture: ${BOOTARCH}" | tee -a ${LOG}
echo "Using Makefile.$BOOTARCH." | tee -a ${LOG}
make -f Makefile.$BOOTARCH $@
