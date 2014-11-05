#!/bin/bash

if [[ -z "$GWD_TESTLIB_PATH" ]] ; then
    echo ERROR GWD_TESTLIB_PATH not set
    exit 1
fi

CTLIB_RUN_CMD=false
${GWD_TESTLIB_REMOTE:=false}

[[ -n "$GWD_LIB" ]] || CTLIB_RUN_CMD=true

GWD_LIB=1

TESTLIB_HELP=()

# Common argument-parsing code common to all functions
arg_parse_cmd=\
"local -a args;
local _a;
local _vn;
local _vv;


while [[ -n \"\$@\" ]] ; do
    _vn=\${1%%=*};
    _vv=\"\${1##*=}\";
    if ! [[ \"\$_vn\" = \"\$_vv\" ]] ; then
	eval \"local \$_vn\";
	eval \$_vn=\"\$_vv\";
        shift;
    else
	break;
    fi; 
done"

arg_parse_cmd=\
"local -a args;
local _a;
local _vn;
args=($@);

while [[ -n \"\${args[@]}\" ]] ; do
    _a=\"\${args[0]}\";       
    if [[ \`expr match \${_a} '.*='\` != \"0\" ]] ; then
	args=(\${args[@]:1});
        _vn=\${_a%%=*};
	eval \"local \$_vn\";
	eval \"\$_a\";
    else
	break;
    fi; 
done"

arg_parse_cmd=\
"local -a args;
local _a;
local _vn;
args=(\"\$@\");

while [[ -n \"\${args[@]}\" ]] ; do
    _a=\"\${args[0]}\";       
    if [[ \`expr match \${_a} '.*='\` != \"0\" ]] ; then
	args=(\${args[@]:1});
        _vn=\${_a%%=*};
	eval \"local \$_vn\";
	eval \"\$_a\";
    else
	break;
    fi; 
done"

arg_parse_cmd=\
"local -a args;
local _a;
local _vn;
local _m;

_m=true;

for _a in \"\$@\" ; do
    if \$_m && [[ \`expr match \"\${_a}\" '.*='\` != \"0\" ]] ; then
        _vn=\${_a%%=*};
	eval \"local \$_vn\";
	eval \"\$_a\";
    else
        _m=false
        args+=(\"\$_a\");
    fi; 
done"

arg_parse_cmd=\
"local -a args;
local _a;
local _vn;
local _m;

_m=true;

for _a in \"\$@\" ; do
    case \"${_a}\" in
    *=*)
        if \${_m} ; then
            _vn=\${_a%%=*};
	    eval \"local \$_vn\";
            echo \"Variable \$_a\";
	    eval \"\$_a\";
        fi ;
        ;;
    *)
        _m=false;
        echo \"Args \$_a\";
        args+=(\"\$_a\");
        ;;
    esac ;
done"

arg_parse_cmd=\
"local -a args;
local _a;
local _vn;
local _m;

_m=true;

for _a in \"\$@\" ; do
    false && echo \"Evaluating \${_a} [[ \"\${_a/=}\" = \"\${_a}\" ]]\";
    if \$_m && [[ \"\${_a/=}\" != \"\${_a}\" ]] ; then
        false && echo Parameter;
        _vn=\${_a%%=*};
        eval \"local \$_vn\";
        eval \"\$_a\";
    else
        false && echo Argument;
        _m=false;
        args+=(\"\$_a\");
    fi;
done"

arg_parse="eval $arg_parse_cmd"

function pop()
{
    local _var
    _var="$1";

    eval "${_var}=(\"\${${_var}[@]:1}\")"
}

. $GWD_TESTLIB_PATH/xllib.sh
. $GWD_TESTLIB_PATH/xelib.sh
. $GWD_TESTLIB_PATH/xrtlib.sh
. $GWD_TESTLIB_PATH/bootlib.sh
. $GWD_TESTLIB_PATH/guestlib.sh
. $GWD_TESTLIB_PATH/perflib.sh
. $GWD_TESTLIB_PATH/defcfg.sh

# Load extra config stuff
if [[ -n "$GWD_TESTLIB_CONFIG" ]] ; then
    . $GWD_TESTLIB_CONFIG
fi

# Sensible defaults, can be overridden
host_powerdown_wait=30

status_popup=${cfg_popup_status}
fail_popup=${cfg_popup_fail}
dry_run=false

function fail()
{
   echo FATAL $@
   $fail_popup && (zenity --info --text="$@" &)
   [[ -n "$fail_cleanup" ]] && $fail_cleanup
   exit 1
}

function info()
{
   echo INFO $@ 1>&2
}

function error()
{
   echo ERROR $@ 1>&2
}

function status()
{
   echo STATUS $@ 1>&2
   $status_popup && (zenity --info --text="$@" &)
   return 0
}

function parse-separator-array()
{
    local _pca_array_var="$2"
    local _pca_list="$3"
    local -a _pca_internal
    local OLD_IFS

    OLD_IFS=${IFS}
    IFS="$1"
    _pca_internal=($_pca_list)
    IFS="${OLD_IFS}"

    eval "${_pca_array_var}=(${_pca_internal[@]})"
}

function parse-comma-array()
{
    parse-separator-array "," "$1" "$2"
}

function test-parse-comma-array()
{
    local vars
    local out
    local i

    vars="a,b,c"
    parse-comma-array out $vars

    for i in ${out[@]} ; do
	echo "X $i";
    done
}

function test-parse-colon-array()
{
    local vars
    local out
    local i

    vars="kodo2:c6-test:c6-vm"
    parse-separator-array ":" out $vars

    for i in ${out[@]} ; do
	echo "X $i";
    done
}


# function parse-comma-array()
# {
#     local _pca_array_var="$1"
#     local _pca_list="$2"
#     local -a _pca_internal
#     local OLD_IFS

#     OLD_IFS=${IFS}
#     IFS=","
#     _pca_internal=($_pca_list)
#     IFS="${OLD_IFS}"

#     eval "${_pca_array_var}=(${_pca_internal[@]})"
# }

# Parse a configuration array, then find out how to reset it
function parse-config-array()
{
    local _pcfga_array_var="$1"
    local _pcfga_reset_array_var="$2"
    local _pcfga_list="$3"
    local -a _pcfga_internal
    local -a _pcfgr_internal
    local _j
    local _varname
    local _value

    echo "About to parse list"
    parse-comma-array _pcfga_internal ${_pcfga_list}

    echo Reset values
    for _j in ${_pcfga_internal[@]} ; do
	_varname=$(expr match "${_j}" '\([^=]*\)')
	_value=$(eval echo \$$_varname)
	echo " $_varname=$_value"
	_pcfgr_internal=(${_pcfgr_internal[@]} "${_varname}=${_value}")
    done

    eval "${_pcfga_array_var}=(${_pcfga_internal[@]})"
    eval "${_pcfga_reset_array_var}=(${_pcfgr_internal[@]})"
}

# Pass in either the current function name, or the name of the script
requireargs="eval _func=\"\$FUNCNAME\" ; eval [[ -n \\\"\$_func\\\" ]] || _func=\$0 ; eval _require-args \$_func"

function _require-args()
{
    local _arg
    local _args
    local fail_popup

    _args=($@)

    fail_popup=false

    for _arg in ${_args[@]:1} ; do
	eval "[[ -n \"\${$_arg}\" ]] || fail \"${_args[0]}: Missing $_arg\""
    done
}

# Used to make a local cfg_ variable overriding the global one if
# a given argument is given; otherwise, set the local variable to the
# global one.
#
# For example, you can pass isosr_path to host-install, and it will
# create a local variable cfg_isosr_path and set it to iso-sr, so that
# host-install-post will get that value without having to pass it in;
# Alternately, you can set iso_sr to cfg_isosr_path.
#
# Use like this: cfg_override [global_var] [local_var] ; eval $ret_eval
function cfg_override()
{
    unset ret_eval
    if eval "[[ -n \"\$$2\" ]]" ; then
	ret_eval="local $1=\$$2"
    else
	ret_eval="$2=\$$1"
    fi
}


# To be called by top-level programs.  Specific features:
# - Will not create local variable
# - Will special-case 'cfg' and process it right away
function parse-cmd-args()
{
    args=($@)
    
    while [[ -n "${args[@]}" ]] ; do
	a=${args[0]};       # Use first element
	
	args=(${args[@]:1}) # Element processed, pop it off
	
	if [[ `expr match ${a} '^[^=].*='` != "0" ]] ; then
	    eval "$a" || fail "Evaluation failed"
	else
	    fail "Unexpected arg format: $a"
	fi
        # Process a config in-line, so that elements can be overriden by subsequent args
	if [[ `expr match ${a} 'cfg='` != "0" ]] ; then
	    [[ -n "${cfg}" ]] || fail "Detected cfg, but failed to set!"
	    . ${cfg}
	fi
    done
}

function time-command()
{
    local start
    local end

    unset ret_time

    start=$(date +%s.%N)
    "$@" || return 1
    end=$(date +%s.%N)

    ret_time=$(echo "$end-$start" | bc)
}

function time-command()
{
    local start
    local end

    unset ret_time

    $arg_parse

    start=$(date +%s.%N)
    echo Timing command "${args[@]}"
    "${args[@]}" || return 1
    end=$(date +%s.%N)

    ret_time=$(echo "$end-$start" | bc)
}

function vm-pin-list()
{
    # Parameters with local-only defaults
    local verbose=false

    # Really local parameters
    local -a vms
    local -a ips
    local vm_list
    local IFS

    # Read and process [varname]=[value] options
    $arg_parse

    # Extra processing
    if [[ -n "${vmlist}" ]] ; then
	IFS=","
	vms=($vmlist)
    fi
    if [[ -n "${vmset}" ]] ; then
	parse-vm-file ${vmset}.vm-list.txt vms ips
    fi

    if [[ -n "${vmcount}" ]] ; then
	vm_list="${vms[@]:0:${vmcount}}"
    else
	vm_list="${vms[@]}"
    fi

    # Make sure we have the minimum
    $requireargs host vm_list bitmap vmax

    info "Setting affinity of VMs ${vm_list} on host ${host} to ${bitmap}"

    time (
	for vm in $vm_list ; do 
	    ${verbose} && info "-- Setting affinity $vm" ; 
	    ssh root@${host} "for vcpu in {0..${vmax}} ; do ${verbose} && echo v\${vcpu} ; /opt/xensource/debug/xenops affinity_set -domid \$(/tmp/htlib.sh domid-from-vm $vm) -vcpu \${vcpu} -bitmap ${bitmap} ; done" ; 
	    ssh root@${host} "for vcpu in {0..${vmax}} ; do ${verbose} && echo v\${vcpu} ; /opt/xensource/debug/xenops affinity_get -domid \$(/tmp/htlib.sh domid-from-vm $vm) -vcpu \${vcpu} ; done" ; 
	done )

}

function vm-vcpu-count-list()
{
    # Passable parameters
    local verbose=false

    # Really local parameters
    local -a vms
    local -a ips
    local vm_list
    local uuid_test
    local IFS

    # Read and process [varname]=[value] options
    $arg_parse

    # Extra processing
    if [[ -n "${vmlist}" ]] ; then
	IFS=","
	vms=($vmlist)
    fi
    if [[ -n "${vmset}" ]] ; then
	parse-vm-file ${vmset}.vm-list.txt vms ips
    fi

    if [[ -n "${vmcount}" ]] ; then
	vm_list="${vms[@]:0:${vmcount}}"
    else
	vm_list="${vms[@]}"
    fi

    # Make sure we have the minimum
    $requireargs host vm_list vcpu_count

    info "Setting vcpu count of VMs ${vm_list} on host ${host} to ${vcpu_count}"

    time (
	# Make sure all of the VMs are in the "off" state
	for vm in $vm_list ; do 
	    ${verbose} && info "-- Checking that vm $vm is off" ; 
	    uuid_test="d3adb33f"
	    ${dry_run} || uuid_test=$(ssh root@${host} "xe vm-list --minimal name-label=${vm} power-state=halted")
	    [[ -n "$uuid_test" ]] || fail "VM $vm running!"
	done 
	for vm in $vm_list ; do 
	    ${verbose} && info "-- Setting vcpu count for vm $vm" ; 
	    ${dry_run} || uuid_test=$(ssh root@${host} "xe vm-list --minimal name-label=${vm} power-state=halted")
	    [[ -n "$uuid_test" ]] || fail "Failed to get uuid for VM $vm!"
	    # Always set VCPUs-at-startup to 1 first, so there aren't any constraint check problems when reducing vcpu count
	    ${dry_run} || ssh root@${host} "xe vm-param-set uuid=${uuid_test} VCPUs-at-startup=1 VCPUs-max=${vcpu_count} VCPUs-at-startup=${vcpu_count}" || fail "Setting VCPUs"
	done )

}

function wait-for-online()
{
    local host;
    local timeout="${cfg_timeout_boot}"
    local ping_output

    # Read and process [varname]=[value] options
    $arg_parse

    host=${args[0]}

    $requireargs host

    info "Pinging ${host}"
    ${dry_run} || ping_output=$(ping -c 1 -i 5 -q -w ${timeout} ${host})

    if [[ "$?" != "0" ]] ; then
	echo "ERROR Timed out pinging ${host} after ${timeout} seconds: ${ping_output}"
	return 1
    fi
}

function wait-for-port()
{
    local host
    local port
    local invert=false # false = wait to appear, true = wait to disappear

    local time=0
    local bang='!';

    # Read and process [varname]=[value] options
    $arg_parse

    $requireargs host timeout port interval

    $invert && bang="";

    if ! ${dry_run} ; then
	echo -n "INFO Probing host ${host} port ${port} timeout ${timeout}"
	while eval "$bang echo | nc -z -w 1 ${host} ${port} >& /dev/null" && [[ $time -lt $timeout ]] ; do
	    echo -n "."
	    time=$(($time+$interval))
	    sleep $interval
	done
	echo
    fi

    if ! [[ $time -lt $timeout ]] ; then
	if $invert ; then
	    echo "INFO Timed out waiting for port ${port} to close on ${host}" 
	else
	    echo "ERROR Timed out waiting for port ${port} to open on ${host}" 
	fi
	return 1
    else
	if $invert ; then
	    echo "INFO Port ${port} disappeared after ${time}"
	else
	    echo "INFO Port ${port} appeared after ${time}"
	fi
	return 0
    fi

}

# Override if remote
if $GWD_TESTLIB_REMOTE ; then
function wait-for-port()
{
    ssh elijah '$GWD_TESTLIB_PATH/gwd_testlib.sh' wait-for-port "$@"
}
fi

function wait-for-boot()
{
    local host;

    # Read and process [varname]=[value] options
    $arg_parse

    cfg_override cfg_timeout_boot timeout     ; eval $ret_eval
    cfg_override cfg_timeout_ssh  timeout_ssh ; eval $ret_eval

    # FIXME Require host=foo
    host=${args[0]}

    $requireargs host

    wait-for-online ${host} || return 1

    info "Attempting ssh connect to ${host} timeout ${s_timeout}"
    wait-for-port host=${host} timeout=${cfg_timeout_ssh} interval=1 port=22 || return 1

    status "Host ${host} responding to ssh." 
    return 0
}

function wait-for-host()
{
    local host
    local sp_orig

    # Read and process [varname]=[value] options
    $arg_parse

    # FIXME
    host=${args[0]}

    $requireargs htype host
    
    # Temporarily disable pop-ups for status reports
    sp_orig="${status_popup}"
    status_popup="false"
    wait-for-boot ${host} || return 1
    status_popup="${sp_orig}"

    time-command ${htype}-host-ready host=${host} || return 1
    info Host ready after $ret_time

    return 0
}

#
# wait-for-offline host
# Ping a host every second until it doesn't respond.
function wait-for-offline()
{
    # Required args
    local host;
    # Optional args
    local timeout="${cfg_timeout_shutdown}"
    # local
    local ping_timeout=5
    local interval=1
    local wait_time=0

    # Read and process [varname]=[value] options
    $arg_parse

    host=${args[0]}

    $requireargs host

    info "Waiting for ${host} to stop responding to pings"
    while ! $dry_run && ping -c 1 -W ${ping_timeout} ${host} >& /dev/null && [[ ${wait_time} -lt ${timeout} ]] ; do
	sleep ${interval}
	wait_time=$((${wait_time}+${interval}))
    done

    if $dry_run || [[ ${wait_time} -lt ${timeout} ]] ; then
	status "Host ${host} offline"
	return 0
    else
	echo "ERROR Timeout waiting for ${host} to go offline"
	return 1
    fi
}

function wait-for-reboot()
{
    local host;

    # Read and process [varname]=[value] options
    $arg_parse

    cfg_override cfg_timeout_boot timeout     ; eval $ret_eval
    cfg_override cfg_timeout_ssh  timeout_ssh ; eval $ret_eval

    # FIXME Require host=foo
    host=${args[0]}

    $requireargs host

    wait-for-offline ${host} || return 1
    wait-for-boot ${host} || return 1

    return 0
}

function loop-exec()
{
    $arg_parse

    $requireargs host

    wait-for-boot ${host}

    ${args[@]}

    while wait-for-reboot ${host} ; do
	${args[@]}
    done
}


function host-reboot()
{
    local wait

    wait=true

    $arg_parse

    $requireargs host

    if ! ssh root@${host} "reboot" ; then
	info "Reboot failed"
	return 1
    fi

    # Return right now if we don't want to wait
    $wait || return 0

    if ! time-command wait-for-offline ${host} ; then
	error Timed out waiting for host offline
	return 1
    fi
    info Offline in $ret_time

    if ! time-command wait-for-online ${host} ; then
	info "Boot failed -- trying manual power cycle"
	xenuse --off ${host}
	sleep 5
	xenuse --on ${host}
	if ! time-command wait-for-online ${host} ; then
	    error Timed out waiting for host offline
	    return 1
	fi
    fi
    info Came online in $ret_time

    info "Attempting ssh connect to ${host} timeout ${s_timeout}"
    if ! wait-for-port host=${host} timeout=${cfg_timeout_ssh} interval=1 port=22 ; then
	error "Waiting for SSH to appear"
	return 1;
    fi

    status "Host ${host} responding to ssh." 

    if ! time-command $htype-host-ready host=${host} ; then
	error "Waiting for host to be ready"
	return 1;
    fi
    status Host ready after $ret_time
}

#
# Functions related to host management
# 
function host2pxe()
{
    local host="$1"
    local host_output;

    # FIXME use gethostbyname to get stuff in /etc/hosts
    host_output=$(host $1)
    if [[ $? != 0 ]] ; then
	echo "ERROR host failed"
	return 1
    fi
    RET=$(echo ${host_output} | perl -ne 'if(/ ([0-9]*)\.([0-9]*)\.([0-9]*)\.([0-9]*)$/) {\
               printf "%02X%02X%02X%02X\n",$1,$2,$3,$4; }')
    return 0%
}

function host-install-post-debian()
{
    local host

    $arg_parse

    info "Updating"
    ssh root@${host} "apt-get update && apt-get upgrade"

    info "Setting up bridging"
    ssh root@${host} "apt-get install -y bridge-utils" || fail "Installing bridge-utils"
    tmp_interfaces=$(mktemp)
    # FIXME: Allow interface number to be configurable
    cat > $tmp_interfaces <<EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug eth0
auto xenbr0
iface eth0 inet manual
iface xenbr0 inet dhcp
    bridge_ports regex vif.* noregex eth0
EOF
    scp $tmp_interfaces root@${host}:/etc/network/interfaces
    rm -f $tmp_interfaces

    info "Installing libc6 library"
    ssh root@${host} "apt-get install -y libc6-xen"

    # FIXME: Deal with 64-bit install
    info "Installing Xen kernel"
    ssh root@${host} "apt-get install -y linux-image-xen-686"


    # FIXME: This should be a separate set-up 
    info "Installing build dependencies"
    ssh root@${host} "apt-get install -y build-essential zlib1g-dev gawk gettext python-dev libssl-dev libx11-dev git-core curl ncurses-dev bcc iasl libpci-dev uuid-dev ocaml libyajl-dev libaio-dev pkg-config libsdl-dev ocaml-findlib bison stgit libpixman-1-dev"

    info "Installing xen-tools"
    ssh root@${host} "apt-get install --no-install-recommends -y xen-tools"

    info "Cloning and building Xen repo"
    ssh root@${host} "git clone git://xenbits.xensource.com/xen.git xen.git && cd xen.git && ./configure"

    #info "Installing .deb"
    #ssh root@${host} "dpkg -i xen-unstable.hg/dist/xen-*.deb"
    #ssh root@${host} "update-rc.d xencommons defaults"

    info "Updating grub"
    #ssh root@${host} "dpkg-divert --divert /etc/grub.d/08_linux_xen --rename /etc/grub.d/20_linux_xen"
    ssh root@${host} "update-grub"
    # Find out best fit for booting Xen, set that as default
    ssh root@${host} "echo GRUB_DEFAULT=\\\"\$(perl -ne 'if(/^menuentry .(.*XEN xen)[^ ]/) { print \"\$1\n\"; exit 0; }' /boot/grub/grub.cfg)\\\" >> /etc/default/grub"
    ssh root@${host} "echo  GRUB_CMDLINE_LINUX_DEFAULT=\\\"\\\" >> /etc/default/grub"

    ssh root@${host} "update-grub"

    # Just storing this here for later:
    # xen-create-image --dir=/vm --dhcp --hostname=pv --dist=squeeze --password=xenroot --genpass=0 --pygrub --mirror=http://debian.uk.xensource.com/debian/
}

function install-sandbox()
{
    local host

    $arg_parse

}

function host-install-post()
{
    # Required arguments
    local host
    local host_pwd
    local isosr_path
    local isosr_mnt
    local version

    $arg_parse

    cfg_override cfg_host_pwd host_pwd ; eval $ret_eval
    cfg_override cfg_isosr_path isosr_path ; eval $ret_eval
    cfg_override cfg_isosr_mount_point isosr_mnt ; eval $ret_eval

    $requireargs host htype host_pwd upgrade version

    info "Installing ssh keys"
    $dry_run || sshpass -p ${host_pwd} ssh-copy-id root@${host} || fail "Installing ssh keys"

    info "Copying sut scripts"
    $dry_run || scp -r sut root@${host}: || fail "Copying sut scripts"

    info "Tweaking /boot for easy hv replacement"
    $dry_run || ssh root@${host} "file=/boot/xen.gz ; cpath=\$(readlink -f \$file) ; if [[ \$cpath != \$file ]] ; then echo Replacing link \$file with path \$cpath ; rm -f \$file ; cp \$cpath \$file ; fi"

    if [[ -n "${pvconsole_log_template}" ]] ; then
	info "Setting pv guest consoles to ${pvconsole_log_template}"
	$dry_run || ssh root@${host} "xenstore-write /local/logconsole/@ ${pvconsole_log_template}"
    fi

    if [[ "$htype" == "xl" ]] ; then
	info "Adding 'touch /tmp/.finished-booting' to /etc/rc.local"
	$dry_run || ssh root@${host} "grep -v \"^exit 0\" /etc/rc.local > /tmp/rc.local && mv /tmp/rc.local /etc/rc.local"
	$dry_run || ssh root@${host} "echo \"touch /tmp/.finished-booting\" >> /etc/rc.local"
	$dry_run || ssh root@${host} "chmod +x /etc/rc.local"
    elif [[ "$htype" == "xe" ]] ; then
	${htype}-host-ready host=${host} || return 1
    fi


    if ! $upgrade ; then
	# FIXME: Set up iso path for xl guests as well
	if [[ "$htype" == "xe" ]] ; then
	    if [[ -n "${isosr_path}" ]] ; then
		info "Setting up autoinstall sr ${isosr_path}"
		$dry_run || ssh root@${host} "xe-mount-iso-sr ${isosr_path}" || fail "Mounting autoinstall SR"
		info "Waiting for isosr scan to complete"
		$dry_run || sleep 10
	    fi
	elif [[ "$htype" == "xl" ]] ; then
	    if [[ -n "${isosr_path}" ]] ; then
		info "Mounting isosr"
		$dry_run || ssh root@${host} "mkdir -p ${isosr_mnt} && echo '${isosr_path} ${isosr_mnt} nfs defaults,ro 0 0' > /etc/fstab && mount ${isosr_mnt}" || fail "Mounting isosr"
	    fi
	fi
    fi

    if [[ "$htype" == "xe" ]] ; then
	xe-host-fake-license host=${host} version=${version}
    fi

    case $version in
	debian-squeeze)
	    host-install-post-debian host=${host}
	    ;;
    esac
}

function host-install-start()
{
    # Required arguments
    local host
    local version # FIXME should we use cfg_host_install_version here?

    # Optional arguments with defaults
    local host_powerdown_wait="${cfg_wait_powerdown}"
    local hard_power_cycle
    # FIXME Make work; make permanent; make global
    #local pvconsole_log_template="/var/run/console/console.%d.log"
    local boot_method

    # Other args
    # FIXME: Make these locally overrideable
    #local pxedir
    #local pxe_config_base

    # Really local
    local action
    local shutdown_command
    local boot_method_args

    $arg_parse

    # Local config overrides
    cfg_override cfg_boot_method boot_method ; eval $ret_eval
    cfg_override cfg_isosr_path isosr_path ; eval $ret_eval
    cfg_override cfg_host_pwd host_pwd ; eval $ret_eval

    $requireargs host version upgrade

    [[ "${cfg_boot_method}" == "pxe" ]] || fail "$0: boot_method must be pxe!"

    [[ -n "${cfg_boot_pxe_target_path}" ]] || cfg-boot-pxe-target-set host=${host}
    
    if ! [[ -e ${cfg_boot_pxe_target_path} ]] ; then
	echo ERROR: ${cfg_boot_pxe_target_path} does not exist!
	exit 1
    fi
    
    # If we're upgrading, don't hard power cycle by default.
    # If we're installing fresh, hard power cycle by default.
    if $upgrade ; then
	action=upgrade
	[[ -n "${hard_power_cycle}" ]] || hard_power_cycle=false
    else
	action=install
	[[ -n "${hard_power_cycle}" ]] || hard_power_cycle=true
    fi

    info Setting boot config to ${action}-${version}
    boot-config host=${host} boot_config=${action}-${version} || fail "Boot config failed!"
    fail_cleanup="boot-config-cleanup"

    # Put in a function
    if ! ${hard_power_cycle} ; then
	info Trying to reboot host ${host} via ssh
	if ssh root@${host} "reboot" ; then
#	if ssh root@${host} "xe host-reboot host=${host}" ; then
	    info Reboot command succeeded.  Waiting for host ${host} to shutdown.
	    if ! wait-for-offline ${host} ; then
		info Waiting for host ${host} to go offline failed.  Falling back to hard power cycle
		hard_power_cycle=true;
	    else
		info Host ${host} powered down.
	    fi
	else
	    #fail "xe host-reboot failed!"
	    info Reboot command failed on host ${host}.  Falling back to hard power cycle
	    hard_power_cycle=true;
	fi
    fi

    if ${hard_power_cycle} ; then
	info Powering off host ${host} with xenuse
	$dry_run || xenuse --off ${host} || fail "Shutting down host!"
	info Waiting ${host_powerdown_wait} seconds to let machine cool down
	$dry_run || sleep ${host_powerdown_wait}

	info Powering on host ${host} with xenuse
	$dry_run || xenuse --on ${host} || fail "Powering on host!"
    fi

    # Some boxen with lots of cards can take 20 minutes just to do the networking...
    info Waiting for ${action} to start...
    wait-for-online timeout=3600 ${host} || fail "Waiting for installer to come online"

    unset fail_cleanup

    info Setting boot config to local
    boot-config boot_config=local || fail "Boot config failed!"

    info Waiting for ${action} to end
    wait-for-offline timeout=1200 ${host} || fail "Waiting for installer to shutdown"

    info Waiting for host to boot
    # NB: not wait-for-host because we don't have the ssh keys installed yet.  Waiting below...
    wait-for-boot ${host} || fail "Waiting for Xenserver to boot"
}

function host-install()
{
    # Required arguments
    local host
    local version # FIXME should we use cfg_host_install_version here?
    local upgrade=false

    $arg_parse

    $requireargs host version upgrade

    host-install-start host=${host} version=${version}

    host-install-post host=${host} version=${version}
}

function host-install-old()
{
    # Required arguments
    local host
    local version # FIXME should we use cfg_host_install_version here?

    # Optional arguments with defaults
    local host_powerdown_wait="${cfg_wait_powerdown}"
    local upgrade=false
    local hard_power_cycle
    # FIXME Make work; make permanent; make global
    local pvconsole_log_template="/var/run/console/console.%d.log"

    # Other args
    # FIXME: Make these locally overrideable
    #local pxedir
    #local pxe_config_base

    # Really local
    local action
    local shutdown_command
    local boot_method_args

    $arg_parse

    # Local config overrides
    cfg_override cfg_boot_method boot_method ; eval $ret_eval
    cfg_override cfg_isosr_path isosr_path ; eval $ret_eval
    cfg_override cfg_host_pwd host_pwd ; eval $ret_eval

    $requireargs host version upgrade

    [[ "${cfg_boot_method}" == "pxe" ]] || fail "$0: boot_method must be pxe!"

    [[ -n "${cfg_boot_pxe_target_path}" ]] || cfg-boot-pxe-target-set host=${host}
    
    if ! [[ -e ${cfg_boot_pxe_target_path} ]] ; then
	echo ERROR: ${cfg_boot_pxe_target_path} does not exist!
	exit 1
    fi
    
    # If we're upgrading, don't hard power cycle by default.
    # If we're installing fresh, hard power cycle by default.
    if $upgrade ; then
	action=upgrade
	[[ -n "${hard_power_cycle}" ]] || hard_power_cycle=false
    else
	action=install
	[[ -n "${hard_power_cycle}" ]] || hard_power_cycle=true
    fi

    info Setting boot config to ${action}-${version}
    boot-config host=${host} boot_config=${action}-${version} || fail "Boot config failed!"
    fail_cleanup="boot-config-cleanup"

    # Put in a function
    if ! ${hard_power_cycle} ; then
	info Trying to reboot host ${host} via ssh
	if ssh root@${host} "reboot" ; then
#	if ssh root@${host} "xe host-reboot host=${host}" ; then
	    info Reboot command succeeded.  Waiting for host ${host} to shutdown.
	    if ! wait-for-offline ${host} ; then
		info Waiting for host ${host} to go offline failed.  Falling back to hard power cycle
		hard_power_cycle=true;
	    else
		info Host ${host} powered down.
	    fi
	else
	    #fail "xe host-reboot failed!"
	    info Reboot command failed on host ${host}.  Falling back to hard power cycle
	    hard_power_cycle=true;
	fi
    fi

    if ${hard_power_cycle} ; then
	info Powering off host ${host} with xenuse
	$dry_run || xenuse --off ${host} || fail "Shutting down host!"
	info Waiting ${host_powerdown_wait} seconds to let machine cool down
	$dry_run || sleep ${host_powerdown_wait}

	info Powering on host ${host} with xenuse
	$dry_run || xenuse --on ${host} || fail "Powering on host!"
    fi

    # Some boxen with lots of cards can take 20 minutes just to do the networking...
    info Waiting for ${action} to start...
    wait-for-online timeout=3600 ${host} || fail "Waiting for installer to come online"

    unset fail_cleanup

    info Setting boot config to local
    boot-config boot_config=local || fail "Boot config failed!"

    info Waiting for ${action} to end
    wait-for-offline timeout=1200 ${host} || fail "Waiting for installer to shutdown"

    info Waiting for host to boot
    # NB: not wait-for-host because we don't have the ssh keys installed yet.  Waiting below...
    wait-for-boot ${host} || fail "Waiting for Xenserver to boot"

    host-install-post host=${host} version=${version}
}

function parse-vm-file()
{
    local _pvf_file="$1"
    local _pvf_name_list_var="$2"
    local _pvf_ip_list_var="$3"
    local _pvf_tmp
    
    echo reading ${_pvf_file}

    [[ -e ${_pvf_file} ]] || fail "Cannot find file ${_pvf_file}"

    _pvf_tmp=$(awk '{print $1;}' ${_pvf_file})
    eval ${_pvf_name_list_var}="($_pvf_tmp)"
    _pvf_tmp=$(awk '{print $2;}' ${_pvf_file})
    eval ${_pvf_ip_list_var}="($_pvf_tmp)"
}

function parse-vm-test()
{
    local vms
    local ips

    parse-vm-file $1 vms ips

    echo ${vms[$2]}
    echo ${ips[$2]}
}

function xe-vm-tools-shutdown-all()
{
    local fn="vm-tools-shutdown-all"
    # Parameters
    local host

    # Local vars
    local uuid_list
    
    # Read and process [varname]=[value] options
    $arg_parse

    $requireargs host

    ${dry_run} || uuid_list=$(ssh root@${host} "xe vm-list --minimal power-state=running is-control-domain=false")

    if [[ -n "${uuid_list}" ]] ; then
	echo Found running VMs, shutting down...
	${dry_run} || ssh root@${host} "xe vm-shutdown --multiple power-state=running" || fail "VM shutdown failed!"
    else
	echo No running VMs found.
    fi

    return 0
}

function vm-shutdown-list()
{
    # Stuff
    local fn="vm-boot-list"
    # Passable parameters
    local host
    #local vmlist
    local vmset
    local vmlist
    local vmcount
    local iosched
    local popup="false"
    local force="true"

    # Really local parameters
    local -a vms
    local -a ips
    local vm_list
    local IFS
    local shutdown_extra
    local timeout
    local shutdown_interval

    # Read and process [varname]=[value] options
    $arg_parse

    # Extra processing
    if [[ -n "${vmlist}" ]] ; then
	IFS=","
	vms=($vmlist)
    fi
    if [[ -n "${vmset}" ]] ; then
	parse-vm-file ${vmset}.vm-list.txt vms ips
    fi

    if [[ -n "${vmcount}" ]] ; then
	vm_list="${vms[@]:0:${vmcount}}"
	ip_list="${ips[@]:0:${vmcount}}"
    else
	vm_list="${vms[@]}"
	ip_list="${ips[@]}"
    fi

    $requireargs host vm_list htype

    [[ "${htype}" != "xl" ]] || [[ -n "${ip_list}" ]] || fail "${fn}: no ips!"

    # Copy "extra" wait-for-shutdown parameters
    [[ -n "${timeout}" ]] && shutdown_extra="$shutdown_extra timeout=${timeout}"
    [[ -n "${shutdown_interval}" ]] && shutdown_extra="$shutdown_extra shutdown_interval=${shutdown_interval}"

    info "Shutting down VMs: ${vm_list}"
    time (
	for vm in $vm_list ; do 
	    ${htype}-vm-shutdown host=${host} vm=${vm}
	done ; 

	for vm in $vm_list ; do 
	    ${htype}-vm-wait-shutdown host=${host} vm=${vm}  $shutdown_extra \
		|| ! ${force} || ${htype}-vm-force-shutdown host=${host} vm=${vm}
	done
	)

    return 0
}

function vm-boot-list()
{
    # Stuff
    local fn="vm-boot-list"
    # Passable parameters
    local host
    #local vmlist
    local vmset
    local vmlist
    local vmcount
    local iosched
    local popup="false"

    # Really local parameters
    local -a vms
    local -a ips
    local vm_list
    local IFS

    # Read and process [varname]=[value] options
    $arg_parse

    # Extra processing
    if [[ -n "${vmlist}" ]] ; then
	IFS=","
	vms=($vmlist)
    fi
    if [[ -n "${vmset}" ]] ; then
	parse-vm-file ${vmset}.vm-list.txt vms ips
    fi

    if [[ -n "${vmcount}" ]] ; then
	vm_list="${vms[@]:0:${vmcount}}"
	ip_list="${ips[@]:0:${vmcount}}"
    else
	vm_list="${vms[@]}"
	ip_list="${ips[@]}"
    fi

    $requireargs host vm_list htype

    [[ "${htype}" != "xl" ]] || [[ -n "${ip_list}" ]] || fail "${fn}: no ips!"

    info "Starting VMs: ${vm_list}"
    time (
	for vm in $vm_list ; do 
	    ${htype}-vm-start host=${host} vm=${vm}
	done ; 

	# xe uses vm name, xl uses ip address
	if [[ "${htype}" == "xe" ]] ; then
	    for vm in $vm_list ; do 
		${htype}-vm-wait-for-boot host=${host} vm=${vm}
	    done
	elif [[ "${htype}" == "xl" ]] ; then
	    for vmip in $ip_list ; do 
		${htype}-vm-wait-for-boot host=${host} ip=${vmip}
	    done
	fi
	)

    return 0
}

function test-host-prep()
{
    # Passable parameters
    local host
    #local vmlist
    local vmset
    local vmlist
    local vmcount
    local iosched
    local popup="false"

    # Really local parameters
    local vm_boot_params

    # Read and process [varname]=[value] options
    $arg_parse

    # Arguments to pass on
    # FIXME: Audit to see if we need to pass these on
    if [[ -n "${host}" ]] ; then
	vm_boot_params="${vm_boot_params} host=${host}"
    fi

    if [[ -n "${vmlist}" ]] ; then
	vm_boot_params="${vm_boot_params} vmlist=${vmlist}"
    fi

    if [[ -n "${vmset}" ]] ; then
	vm_boot_params="${vm_boot_params} vmset=${vmset}"
    fi

    if [[ -n "${vmcount}" ]] ; then
	vm_boot_params="${vm_boot_params} vmcount=${vmcount}"
    fi

    # Make sure we have the minimum
    $requireargs host

    info "Prepping ${host}"
	
    wait-for-xenserver ${host} || fail "Boot failed!"

    if [[ -n "${iosched}" ]] ; then
	info "Setting scheduler to ${iosched}"
	${dry_run} || ssh root@${host} "echo ${iosched} > /sys/block/sda/queue/scheduler" || fail "Setting io scheduler"
    fi

    vm-boot-list ${vm_boot_params} || fail "Booting VMs"

    status "${host} ready to rumble"

    return 0
}

function help()
{
    for i in "${TESTLIB_HELP[@]}" ; do
	echo "$i"
    done
}

## Unit test individual functions
function main()
{
    local cmd;

    if [[ "$#" -eq "0" ]] ; then
	echo "Usage: $0 function-name [arguments...]"
	exit 1
    fi

    # We want to be able to parse variables at the beginning before executing commands
    #info Running $1
    #"$@" || exit 1

    $arg_parse
    info Running "${args[0]}"
    "${args[0]}" "${args[@]:1}" || exit 1

    if ! [[ -z "$RET" ]] ; then
	echo $RET
    fi
}

# Only run main if this is not being included as a library
if $CTLIB_RUN_CMD ; then
    main "$@"
fi
