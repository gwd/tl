function quote-array()
{
    local _array
    local _v
    _v=$1

    while eval "[[ -n \"$_v\" ]]" ; do
	echo hi;
    done
}

function xrt-daemon()
{
    #args=($@)

    #quote-array args

    echo "$GWD_TESTLIB_PATH/../viadaemon.py $@"
    $GWD_TESTLIB_PATH/../viadaemon.py $@
}

function xrt-daemon2()
{
    #args=($@)

    #quote-array args

    $arg_parse

    vm-helper-get-ip

    info $GWD_TESTLIB_PATH/../viadaemon.py $vm_ip "${args[@]}"
    $GWD_TESTLIB_PATH/../viadaemon.py $vm_ip "$args"
}

function xrt-daemon-wait()
{
    local timeout
    local interval

    timeout=3600
    interval=10

    $arg_parse

    vm-helper-get-ip

    info Calling wait-for-port host=${vm_ip} port=${cfg_xrt_daemon_port} 

    wait-for-port host=${vm_ip} port=${cfg_xrt_daemon_port} 
}

function xrt-ready()
{
    xrt-daemon-wait interval=1
}

function xrt-shutdown()
{
    $arg_parse

    vm-helper-get-ip

    xrt-daemon -S $vm_ip
}

function xrt-reboot()
{
    local vm_ip

    $arg_parse

    $requireargs vm_ip

    xrt-daemon -S $vm_ip
}

function xrt-copy-file()
{
    # Required variables
    local www_path
    local remote_path
    local filename

    # Overrideable
    local www_base=${cfg_www_local_base}
    local url_base=${cfg_www_url_base}

    $arg_parse

    $requireargs filename remote_path www_base url_base

    vm-helper-get-ip

    if [[ -n "$remote_filename" ]] ; then
	remote_path=${remote_path}${remote_filename}
    else
	remote_path=${remote_path}${filename}
    fi

    # Copy file to www_local_base
    echo cp $local_path/$filename $www_base/$filename
    cp $local_path/$filename $www_base/$filename || return 1
    
    echo xrt-daemon -u ${url_base}/$filename -F "$remote_path" ${vm_ip}
    xrt-daemon -u ${url_base}/$filename -F "$remote_path" ${vm_ip} || fail "Copying tools"

}