#!/bin/bash

function xl-vm-start()
{
    $arg_parse

    tgt-helper

    info "Starting vm ${tgt_name} on host ${host_addr}" ; 
    ${dry_run} || ssh-cmd "xl create ${tgt_name}.cfg" || fail "Starting VM ${tgt_name}"
    ${dry_run} || sleep 5 
}

function xl-vm-shutdown()
{
    local fn="xe-vm-shutdown"
    # Passable parameters
    local host
    local vm

    $arg_parse

    tgt-helper

    info "Shutting down vm ${tgt_name}" ; 
    ${dry_run} || ssh-cmd host=$host_addr "xl shutdown ${tgt_name}" || return 1
}

# This explicitly "returns" domid
function xl-vm-wait()
{
    default timeout 600 ; $default_post

    $requireargs host_addr tgt_name

    info "Waiting for vm $tgt_name to appear"

    retry ssh-cmd host=$host_addr "xl domid $tgt_name 2>/dev/null"

    info "VM $tgt_name running"
    domid="$retry_result"
}

function xl-vm-wait-shutdown()
{
    local domid

    $requireargs host_addr tgt_name

    info "Waiting for vm $tgt_name to disappear"
    retry invert=true ssh-cmd host=$host_addr "xl domid $tgt_name 2>/dev/null"

    info "VM $tgt_name on $host_addr shut down"
}


function xl-vm-get-mac()
{
    unset ret_vm_mac;

    local ret
    local host
    local vm_name
    local t1
    local t2

    $arg_parse

    $requireargs host vm_name

    xl-vm-wait

    retry timeout=5 ssh-cmd host=$host_addr "xl network-list $tgt_name | grep '^0 '"

    t2=($retry_result)

    ret_vm_mac=${t2[2]}

    info ${vm_name} mac ${ret_vm_mac}
    
    eval "return $ret"
}

function xl-vm-console()
{
    $arg_parse

    tgt-helper

    xl-vm-wait

    ssh-cmd -t "xl console ${tgt_name}"
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

    tgt-helper

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
