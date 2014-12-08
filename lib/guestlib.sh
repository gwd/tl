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

    if [[ -z "$vm_mac" ]] ; then
	fail "Couldn't get mac"
    fi

    # host inherited
    ret_vm_ip=$(ssh-cmd "tl/sut/arp-get-ip ${vm_mac}")

    info $vm_name ip $ret_vm_ip
}

function vm-helper()
{
    fail "Function no longer in use!"
}

function vm-helper-get-ip()
{
    vm-helper ip
}

# Make it easy to unify commands for nested virtualization, and for hosts
# 
# tgt=a[:b[:c...]]
#
# - tgt_name = addr of last entry
# - if more than one entry exists, host_addr = addr of second-to-last entry
# - if 'addr' is passed, tgt_addr will be an ssh-able hostname for the last entry.

function tgt-helper()
{
    if [[ "$_stored_tgt" == "$tgt" ]] ; then
	if [[ -z "$1" && -n "$tgt_name" ]] ; then
	    unset tgt_addr
	    return 0
	elif [[ -n "$1" && -n "$tgt_addr" ]] ; then
	    return 0
	fi
    fi

    _stored_tgt="$tgt"

    local fn
    local stack

    fn="$1"

    
    $requireargs tgt

    unset host_addr
    unset tgt_addr

    parse-separator-array ":" stack $tgt

    tgt_name="${stack[0]}"
    pop stack

    while [[ -n "${stack[0]}" ]] ; do
	# Transtate tgt_name into an addr and put it in host_addr.
	# If we're at the top level, addr is just tgt_name.
	# If we're below that, look up the tgt_addr on the host.
	if [[ -z "${host_addr}" ]] ; then
	    host_addr="${tgt_name}"
	else
	    info Looking up host ${host_addr} vm_name ${tgt_name}
	    vm-wait-ip host=${host_addr} vm_name=${tgt_name}
	    host_addr=$ret_vm_ip
	fi
	tgt_name=${stack[0]}
	pop stack
    done

    if [[ "$fn" == "addr" ]] ; then
	if [[ -z "${host_addr}" ]] ; then
	    tgt_addr="${tgt_name}"
	else
	    info Looking up host ${host_addr} vm_name ${tgt_name}
	    vm-wait-ip host=${host_addr} vm_name=${tgt_name}
	    tgt_addr=$ret_vm_ip
	fi
    fi
}

# "Returns" domid
function vm-wait()
{
    $arg_parse

    tgt-helper

    $htype-vm-wait
}

TESTLIB_HELP+=($'vm-ip\t\t[vm=VMPATH|host=HOST (vm_name=|vm_ip=)]')
function tgt-addr()
{
    $arg_parse

    tgt-helper addr

    echo ${tgt_addr}
}

function vm-wait-shutdown()
{
    $arg_parse

    tgt-helper

    $requireargs htype

    $htype-vm-wait-shutdown
}

TESTLIB_HELP+=($'vm-start\t[vm=VMPATH|host=HOST (vm_name=|vm_ip=)] [extra args]')
function vm-start()
{
    $arg_parse

    $requireargs htype

    tgt-helper

    $htype-vm-start host=$host_addr vm_name=$tgt_name "${args[@]}"
}

# *** WARNING ***
# This function at the moment BEHAVES DIFFERENTLY than tgt-ssh.
# 
# It does not accept a tgt.  But it will accept the following in order:
# - host
# - tgt_addr
# - host_addr
#
# So you can always specify host=[blah]
#
# But you can also run "tgt-helper" (without "addr") to have it run host_addr,
# or run "tgt-helper addr" to have it run tgt_addr.
function ssh-cmd()
{
    $arg_parse

    if [[ -z "${host}" ]] ; then
	if [[ -n "${tgt_addr}" ]] ; then
	    host="${tgt_addr}"
	elif [[ -n "${host_addr}" ]] ; then
	    host="${host_addr}"
	fi
    fi

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

    tgt-helper addr

    ssh-cmd "shutdown -h now"
}

function display-tunnel()
{
    local lport
    local display
    local ssh_user

    $arg_parse

    [[ -z "${host}" ]] && host="${host_addr}"

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

function vm-console()
{
    $arg_parse

    $requireargs htype

    $htype-vm-console
}


function acpi-shutdown()
{
    $arg_parse

    tgt-helper
    
    ssh-cmd "xl trigger ${tgt_name} power" 
}


function ssh-ready()
{
    $arg_parse

    tgt-helper addr

    info "Attempting ssh connect to addr ${tgt_addr} timeout ${cfg_timeout_ssh}"
    if ! wait-for-port host=${tgt_addr} timeout=${cfg_timeout_ssh} interval=1 port=22 ; then
	error "Waiting for SSH to appear"
	return 1;
    fi
}

function vm-ssh()
{
    fail "Function no longer in use!"
}

function tgt-ssh()
{
    # NB ssh_htype should be used by tgt-helper, ssh_vtype for the guest

    $arg_parse

    tgt-helper addr

    info "Attempting ssh connect to target ${tgt_addr} type ${ssh_htype} timeout ${cfg_timeout_ssh}"
    if ! wait-for-port host=${tgt_addr} timeout=${cfg_timeout_ssh} interval=1 port=22 ; then
	error "Waiting for SSH to appear"
	return 1;
    fi


    case "$ssh_vtype" in
	ubuntu)
	    [[ -z "$ssh_user" ]] && ssh_user="xenuser"
	    ssh -t $ssh_user@${tgt_addr} "sudo bash"
	    ;;
	*)
	    [[ -n "$ssh_user" ]] || ssh_user="root"
	    ssh $ssh_user@${tgt_addr} "${args[@]}"
	    ;;
    esac
}

# This is a bit hackish; requires adding the following line to your /etc/rc.local:
#  touch /tmp/.finished-booting
# and making sure that /tmp is deleted before ssh starts.
function tgt-ready()
{
    $arg_parse

    tgt-helper addr

    default timeout 600 ; $default_post

    ssh-ready

    info "Waiting for ${tgt_addr} to be ready"
    retry ssh-cmd "[[ -e /dev/shm/tl-finished-booting ]]"

    status "Target ${tgt_addr} ready."
    return 0
}

function vm-shutdown()
{
    $arg_parse

    $requireargs ctype

    default wait "true" ; $default_post
    default acpi "false" ; $default_post

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
