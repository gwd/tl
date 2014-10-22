function vm-create()
{
    unset ret_vm_name
    # Required args
    local host
    local vm_name
    local vm_install_os

    $arg_parse

    $requireargs htype host vm_install_os

    if [[ -z "${vm_name}" ]] ; then
	echo No name given, using default
	vm-config-get vm_install_os=${vm_install_os}
	echo Using name ${install_vm_name}
	vm_name=$install_vm_name
    fi

    $htype-vm-create host=${host} vm_install_os=${vm_install_os} vm_name=${vm_name}

    # FIXME Allow return values from the above function instead
    ret_vm_name=${vm_name}
}

function vm-wait-ip()
{
    unset ret_vm_ip
    # Required args
    local host
    local vm_name
    local vm_mac

    $arg_parse

    $requireargs host
    
    [[ -n "$vm_name" ]] || [[ -n "$vm_mac" ]] || fail "Need either vm_name or vm_mac"

    if [[ -z "$vm_mac" ]] ; then
	$htype-vm-get-mac host=${host} vm_name=${vm_name}
	vm_mac=$ret_vm_mac
    fi

    ret_vm_ip=$(ssh_cmd="sut/arp-get-ip ${vm_mac}" ssh-cmd)

    info $vm_name ip $ret_vm_ip
}

# 
# vm_ip: Er, do we actually want this anymore?
# host, vm_name: 
# vm: walk down "stack" and return
function vm-helper()
{
    local fn

    fn="$1"

    [[ -n "$vm_name" && -n "$host" ]] || [[ -n "$vm" ]] || [[ -n "$vm_ip" ]] \
	|| fail "Need either vm_ip, vm_name and host, or vm"

    if [[ -n "$vm_ip" ]] ; then
	return;
    fi

    local guest
    local stack

    if [[ -z "$host" ]] ; then
	parse-separator-array ":" stack $vm

	host="${stack[0]}"
	vm_name="${stack[1]}"
	pop stack
    fi

    while [[ -n "${stack[1]}" ]] ; do
	info Looking up host $host vm_name $vm_name
	vm-wait-ip host=$host vm_name=$vm_name
	host=$ret_vm_ip
	vm_name="${stack[1]}"
	pop stack
    done

    if [[ "$fn" == "ip" ]] ; then
	info Looking up host $host vm_name $vm_name
	vm-wait-ip host=$host vm_name=$vm_name
	vm_ip=$ret_vm_ip
    fi
}

function vm-helper-get-ip()
{
    vm-helper ip
}

TESTLIB_HELP+=($'vm-ip\t\t[vm=VMPATH|host=HOST (vm_name=|vm_ip=)]')
function vm-ip()
{
    $arg_parse

    vm-helper ip

    echo $vm_ip
}

function vm-helper-get-ip-OLD()
{
    [[ -n "$vm_name" ]] || [[ -n "$vm_ip" ]] || fail "Need either vm_name or vm_ip"

    if [[ -z "$vm_ip" ]] ; then
	vm-wait-ip host=$host vm_name=$vm_name
	vm_ip=$ret_vm_ip
    fi
}

function vm-wait-shutdown()
{
    $arg_parse

    $requireargs htype host vm_name

    $htype-vm-wait-shutdown host=$host vm_name=$vm_name
}

TESTLIB_HELP+=($'vm-start\t[vm=VMPATH|host=HOST (vm_name=|vm_ip=)] [extra args]')
function vm-start()
{
    $arg_parse

    $requireargs htype

    vm-helper

    $htype-vm-start host=$host vm_name=$vm_name "${args[@]}"
}

# ssh conventions
#
# ssh_user: defaults to root
# ssh_htype: "ubuntu" will do "sudo $cmd" or "sudo bash"
# ssh_cmd can be set beforehand

function ssh-cmd()
{
    local cmd 

    $arg_parse

    # Always override "ssh_cmd" with "cmd" if it exists
    # NB: at the moment arg_parse discards quotes, so anything
    #     with a space will get mangled.
    [[ -n "$cmd" ]] && ssh_cmd="$cmd"

    $requireargs host ssh_cmd

    case "$ssh_htype" in
	ubuntu)
	    [[ -z "$ssh_user" ]] && ssh_user="xenuser"
	    ssh $ssh_user@$host "sudo $ssh_cmd"
	    ;;
	*)
	    [[ -z "$ssh_user" ]] && ssh_user="root"
	    ssh $ssh_user@$host "$ssh_cmd"
	    ;;
    esac
}

function ssh-cmd2()
{
    $arg_parse

    $requireargs host

    case "$ssh_htype" in
	ubuntu)
	    [[ -z "$ssh_user" ]] && ssh_user="xenuser"
	    ssh $ssh_user@$host "sudo ${args[@]}"
	    ;;
	*)
	    [[ -z "$ssh_user" ]] && ssh_user="root"
	    ssh $ssh_user@$host "${args[@]}"
	    ;;
    esac
}

function ssh-shutdown()
{
    $arg_parse

    vm-helper-get-ip

    #ssh root@${vm_ip} "shutdown -h now"
    ssh_cmd="shutdown -h now" ssh-cmd host=${vm_ip}
}

function display-tunnel()
{
    local lport
    local display
    local ssh_user

    $arg_parse

    $requireargs host rport

    case "$ssh_htype" in
	ubuntu)
	    [[ -z "$ssh_user" ]] && ssh_user="xenuser"
	    ;;
	*)
	    [[ -z "$ssh_user" ]] && ssh_user="root"
	    ;;
    esac

    if [[ -z "$loffset" ]] ; then
	local loffset
	loffset="1"
    fi

    lport=$(($rport+$loffset))
    display=$(($lport-5900))
    info ssh -f -L $lport:localhost:$rport $ssh_user@$host "sleep 5"
    ssh -f -L $lport:localhost:$rport $ssh_user@$host "sleep 5"
    info vncviewer :$display
    vncviewer :$display
}

TESTLIB_HELP+=($'vm-vnc\t\t[vm=VMPATH|host=HOST (vm_name=|vm_ip=)]')
function vm-vnc()
{
    $arg_parse

    $requireargs htype

    $htype-vm-vnc
}


function acpi-shutdown()
{
    $arg_parse

    $requireargs host vm_name

    #ssh root@${host} "xl trigger ${vm_name} power"
    ssh_cmd="xl trigger ${vm_name} power" ssh-cmd
}


function ssh-ready()
{
    $arg_parse

    vm-helper-get-ip

    info "Attempting ssh connect to vm ${vm_ip} timeout ${s_timeout}"
    if ! wait-for-port host=${vm_ip} timeout=${cfg_timeout_ssh} interval=1 port=22 ; then
	error "Waiting for SSH to appear"
	return 1;
    fi
}

TESTLIB_HELP+=($'vm-ssh\t\t[vm=VMPATH|host=HOST (vm_name=|vm_ip=)] [ssh commands]')

function vm-ssh()
{
    # NB ssh_htype should be used by vm-helper-get-ip, ssh_vtype for the guest

    $arg_parse

    vm-helper-get-ip

    info "Attempting ssh connect to vm ${vm_ip} type ${ssh_htype} timeout ${s_timeout}"
    if ! wait-for-port host=${vm_ip} timeout=${cfg_timeout_ssh} interval=1 port=22 ; then
	error "Waiting for SSH to appear"
	return 1;
    fi


    case "$ssh_vtype" in
	ubuntu)
	    [[ -z "$ssh_user" ]] && ssh_user="xenuser"
	    ssh -t $ssh_user@$vm_ip "sudo bash"
	    ;;
	*)
	    [[ -n "$ssh_user" ]] || ssh_user="root"
	    ssh $ssh_user@$vm_ip "${args[@]}"
	    ;;
    esac
}

function ssh-vm-ubuntu()
{
    $arg_parse

    vm-helper-get-ip

    info "Attempting ssh connect to vm ${vm_ip} timeout ${s_timeout}"
    if ! wait-for-port host=${vm_ip} timeout=${cfg_timeout_ssh} interval=1 port=22 ; then
	error "Waiting for SSH to appear"
	return 1;
    fi

    ssh -t xenuser@${vm_ip} "sudo bash"
}

function vm-shutdown()
{
    $arg_parse

    $requireargs ctype

    [[ -n "$wait" ]] || eval "local wait; wait=true"
    [[ -n "$acpi" ]] || eval "local acpi; lacpi=false"
    

    if $acpi ; then
	acpi-shutdown
    else
	$ctype-shutdown
    fi

    $wait && vm-wait-shutdown
}

function vm-ready()
{
    $arg_parse

    $requireargs ctype

    $ctype-ready
}

function vm-get-mac()
{
    $arg_parse

    $requireargs htype host vm_name

    $htype-vm-get-mac host=${host} vm_name=${vm_name}
}

# Takes a created VM and goes through the installation process
# FIXME: This is for Windows w/ the XenRT control daemon
function vm-install()
{
    # Local
    local vm_mac

    $arg_parse

    $requireargs htype host vm_name

    if [[ -z "${vm_mac}" ]] ; then
	vm-get-mac host=${host} vm_name=${vm_name}
	vm_mac=$ret_vm_mac
    fi

    $htype-vm-start host=${host} vm_name=${vm_name} || fail "Starting vm $vm_name"

    vm-wait-ip host=${host} vm_mac=${vm_mac} || fail "Waiting for IP"
    vm_ip=$ret_vm_ip
    info ${vm_name} ip ${vm_ip}

    info "Waiting for xenrt daemon to respond at ${vm_ip}"
    xrt-daemon-wait vm_ip=${vm_ip} || fail "Waiting for test daemon"

    # Occasionally we've had the above succeed but then the shutdown 
    # fail; presumably the daemon comes up briefly and then shuts down
    # immediately.  So probe first.
    info "Waiting for port to disappear, or stay for 20 seconds"
    if wait-for-port host=${vm_ip} port=${cfg_xrt_daemon_port} interval=1 timeout=20 invert=true ; then
	# If the port did disappear, wait for the test daemon to come back up
	info "Waiting for VM to shutdown"
	sleep 30
	info "Waiting for xenrt daemon to respond at ${vm_ip}"
	xrt-daemon-wait vm_ip=${vm_ip} || fail "Waiting for test daemon"
    fi

    info "Shutting down vm with xenrt daemon at ${vm_ip}"
    xrt-shutdown vm_ip=${vm_ip} || fail "Shutting down VM"

    info "Waiting for VM to shutdown"
    sleep 30

    info Ejecting CD
    $htype-vm-cd-eject host=${host} vm_name=${vm_name} || fail "Ejecting CD"
}


function vm-install-pv-drivers()
{
    # Local
    local vm_mac

    $arg_parse

    $requireargs htype host vm_name

    if [[ -z "${vm_mac}" ]] ; then
	$htype-vm-get-mac host=${host} vm_name=${vm_name}
	vm_mac=$ret_vm_mac
    fi

    info Starting ${vm_name}
    $htype-vm-start host=${host} vm_name=${vm_name}

    $htype-vm-cd-eject vm_name=${vm_name} # May fail if the drive is empty
    $htype-vm-cd-insert vm_name=${vm_name} cd-name=xs-tools.iso || fail "Inserting tools CD"
    
    #ssh root@${host} "xe vm-start vm=${vm_name} on=${host}" || fail "Starting VM"

    vm-wait-ip host=${host} vm_mac=${vm_mac} || fail "Waiting for IP"
    vm_ip=$ret_vm_ip
    info ${vm_name} ip ${vm_ip}

    info "Waiting for xenrt daemon to respond at ${vm_ip}"
    xrt-daemon-wait vm_ip=${vm_ip} || fail "Waiting for xenrt daemon"

    # Upgrade exec daemon
    # - I don't thinks this is actually necessary
    # "c:\certmgr.exe"

    # Enable test signing (if necessary)
    # Copy test certificate files
    # Activate test cert
    if $needs_test_signing ; then
	info Enabling test signing
	xrt-daemon ${vm_ip} "bcdedit /set testsigning on" || fail "Enabling test signing"
	info Copying cert files
	xrt-daemon -L ${certmgr_lpath} -F ${certmgr_rpath} ${vm_ip} || fail "Copying certmgr"
	xrt-daemon -L ${xencert_lpath} -F ${xencert_rpath} ${vm_ip} || fail "Copying xencert"
	info Activating test cert
	xrt-daemon ${vm_ip} "${certmgr_rpath} /add ${xencert_rpath} /s /r localmachine root" \
	    || fail "Adding test cert to root"
	xrt-daemon ${vm_ip} "${certmgr_rpath} /add ${xencert_rpath} /s /r localmachine trustedpublisher" \
	    || fail "Adding test cert to trustedpublisher"
    fi
    
    if xrt-daemon ${vm_ip} "dir d:\\${dotnet_binary}" | grep ${dotnet_binary} ; then
	info ".Net binary found on install iso, checking for guest framework"
	if ! xrt-daemon ${vm_ip} "dir c:\\windows\\microsoft.net\\framework\\v4.0*" | grep "<DIR>.*v4" ; then
	    info ".Net not installed, installing"
	    xrt-daemon ${vm_ip} "d:\\${dotnet_binary} /q /norestart"

	    info "Rebooting vm with xenrt daemon at ${vm_ip}"
	    xrt-reboot vm_ip=${vm_ip} || fail "Rebooting VM"
	    
	    info Waiting 30 seconds for VM to reboot
	    sleep 30
	    
	    info "Waiting for xenrt daemon to respond at ${vm_ip}"
	    xrt-daemon-wait vm_ip=${vm_ip} || fail "Waiting for xenrt daemon"
	fi
    fi

    # Run tools install from D: instead
    info "Installing tools"
    #./viadaemon.py ${vm_ip} "d:\\xensetup.exe /S /norestart" || fail "Installing tools"
    xrt-daemon ${vm_ip} "d:\\msiexec /quiet /i d:\installwizard.msi" || fail "Installing tools"

    # Eject CD
    info Ejecting CD
    $htype-cd-eject host=${host} vm_name=${vm_name} || fail "Ejecting tools CD"

    #info Copying tools to vm
    #./viadaemon.py -L ${root}/xensetup.exe -F C:\\xensetup.exe ${vm_ip} || fail "Copying tools"
    #echo "./viadaemon.py -u ${www_url_base}/xensetup.exe -F C:\\xensetup.exe ${vm_ip}"
    #./viadaemon.py -u ${www_url_base}/xensetup.exe -F C:\\xensetup.exe ${vm_ip} || fail "Copying tools"

    #info Installing tools
    #./viadaemon.py ${vm_ip} 'C:\xensetup.exe /S /norestart' || fail "Installing tools"

    info "Rebooting vm with xenrt daemon at ${vm_ip}"
    xrt-reboot vm_ip=${vm_ip} || fail "Rebooting VM"

    info Waiting 30 seconds for VM to reboot
    sleep 30

    info "Waiting for xenrt daemon to respond at ${vm_ip}"
    xrt-daemon-wait vm_ip=${vm_ip} || fail "Waiting for xenrt daemon"

    if [[ "$htype" == "xe" ]] ; then
	info "Sanity check: PV driver reporting same IP as arpwatch"
	tools_vm_ip=$(ssh root@${host} "sut/xe-vm-get-ip ${vm_name}")
    
	[[ "$tools_vm_ip" == "$vm_ip" ]] || fail "VM ip doesn't match! $tools_vm_ip != ${vm_ip}"
    fi

    $htype-vm-shutdown vm_ip=${vm_name}
}

# NB: This function will change the following vars in the context of the caller:
# install_vm_name
# install_cd
# install_template
# install_repo
# install_params
function vm-config-get()
{
    local vm_install_os

    $arg_parse

    $requireargs vm_install_os

    case $vm_install_os in
	w2k3)
	    install_cd=w2k3eesp2.iso
	    install_template="Windows Server 2003 (32-bit)"
	    install_vm_name="a0"
	    ;;
	winxp)
	    install_cd=winxpsp3.iso
	    install_template="Windows XP SP3 (32-bit)"
	    install_vm_name="b0"
	    ;;
	vista)
	    install_cd=vistaeesp2.iso
	    install_template="Windows Vista (32-bit)"
	    install_vm_name="c0"
	    ;;
	w2k8)
	    install_cd=ws08sp2-x86.iso
	    install_template="Windows Server 2008 (32-bit)"
	    install_vm_name="d0"
	    ;;
	w2k8-64)
	    install_cd=ws08sp2-x64.iso
	    install_template="Windows Server 2008 (64-bit)"
	    install_vm_name="D0"
	    ;;
	win7)
	    install_cd=win7-x86.iso
	    install_template="Windows 7 (32-bit)"
	    install_vm_name="e0"
	    ;;
	win7-64)
	    install_cd=win7-x64.iso
	    install_template="Windows 7 (64-bit)"
	    install_vm_name="E0"
	    ;;
	centos45)
	    install_repo="http://www.uk.xensource.com/distros/CentOS/4.5/os/i386"
	    install_params="ks=nfs:telos:/linux/distros/auto-install/centos45.cfg"
	    install_template="CentOS 4.5 (32-bit)"
	    install_vm_name="m0"
	    ;;
	demovm)
	    install_template="Demo Linux VM"
	    install_vm_name="n0"
	    ;;
	debian-lenny)
	    install_template="Debian Lenny 5.0 (32-bit)"
	    install_repo="http://debian.uk.xensource.com/debian"
	    install_params="auto-install/enable=true hostname=p0 domain=uk.xensource.com url=http://cosworth.uk.xensource.com/users/ianc/ks/lenny.cfg"
	    install_vm_name="p0"
	    ;;
	rhel48)
	    install_repo="http://www.uk.xensource.com/distros/RHEL/4.8/i386"
	    install_params="ks=nfs:telos:/linux/distros/auto-install/rhel48.cfg"
	    install_template="Red Hat Enterprise Linux 4.8 (32-bit)"
	    install_vm_name="u0"
	    ;;
	rhel60)
	    install_repo="http://www.uk.xensource.com/distros/RHEL/6.0/i386"
	    install_params="ks=http://www.uk.xensource.com/distros/auto-install/rhel60.cfg"
	    install_template="Red Hat Enterprise Linux 6 (32-bit)"
	    install_vm_name="v0"
	    ;;
	rhel56-64)
	    install_repo="http://elijah.uk.xensource.com/distros/RHEL/5.6/x86_64"
	    install_params="ks=http://elijah.uk.xensource.com/distros/auto-install/rhel56-x86_64.cfg"
	    install_template="Red Hat Enterprise Linux 5 (64-bit)"
	    install_vm_name="V0"
	    ;;
	rhel55)
	    install_repo="http://www.uk.xensource.com/distros/RHEL/5.5/i386"
	    install_params="ks=nfs:telos:/linux/distros/auto-install/rhel55.cfg"
	    install_template="Red Hat Enterprise Linux 5 (32-bit)"
	    install_vm_name="v0"
	    ;;
	sles111)
	    install_repo="http://www.uk.xensource.com/distros/SLES/11SP1/i386"
	    install_params="autoyast=http://www.uk.xensource.com/distros/auto-install/sles11sp1.cfg"
	    install_template="SUSE Linux Enterprise Server 11 SP1 (32-bit)"
	    install_vm_name="w0"
	    ;;
	opensolaris)
	    install_cd=sol-10-u9-ga-x86-dvd-jumpstart-32.iso
	    install_template="Solaris 10 (experimental)"
	    install_vm_name="o0"
	    ;;
	*)
	    fail "Unknown config ${vm_install_os}!"
	    ;;
    esac	    
}
