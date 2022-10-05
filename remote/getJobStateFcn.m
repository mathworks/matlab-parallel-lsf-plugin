function state = getJobStateFcn(cluster, job, state)
%GETJOBSTATEFCN Gets the state of a job from LSF
%
% Set your cluster's PluginScriptsLocation to the parent folder of this
% function to run it when you query the state of a job.

% Copyright 2010-2022 The MathWorks, Inc.

% Store the current filename for the errors, warnings and
% dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericLSF:SubmitFcnError', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end
if ~cluster.HasSharedFilesystem
    error('parallelexamples:GenericLSF:NotSharedFileSystem', ...
        'The function %s is for use with shared filesystems.', currFilename)
end

% Get the information about the actual cluster used
data = cluster.getJobClusterData(job);
if isempty(data)
    % This indicates that the job has not been submitted, so just return
    dctSchedulerMessage(1, '%s: Job cluster data was empty for job with ID %d.', currFilename, job.ID);
    return
end
% Shortcut if the job state is already finished or failed
jobInTerminalState = strcmp(state, 'finished') || strcmp(state, 'failed');
if jobInTerminalState
    return
end
remoteConnection = getRemoteConnection(cluster);
[schedulerIDs, numSubmittedTasks] = getSimplifiedSchedulerIDsForJob(job);

commandToRun = sprintf('bjobs %s', sprintf('%s ', schedulerIDs{:}));
dctSchedulerMessage(4, '%s: Querying cluster for job state using command:\n\t%s', currFilename, commandToRun);

try
    % We will ignore the status returned from the state command because
    % a non-zero status is returned if the job no longer exists
    % Execute the command on the remote host.
    [~, cmdOut] = remoteConnection.runCommand(commandToRun);
catch err
    ex = MException('parallelexamples:GenericLSF:FailedToGetJobState', ...
        'Failed to get job state from cluster.');
    ex = ex.addCause(err);
    throw(ex);
end

clusterState = iExtractJobState(cmdOut, numSubmittedTasks);
dctSchedulerMessage(6, '%s: State %s was extracted from cluster output.', currFilename, clusterState);

% If we could determine the cluster's state, we'll use that, otherwise
% stick with MATLAB's job state.
if ~strcmp(clusterState, 'unknown')
    state = clusterState;
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function state = iExtractJobState(bjobsOut, numJobs)
% Function to extract the job state from the output of bjobs

% How many PEND, PSUSP, USUSP, SSUSP, WAIT
numPending = numel(regexp(bjobsOut, 'PEND|PSUSP|USUSP|SSUSP|WAIT'));
% How many RUN strings - UNKWN started running and then comms was lost
% with the sbatchd process.
numRunning = numel(regexp(bjobsOut, 'RUN|UNKWN'));
% How many EXIT, ZOMBI strings
numFailed = numel(regexp(bjobsOut, 'EXIT|ZOMBI'));
% How many DONE
numFinished = numel(regexp(bjobsOut, 'DONE'));

% If the number of finished jobs is the same as the number of jobs that we
% asked about then the entire job has finished.
if numFinished == numJobs
    state = 'finished';
    return
end

% Any running indicates that the job is running
if numRunning > 0
    state = 'running';
    return
end
% We know numRunning == 0 so if there are some still pending then the
% job must be queued again, even if there are some finished
if numPending > 0
    state = 'queued';
    return
end
% Deal with any tasks that have failed
if numFailed > 0
    % Set this job to be failed
    state = 'failed';
    return
end

state = 'unknown';
end
