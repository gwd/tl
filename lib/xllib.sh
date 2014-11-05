#!/bin/bash

function xl-vm-start()
{
    $arg_parse

    vm-helper

    info "Starting vm $vm_name on host ${host}" ; 
    ${dry_run} || ssh-cmd "xl create ${vm_name}.cfg" || fail "Starting VM ${vm_name}"
    ${dry_run} || sleep 5 
}

function xl-vm-shutdown()
{
    local fn="xe-vm-shutdown"
    # Passable parameters
    local host
    local vm

    $arg_parse

    vm-helper

    info "Shutting down vm $vm_name" ; 
    ${dry_run} || ssh-cmd "xl shutdown ${vm_name}" || return 1
}

# This explicitly "returns" domid
function xl-vm-wait()
{
    while ! domid=$(ssh-cmd "xl domid $vm_name 2>/dev/null") ; do
	info Waiting for vm $vm_name 
	sleep 1
    done
}

function xl-vm-wait-shutdown()
{
    local domid

    while domid=$(ssh-cmd "xl domid $vm_name 2>/dev/null") ; do
	info Waiting for vm $vm_name to shutdown
	sleep 1
    done
}


function xl-vm-get-mac()
{
    unset ret_vm_mac;

    local ret
    local host
    local vm_name
    local t1
    local t2
    local retries=2

    $arg_parse

    $requireargs host vm_name

    xl-vm-wait

    while true ; do
	t1=$(ssh-cmd "xl network-list $vm_name | grep '^0 '")
	ret=$?

	if [[ "$ret" = "0" ]] ; then
	    break
	fi

	if [[ $retries -gt 0 ]] ; then
	    retries=$(($retries-1))
	    info No mac for ${vm_name}, retrying...
	else
	    info No mac for ${vm_name}, giving up
	    return 1
	fi
    done

    #info Testline $vm_mac
    t2=($t1)

    ret_vm_mac=${t2[2]}

    info ${vm_name} mac ${ret_vm_mac}
    

    #grep -i $(xl network-list a0 | grep "^0 " | awk '{print $3}') /var/local/arp.log | tail -1 | awk '{print $2}'
    eval "return $ret"
}

function xl-vm-force-shutdown()
{
    local fn="xe-vm-force-shutdown"
    # Passable parameters
    local host
    local vm

    $arg_parse

    $requireargs host vm_name


    info "Shutting down vm $vm_name" ; 
    ${dry_run} || ssh root@${host} "xl destroy ${vm_name}" || return 1
    status "VM $vm forcibly shut down"
}

function xl-vm-wait-for-boot()
{
    local fn="xe-vm-wait-for-boot"
    # Passable parameters
    local host
    local ip

    $arg_parse


    $requireargs host ip

    ${dry_run} || wait-for-boot ${ip} || fail "Waiting for ip ${ip}"
}

function xl-vm-get-vnc-display()
{
    unset ret_remote_display

    local fn="xe-vm-get-vnc-display"

    local vinfo
    local display

    $arg_parse

    $requireargs host vm

    vinfo=$(ssh root@$host "xl list -l" | jq "map(select(.config.c_info.name==\"$vm\"))[0]")
    display=$(echo "$vinfo" | jq .config.b_info.u.vnc.display)
    while [[ -z "$display" ]] ; do 
	info Waiting for vm $vm 
	sleep 1
	vinfo=$(ssh root@$host "xl list -l" | jq "map(select(.config.c_info.name==\"$vm\"))[0]")
	display=$(echo "$vinfo" | jq .config.b_info.u.vnc.display)
    done

    echo $display
    ret_remote_display="$display"
}

function xl-vm-get-vnc-port()
{
    unset ret_remote_port

    local fn="xl-vm-get-vnc-port"

    local domid
    local port

    $arg_parse

    vm-helper

    vm-wait
    
    port=$(ssh-cmd "xenstore-read /local/domain/$domid/console/vnc-port")

    echo $port
    ret_remote_port="$port"
}


function xl-vm-vnc()
{
    local rport

    $arg_parse

    xl-vm-get-vnc-port 
    rport="$ret_remote_port"
    display-tunnel 
}


# This is a bit hackish; requires adding the following line to your /etc/rc.local:
#  touch /tmp/.finished-booting
# and making sure that /tmp is deleted before ssh starts.
function xl-host-ready()
{
    local fn="xl-host-ready"
    # Passable parameters
    local host
    local cmd
 
    $arg_parse

    $requireargs host

    while ! ssh-cmd "[[ -e /tmp/.finished-booting ]]" ; do
	info "Waiting for ${host} to be ready"
	sleep 1
    done

    status "Host ${host} ready."
    return 0
}

