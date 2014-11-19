function xrt-daemon()
{
    echo "$TESTLIB_PATH/../viadaemon.py $@"
    $TESTLIB_PATH/../viadaemon.py "$@"
}

function xrt-daemon2()
{
    $arg_parse

    tgt-helper addr

    info $TESTLIB_PATH/../viadaemon.py $tgt_addr "${args[@]}"
    $TESTLIB_PATH/../viadaemon.py $tgt_addr "${args[@]}"
}

function xrt-daemon-wait()
{
    local timeout
    local interval

    timeout=3600
    interval=10

    $arg_parse

    tgt-helper addr

    info Calling wait-for-port host=${tgt_addr} port=${cfg_xrt_daemon_port} 
    wait-for-port host=${tgt_addr} port=${cfg_xrt_daemon_port} 
}

function xrt-ready()
{
    xrt-daemon-wait interval=1
}

function xrt-shutdown()
{
    $arg_parse

    tgt-helper addr

    xrt-daemon -S $tgt_addr
}

function xrt-reboot()
{
    local vm_ip

    $arg_parse

    tgt-helper addr

    xrt-daemon -S $tgt_addr
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

    tgt-helper addr

    if [[ -n "$remote_filename" ]] ; then
	remote_path=${remote_path}${remote_filename}
    else
	remote_path=${remote_path}${filename}
    fi

    # Copy file to www_local_base
    echo cp $local_path/$filename $www_base/$filename
    cp $local_path/$filename $www_base/$filename || return 1
    
    echo xrt-daemon -u ${url_base}/$filename -F "$remote_path" ${tgt_addr}
    xrt-daemon -u ${url_base}/$filename -F "$remote_path" ${tgt_addr} || fail "Copying tools"

}