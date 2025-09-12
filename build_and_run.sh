#!/bin/sh

set -o pipefail
set -o errexit
set -o nounset

# remove the leading "error: " to match vim's errorformat
pdc source forklift2.pdx 2>&1 | sed 's/^error: //'
open "/Users/a/Developer/PlaydateSDK/bin/Playdate Simulator.app" forklift2.pdx
