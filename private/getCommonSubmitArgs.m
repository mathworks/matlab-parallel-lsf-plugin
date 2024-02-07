function commonSubmitArgs = getCommonSubmitArgs(cluster)
% Get any additional submit arguments for the LSF bsub command
% that are common to both independent and communicating jobs.

% Copyright 2016-2023 The MathWorks, Inc.

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

function commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, propName, propType, submitPattern, defaultValue)
% Helper fcn to append a scheduler option to the submit string.
% Inputs:
%  commonSubmitArgs: submit string to append to
%  ap: AdditionalProperties object
%  propName: name of the property
%  propType: type of the property, i.e. char, double or logical
%  submitPattern: sprintf-style string specifying the format of the scheduler option
%  defaultValue (optional): value to use if the property is not specified in ap

if nargin < 6
    defaultValue = [];
end
arg = validatedPropValue(ap, propName, propType, defaultValue);
if ~isempty(arg) && (~islogical(arg) || arg)
    commonSubmitArgs = [commonSubmitArgs, ' ', sprintf(submitPattern, arg)];
end
end

function commonSubmitArgs = iAppendRequiredArgument(commonSubmitArgs, ap, propName, propType, submitPattern, errMsg) %#ok<DEFNU>
% Helper fcn to append a required scheduler option to the submit string.
% An error is thrown if the property is not specified in AdditionalProperties or is empty.
% Inputs:
%  commonSubmitArgs: submit string to append to
%  ap: AdditionalProperties object
%  propName: name of the property
%  propType: type of the property, i.e. char, double or logical
%  submitPattern: sprintf-style string specifying the format of the scheduler option
%  errMsg (optional): text to append to the error message if the property is not specified in ap

if ~isprop(ap, propName)
    errorText = sprintf('Required field %s is missing from AdditionalProperties.', propName);
    if nargin > 5
        errorText = [errorText newline errMsg];
    end
    error('parallelexamples:GenericLSF:MissingAdditionalProperties', errorText);
elseif isempty(ap.(propName))
    errorText = sprintf('Required field %s is empty in AdditionalProperties.', propName);
    if nargin > 5
        errorText = [errorText newline errMsg];
    end
    error('parallelexamples:GenericLSF:EmptyAdditionalProperties', errorText);
end
commonSubmitArgs = iAppendArgument(commonSubmitArgs, ap, propName, propType, submitPattern);
end
