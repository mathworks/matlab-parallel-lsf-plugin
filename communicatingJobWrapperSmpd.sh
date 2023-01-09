#!/bin/sh
# This wrapper script is intended to be submitted to LSF to support
# communicating jobs.
#
# This script uses the following environment variables set by the submit MATLAB code:
# PARALLEL_SERVER_CMR         - the value of ClusterMatlabRoot (may be empty)
# PARALLEL_SERVER_MATLAB_EXE  - the MATLAB executable to use
# PARALLEL_SERVER_MATLAB_ARGS - the MATLAB args to use
#
# The following environment variables are forwarded through mpiexec:
# PARALLEL_SERVER_DECODE_FUNCTION     - the decode function to use
# PARALLEL_SERVER_STORAGE_LOCATION    - used by decode function
# PARALLEL_SERVER_STORAGE_CONSTRUCTOR - used by decode function
# PARALLEL_SERVER_JOB_LOCATION        - used by decode function

# Copyright 2006-2022 The MathWorks, Inc.

# If PARALLEL_SERVER_ environment variables are not set, assign any
# available values with form MDCE_ for backwards compatibility
PARALLEL_SERVER_CMR=${PARALLEL_SERVER_CMR:="${MDCE_CMR}"}
PARALLEL_SERVER_MATLAB_EXE=${PARALLEL_SERVER_MATLAB_EXE:="${MDCE_MATLAB_EXE}"}
PARALLEL_SERVER_MATLAB_ARGS=${PARALLEL_SERVER_MATLAB_ARGS:="${MDCE_MATLAB_ARGS}"}

# Create full paths to mw_smpd/mw_mpiexec if needed
FULL_SMPD=${PARALLEL_SERVER_CMR:+${PARALLEL_SERVER_CMR}/bin/}mw_smpd
FULL_MPIEXEC=${PARALLEL_SERVER_CMR:+${PARALLEL_SERVER_CMR}/bin/}mw_mpiexec
SMPD_LAUNCHED_HOSTS=""

###################################
## CUSTOMIZATION MAY BE REQUIRED ##
###################################
# This script assumes that SSH is set up to work without passwords between
# all nodes on the cluster.
# You may wish to modify SSH_COMMAND to include any additional ssh options that
# you require.
SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

#########################################################################################
# manipulateHosts carries out the functions of both chooseSmpdHosts and
# chooseMachineArg - it is convenient to calculate both properties together
# since they both involve parsing the LSB_MCPU_HOSTS environment variable as set
# by LSF.
manipulateHosts() {
    # Make sure we don't execute the body of this function more than once
    if [ "${SMPD_HOSTS:-UNSET}" = "UNSET" ] ; then
        echo "Calculating SMPD_HOSTS and MACHINE_ARG"

        # LSB_MCPU_HOSTS is a series of hostnames and numbers, we need to pick
        # out just the names for the SMPD_HOSTS argument, and also count the
        # number of different hosts in use for mpiexec's "-hosts" argument.
        isHost=1
        SMPD_HOSTS=""
        NUM_PM_HOSTS=0

        # Loop over every entry in LSB_MCPU_HOSTS
        for x in ${LSB_MCPU_HOSTS}
          do
          if [ ${isHost} -eq 1 ] ; then
              # every other entry is a hostname
              SMPD_HOSTS="${SMPD_HOSTS} ${x}"
              NUM_PM_HOSTS=`expr 1 + ${NUM_PM_HOSTS}`
          fi
          isHost=`expr 1 - ${isHost}`
        done
        MACHINE_ARG="-hosts ${NUM_PM_HOSTS} ${LSB_MCPU_HOSTS}"
    fi
}

#########################################################################################
# Work out where we need to launch SMPDs given our hosts file - defines
# SMPD_HOSTS
chooseSmpdHosts() {
    manipulateHosts
}

#########################################################################################
# Work out which port to use for SMPD
chooseSmpdPort() {
    # Use LSF's LSB_JOBID to calculate the port
    SMPD_PORT=`expr ${LSB_JOBID} % 10000 + 20000`
}

#########################################################################################
# Work out how many processes to launch - set MACHINE_ARG
chooseMachineArg() {
    manipulateHosts
}

#########################################################################################
# Shut down SMPDs and exit with the exit code of the last command executed
cleanupAndExit() {
    EXIT_CODE=${?}
    echo ""
    echo "Stopping SMPD on ${SMPD_LAUNCHED_HOSTS} ..."
    for host in ${SMPD_LAUNCHED_HOSTS}
    do
        echo ${SSH_COMMAND} $host \"${FULL_SMPD}\" -shutdown -phrase MATLAB -port ${SMPD_PORT}
        ${SSH_COMMAND} $host \"${FULL_SMPD}\" -shutdown -phrase MATLAB -port ${SMPD_PORT}
    done
    echo "Exiting with code: ${EXIT_CODE}"
    exit ${EXIT_CODE}
}

#########################################################################################
# Use ssh to launch the SMPD daemons on each processor
launchSmpds() {
    # Launch the SMPD processes on all hosts using SSH
    echo "Starting SMPD on ${SMPD_HOSTS} ..."
    for host in ${SMPD_HOSTS}
      do
      echo ${SSH_COMMAND} $host \"${FULL_SMPD}\" -s -phrase MATLAB -port ${SMPD_PORT}
      ${SSH_COMMAND} $host \"${FULL_SMPD}\" -s -phrase MATLAB -port ${SMPD_PORT}
      ssh_return=${?}
      if [ ${ssh_return} -ne 0 ] ; then
          echo "Launching smpd failed for node: ${host}"
          exit 1
      else
          SMPD_LAUNCHED_HOSTS="${SMPD_LAUNCHED_HOSTS} ${host}"
      fi
    done
    echo "All SMPDs launched"
}

#########################################################################################
runMpiexec() {

    ENVS_TO_FORWARD="PARALLEL_SERVER_DECODE_FUNCTION,PARALLEL_SERVER_STORAGE_LOCATION,PARALLEL_SERVER_STORAGE_CONSTRUCTOR,PARALLEL_SERVER_JOB_LOCATION,PARALLEL_SERVER_DEBUG,PARALLEL_SERVER_LICENSE_NUMBER,MLM_WEB_LICENSE,MLM_WEB_USER_CRED,MLM_WEB_ID"
    LEGACY_ENVS_TO_FORWARD="MDCE_DECODE_FUNCTION,MDCE_STORAGE_LOCATION,MDCE_STORAGE_CONSTRUCTOR,MDCE_JOB_LOCATION,MDCE_DEBUG,MDCE_LICENSE_NUMBER"
    CMD="\"${FULL_MPIEXEC}\" -smpd -phrase MATLAB -port ${SMPD_PORT} \
        -l ${MACHINE_ARG} -genvlist $ENVS_TO_FORWARD,$LEGACY_ENVS_TO_FORWARD \
        \"${PARALLEL_SERVER_MATLAB_EXE}\" ${PARALLEL_SERVER_MATLAB_ARGS}"

    # As a debug stage: echo the command ...
    echo $CMD

    # ... and then execute it.
    eval $CMD

    MPIEXEC_CODE=${?}
    if [ ${MPIEXEC_CODE} -ne 0 ] ; then
        exit ${MPIEXEC_CODE}
    fi
}

#########################################################################################
# Define the order in which we execute the stages defined above
MAIN() {
    # Install a trap to ensure that SMPDs are closed if something errors or the
    # job is cancelled.
    trap "cleanupAndExit" 0 1 2 15
    chooseSmpdHosts
    chooseSmpdPort
    launchSmpds
    chooseMachineArg
    runMpiexec
    exit 0 # Explicitly exit 0 to trigger cleanupAndExit
}

# Call the MAIN loop
MAIN
