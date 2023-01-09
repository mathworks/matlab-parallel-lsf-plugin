function submitString = getSubmitString(jobName, quotedLogFile, quotedCommand, ...
    varsToForward, additionalSubmitArgs, jobArrayString)
%GETSUBMITSTRING Gets the correct bsub command for an LSF cluster

% Copyright 2010-2022 The MathWorks, Inc.

envString = strjoin(varsToForward, ',');

% Submit to LSF using bsub.  Note the following:
% "-J" - specifies the job name
% "-o" - specifies where standard output goes to (and standard error, when -e is not specified)
% "-env" - specifies the environment variables to forward to the workers
% Note that extra spaces in the bsub command are permitted

if ~isempty(jobArrayString)
    jobName = strcat(jobName, '[', jobArrayString, ']');
end

submitString = sprintf('bsub -J %s -o %s -env "%s" %s %s', ...
    jobName, quotedLogFile, envString, additionalSubmitArgs, quotedCommand);

end
