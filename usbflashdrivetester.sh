#!/bin/bash
# 20171106 properlyindented

# uses:
# badblocks(8)
# lsblk(8)

function fatal
{
    local rc=-1
    if [[ "$1" =~ ^[0-9]+$ ]]
    then
        rc=$1
        shift
    fi
    echo "$*" >&2
    exit $rc
}

function init
{
    if [ "$( id -u )" -ne 0 ]
    then
        echo You are not root.
        yesno n "Do you wish to continue?"
        if [ "$REPLY" != "Y" ]
        then
          exit
        fi
    fi
    # Making sure these external programs exist
    local program
    for program in lsblk badblocks
    do
        which "$program" > /dev/null ||
            fatal 1 "$program not found in your path."
    done
    # Set up nice colours.
    declare -g csi=$( echo -ne '\e[' )
    declare -Ag fg=(
         [black]=30
           [red]=31
         [green]=32
        [yellow]=1\;33
         [white]=37
    )
    declare -Ag bg=(
         [black]=40
           [red]=41
         [green]=42
        [yellow]=43
         [white]=47
    )
    trap reset_terminal 0
}

function reset_terminal
{
    stty sane
}

function yesno
{
    # Returns upper case Y or N in $REPLY
    # First argument must specify default character to return
    # Second argument is the text string prompted with.
    # First character of $1
    local default_answer=${1:0:1}
    # Uppercase
    local default_uc=${default_answer^?}
    local other prompt
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
    if [ "${REPLY}" != "${other}" ]
    then
        REPLY=$default_uc
    fi
    echo $REPLY
}

function justone_sort
{
    (
        while [ -n "$1" ]
        do
            echo "$1"
            shift
        done
    ) |
    sort -u
}

function devicelist
{
    # This function should return a list of connected "disks"
    # The use of tail removes the title (the first line) which is "NAME"
    local dev
    unset devlist[*]
    declare -Ag devlist
    for dev in $(
        lsblk --path --nodeps --output NAME |
        tail -n +2 |
        sort -u
    )
    do
        dev=${dev#/dev/}
        devlist[$dev]=1
    done
    # The expected outcome of this function is one line per disk like:
    # /dev/sda
    # /dev/sdb
    # /dev/sdc
    # /dev/sr0
}

function reset_colour
{
    echo -n "${csi}m"
}

function colour_it
{
    echo -n "${csi}${fg[$1]};${bg[$2]}m${3}${csi}0m"
}

function centertext
{
    local cols=$( tput cols )
    local strlen=${#1}
    local tmp=$(( ( $cols - $strlen ) / 2 - 3 ))
    local equals=
    if [ $tmp -gt 0 ]
    then
        equals=$( head -c $tmp /dev/zero | sed 's/./-/g' )
    fi
    echo "${equals}|  ${1}  |${equals}"
}

function devicedetect
{
    # Keeps calling 'devicelist' until a new device is detected.
    # Basically; wait for insertion of USB flash drive
    echo -n "${csi}H${csi}J${csi}m"
    centertext Legend
    echo ' ' $( colour_it black white  " device " ) "Existing device."
    echo ' ' $( colour_it black green  " device " ) "A  new   device."
    echo ' ' $( colour_it black yellow " device " ) "Existing device without read/write access."
    echo ' ' $( colour_it white red    " device " ) "A  new   device without read/write access."
    echo ' ' $( colour_it red   black  " device " ) "Device have disappeared."
    declare -g testdevice=
    local -A known_devices
    local i=0
    while [ -z "$testdevice" ]
    do
        let i++
        # Goto Line 7 - update timestamp etc
        echo -n "${csi}7;1H"
        centertext "$( date -u '+%H:%M:%S UTC' )"
        # Clear to end of screen
        echo -n "Block devices:${csi}J"
        devicelist
        for dev in $(  justone_sort ${!devlist[*]} ${!known_devices[*]}  )
        do
            if   [ -z "${devlist[$dev]}" ]
            then
                # A device has disappeared
                echo -n ' '
                colour_it red black " ${dev} "
                unset known_devices[$dev]
            elif [ -z "${known_devices[$dev]}" -a $i -gt 1 ]
            then
                # new device
                known_devices[$dev]=$i
                echo -n ' '
                if [ -w "/dev/$dev" ]
                then
                  # we can write to the new device
                  testdevice="/dev/$dev"
                  colour_it black green " $dev "
                else
                  # we can not write to the new device
                  colour_it white red   " $dev "
                fi
            else
                # We already know the device
                known_devices[$dev]=$i
                echo -n ' '
                if [ -w "/dev/$dev" ]
                then
                  colour_it black white  " $dev "
                else
                  colour_it black yellow " $dev "
                fi
            fi
        done
        echo
        if [ -n "$testdevice" ]
        then
            echo
            return
        fi
        sleep 3
    done
}

init
devicedetect

# How many octets are on the drive
capacity=$(
    lsblk --bytes --nodeps --output SIZE $testdevice |
    tail -n +2 |
    xargs -n 1 echo # trims output
)
if   [ -z "$capacity" ]
then
    fatal 1 "Could not find the size of the device."
elif [ $capacity -lt $(( 32 * 1024 * 1024 )) ]
then
    fatal 1 "The reported size was less than 32MB. Probably incorrect."
fi

# Physical sector size (probably a lie)
sector_size=$(
    lsblk --bytes --nodeps --output PHY-SEC $testdevice |
    tail -n +2 |
    xargs -n 1 echo # trims output
)
if   [ -z "$sector_size" ]
then
    fatal 1 "Could not find the physical sector size of the device."
elif [ $sector_size -eq 0 ]
then
    fatal 1 "Physical sectors must be bigger than 0 bytes long."
fi
# How many bytes to test at a time
MBtestsize=128
testsize=$(( $MBtestsize * 1024 * 1024 ))
testblocks=$(( $testsize / $sector_size ))
# Calculate the number of blocks
blocks=$(( $capacity / $sector_size ))
lastblock=$(( $blocks - 1 ))
printf "%s is reported to have a capacity of %'u octets\\n" \
    $testdevice $capacity
printf "and is divided into %'u physical sectors of %'u octets each.\\n" \
    $blocks $sector_size
printf "Tests will be performed writing and reading chunks of\n"
printf "%'u MB (%'u sectors) each, on various places on the device.\\n" \
    $MBtestsize $testblocks
printf "DATA ON THE DEVICE WILL BE DESTROYED.\\n\\n"
yesno y "Do you wish to perform a DESTRUCTIVE test of $testdevice ?"
if [ "$REPLY" != "Y" ]
then
    exit 0
fi
function chunktest
{
    local start=$(( $1 + $2 - 1 ))
    echo Test starting from sector $2.
    local tmp=$( mktemp --tmpdir=. badblocks-list.XXXXXX )
    badblocks -o $tmp -w -s -b $sector_size -c 64 $testdevice $1 $2
    echo $( wc -l < $tmp ) faulty sectors between $2 and $(( $1 + $2 - 1 )).
}
chunktest $testblocks 0
chunktest $(( $blocks - 1 )) $(( $blocks - 1 - $testblocks )) 
