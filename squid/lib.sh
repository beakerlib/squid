#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /CoreOS/squid/Library/squid
#   Description: Library for Squid testing
#   Author: Martin Frodl <mfrodl@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   library-prefix = squid
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

squid/squid - Library for Squid testing

=head1 DESCRIPTION

Collection of utilities which make Squid testing easier.

=head2 USAGE

To use this library in a test, add the following line to its C<Makefile>:

	@echo "RhtsRequires:    library(squid/squid)" >> $(METADATA)

In C<runtest.sh>, import the library as follows:

	rlImport squid/squid

Be sure to import the library B<before> checking installed packages with
C<rlAssertRpm>.

The rest is quite straightforward:

	rlLog "Tested package: ${squidPACKAGE}"
	rlLog "Configuration file: ${squidCONF}"

	rlRun "squidStart" 0 "Starting Squid proxy"
	rlRun "squidRestart" 0 "Restarting Squid proxy"
	rlRun "squidStop" 0 "Stopping Squid proxy"

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 VARIABLES

Below is the list of global variables.

=over

=item squidPACKAGE

Name of Squid package detected from the C<PACKAGES> variable. Possible values
are C<squid> (default) or C<squid34>.

=item squidCONF

Path to Squid's configuration file.

=back

=cut

export squidPACKAGE=${squidPACKAGE:-"squid"}
export squidCONF=${squidCONF:-"/etc/squid/squid.conf"}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 squidStart

Starts squid service and waits for the configured port(s) to start listening.

=cut

squidStart() {
    # Initially, try simply starting the service. When this action fails,
    # chances are that some of the previous tests left the system in a broken
    # state. Perform all the necessary cleanup operations and try to start the
    # service again. Only when this second attempt fails too, exit with a
    # non-zero status.
    if ! rlServiceStart squid; then
        __squidCleanup
        if ! rlServiceStart squid; then
            return 1
        fi
    fi

    # Sometimes squid takes some time to start up. We therefore want to wait
    # until all the ports configured to listen are actually listening.
    local PORTS=$(awk '/^\s*https?_port/ { print $2 }' ${squidCONF})
    for PORT in ${PORTS}; do
        rlRun "rlWaitForSocket ${PORT}" 0 \
            "Waiting for squid to start listening on port ${PORT}"
    done
}

true <<'=cut'
=pod

=head2 squidStop

Stop C<squid> service and performs a cleanup. This includes deleting the PID
file, lock file and shared memory segments.

=cut

squidStop() {
    rlServiceStop squid
    __squidCleanup
}

true <<'=cut'
=pod

=head2 squidRestart

Restart C<squid> service; equivalent to C<squidStop> + C<squidStart>.

=cut

squidRestart() {
    squidStop
    squidStart
}

__squidCleanup() {
    # Kill all running squid processes
    while pgrep squid; do
        rlLogInfo "Squid is still running, killing it violently"
        pkill -9 squid
        sleep 5
    done

    # Wait for all sockets used by squid to be closed
    local PORTS=$(awk '/^\s*https?_port/ { print $2 }' ${squidCONF})
    for PORT in ${PORTS}; do
        # TODO: once BZ#1388422 is fixed, uncomment the following two lines and
        # delete the rest of the loop's body:
        # rlRun "rlWaitForSocket --close ${PORT}" 0 \
        #     "Waiting for squid to stop listening on port ${PORT}"
        PORT_OPEN="ss -tan | grep -q :${PORT}"
        rlRun "rlWatchdog 'while ${PORT_OPEN}; do sleep 1; done' 120" \
            0 "Waiting for squid to stop listening on port ${PORT}"
    done

    # Delete PID file
    if [[ -e /var/run/squid.pid ]]; then
        rlRun "rm -f /var/run/squid.pid" 0 "Removing Squid's PID file"
    fi

    # Delete lock file
    if [[ -e /var/lock/subsys/squid ]]; then
        rlRun "rm -f /var/lock/subsys/squid" 0 "Removing Squid's lock file"
    fi

    # Delete shared memory segments
    local SHM=(/dev/shm/squid-*.shm)
    if [[ -e ${SHM} ]]; then
        SHM="${SHM[@]}"
        rlRun "rm -f ${SHM}" 0 "Removing Squid's shared memory segments"
    fi
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Execution
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 EXECUTION

This library supports direct execution. When run as a task, phases
provided in the PHASE environment variable will be executed.
Supported phases are:

=over

=item Test

Run the self test suite.

=back

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Verification
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   When the library is first loaded, detect the squid package which is being
#   tested from the PACKAGES variable. If this detection fails for some reason,
#   exit with 1.

squidLibraryLoaded() {
    if [[ -n ${BASEOS_CI_COMPONENT+x} ]]; then
        rlLogInfo "BASEOS_CI_COMPONENT set, overriding PACKAGES"
        PACKAGES="${BASEOS_CI_COMPONENT}"
    fi

    if [[ -z ${PACKAGES+x} ]]; then
        rlFail "Variable PACKAGES is not set"
        return 1
    fi

    squidPACKAGE="$(grep -o squid[0-9]* <<< ${PACKAGES})"

    if [[ -z ${squidPACKAGE} ]]; then
        rlLogWarning "No Squid package found in PACKAGES, defaulting to 'squid'"
        squidPACKAGE="squid"
    fi

    rlPass "Squid library loaded successfully"
    rlLogInfo "squidPACKAGE=${squidPACKAGE}"
    rlLogInfo "squidCONF=${squidCONF}"

    return 0
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Martin Frodl <mfrodl@redhat.com>

=back

=cut
