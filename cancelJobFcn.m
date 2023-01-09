function OK = cancelJobFcn(cluster, job)
%CANCELJOBFCN Cancels a job on LSF
%
% Set your cluster's PluginScriptsLocation to the parent folder of this
% function to run it when you cancel a job.

% Copyright 2010-2022 The MathWorks, Inc.

% Store the current filename for the errors, warnings and
% dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericLSF:SubmitFcnError', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

% Get the information about the actual cluster used
data = cluster.getJobClusterData(job);
if isempty(data)
    % This indicates that the job has not been submitted, so return true
    dctSchedulerMessage(1, '%s: Job cluster data was empty for job with ID %d.', currFilename, job.ID);
    OK = true;
    return
end

% Get a simplified list of schedulerIDs to reduce the number of calls to
% the scheduler.
schedulerIDs = getSimplifiedSchedulerIDsForJob(job);
erroredJobAndCauseStrings = cell(size(schedulerIDs));
% Get the cluster to delete the job
for ii = 1:length(schedulerIDs)
    schedulerID = schedulerIDs{ii};
    commandToRun = sprintf('bkill "%s"', schedulerID);
    dctSchedulerMessage(4, '%s: Canceling job on cluster using command:\n\t%s.', currFilename, commandToRun);
    try
        [cmdFailed, cmdOut] = runSchedulerCommand(cluster, commandToRun);
    catch err
        cmdFailed = true;
        cmdOut = err.message;
    end
    % If a job is already in a terminal state, bkill will return a failed
    % failed error code and cmdOut will be of the form:
    % 'Job <7800>: Job has already finished'
    % If this happens we do not consider the command to have failed.
    if cmdFailed && ~contains(cmdOut, 'Job has already finished')
        % Keep track of all jobs that errored when being cancelled, either
        % through a bad exit code or if an error was thrown. We'll report
        % these later on.
        erroredJobAndCauseStrings{ii} = sprintf('Job ID: %s\tReason: %s', schedulerID, strtrim(cmdOut));
        dctSchedulerMessage(1, '%s: Failed to cancel job %s on cluster.  Reason:\n\t%s', currFilename, schedulerID, cmdOut);
    end
end

if ~cluster.HasSharedFilesystem
    % Only stop mirroring if we are actually mirroring
    remoteConnection = getRemoteConnection(cluster);
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

% Now warn about those jobs that we failed to cancel.
erroredJobAndCauseStrings = erroredJobAndCauseStrings(~cellfun(@isempty, erroredJobAndCauseStrings));
if ~isempty(erroredJobAndCauseStrings)
    warning('parallelexamples:GenericLSF:FailedToCancelJob', ...
        'Failed to cancel the following jobs on the cluster:\n%s', ...
        sprintf('  %s\n', erroredJobAndCauseStrings{:}));
end
OK = isempty(erroredJobAndCauseStrings);

end
