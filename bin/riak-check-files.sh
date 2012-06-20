#!/bin/bash

##
# Usage: check_files.sh 'Node name' [Limit] [Critical Limit]
#
# Locates the PID for the beam process running the specified node
# counts the number of files handles that PID is using via lsof
# returns nagios compatible responses
#
# Unspecified argument defaults:
#    Node name      - riak@<host fqdn>
#    Limit          - 5000
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

TargetNode=$1
WarnLim=${2:-5000}
CritLim=${3:-10000}
[ -z "$TargetNode" ] && TargetNode="riak@`hostname -f`"

pid=$(ps axww 2>/dev/null | grep beam.smp 2>/dev/null | sed -n -e "/$TargetNode/s/^[ ]*\([0-9]*\).*$/\1 /p" 2>&1)
[[ "$pid" =~ ^[\ ]*[0-9]+[\ ]*$ ]] &&  fdcount=$(lsof -p $pid 2>/dev/null | wc -l 2>&1)
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
    echo "CRITICAL: Could not evaluate count $fdcount against limits $WarnLim and $Critlim on node $TargetNode"
    exit 2
else
    echo "CRITICAL: Unable to get file descriptor count."
    exit 2
fi

