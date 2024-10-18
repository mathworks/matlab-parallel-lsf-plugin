function independentSubmitFcn(cluster, job, environmentProperties)
%INDEPENDENTSUBMITFCN Submit a MATLAB job to a LSF cluster
%
% Set your cluster's PluginScriptsLocation to the parent folder of this
% function to run it when you submit an independent job.
%
% See also parallel.cluster.generic.independentDecodeFcn.

% Copyright 2010-2023 The MathWorks, Inc.

% Store the current filename for the errors, warnings and dctSchedulerMessages.
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericLSF:NotClusterObject', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

decodeFunction = 'parallel.cluster.generic.independentDecodeFcn';

% Get the correct quote and file separator for the Cluster OS.
clusterOS = cluster.OperatingSystem;
if strcmpi(clusterOS, 'unix')
    quote = '''';
    fileSeparator = '/';
    scriptExt = '.sh';
    shellCmd = 'sh';
else
    quote = '"';
    fileSeparator = '\';
    scriptExt = '.bat';
    shellCmd = 'cmd /c';
end

if isprop(cluster.AdditionalProperties, 'ClusterHost')
    remoteConnection = getRemoteConnection(cluster);
end

[useJobArrays, maxJobArraySize] = iGetJobArrayProps(cluster);
% Store data for future reference
cluster.UserData.UseJobArrays = useJobArrays;
if useJobArrays
    cluster.UserData.MaxJobArraySize = maxJobArraySize;
end

% Determine the debug setting. Setting to true makes the MATLAB workers
% output additional logging. If EnableDebug is set in the cluster object's
% AdditionalProperties, that takes precedence. Otherwise, look for the
% PARALLEL_SERVER_DEBUG and MDCE_DEBUG environment variables in that order.
% If nothing is set, debug is false.
enableDebug = 'false';
if isprop(cluster.AdditionalProperties, 'EnableDebug')
    % Use AdditionalProperties.EnableDebug, if it is set
    enableDebug = char(string(cluster.AdditionalProperties.EnableDebug));
else
    % Otherwise check the environment variables set locally on the client
    environmentVariablesToCheck = {'PARALLEL_SERVER_DEBUG', 'MDCE_DEBUG'};
    for idx = 1:numel(environmentVariablesToCheck)
        debugValue = getenv(environmentVariablesToCheck{idx});
        if ~isempty(debugValue)
            enableDebug = debugValue;
            break
        end
    end
end

% The job specific environment variables
% Remove leading and trailing whitespace from the MATLAB arguments
matlabArguments = strtrim(environmentProperties.MatlabArguments);

% Where the workers store job output
if cluster.HasSharedFilesystem
    storageLocation = environmentProperties.StorageLocation;
else
    storageLocation = remoteConnection.JobStorageLocation;
    % If the RemoteJobStorageLocation ends with a space, add a slash to ensure it is respected
    if endsWith(storageLocation, ' ')
        storageLocation = [storageLocation, fileSeparator];
    end
end
variables = { ...
    'PARALLEL_SERVER_DECODE_FUNCTION', decodeFunction; ...
    'PARALLEL_SERVER_STORAGE_CONSTRUCTOR', environmentProperties.StorageConstructor; ...
    'PARALLEL_SERVER_JOB_LOCATION', environmentProperties.JobLocation; ...
    'PARALLEL_SERVER_MATLAB_EXE', environmentProperties.MatlabExecutable; ...
    'PARALLEL_SERVER_MATLAB_ARGS', matlabArguments; ...
    'PARALLEL_SERVER_DEBUG', enableDebug; ...
    'MLM_WEB_LICENSE', environmentProperties.UseMathworksHostedLicensing; ...
    'MLM_WEB_USER_CRED', environmentProperties.UserToken; ...
    'MLM_WEB_ID', environmentProperties.LicenseWebID; ...
    'PARALLEL_SERVER_LICENSE_NUMBER', environmentProperties.LicenseNumber; ...
    'PARALLEL_SERVER_STORAGE_LOCATION', storageLocation};
% Environment variable names different prior to 19b
if verLessThan('matlab', '9.7')
    variables(:,1) = replace(variables(:,1), 'PARALLEL_SERVER_', 'MDCE_');
end
% Trim the environment variables of empty values.
nonEmptyValues = cellfun(@(x) ~isempty(strtrim(x)), variables(:,2));
variables = variables(nonEmptyValues, :);

% The job directory as accessed by this machine
localJobDirectory = cluster.getJobFolder(job);

% The job directory as accessed by workers on the cluster
if cluster.HasSharedFilesystem
    jobDirectoryOnCluster = cluster.getJobFolderOnCluster(job);
else
    jobDirectoryOnCluster = remoteConnection.getRemoteJobLocation(job.ID, clusterOS);
end

% Name of the wrapper script to launch the MATLAB worker
if strcmpi(clusterOS, 'unix')
    jobWrapperName = 'independentJobWrapper.sh';
else
    jobWrapperName = 'independentJobWrapper.bat';
end
% The wrapper script is in the same directory as this file
dirpart = fileparts(mfilename('fullpath'));
localScript = fullfile(dirpart, jobWrapperName);
% Copy the local wrapper script to the job directory
copyfile(localScript, localJobDirectory, 'f');

% The script to execute on the cluster to run the job
wrapperPath = sprintf('%s%s%s', jobDirectoryOnCluster, fileSeparator, jobWrapperName);
quotedWrapperPath = sprintf('%s%s%s', quote, wrapperPath, quote);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% CUSTOMIZATION MAY BE REQUIRED %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if strcmpi(clusterOS, 'unix')
    % Setting affinity not supported on Windows
    additionalSubmitArgs = sprintf('-R "affinity[core(%d)]"', ...
        cluster.NumThreads);
else
    additionalSubmitArgs = '';
end
commonSubmitArgs = getCommonSubmitArgs(cluster);
additionalSubmitArgs = strtrim(sprintf('%s %s', additionalSubmitArgs, commonSubmitArgs));
if validatedPropValue(cluster.AdditionalProperties, 'DisplaySubmitArgs', 'logical', false)
    fprintf('Submit arguments: %s\n', additionalSubmitArgs);
end

% Only keep and submit tasks that are not cancelled. Cancelled tasks
% will have errors.
isPendingTask = cellfun(@isempty, get(job.Tasks, {'Error'}));
tasks = job.Tasks(isPendingTask);
taskIDs = cell2mat(get(tasks, {'ID'}));
numberOfTasks = numel(tasks);

% Only use job arrays when you can get enough use out of them.
if numberOfTasks < 2 || maxJobArraySize <= 0
    useJobArrays = false;
end

if useJobArrays
    % LSF places a limit on the number of jobs that may be submitted as a
    % single job array. The default value is 1,000, or 10,000 if the cluster
    % has been configured with the HIGH_THROUGHPUT template. If there are
    % more tasks in this job than will fit in a single job array, submit
    % the tasks as several smaller job arrays. LSF accepts job arrays with
    % indices greater than maxJobArraySize, providing the number of indices
    % is less than maxJobArraySize.  For example, if maxJobArraySize is
    % 1000, then indices [1001-2000] would be valid.
    taskIDGroupsForJobArrays = iCalculateTaskIDGroupsForJobArrays(taskIDs, maxJobArraySize);
    
    jobName = sprintf('MATLAB_R%s_Job%d', version('-release'), job.ID);
    numJobArrays = numel(taskIDGroupsForJobArrays);
    commandsToRun = cell(numJobArrays, 1);
    jobIDs = cell(numJobArrays, 1);
    schedulerJobArrayIndices = cell(numJobArrays, 1);
    for ii = 1:numJobArrays
        schedulerJobArrayIndices{ii} = taskIDGroupsForJobArrays{ii};
        
        % Create a character vector with the ranges of IDs to submit.
        jobArrayString = iCreateJobArrayString(schedulerJobArrayIndices{ii});
        
        % Choose a file for the output
        if strcmpi(clusterOS, 'unix')
            logFileName = 'Task%I.log';
        else
            % Must escape percent sign in Windows bat script
            logFileName = 'Task%%I.log';
        end
        logFile = sprintf('%s%s%s', jobDirectoryOnCluster, fileSeparator, logFileName);
        quotedLogFile = sprintf('%s%s%s', quote, logFile, quote);
        dctSchedulerMessage(5, '%s: Using %s as log file', currFilename, quotedLogFile);
        
        environmentVariables = variables;
        
        % Path to the submit script, to submit the LSF job using bsub
        submitScriptName = sprintf('submitScript%d%s', ii, scriptExt);
        localSubmitScriptPath = sprintf('%s%s%s', localJobDirectory, fileSeparator, submitScriptName);
        submitScriptPathOnCluster = sprintf('%s%s%s', jobDirectoryOnCluster, fileSeparator, submitScriptName);
        quotedSubmitScriptPathOnCluster = sprintf('%s%s%s', quote, submitScriptPathOnCluster, quote);
        
        % Path to the environment wrapper, which will set the environment variables
        % for the job then execute the job wrapper
        envScriptName = sprintf('environmentWrapper%d%s', ii, scriptExt);
        localEnvScriptPath = sprintf('%s%s%s', localJobDirectory, fileSeparator, envScriptName);
        envScriptPathOnCluster = sprintf('%s%s%s', jobDirectoryOnCluster, fileSeparator, envScriptName);
        quotedEnvScriptPathOnCluster = sprintf('%s%s%s', quote, envScriptPathOnCluster, quote);
        
        % Create the scripts to submit a LSF job.
        % These will be created in the job directory.
        dctSchedulerMessage(5, '%s: Generating scripts for job array %d', currFilename, ii);
        createEnvironmentWrapper(localEnvScriptPath, quotedWrapperPath, ...
            environmentVariables, clusterOS);
        createSubmitScript(localSubmitScriptPath, jobName, quotedLogFile, ...
            quotedEnvScriptPathOnCluster, additionalSubmitArgs, clusterOS, jobArrayString);
        
        % Create the command to run on the cluster
        commandsToRun{ii} = sprintf('%s %s', shellCmd, quotedSubmitScriptPathOnCluster);
    end
else
    % Do not use job arrays and submit each task individually.
    taskLocations = environmentProperties.TaskLocations(isPendingTask);
    jobIDs = cell(1, numberOfTasks);
    commandsToRun = cell(numberOfTasks, 1);
    
    % Loop over every task we have been asked to submit
    for ii = 1:numberOfTasks
        taskLocation = taskLocations{ii};
        % Add the task location to the environment variables
        if verLessThan('matlab', '9.7') % variable name changed in 19b
            environmentVariables = [variables; ...
                {'MDCE_TASK_LOCATION', taskLocation}];
        else
            environmentVariables = [variables; ...
                {'PARALLEL_SERVER_TASK_LOCATION', taskLocation}];
        end
        
        % Choose a file for the output
        logFileName = sprintf('Task%d.log', taskIDs(ii));
        logFile = sprintf('%s%s%s', jobDirectoryOnCluster, fileSeparator, logFileName);
        quotedLogFile = sprintf('%s%s%s', quote, logFile, quote);
        dctSchedulerMessage(5, '%s: Using %s as log file', currFilename, quotedLogFile);
        
        % Submit one task at a time
        jobName = sprintf('MATLAB_R%s_Job%d.%d', version('-release'), job.ID, taskIDs(ii));
        
        % Path to the submit script, to submit the LSF job using bsub
        submitScriptName = sprintf('submitScript%d%s', ii, scriptExt);
        localSubmitScriptPath = sprintf('%s%s%s', localJobDirectory, fileSeparator, submitScriptName);
        submitScriptPathOnCluster = sprintf('%s%s%s', jobDirectoryOnCluster, fileSeparator, submitScriptName);
        quotedSubmitScriptPathOnCluster = sprintf('%s%s%s', quote, submitScriptPathOnCluster, quote);
        
        % Path to the environment wrapper, which will set the environment variables
        % for the job then execute the job wrapper
        envScriptName = sprintf('environmentWrapper%d%s', ii, scriptExt);
        localEnvScriptPath = sprintf('%s%s%s', localJobDirectory, fileSeparator, envScriptName);
        envScriptPathOnCluster = sprintf('%s%s%s', jobDirectoryOnCluster, fileSeparator, envScriptName);
        quotedEnvScriptPathOnCluster = sprintf('%s%s%s', quote, envScriptPathOnCluster, quote);
        
        % Create the scripts to submit a LSF job.
        % These will be created in the job directory.
        dctSchedulerMessage(5, '%s: Generating scripts for task %d', currFilename, ii);
        createEnvironmentWrapper(localEnvScriptPath, quotedWrapperPath, ...
            environmentVariables, clusterOS);
        createSubmitScript(localSubmitScriptPath, jobName, quotedLogFile, ...
            quotedEnvScriptPathOnCluster, additionalSubmitArgs, clusterOS);
        
        % Create the command to run on the cluster
        commandsToRun{ii} = sprintf('%s %s', shellCmd, quotedSubmitScriptPathOnCluster);
    end
end

if ~cluster.HasSharedFilesystem
    % Start the mirror to copy all the job files over to the cluster
    dctSchedulerMessage(4, '%s: Starting mirror for job %d.', currFilename, job.ID);
    remoteConnection.startMirrorForJob(job);
end

if strcmpi(clusterOS, 'unix')
    % Add execute permissions to shell scripts
    runSchedulerCommand(cluster, sprintf( ...
        'chmod u+x "%s%s"*.sh', jobDirectoryOnCluster, fileSeparator));
    % Convert line endings to Unix
    runSchedulerCommand(cluster, sprintf( ...
        'dos2unix --allow-chown "%s%s"*.sh', jobDirectoryOnCluster, fileSeparator));
end

for ii=1:numel(commandsToRun)
    commandToRun = commandsToRun{ii};
    jobIDs{ii} = iSubmitJobUsingCommand(cluster, job, commandToRun);
end

% Calculate the schedulerIDs
if useJobArrays
    % The scheduler ID of each task is a combination of the job ID and the
    % scheduler array index. cellfun pairs each job ID with its
    % corresponding scheduler array indices in schedulerJobArrayIndices and
    % returns the combination of both. For example, if jobIDs = {1,2} and
    % schedulerJobArrayIndices = {[1,2];[3,4]}, the schedulerID is given by
    % combining 1 with [1,2] and 2 with [3,4], in the canonical form of the
    % scheduler.
    schedulerIDs = cellfun(@(jobID,arrayIndices) jobID + "[" + arrayIndices + "]", ...
        jobIDs, schedulerJobArrayIndices, 'UniformOutput', false);
    schedulerIDs = vertcat(schedulerIDs{:});
else
    % The scheduler ID of each task is the job ID.
    schedulerIDs = string(jobIDs);
end

% Store the scheduler ID for each task and the job cluster data
jobData = struct('type', 'generic');
if isprop(cluster.AdditionalProperties, 'ClusterHost')
    % Store the cluster host
    jobData.RemoteHost = remoteConnection.Hostname;
end
if ~cluster.HasSharedFilesystem
    % Store the remote job storage location
    jobData.RemoteJobStorageLocation = remoteConnection.JobStorageLocation;
    jobData.HasDoneLastMirror = false;
end
if verLessThan('matlab', '9.7') % schedulerID stored in job data
    jobData.ClusterJobIDs = schedulerIDs;
else % schedulerID on task since 19b
    set(tasks, 'SchedulerID', schedulerIDs);
end
cluster.setJobClusterData(job, jobData);

end

function [useJobArrays, maxJobArraySize] = iGetJobArrayProps(cluster)
% Look for useJobArrays and maxJobArray size in the following order:
% 1.  Additional Properties
% 2.  User Data
% 3.  Query scheduler for MaxJobArraySize

useJobArrays = validatedPropValue(cluster.AdditionalProperties, 'UseJobArrays', 'logical');
if isempty(useJobArrays)
    if isfield(cluster.UserData, 'UseJobArrays')
        useJobArrays = cluster.UserData.UseJobArrays;
    else
        useJobArrays = true;
    end
end

if ~useJobArrays
    % Not using job arrays so don't need the max array size
    maxJobArraySize = 0;
    return
end

maxJobArraySize = validatedPropValue(cluster.AdditionalProperties, 'MaxJobArraySize', 'numeric');
if ~isempty(maxJobArraySize)
    if maxJobArraySize < 1
        error('parallelexamples:GenericLSF:IncorrectArguments', ...
            'MaxJobArraySize must be a positive integer');
    end
    return
end

if isfield(cluster.UserData,'MaxJobArraySize')
    maxJobArraySize = cluster.UserData.MaxJobArraySize;
    return
end

% Get job array information by querying the scheduler.
commandToRun = 'bparams -a';
try
    [cmdFailed, cmdOut] = runSchedulerCommand(cluster, commandToRun);
catch err
    cmdFailed = true;
    cmdOut = err.message;
end
if cmdFailed
    error('parallelexamples:GenericLSF:FailedToRetrieveInfo', ...
        'Failed to retrieve LSF configuration information using command:\n\t%s.\nReason: %s', ...
        commandToRun, cmdOut);
end

maxJobArraySize = 0;
% Extract the maximum array size for job arrays. For LSF, the configuration
% line that contains the maximum array size looks like this:
% MAX_JOB_ARRAY_SIZE = 1000
% Use a regular expression to extract this parameter.
tokens = regexp(cmdOut,'MAX_JOB_ARRAY_SIZE\s*=\s*(\d+)', ...
    'tokens','once');

if isempty(tokens)
    % No job array support.
    useJobArrays = false;
    return
end

useJobArrays = true;
% Set the maximum array size.
maxJobArraySize = str2double(tokens{1});
end

function jobID = iSubmitJobUsingCommand(cluster, job, commandToRun)
currFilename = mfilename;
% Ask the cluster to run the submission command.
dctSchedulerMessage(4, '%s: Submitting job %d using command:\n\t%s', currFilename, job.ID, commandToRun);
try
    [cmdFailed, cmdOut] = runSchedulerCommand(cluster, commandToRun);
catch err
    cmdFailed = true;
    cmdOut = err.message;
end
if cmdFailed
    if ~cluster.HasSharedFilesystem
        % Stop the mirroring if we failed to submit the job - this will also
        % remove the job files from the remote location
        remoteConnection = getRemoteConnection(cluster);
        % Only stop mirroring if we are actually mirroring
        if remoteConnection.isJobUsingConnection(job.ID)
            dctSchedulerMessage(5, '%s: Stopping the mirror for job %d.', currFilename, job.ID);
            try
                remoteConnection.stopMirrorForJob(job);
            catch err
                warning('parallelexamples:GenericLSF:FailedToStopMirrorForJob', ...
                    'Failed to stop the file mirroring for job %d.\nReason: %s', ...
                    job.ID, err.getReport);
            end
        end
    end
    error('parallelexamples:GenericLSF:FailedToSubmitJob', ...
        'Failed to submit job to LSF using command:\n\t%s.\nReason: %s', ...
        commandToRun, cmdOut);
end

jobID = extractJobId(cmdOut);
if isempty(jobID)
    error('parallelexamples:GenericLSF:FailedToParseSubmissionOutput', ...
        'Failed to parse the job identifier from the submission output: "%s"', ...
        cmdOut);
end
end

function taskIDGroupsForJobArrays = iCalculateTaskIDGroupsForJobArrays(taskIDsToSubmit, maxJobArraySize)
% Calculates the groups of task IDs to be submitted as job arrays.

% The number of tasks in each job array must be less than maxJobArraySize.
numTasks = numel(taskIDsToSubmit);
jobArraySizes = iCalculateJobArraySizes(numTasks, maxJobArraySize);
taskIDGroupsForJobArrays = mat2cell(taskIDsToSubmit, jobArraySizes);
end

function jobArraySizes = iCalculateJobArraySizes(numTasks, maxJobArraySize)
if isinf(maxJobArraySize)
    numJobArrays = 1;
else
    numJobArrays = ceil(numTasks./maxJobArraySize);
end
jobArraySizes = repmat(maxJobArraySize, 1, numJobArrays);
remainder = mod(numTasks, maxJobArraySize);
if remainder > 0
    jobArraySizes(end) = remainder;
end
end

function rangesString = iCreateJobArrayString(taskIDs)
% Create a character vector with the ranges of task IDs to submit
if taskIDs(end) - taskIDs(1) + 1 == numel(taskIDs)
    % There is only one range.
    rangesString = sprintf('%d-%d',taskIDs(1),taskIDs(end));
else
    % There are several ranges.
    % Calculate the step size between task IDs.
    step = diff(taskIDs);
    % Where the step changes, a range ends and another starts. Include
    % the initial and ending IDs in the ranges as well.
    isStartOfRange = [true; step > 1];
    isEndOfRange   = [step > 1; true];
    rangesString = strjoin(compose('%d-%d', ...
        taskIDs(isStartOfRange),taskIDs(isEndOfRange)),',');
end
end
