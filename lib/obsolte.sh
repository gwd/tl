# Transition place for code that I think I probably don't need anymore
# host-set-config host config
function host-set-bootcfg()
{
    local host="$1"
    local config="$2"
    local target;

    local cfg_base="/usr/groups/netboot/gdunlap/"
    local tgt_base="/usr/groups/netboot/pxelinux.cfg/"

    host2pxe $host;
    if [ $? != 0 ] ; then
	echo "ERROR host2pxe failed"
	return 1
    fi
    cfg=${cfg_base}/${host}/${config}.cfg
    if ! [ -e ${cfg} ] ; then
	echo "ERROR Configuration file $cfg does not exist!"
	return 1
    fi

    target=${tgt_base}/${RET}

    echo "INFO Copying ${cfg} to ${target}"
    if [ -z "$3" ] ; then
	cp ${cfg} ${target}
    fi

    RET=""
}

function host-boot()
{
    local host="$1"

    info "Trying to reboot via ssh"
    wait-for-boot $1

    if [ "$?"=="0" ]; then
	ssh root@${host} "reboot"
	wait-for-offline $1
    else
	# FIXME: Detect and use xenuse automatically if available
	echo "ERROR Failed waiting for ${host} to boot"
	return 1
    fi

    wait-for-boot $1
}

function host-prep()
{
    local host="$1"

    echo "INFO Checking something.  Not sure what. "
}

function host-copy-boot-binaries()
{
    #fail "Just a placeholder"

    # Required params
    local host

    # Optional params
    local bdir="/boot"
    local netboot_dir="/usr/groups/netboot"
    local target

    # Truly local
    local fname
    local fsearch
    local target_esc
    local bdir_esc
    local dry_run=false

    # Read and process [varname]=[value] options
    $arg_parse

    [[ -n "${host}" ]] || fail "No host!"
    #[[ -n "${target}" ]] || fail "target empty!"
    #[[ -n "${htype}" ]] || fail "No host type!"

    #rm -rf ${netboot_dir}/${target}
    [[ -n "${target}" ]] || target="$USER/${host}/installed"

    echo mkdir -p ${netboot_dir}/${target}
    ${dry_run} || mkdir -p ${netboot_dir}/${target}

    for fsearch in "xen-*.gz" "initrd-*xen.img" "vmlinuz-*xen" ; do
	fname=$(ssh root@${host} "find ${bdir} -type f -name $fsearch -printf %f")
	[[ -n "${fname}" ]] || fail "Cannot find $fsearch"
	${dry_run} || scp root@${host}:${bdir}/${fname} ${netboot_dir}/${target}/${fname}
	${dry_run} || chmod +r ${netboot_dir}/${target}/${fname}
    done

    ${dry_run} || scp root@${host}:/boot/extlinux.conf ${netboot_dir}/${target}/extlinux.conf

    bdir_esc=${bdir//\//\\/}
    target_esc=${target//\//\\/}

    if ! ${dry_run} ; then
	echo Creating pxeconfig from extlinux.conf
	echo "default installed" > ${netboot_dir}/${target}/pxeconfig
	echo "label installed" >> ${netboot_dir}/${target}/pxeconfig
	perl -ne "if(\$s==0 && /fallback-serial/) 
              { \$s=1; } 
              elsif (\$s==1 && \!/label/) 
              { s/$bdir_esc/$target_esc/g; print; }
              elsif (\$s==1 && /label/)
              { exit 0; }" \
		  < ${netboot_dir}/${target}/extlinux.conf \
		  >> ${netboot_dir}/${target}/pxeconfig
	cat ${netboot_dir}/${target}/pxeconfig
    fi
}

function vm-start()
{
    local host="$1"
    local vm_name="$2"

    echo "INFO Attempting to create vm ${vm_name} on ${host}"
    if ssh root@${host} "xl create ${vm_name}" ; then
	return 0
    else
	return 1
    fi
}

function vm-up()
{
    local host="$1"
    local vm_name="$2"
    local vm_ip="$3"

    if vm-start ${host} ${vm_name} ; then
	echo "INFO domain created, waiting for boot"
	wait-for-boot ${vm_ip}
    else
	echo "ERROR Domain create ${vm_name} on host ${host} failed!"
	return 1
    fi
}

function vm-initiate-shutdown()
{
    local vm_ip="$1"

    echo "INFO Instructing vm_ip ${vm_ip} to shut down"
    if ssh root@${vm_ip} "shutdown -h now" ; then
	return 0
    else
	return 1
    fi
}

function vm-wait-for-shutdown()
{
    local host="$1"
    local vm_name="$2"

    echo "INFO: Waiting for vm ${vm_name} on host ${host} to disappear"
    if ssh root@${host} "control/htlib.sh wait-for-shutdown ${vm_name}" ; then
	return 0
    else
	return 1
    fi
}

function vm-down()
{
    local host="$1"
    local vm_name="$2"
    local vm_ip="$3"

    if ! vm-initiate-shutdown ${vm_ip}; then
	echo "ERROR shutdown failed!"
	return 1
    fi

    if ! vm-wait-for-shutdown ${host} ${vm_name} ; then
	echo "ERROR wait-forshutdown failed!"
	return 1
    fi

    echo "INFO: vm ${vm_name} completed shutdown"
}
