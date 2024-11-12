#!/bin/bash

#   FILE: bootsparc.sh  
# AUTHOR: Gratien D'haese
#   DATE: 10 April 2003 (v1.0)
# 
# Copyright (C) 2005 Gratien D'haese
# All rights reserved.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

. ./Config.sh
. ${SCRIPTS}/common.sh

echo "------------< Entering `basename $0` >-----------" | tee -a ${LOG}

echo "Create boot directory into isofs root" | tee -a ${LOG}
mkdir -p ${ISOFS_DIR}/boot/

echo "Copying initrd.img.gz into isofs root" | tee -a ${LOG}
cp initrd.img.gz ${ISOFS_DIR}/boot/initrd.gz

echo "Copying kernel into isofs root" | tee -a ${LOG}
copy_kernel ${ISOFS_DIR}/boot/vmlinux

echo "Copying cd.b into isofs root, or" | tee -a ${LOG}
cp /boot/cd.b ${ISOFS_DIR}/boot/

echo "copying isofs.b into isofs root" | tee -a ${LOG}
cp /boot/isofs.b ${ISOFS_DIR}/boot/

echo "Copying second.b into isofs root" | tee -a ${LOG}
cp /boot/second.b ${ISOFS_DIR}/boot/

echo "Copying message file into isofs root" | tee -a ${LOG}
cp ${SCRIPTS}/messages/message.sparc ${ISOFS_DIR}/boot/message.txt

echo "Creating silo.conf in isofs root" | tee -a ${LOG}
cat > ${ISOFS_DIR}/boot/silo.conf << EOF
message=/boot/message.txt

default=mkcdrec
timeout=50

image=/boot/vmlinux
label=mkcdrec
initrd=/boot/initrd.gz
EOF

echo "------------< Leaving `basename $0` >-----------" | tee -a ${LOG}
