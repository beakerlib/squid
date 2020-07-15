#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/squid/Library/squid
#   Description: Library for squid testing
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

# Include Beaker environment
[ -e /usr/bin/rhts-environment.sh ] && . /usr/bin/rhts-environment.sh
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGES=${PACKAGES:-"squid"}
PHASE=${PHASE:-"Test"}

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport squid/squid"
    rlPhaseEnd

    if [[ ${PHASE} =~ "Test" ]]; then
        rlPhaseStartTest "Test service start and stop"
            rlRun "echo Quack\! > /var/www/html/duck" 0 "Creating test file"
            rlRun "rlServiceStart httpd" 0 "Starting HTTP server"
            rlRun "squidStart" 0 "Starting Squid server"

            rlRun -s "curl -4 -v -x $(hostname):3128 $(hostname)/duck" 0 \
                "Downloading file via Squid proxy"
            rlAssertGrep 'Quack!' ${rlRun_LOG}

            rlRun "squidStop" 0 "Stopping Squid server"
            rlRun "rlServiceStop httpd" 0 "Stopping HTTP server"
        rlPhaseEnd
    fi

rlJournalPrintText
rlJournalEnd
