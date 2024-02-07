function createSubmitScript(outputFilename, jobName, quotedLogFile, ...
    quotedWrapperPath, additionalSubmitArgs, clusterOS, jobArrayString)
% Create a script that runs the LSF bsub command.

% Copyright 2010-2023 The MathWorks, Inc.

if nargin < 7
    jobArrayString = [];
end

dctSchedulerMessage(5, '%s: Creating submit script for %s at %s', mfilename, jobName, outputFilename);

if strcmpi(clusterOS, 'unix')
    % Open file in binary mode to make it cross-platform.
    fid = fopen(outputFilename, 'w');
else
    % Open file in text mode to handle line endings.
    fid = fopen(outputFilename, 'wt');
end
if fid < 0
    error('parallelexamples:GenericLSF:FileError', ...
        'Failed to open file %s for writing', outputFilename);
end
fileCloser = onCleanup(@() fclose(fid));

if strcmpi(clusterOS, 'unix')
    % Specify shell to use
    fprintf(fid, '#!/bin/sh\n');
else
    % Turn off command echoing
    fprintf(fid, '@echo off\n');
end

commandToRun = getSubmitString(jobName, quotedLogFile, quotedWrapperPath, ...
    additionalSubmitArgs, jobArrayString);
fprintf(fid, '%s\n', commandToRun);

end
