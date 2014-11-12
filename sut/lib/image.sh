#!/bin/bash
set -ex

function vhd-create()
{
    $arg_parse

    vhd-util create -n $image -s $size    
}

function raw-create()
{
    $arg_parse

    truncate -s "${size}"M "$image"
}

function qcow2-create()
{
    $arg_parse

    qemu-img create -f qcow2 "$image" "${size}"M
}

function tb-c6-post()
{
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

}

function image-attach()
{
    local spec

    $arg_parse

    $requireargs dev format image

    spec="vdev=${dev},format=${format},target=${image}"

    [[ -n "$backendtype" ]] && spec="backendtype=${backendtype},${spec}"

    xl block-attach 0 ${spec}
    # !!!!
    usleep 100000
}

function tbz-to-image()
{
    $arg_parse

    ${wdir:=/tmp}
    ${odir:=/images}
    ${basename:=c6}
    ${format:=vhd}
    ${size:=2048}
    ${dev:=xvda}

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
    rm -f $image
    $format-create

    # Attach image to dom0
    image-attach

    # Make partitions
    parted -a optimal /dev/$dev mklabel msdos

    parted -a optimal -- /dev/$dev unit compact mkpart primary ext3 "1" "-1" 

    # Make filesystem
    mkfs.ext4 /dev/$devp

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

    xl block-detach 0 $dev
    ls -l $image

}
