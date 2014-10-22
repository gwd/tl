#!/bin/bash
boot_timeout=600
shutdown_timeout=600
dry_run=false

function die()
{
   echo FATAL $@
   exit 1
}

function vm-uninstall() {
    local vm
    local vm_uuid
    local vbd_uuid
    local vdi_uuid
    local verbose="true"
    local dryrun="false"
    

    args=($@)

    while [[ -n "${args[@]}" ]] ; do
	a=${args[0]};       # Use first element
	if [[ `expr match ${a} '.*='` != "0" ]] ; then
	    args=(${args[@]:1}) # Element processed, pop it off
	#echo Evaluating "$a"
	    eval "$a"
	else
	    break
	fi
    done

    if [[ -n "vm" ]] ; then
	vm_uuid=$(xe vm-list --minimal name-label=${vm})
    fi

    [[ -n ${vm_uuid} ]] || die "Can't find vm_uuid!"

    ${verbose} && echo "About to uninstall vm uuid ${vm_uuid}"

    vbd_uuid=$(xe vbd-list --minimal vm-uuid=${vm_uuid} type=Disk)

    if [[ -n "${vbd_uuid}" ]] ; then
	${verbose} && echo "Found vbd ${vbd_uuid}"
	vdi_uuid=$(xe vdi-list --minimal vbd-uuids=${vbd_uuid})

	${verbose} && echo "Found vdi ${vdi_uuid}"
	
	${dryrun} || xe vdi-destroy uuid=${vdi_uuid}
	${dryrun} || xe vbd-destroy uuid=${vbd_uuid}
    fi
    
    ${dryrun} || xe vm-uninstall force=true uuid=${vm_uuid}
}


function domid-from-uuid() {
    local vm_uuid=$1
    local retvar=$2
    local RET

    # Check to see if the VM is running
    ps=$(xe vm-param-get uuid=$vm_uuid param-name=power-state)
    if [[ "$ps" != "running" ]] ; then
	echo VM not running
	return 1
    fi

    # Get the domid
    RET=$(xe vm-param-get uuid=$vm_uuid param-name=dom-id)

    if [[ -n "${retvar}" ]] ; then
	eval ${retvar}="$RET"
    else
	echo $RET
    fi
}

function domid-from-vm() {
    local vm_name=$1
    local retvar=$2
    local vm_uuid

    vm_uuid=$(xe vm-list --minimal name-label=$vm_name)
    
    domid-from-uuid $vm_uuid $retvar
}

function wait_for_boot_uuid() {
    local t=0
    local domid
    local d
    local vm=$1
    local crashed
    local rebooted

    crashed=false
    rebooted=false

    echo .Waiting for vm to be in state "running"

    while [ $t -lt $timeout ]; do
	ps=$(xe vm-param-get uuid=$vm param-name=power-state)
        if [ "$ps" = "running" ] ; then
	    break;
        fi
    done

    if [ $t -ge $timeout ] ; then
	echo Timed out waiting for domain to appear
	exit 1;
    fi

    domid-from-uuid $vm domid
	    
    echo .VM domain $domid. Waiting for tools to come up...

    while [ $t -lt $timeout ] ; do
	echo "[checking for networks]"
	nw=$(xe vm-param-get uuid=$vm param-name=networks)
	if [ "$nw" != "<not in database>" ] ; then 
	    booted=true
	    break
	fi
	echo "[checking power-state]"
	ps=$(xe vm-param-get uuid=$vm param-name=power-state)
        if [ "$ps" != "running" ] ; then
	    echo "Crashed"
            crashed=true
	    exit
        fi
	echo "[checking for changed domid]"
        d=$(xe vm-param-get uuid=$vm param-name=dom-id)
        if [ "$d" != "$domid" ] ; then
	    echo "Rebooted"
            rebooted=true
            exit
        fi

	echo "  Chilling."
	sleep 10
	t=$(($t+10))
    done
}

function wait_for_boot_vm() {
    local vm
    vm=$(xe vm-list --minimal name-label=$1)
    wait_for_boot_uuid $vm
}

function wait-for-boot()
{
    local host;
    local timeout="${boot_timeout}"
    local ssh_timeout="20"
    local ssh_time=0;
    local ssh_interval="1"
    local ping_output

    # Read and process [varname]=[value] options
    args=($@)
    
    while [[ -n "${args[@]}" ]] ; do
	a=${args[0]};       # Use first element
	if [[ `expr match ${a} '.*='` != "0" ]] ; then
	    args=(${args[@]:1}) # Element processed, pop it off
	#echo Evaluating "$a"
	    eval "$a"
	else
	    break
	fi
    done

    host=${args[0]}

    [ -n "${host}" ] || fail "Missing host"

    echo "INFO Pinging ${host}"
    ${dry_run} || ping_output=$(ping -c 1 -i 5 -q -w ${timeout} ${host})

    if [ "$?" != "0" ] ; then
	echo "ERROR Timed out pinging ${host} after ${timeout} seconds: ${ping_output}"
	return 1
    fi

    ssh_time=0;

    echo "INFO Attempting ssh connect to ${host}"
    if ! ${dry_run} ; then
	while ! echo | nc ${host} 22 >& /dev/null && [ $ssh_time -lt $ssh_timeout ] ; do
	    ssh_time=$(($ssh_time+$ssh_interval))
	    sleep $ssh_interval
	done
    fi

    if ! [ $ssh_time -lt $ssh_timeout ] ; then
	echo "ERROR Timed out waiting for ssh to open on ${host}" 
	return 1
    fi

    echo "STATUS Host ${host} responding to ssh." 
    return 0
}

function wait-for-shutdown()
{
    local vm_name
    local timeout="${shutdown_timeout}"
    local shutdown_interval=1
    local shutdown_time=0

    args=($@)

    while [[ -n "${args[@]}" ]] ; do
	a=${args[0]};       # Use first element
	if [[ `expr match ${a} '.*='` != "0" ]] ; then
	    args=(${args[@]:1}) # Element processed, pop it off
	#echo Evaluating "$a"
	    eval "$a"
	else
	    break
	fi
    done

    vm_name=${args[0]}

    while [[ ! $(xl list | grep ${vm_name} | wc -l) == "0" ]] \
        && [[ $shutdown_time -lt $timeout ]] ; do
	shutdown_time=$(($shutdown_time+$shutdown_interval));
	sleep $shutdown_interval;
    done	

    if ! [ $shutdown_time -lt $timeout ] ; then
	echo "ERROR Timed out waiting for ${vm_name} to shut down" 
	return 1
    fi

    echo "STATUS ${vm_name} shut down." 
    return 0
}

## Unit test individual functions                                                                                                                                                                                                                                      
function main()
{
    local cmd;

    if [ "$#" -eq "0" ] ; then
        echo "Usage: $0 function-name [arguments...]"
        exit 1
    fi

    args=($@)

    # Run first arg, pass the rest                                                                                                                                                                                                                                     
    if ${args[0]} ${args[@]:1} ; then
	exit 0
    else
	exit 1
    fi

    if ! [ -z "$RET" ] ; then
        echo $RET
    fi
}

# Only run main if this is not being included as a library                                                                                                                                                                                                             
if [ -z "$GWD_LIB" ] ; then
    main $@
fi
