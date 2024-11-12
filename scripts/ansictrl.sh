########
#
# ANSI Screen Control Routines (borrowed from CRU)
#
# Copyright (c) 1999, Enhanced Software Technologies, Inc
# All Rights Reserved
# License : The Q PUBLIC LICENSE version 1.0
#
# Tim Jones
#
########

# $Id: ansictrl.sh,v 1.12 2008/02/27 17:06:59 gdha Exp $
#
# Position the cursor on the screen
#
# locate row col
#
###
# MY_TTY replaces the /dev/tty parameter as work-around for the device not
# found error on the 1st console (gdha, 11/08/2002)
# check current tty and fill in proper CONSOLE value
tty -s 2>/dev/null || MY_TTY=/dev/console && MY_TTY=`tty | awk '{print $1}'`
echo ${MY_TTY} >/tmp/my_tty     # ask.for.cd.sh will pick proper value

locate () {
   echo -ne ${c_esc}[${1}\;${2}H
}

###
#
# Move the cursor Up, Left, Right, Down
#
# Up 3  Down 1  Left 7  etc.
#
###

Up () {
   echo -ne ${c_esc}[${1}A
}

Down () {
   echo -ne ${c_esc}[${1}B
}

Left () {
   echo -ne ${c_esc}[${1}D
}

Right () {
   echo -ne ${c_esc}[${1}C
}

###
#
# Set all color attributes in one call
#
# color foreground background
#
###

color () {

   if [ x$USECOLOR = xn ] ; then
      return
   fi

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

   out="${c_esc}[${f}${b}m"
   echo -ne ${out}
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
   if [ x"${USECOLOR}" = xy ]; then
      locate ${row} ${col}
   fi
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

    echo -ne "${c_end}Press ${c_hiend}[ENTER]${c_end} to continue or ${c_hiend}[CTRL-C]${c_end} to abort: "
    read junk <${MY_TTY}
}

#
# warn prints the first arg as a  warning message and then prompts for 
# continuation using the prompt function.
#
warn() {

    echo -ne "${c_warn}WARNING:${c_end}\n"
    echo -ne "${c_warntxt}${1}${c_end}\n"
    [ -f /etc/recovery/AUTODR ] || prompt

}

#
# error prints the second arg as an error message and then exits with the 
# error level passed as the first arg.
#
error() {

    echo -ne "${c_error}    ERROR:    ${c_end}\n"
    echo -ne "${c_errortxt}${2}${c_end}\n"
    echo -ne "${c_end}Press ${c_hiend}[ENTER]${c_end} to exit: "
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

    echo -ne "${c_askyn}${2} [${c_hiend}${order}${c_askyn}] ? ${c_end}"

    [ -f /etc/recovery/AUTODR ] || read answer <${MY_TTY}

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

    echo -ne "\a${c_st}Please choose from the above list [${c_sl}${1}${c_st}]: ${c_end}"
    read choice <${MY_TTY}
    while [ ${choice} -lt ${lowend} -o ${choice} -gt ${highend} ]
    do
        Up 1
        echo -ne "                                                                \r"
        echo -ne "\a${c_st}Please choose from the above list [${c_sl}${1}${c_st}]:${c_end}"
        read choice <${MY_TTY}
    done
    return ${choice}
}
