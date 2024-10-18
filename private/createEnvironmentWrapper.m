function createEnvironmentWrapper(outputFilename, quotedWrapperPath, environmentVariables, clusterOS)
% Create a script that sets the correct environment variables and then
% calls the job wrapper.

% Copyright 2023 The MathWorks, Inc.

dctSchedulerMessage(5, '%s: Creating environment wrapper at %s', mfilename, outputFilename);

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
    
    % Also forward LANG, as bsub won't do that automatically.
    environmentVariables = [environmentVariables; {'LANG', getenv('LANG')}];
    
    formatSpec = 'export %s=''%s''\n';
else
    % Turn off command echoing
    fprintf(fid, '@echo off\n');
    
    formatSpec = 'set %s=%s\n';
end

% Write the commands to set and export environment variables
for ii = 1:size(environmentVariables, 1)
    fprintf(fid, formatSpec, environmentVariables{ii,1}, environmentVariables{ii,2});
end

% Write the command to run the job wrapper
fprintf(fid, '%s\n', quotedWrapperPath);

end
