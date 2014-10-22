#!/bin/bash
function xe()
{
    local host
    local host_pwd=${cfg_host_pwd}
    local cmd
    local -a args

    #$arg_parse_quiet
    $arg_parse

    $requireargs host host_pwd

    echo "gwd_xe host ${host} host_pwd ${host_pwd} cmd '${args[@]}'" 1>&2

    $GWD_TESTLIB_PATH/gwd_xe -s ${host} -pw ${host_pwd} ${args[@]}
}

function xe-vm-start()
{
    local fn="xe-vm-start"
    # Required parameters
    local host
    local vm_name

    $arg_parse

    # FIXME Accept vm_uuid as well
    $requireargs host vm_name

    info "Starting vm $vm_name on host ${host}"  
    #${dry_run} || xe host=${host} vm-start vm=${vm_name} on=${host} || fail "vm-start failed"
    ${dry_run} || xe host=${host} vm-start vm=${vm_name} || fail "vm-start failed"
}

function xe-vm-wait-for-boot()
{
    local fn="xe-vm-wait-for-boot"
    # Required parameters
    local host
    local vm

    $arg_parse

    $requireargs host vm

    info "-- waiting for ${vm} tools" ; 
    ${dry_run} || ssh root@${host} "/tmp/wait-for-tools.sh ${vm}" ;
}

function xe-wait-for-xapi()
{
    local host
    local host_pwd=${cfg_host_pwd}
    local timeout=${cfg_timeout_xapi}
    local interval=1
    local time=0

    # Read and process [varname]=[value] options
    $arg_parse

    $requireargs host timeout interval


    if ! ${dry_run} ; then
	echo -n "INFO Waiting for ${host} to respond to xapi requests"
	while ! $GWD_TESTLIB_PATH/gwd_xe -s ${host} -pw ${host_pwd} help >& /dev/null \
	    && [[ $time -lt $timeout ]] ; do
	    echo -n "."
	    time=$(($time+$interval))
	    sleep $interval
	done
	echo
    fi

    if ! [[ $time -lt $timeout ]] ; then
	echo "ERROR Timed out waiting for xapi to respond on ${host}" 
	return 1
    else
	echo "INFO xapi appeared after ${time}"
	return 0
    fi

}

function xe-wait-for-host()
{
    local host_uuid
    local host_pwd
    local timeout
    local interval=1
    local time=0

    # Read and process [varname]=[value] options
    $arg_parse

    cfg_override cfg_timeout_xapi timeout ; eval $ret_eval
    cfg_override cfg_host_pwd host_pwd ; eval $ret_eval

    $requireargs host timeout interval host_pwd

    if [[ -z "${host_uuid}" ]] ; then
	${dry_run} || host_uuid=$(ssh root@${host} "source /etc/xensource-inventory ; echo \${INSTALLATION_UUID}")
	if [[ -z "$host_uuid" ]] ; then
	    echo "ERROR Could not get INSTALLATION_UUID for host ${host}!"
	    return 1;
	fi
    fi

    if ! ${dry_run} ; then
	echo -n "INFO Waiting for host $host uuid ${host_uuid} to be enabled"
	while [[ $($GWD_TESTLIB_PATH/gwd_xe -s ${host} -pw ${host_pwd} host-param-get uuid=${host_uuid} param-name=enabled) != "true" ]] \
	    && [[ $time -lt $timeout ]] ; do
	    echo -n "."
	    time=$(($time+$interval))
	    sleep $interval
	done
	echo
    fi

    if ! [[ $time -lt $timeout ]] ; then
	echo "ERROR Timed out waiting for host ${host} to be enabled" 
	return 1
    else
	echo "INFO Host enabled after ${time}"
	return 0
    fi

}

function xe-host-ready()
{
    local fn="xe-host-read"
    # Required parameters
    local host
    local host_uuid
 
    $arg_parse

    $requireargs host

    xe-wait-for-xapi host=${host} || return 1

    xe-wait-for-host host=${host} || return 1;

    status "XenServer host ${host} ready."
}

function xe-host-fake-license()
{
    local fn="xe-host-fake-license"
    local host
    local version
    
    # Read and process [varname]=[value] options
    $arg_parse

    $requireargs host version

    info "Installing fake license daemon"
    if [[ ${license_daemon}=="new" ]] ; then
	$dry_run || ssh root@${host} "sut/fake-license.sh ${version}" || fail "Installing fake license daemon"
    else
	$dry_run || ssh root@${host} "sut/fake-license-cowley.sh" || fail "Installing fake license daemon"
    fi

    xe-wait-for-xapi host=${host} || return 1
    
    # Now go ahead and get yourself a XenServer Platinum Edition:
    xe host=${host} host-apply-edition edition=platinum
}

function xe-vm-get-uuid()
{
    unset ret_vm_uuid

    # Required parameters
    local host
    local vm_name
    local vm_uuid

    $arg_parse

    $requireargs host vm_name

    vm_uuid=$(xe host=${host} vm-list --minimal name-label=${vm_name})
    info ${vm_name} uuid ${vm_uuid}

    ret_vm_uuid=$vm_uuid
}

function xe-vm-get-mac()
{
    unset ret_vm_mac
    
    # Required parameters
    local host
    local vm_name
    local vm_uuid
    # Local
    local vif_uuid
    local vm_mac
    local ret_vm_uuid
 
    $arg_parse

    $requireargs host

    [[ -n "$vm_name" ]] || [[ -n "$vm_uuid" ]] || fail "get-mac: Need either vm_name or vm_uuid"

    if [[ -z "$vm_uuid" ]] ; then
	xe-vm-get-uuid host=${host} vm_name=${vm_name}
	vm_uuid=$ret_vm_uuid
    fi

    vif_uuid=$(xe host=${host} vif-list --minimal vm-uuid=${vm_uuid})
    info ${vm_name} vif-uuid ${vif_uuid}
    vm_mac=$(xe host=${host} vif-param-get param-name=MAC uuid=${vif_uuid})
    info ${vm_name} mac ${vm_mac}

    ret_vm_mac=$vm_mac
}

function xe-vm-cd-eject()
{
    # Required parameters
    local host
    local vm_name
 
    $arg_parse

    # FIXME: Accept vm_uuid as well
    $requireargs host vm_name

    xe host=${host} vm-cd-eject vm=${vm_name} || fail "Ejecting CD"
}

function xe-vm-create()
{
    local vm_name
    local vm_install_os

    $arg_parse

    $requireargs host vm_install_os vm_name

    info Creating vm ${vm_name}, OS ${vm_install_os}
    ssh root@${host} "sut/xe-install-guest -c ${vm_install_os} ${vm_install_extra}" || fail "Installing VM"
}

function xe-vm-create-local()
{

    # Optional parameters
    local template_name
    local vm_name
    local network=true
    local network_uuid
    local network_interface

    # Really local
    local xe
    local vm_uuid
    local pif_uuid

    # FIXME Finish porting this function
    fail "FUNCTION NOT FINISHED PORTING"

    $arg_parse

    xe="gwd_xe -s ${host} -pw ${host_pwd}"


    # First, gather information and do appropriate checks

    # Find network uuid
    if $network ; then
	if [[ -z "$network_uuid" ]] ; then
	    if [[ -z "$network_interface" ]] ; then
		info Looking for network of management interface
		pif_uuid=$(${xe} pif-list --minimal management=true)
		[[ -n "${pif_uuid}" ]] || fail "Can't find management pif"
		network_uuid=(${xe} pif-param-get param-name=network-uuid uuid=$pif_uuid)
	    else
		info Looking for network with bridge 
		network_uuid=$(${XE} network-list bridge=${network_interface} --minimal)
	    fi
	fi
    fi

    # Make sure we have the CD available

    # Actually do the installation
    info Creating a new vm, name $vm_name template $template_name

    vm_uuid=$(${xe} vm-install new-name-label="$vm_name" template="$template_name")

    if [[ -z "${vm_uuid}" ]]; then
	echo VM installation failed.
	exit 1
    fi

    # Add installation media: CD
    if [[ -n "${install_cd}" ]] ; then
	echo Adding installation cd $install_cd
	vm_name=$(${xe} vm-param-get param-name=name-label uuid=${vm_uuid})
	${xe} vm-cd-add vm=${vm_name} device=hdc cd-name=${INSTALL_CD} || die "Failed to add CD"
    fi

    # Add install parameters for PV guests
    if [[ -n "${install_repro}" ]] ; then
	echo Setting install-repository to ${install-repro}
	${xe} vm-param-set uuid=${vm_uuid} other-config-install-repository="${install_repro}"
    fi

    if [[ -n "${install_params}" ]] ; then
	echo Setting PV-args to ${install_params}
	${XE} vm-param-set uuid=${vm_uuid} PV-args="${install_params}"
    fi


    # Add a network
    if $network ; then
	echo Adding a vif, connected to network $network_uuid
	vif_uuid=$(${XE} vif-create vm-uuid=${vm_uuid} network-uuid=${network_uuid} device=0)

	if [[ -z "${vif_uuid}" ]]; then
	    echo vif-create failed.  Deleting vm.
	    ${XE} vm-uninstall force=true uuid=${vm_uuid}
	    exit 1
	fi
    fi

# Resize the disk (if appropriate)
if [[ -n "${VDI_RESIZE_GB}" ]]; then
    echo Resizing main vdi to $VDI_RESIZE_GB GB
    SIZE=$((${VDI_RESIZE_GB} * 1024 * 1024 * 1024))
    vbd_uuid=$(${XE} vbd-list --minimal vm-uuid=${vm_uuid} type=Disk userdevice=0)
    vdi_uuid=$(${XE} vdi-list --minimal vbd-uuids=${vbd_uuid})
    vdi_sr_uuid=$(${XE} vdi-param-get uuid=${vdi_uuid} param-name=sr-uuid)
    vdi_name_label=$(${XE} vdi-param-get uuid=${vdi_uuid} param-name=name-label)
    vdi_sm_config=$(${XE} vdi-param-get uuid=${vdi_uuid} param-name=sm-config)
    echo Deleting old vbd/vdi
    ${XE} vdi-destroy uuid=${vdi_uuid}
    #${XE} vbd-destroy uuid=${vbd_uuid}
    echo Creating new vdi
    vdi_uuid=$(${XE} vdi-create name-label=${vdi_name_label} \
	sm-config=${vdi_sm_config} \
	sr-uuid=${vdi_sr_uuid} \
	type=system \
	virtual-size=${SIZE})
    [[ -n "${vdi_uuid}" ]] || die "Creating alternate vdi"
    vbd_uuid=$(${XE} vbd-create vdi-uuid=${vdi_uuid} \
	type=Disk \
	vm-uuid=${vm_uuid} \
	device=0)
    [ -n "${vbd_uuid}" ] || die "Creating alternate vbd"
    #${XE} vdi-resize uuid=${vdi_uuid} disk-size=${SIZE} || die "Resizing vdi"
fi

if [[ -n "${NUM_VCPUS}" ]] ; then
    echo Setting vcpus to ${NUM_VCPUS}
    ${XE} vm-param-set uuid=${vm_uuid} \
	VCPUs-max=${NUM_VCPUS} \
	VCPUs-at-startup=${NUM_VCPUS} || die "Setting vcpus"
fi    

if [[ -n "${MAX_MEM_MB}" ]] ; then
    echo Setting memory to ${MAX_MEM_MB} MB
    MEMSIZE=$((${MAX_MEM_MB} * 1024 * 1024 ))
    ${XE} vm-memory-limits-set uuid=${vm_uuid} \
	static-max=${MEMSIZE} \
	static-min=${MEMSIZE} \
	dynamic-max=${MEMSIZE} \
	dynamic-min=${MEMSIZE} || die "Setting memory"
fi    

    info Creating vm ${vm_name}, OS ${vm_install_os}
    ssh root@${host} "sut/xe-install-guest -c ${vm_install_os} ${vm_install_extra}" || fail "Installing VM"

}

