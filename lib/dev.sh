# Functions related to development
function tl-sync()
{
    local pushpath="."

    $arg_parse

    tgt-helper addr

    if ! [[ -e ./hl ]] ; then
	[[ -n "${TESTLIB_PATH}" ]] || fail "Must be run from the test repo directory"
	pushpath="${TESTLIB_PATH}/.."
    fi

    pushd "$pushpath"

    rsync -avz --delete --exclude=.git ./ root@${tgt_addr}:tl/

    popd
}

# Functions related to development
function tl-install()
{
    $arg_parse

    tgt-helper addr

    # FIXME: Centos-specific
    ssh-cmd "yum install -y rsync"
    
    tl-sync

    ssh-cmd "mkdir -p /root/bin"

    ssh-cmd "ln -sf /root/tl/hl /root/bin/hl"
    
    ssh-cmd -- "echo export PATH=\\\$PATH:/root/bin >> .bashrc"

    ssh-cmd "hl echo hi" || fail "hl install failed"
}
