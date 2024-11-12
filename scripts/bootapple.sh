#!/bin/bash

#   FILE: bootapple.sh -- 
# AUTHOR: W. Michael Petullo <mkcdrec@flyn.org>
#   DATE: 10 November 2002
# 
# Copyright (C) 2002 W. Michael Petullo <mkcdrec@flyn.org>
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

echo "Copying initrd.img.gz into isofs root" | tee -a ${LOG}
cp initrd.img.gz ${ISOFS_DIR}/initrd.gz

echo "Copying kernel into isofs root" | tee -a ${LOG}
copy_kernel ${ISOFS_DIR}/vmlinux

echo "Copying yaboot into isofs root" | tee -a ${LOG}
cp /usr/lib/yaboot/yaboot ${ISOFS_DIR}/yaboot

echo "Creating yaboot.conf in isofs root" | tee -a ${LOG}
cat > ${ISOFS_DIR}/yaboot.conf << EOF
init-message="Welcome to mkCDrec"

default=mkcdrec
timeout=50

image=vmlinux
label=mkcdrec
initrd=/initrd.gz
EOF
