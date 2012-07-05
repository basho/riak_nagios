#!/bin/bash

##
# Usage: check_compaction.sh
#
# Checks the leveldb logs for messages of compaction errors
#
##

############     NOTE     ##############
#                                      #
# ensure this works on your target     #
# system before putting in production  #
#                                      #
########################################

CompError=$(find /var/lib/riak/leveldb -name "LOG" -exec grep -l 'Compaction error' {} \; | wc -l)

if [ $CompError -eq 0 ] ; then
    echo "OKAY: No Compaction Errors Found."
    exit 0
else
    echo "CRITICAL: $CompError Compaction Errors Found."
    exit 2
fi
