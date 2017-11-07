#!/bin/bash
# 20171106 properlyindented

# uses:
# badblocks(8)
# lsblk(8)
# read-write access to the block device.
# you may want to be root to use this script

esc=$( echo -ne '\e' )
ansi_reset="${esc}[0m"
ansi_fg_red="${esc}[01;31m"
ansi_fg_green="${esc}[01;32m"
ansi_fg_white="${esc}[01;37m"

function fatal
{
    declare rc=-1
    if [[ "$1" =~ ^[0-9]+$ ]]
    then
        rc=$1
        shift
    fi
    echo "$*" >&2
    exit $rc
}

function prereq
{
    while [ -n "$1" ]
    do
        which "$1" > /dev/null || fatal 1 "$1 not found in your path."
        shift
    done
}

function devicelist
{
    # This function should return a list of connected "disks"
    # The use of tail removes the title (the first line) which is "NAME"
    lsblk --nodeps --paths --output NAME | tail -n +2 | sort -u
    # The expected outcome of this function is one line per disk like:
    # /dev/sda
    # /dev/sdb
    # /dev/sdc
    # /dev/sr0
}

function devicedetect
{
    # Keeps calling 'devicelist' until a new device is detected.
    # Basically; wait for insertion of USB flash drive
    declare -A known_devices
    declare retval=
    declare i=0
    while [ -z "$retval" ]
    do
        let i++
        clear >&2
        echo -n $ansi_reset >&2
        date -u '+%H:%M:%S UTC' >&2
        echo -n Devices present: >&2
        for dev in $( devicelist )
        do
            if [ -z "${known_devices[$dev]}" -a $i -gt 1 ]
            then
                retval="$dev"
                echo -n "${ansi_fg_green}" >&2
            else
                echo -n "${ansi_fg_white}" >&2
            fi
            known_devices[$dev]=$i
            echo -n " $dev" >&2
        done
        for dev in ${!known_devices[*]}
        do
            if [[ "${known_devices[$dev]}" != $i ]]
            then
                echo -n " ${ansi_fg_red}${dev}${ansi_reset}" >&2
                unset known_devices[$dev]
            fi
        done
        echo "$ansi_reset" >&2
        if [ -n "$retval" ]
        then
            echo "$retval"
            return
        fi
        sleep 3
    done
}

function yesno
{
    # Returns upper case Y or N in $REPLY
    # First argument must specify default character to return
    # Second argument is the text string prompted with.
    # First character of $1
    declare default_answer=${1:0:1}
    # Uppercase
    declare default_uc=${default_answer^?}
    declare other prompt
    if [ "${default_uc}" = "Y" ]
    then
        other="N"
        prompt="Yn"
    else
        other="Y"
        prompt="yN"
    fi
    read -s -n 1 -p "$2 [$prompt]: "
    # upper case it
    REPLY=${REPLY^?}
    if [ "${REPLY}" != "${default_uc}" ]
    then
        REPLY=$other
    fi
    echo $REPLY
}

prereq lsblk badblocks
newdev=$( devicedetect )
yesno y "Do you wish to perform a DESTRUCTIVE test of $newdev ?"
if [ "$REPLY" != "Y" ]
then
    exit 0
fi
# How many octets are on the drive
size=$(    lsblk --bytes --nodeps --output SIZE    $newdev | tail -n +2  )
# Physical sector size (probably a lie)
physec=$(  lsblk --bytes --nodeps --output PHY-SEC $newdev | tail -n +2  )
# How many bytes to test
testsize=$(( 128 * 1024 * 1024 ))
testblocks=$(( $testsize / $physec ))
# Calculate the number of blocks
blocks=$(( $size / $physec ))
badblocks -w -b $physec -c 64 $newdev $(( $blocks - 1 )) $(( $blocks - 1 - $testblocks )) 

