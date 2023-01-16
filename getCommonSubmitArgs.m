function commonSubmitArgs = getCommonSubmitArgs(cluster)
% Get any additional submit arguments for the LSF bsub command
% that are common to both independent and communicating jobs.

% Copyright 2016-2022 The MathWorks, Inc.

commonSubmitArgs = '';
ap = cluster.AdditionalProperties;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% CUSTOMIZATION MAY BE REQUIRED %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% You may wish to support further cluster.AdditionalProperties fields here
% and modify the submission command arguments accordingly.

% Memory required per CPU
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'MemPerCPU', 'char', '-R "rusage[mem=%s]"');

% Project
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'Project', 'char', '-P %s');

% Queue
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'QueueName', 'char', '-q %s');

% Whether we must have full use of any nodes requested
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'RequireExclusiveNode', 'logical', '-x');

% Wall time
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'WallTime', 'char', '-W %s');

% Email notification
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'EmailAddress', 'char', '-B -N -u %s');

% Catch all: directly append anything in the AdditionalSubmitArgs
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, ...
    'AdditionalSubmitArgs', 'char', '%s');

% Trim any whitespace
commonSubmitArgs = strtrim(commonSubmitArgs);

end

function commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, propName, propType, submitPattern)
arg = validatedPropValue(ap, propName, propType);
if ~isempty(arg) && (~islogical(arg) || arg)
    commonSubmitArgs = sprintf([commonSubmitArgs ' ' submitPattern], arg);
end
end
