function wait-for-online()
{
    $gateway_override

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
    $gateway_override

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
