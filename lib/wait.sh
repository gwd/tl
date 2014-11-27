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
    local cond="appear"

    local time=0

    # Read and process [varname]=[value] options
    $arg_parse

    $requireargs host timeout port interval

    $invert && cond="disappear"

    echo -n "INFO Probing host ${host} port ${port} timeout ${timeout}" 1>&2
    if retry eval "echo | nc -z -w 1 ${host} ${port} >& /dev/null" ; then
	info "Port ${port} ${cond}ed after ${retry_time}"
	return 0
    else
	info "Timed out waiting for port ${port} to ${cond} on ${host}" 
	return 1
    fi
}

function wait-for-boot()
{
    local host;

    # Read and process [varname]=[value] options
    $arg_parse

    cfg_override cfg_timeout_boot timeout     ; eval $ret_eval
    cfg_override cfg_timeout_ssh  timeout_ssh ; eval $ret_eval

    $requireargs host

    wait-for-online ${host} || return 1

    info "Attempting ssh connect to ${host} timeout ${s_timeout}"
    wait-for-port host=${host} timeout=${cfg_timeout_ssh} interval=1 port=22 || return 1

    status "Host ${host} responding to ssh." 
    return 0
}

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

    $requireargs host

    info "Waiting for ${host} to stop responding to pings"
    if retry invert=true eval "ping -c 1 -W ${ping_timeout} ${host} >& /dev/null" ; then
     	status "Host ${host} offline"
     	return 0
    else
     	echo "ERROR Timeout waiting for ${host} to go offline"å
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

    $requireargs host

    wait-for-offline ${host} || return 1
    wait-for-boot ${host} || return 1

    return 0
}
