function value = readDatasetParameter(rawDataFile, routine, param, value)
%READDATASETPARAMETER Returns the value of a specified parameter from the PP or QC 
%parameter file associated to a raw data file.
%
% This function provides a simple interface to retrieve the values of
% parameters stored in a PP or QC parameter file.
%
% A 'parameter' file is a 'mat' file which contains a p structure which 
% fields are the name of a PP or QC routine and subfields the name of their parameters 
% which contain this parameter value.
%
% Inputs:
%
%   rawDataFile - Name of the raw data file. Is used to build the parameter
%               file name (same root but different extension).
%
%   routine     - Name of the PP or QC routine. If the name does not map to any 
%               existing routine then the default value is returned.
%
%   param       - Name of the routine parameter to be retrieved. If the
%               name does not map to a parameter listed in the routine of 
%               the parameter file, an error is raised.
%
%   value       - Value of the default parameter.
%
% Outputs:
%   value       - Value of the dataset parameter.
%
% Author: Guillaume Galibert <guillaume.galibert@utas.edu.au>
%

%
% Copyright (c) 2016, Australian Ocean Data Network (AODN) and Integrated 
% Marine Observing System (IMOS).
% All rights reserved.
% 
% Redistribution and use in source and binary forms, with or without 
% modification, are permitted provided that the following conditions are met:
% 
%     * Redistributions of source code must retain the above copyright notice, 
%       this list of conditions and the following disclaimer.
%     * Redistributions in binary form must reproduce the above copyright 
%       notice, this list of conditions and the following disclaimer in the 
%       documentation and/or other materials provided with the distribution.
%     * Neither the name of the AODN/IMOS nor the names of its contributors 
%       may be used to endorse or promote products derived from this software 
%       without specific prior written permission.
% 
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
% LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
% CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
% POSSIBILITY OF SUCH DAMAGE.
%
narginchk(4,4);

if ~ischar(rawDataFile), error('rawDataFile must be a string'); end
if ~ischar(routine),     error('routine must be a string');     end
if ~ischar(param),       error('param must be a string');       end

switch lower(routine(end-1:end))
    case 'qc'
        pType = 'pqc';
        
    case 'pp'
        pType = 'ppp';
        
    otherwise
        return;
end
pFile = [rawDataFile, '.', pType];

% we need to migrate any remnants of the old file naming convention
% for .pqc files.
[pPath, oldPFile, ~] = fileparts(rawDataFile);
oldPFile = fullfile(pPath, [oldPFile, '.', pType]);
if exist(oldPFile, 'file')
    movefile(oldPFile, pFile);
end

ppp = struct([]);
pqc = struct([]);

if exist(pFile, 'file')
    load(pFile, '-mat', pType);
    
    switch pType
        case 'pqc'
            p = pqc;
            
        case 'ppp'
            p = ppp;
    end
    
    if isfield(p, routine)
        if strcmpi(param, '*')
            value{1} = fieldnames(p.(routine));
            for i=1:length(value{1})
                value{2}{i} = p.(routine).(value{1}{i});
            end
        else
            if isfield(p.(routine), param)
                value = p.(routine).(param);
            else
                error([param ' is not a parameter of ' routine]);
            end
        end
    end
end
