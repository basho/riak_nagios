#!/bin/bash

##
# Usage: check_files.sh [Limit] [Critical Limit]
#
# Compares the number of open file handles against user supplied limits
# returns nagios compatible responses
#
# Unspecified argument defaults:
#    Warning Limit  - 5000
#    Critical Limit - 10000
#
##

############     NOTE     ##############
#                                      #
# This has only been tested on Ubuntu  #
#                                      #
# and WILL NOT work with FreeBSD       #
#                                      #
# ensure this works on your target     #
# sytstem before putting in production #
#                                      #
########################################

WarnLim=${1:-5000}
CritLim=${2:-10000}

fdcount=$(awk '{print $1}' /proc/sys/fs/file-nr 2>/dev/null)
if [ $? = 0 ] && [[ "$fdcount" =~ ^[\ ]*[0-9]+[\ ]*$ ]]; then
    if [ $fdcount -lt $WarnLim ]; then
        echo "OKAY: $fdcount / $WarnLim file descriptors in use."
        exit 0
    fi
    if [ $fdcount -ge $CritLim ]; then
        echo "CRITICAL: $fdcount / $CritLim file descriptors in use."
        exit 2
    fi
    if [ $fdcount -ge $WarnLim ]; then
        echo "WARNING: $fdcount / $WarnLim file descriptors in use."
        exit 1
    fi
    echo "CRITICAL: Could not evaluate count $fdcount against limits $WarnLim and $Critlim"
    exit 2
else
    echo "CRITICAL: Unable to get file descriptor count."
    exit 2
fi

