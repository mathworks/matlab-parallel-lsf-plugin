REM Copyright 2007-2023 The MathWorks, Inc.

@echo off
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

REM If PARALLEL_SERVER_ environment variables are unset, check for MDCE_ format
if "x!PARALLEL_SERVER_MATLAB_EXE!" == "x" (set PARALLEL_SERVER_MATLAB_EXE=!MDCE_MATLAB_EXE!)
if "x!PARALLEL_SERVER_MATLAB_ARGS!" == "x" (set PARALLEL_SERVER_MATLAB_ARGS=!MDCE_MATLAB_ARGS!)

REM Echo the node that the scheduler has allocated to this job:
echo The scheduler has allocated the following node to this job: !COMPUTERNAME!

IF "x!LSB_JOBINDEX!" NEQ "x" IF "!LSB_JOBINDEX!" NEQ "0" (
    REM Use job arrays
    set PARALLEL_SERVER_TASK_LOCATION=!PARALLEL_SERVER_JOB_LOCATION!/Task!LSB_JOBINDEX!
    set MDCE_TASK_LOCATION=!MDCE_JOB_LOCATION!/Task!LSB_JOBINDEX!
)

REM Construct and call the command to run the worker
set FULL_CMD="!PARALLEL_SERVER_MATLAB_EXE!" !PARALLEL_SERVER_MATLAB_ARGS!
echo !FULL_CMD!
call !FULL_CMD!

echo "MATLAB exited with code: !ERRORLEVEL!"
