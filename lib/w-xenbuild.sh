function workload-xenbuild-set-testtype()
{
    testtype="runtime"
}

function workload-xenbuild()
{
    $arg_parse

    default xenbuild_make_args "-j 8" ; $default_post

    cd xen.git 
    
    make -C xen clean 

    make XEN_TARGET_ARCH=x86_64 ${xenbuild_make_args} xen
}

function workload-xenbuild-setup()
{
    $arg_parse

    $requireargs distro wdir

    case $distro in
	c6)
	    ## Minimum needed for just building the hypervisor bit
	    yum -y install git gcc

	    ## Everything needed to do a full build
	    # yum -y groupinstall "Development Tools" 
	    # yum -y install transfig wget tar less texi2html libaio-devel dev86 glibc-devel e2fsprogs-devel gitk iasl xz-devel bzip2-devel
	    # yum -y install pciutils-libs pciutils-devel SDL-devel libX11-devel gtk2-devel bridge-utils PyXML mercurial texinfo
	    # yum -y install libidn-devel yajl yajl-devel ocaml ocaml-findlib ocaml-findlib-devel python-devel uuid-devel libuuid-devel openssl-devel
	    # yum -y install glibc-devel.i686
	    ;;
	*)
	    fail "Unknown distro: $distro"
	    ;;
    esac

    cd $wdir
    
    git clone git://drall.uk.xensource.com:9419/git://xenbits.xen.org/xen.git xen.git

    cd xen.git

    git checkout -b dummy RELEASE-4.4.1
}