function submitString = getSubmitString(jobName, quotedLogFile, quotedCommand, ...
    additionalSubmitArgs, jobArrayString)
%GETSUBMITSTRING Gets the correct bsub command for an LSF cluster

% Copyright 2010-2023 The MathWorks, Inc.

% Submit to LSF using bsub.  Note the following:
% "-J" - specifies the job name
% "-o" - specifies where standard output goes to (and standard error, when -e is not specified)
% Note that extra spaces in the bsub command are permitted

if ~isempty(jobArrayString)
    jobName = strcat(jobName, '[', jobArrayString, ']');
end

% If the command contains spaces, LSF requires extra escaped double-quotes
% outside the quoted command
if contains(quotedCommand, ' ')
    quotedCommand = ['\"' quotedCommand '\"'];
end

submitString = sprintf('bsub -J %s -o %s -env "none" %s %s', ...
    jobName, quotedLogFile, additionalSubmitArgs, quotedCommand);

end
