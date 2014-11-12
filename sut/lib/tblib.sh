#!/bin/bash

# "Image tarball" library
#
# Sets of functions relating to creating disk images and config files
# with different sizes, formats, and operating systems.

function tb-c6-post()
{
    set -ex

    # For now, disable selinux.  Alternate would be "fixfiles relabel"
    sed -i --follow-symlinks "s/SELINUX=enforcing/SELINUX=permissive/;" $mount/etc/selinux/config
    chroot $mount fixfiles -f relabel

    # Replace <UUID> with uuid in /etc/fstab, /etc/grub.conf
    uuid=$(blkid /dev/$devp | perl -ne '/UUID="([a-f0-9-]*)"/; print $1;')

    [[ -n "$uuid" ]] 

    sed -i --follow-symlinks "s/<UUID>/$uuid/;" $mount/etc/fstab
    sed -i --follow-symlinks "s/<UUID>/$uuid/;" $mount/boot/grub/grub.conf

    # We expect this to fail, but it will copy the needed files for the next step
    set +e
    chroot $mount grub-install /dev/xvda
    set -e

    chroot $mount /sbin/grub --batch <<EOF
device (hd0) /dev/xvda
root (hd0,0)
setup (hd0)
quit
EOF
    ls -l $image


    # Run grubby
    vmlinuz=$(ls $mount/boot/vmlinuz-* | tail -1 | sed "s|$mount||;")
    initramfs=$(ls $mount/boot/initramfs-* | tail -1 | sed "s|$mount||;")

    echo vmlinuz $vmlinuz
    echo initramfs $initramfs

    chroot $mount grubby --bad-image-okay --add-kernel=$vmlinuz --initrd=$initramfs --title="CentOS" --make-default --copy-default

    cat $mount/boot/grub/grub.conf
    ls -l $image

    # Set up networking
    cat >$mount/etc/sysconfig/network <<EOF
NETWORKING=yes
HOSTNAME=centos.localdomain
EOF

    cat >$mount/etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DEVICE=eth0
 TYPE=Ethernet
 ONBOOT=yes
 BOOTPROTO=dhcp
EOF
    set +ex
}

function tb-make-image()
{
    set -ex 

    $arg_parse

    : ${wdir:="/tmp"}
    : ${odir:="/images"}
    : ${basename:="c6"}
    : ${format:="vhd"}
    : ${size:="2048"}
    : ${dev:="xvda"}

    if [[ -e /dev/${dev} ]] ; then
	echo /dev/${dev} exists!
	exit 1
    fi

    mount=$wdir/centos-chroot
    tarball=$odir/c6.tar.gz

    case $format in
	vhd|raw|qcow2)
	    image=$odir/$basename-NN.$format
	    ;;
	*)
	    echo Unknown imagetype $imagetype!
	    exit 1
	    ;;
    esac

    devp="${dev}1"

    # Create empty image
    image-create overwrite=true

    # Attach image to dom0
    image-attach

    image-partition

    # Mount filesystem
    #  - procfs, sysfs, mount, /dev/xvd*
    rm -rf $mount
    mkdir -p $mount
    mount /dev/$devp $mount

    ls -l $image

    # Untar filesystem
    tar xzp -f $tarball -C $mount
    ls -l $image

    # Make suitable for chroot
    cp -a /dev/xvda* $mount/dev/

    cat > $mount/etc/mtab <<EOF
/dev/xvda1 / ext4 rw 0 0
EOF

    tb-c6-post

    # Copy ssh keys
    mkdir -p $mount/root/.ssh
    cp /root/.ssh/authorized_keys $mount/root/.ssh/authorized_keys

    # Clean up
    umount $mount

    image-detach

    ls -l $image

    set +ex
}

function tb-make-config()
{
    local blockspec
    local config
    local image

    $arg_parse
    
    # FIXME: Make a system to create local variables
    : ${id:="01"}
    : ${basename="c6"}
    : ${format="vhd"}
    : ${imagedir="/images"}
    : ${type="pv"}
    : ${confdir="$imagedir"}
    : ${memory="2048"}
    : ${vcpus="1"}

    local baseimage=${imagedir}/$basename-NN.$format

    if ! [[ -e ${baseimage} ]] ; then
	echo "${baseimage} not found.  Please run tb-make-image."
	exit 1
    fi

    image=$imagedir/$basename-$id.$format

    if ! [[ -e $image ]] ; then
	info cp $baseimage $image 
	cp $baseimage $image || exit 1
    fi

    case $type in
	pv)
	    builder="generic"
	    ;;
	hvm)
	    builder="hvm"
	    ;;
	*)
	    echo Unknown type: $type
	    exit 1
    esac

    # FIXME: Handle pvgrub

    config="$confdir/$basename-$id.cfg"

    image-get-blockspec var=blockspec dev=xvda

    cat > $config <<EOF
builder="$builder"
bootloader="pygrub"
name = "$basename-$id"
memory = "$memory"
disk = [ '$blockspec' ]
vif = [ 'mac=00:16:4F:0e:05:$id' ]
vcpus=$vcpus
on_crash = 'destroy'
serial='pty'
EOF

    echo "Made config file at $config"
}
