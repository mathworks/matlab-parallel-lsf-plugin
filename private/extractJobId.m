function jobID = extractJobId(cmdOut)
% Extracts the job ID from the bsub command output for LSF

% Copyright 2010-2022 The MathWorks, Inc.

% The output of bsub will be:
% Job <327> is submitted to default queue <normal>.
jobIDCell = regexp(cmdOut, 'Job <(?<jobID>[0-9]+)>', 'tokens', 'once');
jobID = jobIDCell{1};
dctSchedulerMessage(0, '%s: Job ID %s was extracted from bsub output %s.', mfilename, jobID, cmdOut);
end
