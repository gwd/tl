function boot-config-pxe()
{
    local fn="boot-config-pxe-xen-binary"
    # Required parameters
    local host
    local boot_config
    # Optional parameters
    local pxe_target
    local pxe_config

    pxe_config=${cfg_boot_pxe_config_path}

    $arg_parse

    if [[ -z "$pxe_target" ]] ; then
	[[ -z "${cfg_boot_pxe_target_path}"
		&& -n "${host}" ]] &&
	cfg-boot-pxe-target-set host=${host}
	pxe_target=${cfg_boot_pxe_target_path}
    fi

    $requireargs pxe_target pxe_config boot_config

    if [[ -n "${xen_binary_base}" ]] ; then
	echo INFO copying xen-${boot_config}.gz binary
	${dry_run} || cp -f ${xen_binary_base}/xen-${boot_config}.gz ${pxe_target}/xen.gz || fail "Copy failed"
    fi

    if [[ -n "${pxe_config}" ]] ; then
	echo INFO copying pcfg-${boot_config}
	${dry_run} || cp -f ${pxe_config}/pcfg-${boot_config} ${pxe_target}/pxeconfig || fail "Copy failed"
    fi
}

function boot-config-cleanup-pxe()
{
    local fn="boot-config-pxe-xen-binary"
    # Optional args
    local pxe_target
    local host

    $arg_parse

    if [[ -z "$pxe_target" ]] ; then
	[[ -z "${cfg_boot_pxe_target_path}"
		&& -n "${host}" ]] &&
	cfg-boot-pxe-target-set host=${host}
	pxe_target=${cfg_boot_pxe_target_path}
    fi

    $requireargs pxe_target

    ${dry_run} || rm -f ${pxe_target}/pxeconfig || fail "Deleting pxeconfig"
}

function boot-config-host-xen-binary()
{
    local fn="boot-config-host-xen-binary"
    # Required parameters
    local host
    local boot_config

    # Optional arguments with default
    local boot_dir="/boot"

    $arg_parse

    $requireargs host xen_binary_base boot_config

    echo INFO copying xen-${boot_config}.gz binary to host ${host}
    ${dry_run} || scp ${xen_binary_base}/xen-${boot-config}.gz root@${host}:${boot_dir}/xen.gz || fail "Copy failed"
}

function boot-config-cleanup-host-xen-binary()
{
    return;
}

function boot-config()
{
    local fn="boot-config"
    # Required parameters
    local boot_config
    # Optional args
    local boot_method="$cfg_boot_method"

    # Local args
    local -a bargs

    $arg_parse

    $requireargs boot_method boot_config

    parse-comma-array bargs ${boot_method_args}

    echo "Boot method args: ${bargs[@]}"

    boot-config-${boot_method} boot_config=${boot_config} ${bargs[@]}
}

function boot-config-cleanup()
{
    local fn="boot-config"
    # Optional args
    local boot_method="$cfg_boot_method"
    # Local args
    local -a bargs

    $arg_parse

    $requireargs boot_method

    if [[ -n "${boot_method_args}" ]] ; then
	parse-comma-array bargs ${boot_method_args}
    fi

    echo "Boot method args: ${bargs[@]}"

    boot-config-cleanup-${boot_method} ${bargs[@]}
}
