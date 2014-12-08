# VM-boot
function workload-vm-boot-set-testtype()
{
    testtype="vm-boot"
}

# ddk-build
function workload-ddk-build-install()
{
    local viadaemon 
    viadaemon=$TESTLIB_PATH/../viadaemon.py

    $arg_parse

    tgt-helper addr

    info Inserting ddk CD
    ssh-cmd host=${host_addr} "xl cd-insert ${tgt_name} hdc /images/autoinstall/w2k3eesp1_ddk.iso" \
	|| fail "inserting CD"
    info Sleep 5
    sleep 5  
    info Running ddk installation
    ${viadaemon} $tgt_addr "d:\\x86\\kitsetup.exe /dc:\\winddk /g\"Build Environment\" /g\"Network Samples\""
    #./viadaemon -L ddk-build.bat -F "C:\\winddk\\ddk-build.bat" $tgt_addr ;
    xrt-copy-file local_path=$TESTLIB_PATH/../perf/ filename=ddk-build.bat remote_path="C:\\\\winddk\\\\"
}

function workload-ddk-build()
{
    $arg_parse

    xrt-daemon2 \"c:\\WINDDK\\ddk-build.bat\"
}

function workload-ddk-build-set-testtype()
{
    testtype="runtime"
}


function workload-sqlio()
{
    $arg_parse

    tgt-helper addr

    $TESTLIB_PATH/../viadaemon.py $tgt_addr "\"C:\\Program Files\\SQLIO\\sqlio.exe\" -kW -o64 -b256 -s600" 
    #xrt-daemon2 "\"C:\\Program\ Files\\SQLIO\\sqlio.ex\""
}

# Workloads for testing
function workload-null-set-testtype()
{
    testtype="null"
}

function workload-fail-runtime()
{
    #testcmd="ssh root@kodo2 \"echo Args: ${args[@]} && false\""
    echo "Args: ${args[@]}" && false
}

function workload-fail-runtime-set-testtype()
{
    testtype="runtime"
}

# Setup: xenbuild/xen-unstable.hg in a buildable state, and all build requirements
function workload-hello()
{
    $arg_parse

    tgt-helper addr

    ssh-cmd "echo hello"
}

function workload-hello-set-testtype()
{
    testtype="runtime"
}

function time-test()
{
   $arg_parse

   $requireargs resultbase

    echo time ${args[@]}
   /usr/bin/time -f %e -o ${resultbase}.time --quiet ${args[@]} >> ${resultbase}.output
   # NB: $? passed up by default
}

function time-ssh-cmd()
{
   $arg_parse

   tgt-helper addr

   $requireargs cmd resultbase

   tempfile=$(ssh-cmd "mktemp /tmp/xenlib-timeXXXXXX")

   info tempfile $tempfile

   info cmd $cmd

   ssh-cmd "/usr/bin/time -f %e -o$tempfile bash -c \"$cmd\"" >> ${resultbase}.output

   scp root@$tgt_addr:$tempfile ${resultbase}.time

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

function runtest-runtime()
{
    local ret
    local result
    local testcmd
    local time

    $arg_parse

    $requireargs resultbase workload

    ret=0

    # Get the test command
    #workload-${workload}-set-testcmd ${args[@]}

    info "Staring ${workload} at time" `date`;
    time-command workload-run > ${resultbase}.output || ret=1
    time="$ret_time"
    echo "$time" >> $resultbase.time

    #echo "Controller-ts" `date` > ${resultbase}.output ;
    #eval "/usr/bin/time -f %e -o ${resultbase}.time --quiet $testcmd >> ${resultbase}.output"
    #ret=$?
    #echo "Controller-ts" `date` >> ${resultbase}.output ;

    if [[ "$ret"="0" ]] ; then
	info Time $time
	result="succeeded"
    else
	result="failed"
    fi
    info "${workload} on ${vmip} $result at time" `date`
    eval "return $ret"
}

function mytest()
{
    args=("1" "2")

    while [[ -n "${args}" ]] ; do
	echo ${args}
	pop args
    done
}

function runtest-null()
{
    echo Null: $@ tgt_name $tgt_name
}

function runtest()
{
    local testtype
 
    $arg_parse

    echo runtest ${args[@]}

    if [[ -z "$workload" ]] ; then
	local workload
    	workload=${args[0]}
     	pop args;
    fi

    workload-${workload}-set-testtype

    # workload and test-specific args inherited
    runtest-$testtype "${args[@]}"
    # NB: $? passed up by default
}

function boot-shutdown()
{
    local ret
    local result
    local testcmd

    $arg_parse

    tgt-helper

    info "Staring ${tgt_name} at time" `date`;

    time-command vm-start || return 1
    info Create: $ret_time
    [[ -n "${resultbase}" ]] && echo $ret_time > ${resultbase}.create

    ret=0

    ${args[@]} || ret=1

    time-command vm-shutdown || return 1
    info Shutdown : $ret_time
    [[ -n "${resultbase}" ]] && echo $ret_time > ${resultbase}.shutdown

    eval "return $ret"
}

function deb-pkg-install()
{
    $arg_parse

    $requireargs host path deb

    # Verify existence of new deb
    info Verifying existence of ${path}/${deb}.deb
    if ! ssh root@${host} "[[ -e \"${path}/${deb}.deb\" ]]" ; then
	echo "Cannot find deb: ${path}/${deb}.deb"
	return 1
    fi

    # remove old deb
    info Finding old deb
    debname=$(ssh root@${host} "dpkg -l | grep xen-upstream | awk '{print \$2;}'")
    if [[ "$?" != "0" ]] ; then
	error "Finding old deb"
	return 1
    fi

    if [[ -n "$debname" ]] ; then
	if ! ssh root@${host} "dpkg -r $debname" ; then
	    error "Cannot remove old xen"
	    return 1
	fi
    else
	info "No xen packages installed"
    fi


    ssh root@${host} "rm -f /boot/xen.gz"

    # Install new deb
    info Installing new deb
    if ! ssh root@${host} "dpkg -i --force-architecture ${path}/${deb}.deb" ; then
	echo "Install failed"
	return 1
    fi

    if ! ssh root@${host} "ldconfig" ; then
	echo "ldconfig failed"
	return 1
    fi

    # Check for good /boot/xen.gz
    ssh root@${host} "cd /boot ; [[ -e xen.gz ]] || ln -s xen-*.gz xen.gz ; ls -l xen*.gz"

    if ! ssh root@${host} "[[ -e /boot/xen.gz ]]" ; then
	echo "Can't find xen.gz -- install failed"
	return 1
    fi

    status Changed xen to package ${deb}
}

function xendeb()
{
    $arg_parse

    $requireargs host path deb

    # Inherits host, path, deb
    deb-pkg-install || return 1

    # Inherits host
    host-reboot || return 1

    #info Letting host settle for 30s
    #sleep 30

    "${args[@]}" || return 1
    # $? passed back
}

#
# Workload model:
#
# Function name workload-${workload}-${subfunction}
#
# -set-testtype: 
#  Set the "testtype" variable.  Types:
#   - "runtime" will cause the test to be timed.
#
# -setup: 
#  Params distro (c6) and wdir (working directory to install).
#  Set up everything and get the workload ready to run.
#
# [none]:
#  Actually run the test.  Extra args can be used.
#

function workload-run()
{
    $arg_parse

    $requireargs workload

    default test_workload_dir "/workloads" ; $default_post

    tgt-helper addr

    wdir="${test_workload_dir}/${workload}"

    ssh-cmd -t "cd $wdir; hl workload-${workload}"
}

# Run on a system with perf-setup
function workload-setup()
{
    $arg_parse

    $requireargs workload distro

    default test_workload_dir "/workloads" ; $default_post

    tgt-helper addr

    wdir="${test_workload_dir}/${workload}"

    ssh-cmd "rm -rf ${wdir}"

    ssh-cmd "mkdir -p ${wdir}"

    [[ -e "./testconfig" ]] && scp ./testconfig root@${tgt_addr}:${wdir}

    tl-sync

    ssh-cmd -t "cd $wdir; hl workload-${workload}-setup distro=${distro} wdir=${wdir}"
}

# Run on a basic system to make it suitable to run workload-setup 
function perf-setup()
{
    $arg_parse

    default test_workload_dir "/workloads" ; $default_post

    tgt-helper addr

    tl-install

    wdir="${test_workload_dir}"    

    ssh-cmd "mkdir -p ${wdir}"
}

# Form:  iterate count=foo resultbase=bar [command]
function iterate()
{
    local vals
    local i
    local nextbase

    $arg_parse

    $requireargs count resultbase

    # There has GOT to be a better way...
    i="echo {1..${count}}"
    vals=$(eval $i)

    for i in $vals ; do
	nextbase=$resultbase.i$i
	info Running iteration $nextbase
	${args[0]} resultbase=$nextbase "${args[@]:1}" || break
    done
}

# Form: varset var=varname vals=a,b,c [tags=A,B,C] [command]
function varset()
{
    local vals
    local tags
    local nextbase
    local tag

    $arg_parse
   
    $requireargs var vals resultbase

    parse-comma-array vals $vals

    if [[ -n "$tags" ]] ; then
	parse-comma-array tags $tags
    else
	tags=("${vals[@]}")
    fi

    echo var $var values ${vals[@]} tags ${tags[@]}
 
    while [[ -n "${vals[@]}" ]] ; do
	val=${vals[0]};
	tag=${tags[0]};
	nextbase=$resultbase.$tag
	info Running varset $nextbase
	${args[0]} resultbase=$nextbase ${var}=${val} "${args[@]:1}" || break
	pop vals
	pop tags
    done
}