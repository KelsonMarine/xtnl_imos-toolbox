function [data, comment] = readSBE19cnv( dataLines, instHeader, procHeader, mode )
%READSBE19CNV Processes data from a SBE19plus or SBE16plus .cnv file.
%
% This function is able to process data retrieved from a converted (.cnv) 
% data file generated by the Seabird SBE Data Processing program. This
% function is called from SBE19Parse.
%
% Inputs:
%   dataLines  - Cell array of strings, the data lines in the original file.
%   instHeader - Struct containing instrument header.
%   procHeader - Struct containing processed header.
%   mode       - Toolbox data type mode.
%
% Outputs:
%   data       - Struct containing variable data.
%   comment    - Struct containing variable comment.
%
% Author:       Paul McCarthy <paul.mccarthy@csiro.au>
% Contributor:  Guillaume Galibert <guillaume.galibert@utas.edu.au>
%

%
% Copyright (c) 2009, Australian Ocean Data Network (AODN) and Integrated 
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
  narginchk(4, 4);
  
  data = struct;
  comment = struct;
  
  columns = procHeader.columns;
  
  format = '%n';
  format = repmat(format, [1, length(columns)]);
  
  dataLines = [dataLines{:}];
  dataLines = textscan(dataLines, format);
  
  for k = 1:length(columns)
    
    d = dataLines{k};
    
    % any flagged bad data is set to NaN (even flag value itself)
    d(d == procHeader.badFlag) = nan;
    
    [n, d, c] = convertData(genvarname(columns{k}), d, instHeader, procHeader, mode);
    
    if isempty(n) || isempty(d), continue; end
    
    count = 0;
    nn = n;
    switch mode
        case 'profile'
            % if the same parameter appears multiple times, 
            % we deliberately overwrite it assuming the last version is the
            % most relevant
            
        case 'timeSeries'
            % if the same parameter appears multiple times, 
            % don't overwrite it in the data struct - append
            % a number to the end of the variable name, as
            % per the IMOS convention
            while isfield(data, nn)
                count = count + 1;
                nn = [n '_' num2str(count)];
            end
            
    end
    
    data.(nn) = d; 
    comment.(nn) = c; 
  end
  
  % Let's add a new parameter if DOX1, PSAL/CNDC, TEMP and PRES are present and
  % not DOX2
  if isfield(data, 'DOX1') && ~isfield(data, 'DOX2')
      
      % umol/l -> umol/kg
      %
      % to perform this conversion, we need to calculate the
      % density of sea water; for this, we need temperature,
      % salinity, and pressure data to be present
      temp = isfield(data, 'TEMP');
      pres = isfield(data, 'PRES_REL');
      psal = isfield(data, 'PSAL');
      cndc = isfield(data, 'CNDC');
      
      % if any of this data isn't present,
      % we can't perform the conversion to umol/kg
      if temp && pres && (psal || cndc)
          temp = data.TEMP;
          pres = data.PRES_REL;
          if psal
              psal = data.PSAL;
          else
              cndc = data.CNDC;
              % conductivity is in S/m and gsw_C3515 in mS/cm
              crat = 10*cndc ./ gsw_C3515;
              
              psal = gsw_SP_from_R(crat, temp, pres);
          end
          
          % calculate density from salinity, temperature and pressure
          dens = sw_dens(psal, temp, pres); % cannot use the GSW SeaWater library TEOS-10 as we don't know yet the position
          
          % umol/l -> umol/kg (dens in kg/m3 and 1 m3 = 1000 l)
          data.DOX2 = data.DOX1 .* 1000.0 ./ dens;
          comment.DOX2 = ['Originally expressed in mg/l, assuming O2 density = 1.429kg/m3, 1ml/l = 44.660umol/l '...
              'and using density computed from Temperature, Salinity and Pressure '...
              'with the CSIRO SeaWater library (EOS-80) v1.1.'];
      end
  end
end

function [name, data, comment] = convertData(name, data, instHeader, procHeader, mode) 
%CONVERTDATA The .cnv file provides data in a bunch of different units of
% measurement. This function is just a big switch statement which takes
% SBE19 data as input, and attempts to convert it to IMOS compliant name and 
% unit of measurement. Returns empty string/vector if the parameter is not 
% supported.
%

  % the cast date, if present, is used for time field offset
  castDate = 0;
  if isfield(instHeader, 'castDate')
      castDate = instHeader.castDate;
  else
      if isfield(procHeader, 'startTime'), castDate = procHeader.startTime; end
  end
  
  [name, data, comment] = convertSBEcnvVar(name, data, castDate, instHeader, procHeader, mode);
end