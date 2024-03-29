#!/bin/sh

if echo "$@" | grep -- "--debug"
then \
  set -x
fi

# we need absolute dir path of the script so that we can execute this script from any path
scriptdirpath=`dirname $0`
scriptdirpath=`realpath "$scriptdirpath"`

# get a list of all datasets so that we can validate inputs where an existing dataset is required
localalldatasetlist="`zfs list -pH -o name -t filesystem`"

localallsnapshotlist="`zfs list -pH -o name -t snapshot`"

# get a list of all current dataset snapshots so that we can do work with the newest snapshot only
locallatestsnapshots="`zfs get -r -pH -o name,value -t snapshot creation | awk -f "${scriptdirpath}/find_latest_snapshot.awk" | awk '{ print $1 }'`"

# the local selected dataset list is a list that will be replicated and is read from user provided parameters
localselecteddatasetlist=""

# reading user provided parameters
while [ $# -ne 0 ]
do \
  if [ "$1" = "--debug" ]
  then \
    shift
    continue
  fi
  if [ "$1" = "--host" ]
  then \
    shift
    remotesitename="$1"
    shift
    continue
  fi
  if [ "$1" = "--prefix" ]
  then \
    shift
    remotereplicationprefix="$1"
    shift
    continue
  fi
  if echo "$localalldatasetlist" | grep -e "^${1}\$" >/dev/null
  then \
  	if [ "$localselecteddatasetlist" = "" ]
    then \
      localselecteddatasetlist="$1"
    else \
      localselecteddatasetlist="`echo -e "${localselecteddatasetlist}\n${1}"`"
    fi
  fi
  shift
done

# as long as we do not have a valid remotesitename and-or remotereplicationprefix there is no point in continuing
if [ -z "$remotesitename" ] || [ -z "$remotereplicationprefix" ]
then \
  echo "no remote site name and-or remote replication prefix was provided, exiting" >&2
  exit 1
fi

# get a list of latest remote snapshots so that we can match the remote snapshot with our latest snapshot and only transfer the differences
remotelatestsnapshots="`ssh "$remotesitename" zfs get -r -pH -o name,value -t snapshot creation "$remotereplicationprefix" | awk -f "${scriptdirpath}/find_latest_snapshot.awk" | awk '{ print $1 }'`"
remotealldatasets="`ssh "$remotesitename" zfs list -o name -pH -t filesystem`"

# loop over selected dataset instances in order to transfer the differences or their whole contents on the remote side
for localselecteddatasetlistinstance in $localselecteddatasetlist
do \
  # filter out the local instance latest snapshot in order to look for it on the remote side, if it is already there, we can skip to the next dataset
  instancelatestlocalsnapshot=`echo "$locallatestsnapshots" | grep -e "^${localselecteddatasetlistinstance}@" | awk -F'@' '{ print $2 }'`
  # find the remote snapshot that matches our selected instance
  remotelatestinstancesnapshot=`echo "$remotelatestsnapshots" | grep -e "^${remotereplicationprefix}/${localselecteddatasetlistinstance}@"`
  # in case a latest snapshot of a selected dataset does not exist, print a warning and skip selected instance
  if [ -z "$instancelatestlocalsnapshot" ]
  then \
    echo "$localselecteddatasetlistinstance does not have a latest snapshot, skipping" >&2 
    continue
  fi
  if [ "${remotereplicationprefix}/${localselecteddatasetlistinstance}@${instancelatestlocalsnapshot}" == "$remotelatestinstancesnapshot" ]
  then \
    continue # we already have it on remote
  fi
  remotelatestinstancesnapshotname=`echo $remotelatestinstancesnapshot | awk -F'@' '{ print $2 }'`
  if echo "$localallsnapshotlist" | grep -e "^${localselecteddatasetlistinstance}@${remotelatestinstancesnapshotname}\$" >/dev/null
  then \
    zfs send -I "${remotelatestinstancesnapshotname}" "${localselecteddatasetlistinstance}@${instancelatestlocalsnapshot}" | ssh "$remotesitename" zfs receive -F "${remotereplicationprefix}/${localselecteddatasetlistinstance}"
  else \
    if echo "$remotealldatasets" | grep -e "^${remotereplicationprefix}/${localselecteddatasetlistinstance}\$" >/dev/null
    then \
      true
    else \
      ssh "$remotesitename" zfs create -p "${remotereplicationprefix}/${localselecteddatasetlistinstance}"
    fi
    zfs send "${localselecteddatasetlistinstance}@${instancelatestlocalsnapshot}" | ssh "$remotesitename" zfs receive -F "${remotereplicationprefix}/${localselecteddatasetlistinstance}"
  fi
done

