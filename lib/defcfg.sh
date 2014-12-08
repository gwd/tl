# Default configuration options

htype="xl"
ctype="ssh"
cfg_boot_method="pxe"

# Config options specific to Citrix's setup
cfg_host_pwd="xenroot"

cfg_host_install_version="trunk"

cfg_www_local_base="$HOME/public_html/"
cfg_www_url_base="http://files.uk.xensource.com/~${USER}/"

# was pxedir
function cfg-boot-pxe-target-set()
{
    local host
    
    $arg_parse

    $requireargs host USER

    cfg_boot_pxe_target_path=/usr/groups/netboot/${USER}/${host}/test/
}

cfg_xrt_daemon_port=8936


# Stuff relating to booting
cfg_boot_pxe_config_path=$TESTLIB_PATH/../install/
cfg_isosr_path="filer02:/vol/groups/images/autoinstall"
cfg_isosr_mount_point="/misc/iso"


# Timeouts: Give up after waiting
cfg_timeout_boot="600"     # Timeout for a host to boot
cfg_timeout_install="3600" # Timeout for the installer to come up
cfg_timeout_ssh="600"      # Timeout for ssh
cfg_timeout_xapi="600"      # Timeout for xapi
cfg_timeout_shutdown="600"  # Timeout for a host to go down

# Waiting: Sleep to give space for stuff to happen
cfg_wait_powerdown="30"    # Slack to wait for a hard powerdown to take effect

# Functionality
cfg_popup_status=false
cfg_popup_fail=false

