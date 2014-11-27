#!/bin/bash
function vhd-create()
{
    vhd-util create -n ${image} -s ${size}
}

function raw-create()
{
    truncate -s "${size}"M "${image}"
}

function qcow2-create()
{
    qemu-img create -f qcow2 "${image}" "${size}"M
}

function image-create()
{
    $arg_parse

    [[ -z "${overwrite}" ]] && overwrite=false

    $requireargs format image size

    if [[ -e $image ]] ; then
	if "${overwrite}" ; then
	    info "${image} exists; overwriting"
	    rm -f ${image}
	else
	    fail "${image} exists.  Use overwrite=true to overwrite"
	fi
    fi

    ${format}-create
}

function image-get-blockspec()
{
    local _s

    $arg_parse

    $requireargs dev format image var

    _s="vdev=${dev},format=${format},target=${image}"

    [[ -n "$backendtype" ]] && _s="backendtype=${backendtype},${_s}"

    eval "$var=\"$_s\""
}

function image-attach()
{
    local blockspec

    $arg_parse

    image-get-blockspec var=blockspec

    xl block-attach 0 ${blockspec}

    # Pre 4.5, xl block-attach returned success even if the attach
    # failed.  This is complicated by the fact that block-attach also
    # returns before the device actually appears.  Wait for it for 5
    # seconds then give up.
    retry timeout=5 eval "[[ -e /dev/${dev} ]]" || fail "block-attach failed, /dev/${dev} not present!"
}

function image-detach()
{
    $arg_parse

    $requireargs dev

    xl block-detach 0 $dev
}

function image-partition()
{
    $arg_parse

    $requireargs dev

    local devp="${dev}1"

    # Make partitions
    parted -a optimal /dev/$dev mklabel msdos

    parted -a optimal -- /dev/$dev unit compact mkpart primary ext3 "1" "-1" 

    # Make filesystem
    mkfs.ext4 /dev/$devp
}
