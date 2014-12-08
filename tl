#!/bin/bash
#set -x

# Include your defaults
if [[ -e "./testconfig" ]] ; then
    . ./testconfig
elif [[ -e "$HOME/.testconfig" ]] ; then
    . $HOME/.testconfig
fi

# To use this library, include the following line:
[[ -z "$TESTLIB_PATH" ]] && TESTLIB_PATH="$HOME/tl/lib"

# Then as many as the sub-libraries as you need
. ${TESTLIB_PATH}/core.sh
. ${TESTLIB_PATH}/dev.sh
. ${TESTLIB_PATH}/wait.sh
. ${TESTLIB_PATH}/xllib.sh
. ${TESTLIB_PATH}/xrtlib.sh
. ${TESTLIB_PATH}/bootlib.sh
. ${TESTLIB_PATH}/guestlib.sh
. ${TESTLIB_PATH}/perflib.sh
. ${TESTLIB_PATH}/tblib.sh
. ${TESTLIB_PATH}/defcfg.sh


# And do your own thing rather than running commands
# I suggest defining a "main" function of your own and running it like this.
cmdline "$@"
