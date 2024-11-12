. ./Config.sh
. ./ansictrl.sh
. ./restore_common.sh


## debug mode (if for real remove 'echo' command)
DEBUG=

# Version
VERSION=`cat /etc/recovery/VERSION`

# Step 5: make the filesystem on the disk(s)  (format the partitions)
Step5

# Step 6: make the swap if any
# Step 6bis: label partitions if needed (new in RedHat 7.x)
Step6

