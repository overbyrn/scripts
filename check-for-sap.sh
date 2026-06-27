#!/usr/bin/env bash

# Examlpe Wrapper Script to Detect for an SAP instance
# Requires helper library: sap-host-detect.sh

. ./sap-host-detect.sh

if sap_host_detect; then
    echo "SAP detected, continue..."
else
    echo "No SAP, exit"
fi

# Example 1 - simple guard
if ! sap_host_detect; then
    echo "No SAP detected on host"
    exit 0
fi

# Example 2 – with custom SAP base path
if sap_host_detect "/sapmnt/usr/sap"; then
    echo "SAP present"
fi

# Example 3 – hard fail if SAP missing
sap_host_detect || {
    echo "ERROR: SAP system not found"
    exit 1
}

