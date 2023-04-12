REM This wrapper script is used by the lsfscheduler to call MPIEXEC to launch
REM MATLAB on the hosts allocated by LSF. We use "worker.bat" rather than
REM "matlab.bat" to ensure that the exit code from MATLAB is correctly
REM interpreted by MPIEXEC.
REM
REM The following environment variables must be forwarded to the MATLABs:
REM - PARALLEL_SERVER_DECODE_FUNCTION
REM - PARALLEL_SERVER_STORAGE_LOCATION
REM - PARALLEL_SERVER_STORAGE_CONSTRUCTOR
REM - PARALLEL_SERVER_JOB_LOCATION
REM - PARALLEL_SERVER_DEBUG
REM - LSB_JOBID
REM
REM This is done using the "-genvlist" option to MPIEXEC.

REM Copyright 2006-2023 The MathWorks, Inc.

@echo off
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

REM If PARALLEL_SERVER_ environment variables are unset, check for MDCE_ format
if "x!PARALLEL_SERVER_CMR!" == "x" (set PARALLEL_SERVER_CMR=!MDCE_CMR!)
if "x!PARALLEL_SERVER_MATLAB_EXE!" == "x" (set PARALLEL_SERVER_MATLAB_EXE=!MDCE_MATLAB_EXE!)
if "x!PARALLEL_SERVER_MATLAB_ARGS!" == "x" (set PARALLEL_SERVER_MATLAB_ARGS=!MDCE_MATLAB_ARGS!)
if "x!PARALLEL_SERVER_JOB_LOCATION!" == "x" (set PARALLEL_SERVER_JOB_LOCATION=!MDCE_JOB_LOCATION!)
if "x!PARALLEL_SERVER_DEBUG!" == "x" (set PARALLEL_SERVER_DEBUG=!MDCE_DEBUG!)

if "x!PARALLEL_SERVER_CMR!" == "x" (
  REM No ClusterMatlabRoot set, just call mw_mpiexec and matlab.bat directly.
  set MPIEXEC=mw_mpiexec
) else (
  REM Use ClusterMatlabRoot to find mpiexec wrapper and matlab.bat
  set MPIEXEC="!PARALLEL_SERVER_CMR!\bin\mw_mpiexec"
)

REM We need to count how many different hosts are in LSB_MCPU_HOSTS
set HOST_COUNT=0
call :countHosts %LSB_MCPU_HOSTS%

set MPIEXEC_OPTS=-noprompt -l -exitcodes
if "%PARALLEL_SERVER_DELEGATE%" == "true" (
  set MPIEXEC_OPTS=!MPIEXEC_OPTS! -delegate
)

REM The actual call to MPIEXEC. Must use call for the mw_mpiexec.bat
REM wrapper to ensure that we can modify the return code from mpiexec.
set FULL_CMD=!MPIEXEC! !MPIEXEC_OPTS!^
 -hosts %HOST_COUNT% %LSB_MCPU_HOSTS%^
 -genvlist !PARALLEL_SERVER_GENVLIST!^
 !PARALLEL_SERVER_MATLAB_EXE! !PARALLEL_SERVER_MATLAB_ARGS!
echo !FULL_CMD!
call !FULL_CMD!

REM If MPIEXEC exited with code 42, this indicates a call to MPI_Abort from
REM within MATLAB. In this case, we do not wish LSF to think that the job
REM failed; the task error state within MATLAB will correctly indicate the
REM job outcome.
set MPIEXEC_ERRORLEVEL=!ERRORLEVEL!
if %MPIEXEC_ERRORLEVEL% == 42 (
  echo Overwriting MPIEXEC exit code from 42 to zero (42 indicates a user-code failure)
  exit 0
) else (
  exit %MPIEXEC_ERRORLEVEL%
)

REM Loop through LSB_MCPU_HOSTS to count how many unique hosts are present in the list.
:countHosts
if (%1) == () goto :EOF
set /a HOST_COUNT=%HOST_COUNT% + 1
shift
shift
goto countHosts
