. ./Config.sh
. ./ansictrl.sh
. ./restore_common.sh

color white black

BACKUPS_ON_MT=0
OK_TO_REBOOT=0

## debug mode (if for real remove 'echo' command)
DEBUG=

# Version
VERSION=`cat /etc/recovery/VERSION`


# Step 4: partition the disk(s)
Step4         

