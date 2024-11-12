#!/bin/bash
# menu.sh script: provide a simple menu at login
# $Id: menu.sh,v 1.3 2007/11/13 14:38:13 gdha Exp $

trap ":" INT QUIT TSTP
. /etc/profile
tty -s 2>/dev/null || MY_TTY=/dev/console && MY_TTY=`tty`
echo ${MY_TTY} >/tmp/my_tty

locate () {
   echo -n [${1}\;${2}H
}

###
#
# Move the cursor Up, Left, Right, Down
#
# Up 3  Down 1  Left 7  etc.
#
###

Up () {
   echo -n [${1}A
}

Down () {
   echo -n [${1}B
}

Left () {
   echo -n [${1}D
}

Right () {
   echo -n [${1}C
}

###
#
# Set all color attributes in one call
#
# color foreground background
#
###

color () {

   case ${1} in 
      black) f=0\;30
      ;;
      red) f=0\;31
      ;;
      green) f=0\;32
      ;;
      yellow) f=0\;33
      ;;
      blue) f=0\;34
      ;;
      magenta) f=0\;35
      ;;
      cyan) f=0\;36
      ;;
      white) f=0\;37
      ;;
      hi_red) f=1\;31
      ;;
      hi_green) f=1\;32
      ;;
      hi_yellow) f=1\;33
      ;;
      hi_blue) f=1\;34
      ;;
      hi_magenta) f=1\;35
      ;;
      hi_cyan) f=1\;36
      ;;
      hi_white) f=1\;37
	;;
   esac

   case ${2} in
      black) b=\;40
      ;;
      red) b=\;41
      ;;
      green) b=\;42
      ;;
      yellow) b=\;43
      ;;
      blue) b=\;44
      ;;
      magenta) b=\;45
      ;;
      cyan) b=\;46
      ;;
      white) b=\;47
      ;;
      *) b=\;40
      ;;
   esac

   out=[${f}${b}m
   echo -n ${out}
}

#
# move to arg1, arg2 and display the string, arg3.
#
# printat 4 1 "This is a string"
#
printat () {
   row=${1}
   col=${2}
   str=${3}
   locate ${row} ${col}
   echo -ne "${str}"
}

#
# Using the current cursor location, print arg1
#
# Accepts standard ansi controls (\a, \t, \n, \b, etc.)
#
# print "This is the string\n"
#
print () {
   str=${1}
   echo -ne "${str}"
}

#
# prompt takes no arguments and waits for user input
#
# returns null
#
prompt () {

    echo -ne "[0;37;40mPress [1;37;40m[ENTER][0;37;40m to continue or [1;35;40m[CTRL-C][0;37;40m to abort: "
    read junk <${MY_TTY}

}

#
# warn prints the first arg as a  warning message and then prompts for 
# continuation using the prompt function.
#
warn() {

    echo -ne "[1;31;40mWARNING:[0;37;40m\n"
    echo -ne "[0;32;40m${1}[0;37;40m\n"
    prompt

}

#
# error prints the second arg as an error message and then exits with the 
# error level passed as the first arg.
#
error() {

    echo -ne "[0;31;47m    ERROR:    [0;37;40m\n"
    echo -ne "[0;32;40m${2}[0;37;40m\n"
    echo -ne "[0;37;40mPress [1;37;40m[ENTER][0;37;40m to continue: "
    read <${MY_TTY}
    exit ${1}

}

#
# askyn takes two arguments - the default answer (Y or N) and a formatted 
# text pattern that is displayed as provided (including formatting (if any)).
# Do not include the prompt string '[Y.n]' or the closing '?' since the
# function will add them.
#
# askyn Y "This is a question.  Should I run for president"
#
# returns 0 if NO or 1 if YES so you can use a unary test for comparison.
#
askyn () {

    if [ "${1}" = "Y" -o "${1}" = "y" ]
    then
        order="Y/n"
    else
        order="y/N"
    fi

    echo -ne "[0;32;40m${2} [[1;37;40m${order}[0;32;40m] ? [0;37;40m"

    read answer <${MY_TTY}
    if [ "${1}" = "Y" -o "${1}" = "y" ]
    then
        if [ "${answer}" = "n" -o "${answer}" = "N" ]
        then
            return 0
        else
            return 1
        fi
    else
        if [ "${answer}" = "y" -o "${answer}" = "Y" ]
        then
            return 1
        else
            return 0
        fi
    fi
    
}

#
# select assumes that you have displayed a list of some sort and prompts
# the user for a selection from that list.  You must format the list
# using a number selection scheme (i.e.: 1, 2, 3, 4, ....)
# 
# arg1 should be the range of options separated by a hyphen '-'
#
# selection 1-12
#
# results in:
#
#   Please choose from the above list [1-12]: 
#
# If the user chooses an answer outside of range, then the function will
# repeat the prompt using the 'Up 1' function above to keep the display
# neat.
#
# returns the choice
#
selection () {

    lowend=`echo ${1} | awk -F - '{print $1}'`
    highend=`echo ${1} | awk -F - '{print $2}'`
    legal=0

    printat 17 15 "\a[0;36;40mPlease choose from the above list [[1;33;40m${1}[0;36;40m]: [0;37;40m"
    read choice <${MY_TTY}
    while [ ${choice} -lt ${lowend} -o ${choice} -gt ${highend} ]
    do
        printat 17 15 "\a[0;36;40mPlease choose from the above list [[1;33;40m${1}[0;36;40m]: [0;37;40m"
        read choice <${MY_TTY}
    done
    return ${choice}
}

# MAIN Part
while true 
do
color white blue
clear
color hi_red blue
printat 2 20 "Make CD-ROM Recovery (mkCDrec) Menu"
color white blue
printat 7 15 "1. Run start-restore.sh (restore complete system)"
printat 8 15 "2. Run clone-dsk.sh (clone a particular disk)"
printat 9 15 "3. Run restore-fs.sh (restore one filesystem only)"
printat 10 15 "4. Run a bash shell"
printat 11 15 "5. Halt the system"
printat 15 15 ""
selection 1-5
ANS=$?

case ${ANS} in
1) cd /etc/recovery; start-restore.sh
;;
2) cd /etc/recovery; clone-dsk.sh
;;
3) cd /etc/recovery; restore-fs.sh
;;
4) color white black; clear; /bin/bash
;;
5) /bin/busybox poweroff
;;
esac
done
