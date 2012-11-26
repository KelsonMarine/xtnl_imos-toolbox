function sample_data = readXR420( filename, mode )
%readXR420 Parses a data file retrieved from an RBR XR420 depth logger.
%
% This function is able to read in a single file retrieved from an RBR
% XR420 data logger using RBR Windows v 6.13 software. The pressure data 
% is returned in a sample_data struct.
%
% Inputs:
%   filename    - Cell array containing the name of the file to parse.
%
% Outputs:
%   sample_data - Struct containing imported sample data.
%
% Author :      Laurent Besnard <laurent.besnard@utas.edu.au>
% Contributor : Guillaume Galibert <guillaume.galibert@utas.edu.au>

%
% Copyright (c) 2010, eMarine Information Infrastructure (eMII) and Integrated 
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
%     * Neither the name of the eMII/IMOS nor the names of its contributors 
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
  error(nargchk(1,2,nargin));
  
  if ~ischar(filename)  
    error('filename must be a string'); 
  end
  
  % open the file, and read in the header and data
  try 
    
    fid    = fopen(filename, 'rt');
    header = readHeader(fid);
    data   = readData(fid, header);
    fclose(fid);
  
  catch e
    if fid ~= -1, fclose(fid); end
    rethrow(e);
  end
  
  % copy all of the information over to the sample data struct
  sample_data = struct;

  sample_data.toolbox_input_file        = filename;
  sample_data.meta.instrument_make      = header.make;
  sample_data.meta.instrument_model     = header.model;
  sample_data.meta.instrument_firmware  = header.firmware;
  sample_data.meta.instrument_serial_no = header.serial;
  sample_data.meta.instrument_sample_interval = median(diff(data.time*24*3600));
  sample_data.meta.correction           = header.correction;
  
  switch mode
      case 'profile'
          % dimensions creation
          iVarPRES = NaN;
          iVarDEPTH = NaN;
          isZ = false;
          vars = fieldnames(data);
          nVars = length(vars);
          for k = 1:nVars
              if strcmpi('DEPTH', vars{k})
                  iVarDEPTH = k;
                  isZ = true;
                  break;
              end
              if strcmpi('PRES', vars{k})
                  iVarPRES = k;
                  isZ = true;
              end
              if ~isnan(iVarDEPTH) && ~isnan(iVarPRES), break; end
          end
          
          if ~isZ
              error('There is no pressure or depth information in this file to use it in profile mode');
          end
          
          depthComment = '';
          if ~isnan(iVarDEPTH)
              iVarZ = iVarDEPTH;
              depthData = data.(vars{iVarDEPTH});
          else
              iVarZ = iVarPRES;
              depthData = data.(vars{iVarPRES} - 10.1325);
              presComment = ['abolute '...
                  'pressure measurements to which a nominal '...
                  'value for atmospheric pressure (10.1325 dbar) '...
                  'has been substracted'];
              depthComment  = ['Depth computed from '...
                  presComment ', assuming 1dbar ~= 1m.'];
          end
          
          % let's distinguish descending/ascending parts of the profile
          nData = length(data.(vars{iVarZ}));
          zMax = max(data.(vars{iVarZ}));
          posZMax = find(data.(vars{iVarZ}) == zMax);
          iD = [true(posZMax, 1); false(nData-posZMax, 1)];
          
          nD = sum(iD);
          nA = sum(~iD);
          MAXZ = max(nD, nA);
          
          dNaN = nan(MAXZ-nD, 1);
          aNaN = nan(MAXZ-nA, 1);
          
          sample_data.dimensions{2}.name = 'INSTANCE';
          sample_data.dimensions{2}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.dimensions{2}.name, 'type')));
          if nA == 0
              sample_data.dimensions{1}.name = 'DEPTH';
              sample_data.dimensions{1}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.dimensions{1}.name, 'type')));
              sample_data.dimensions{1}.data = sample_data.dimensions{1}.typeCastFunc(depthData);
              sample_data.dimensions{1}.comment = depthComment;
              
              sample_data.dimensions{2}.data = sample_data.dimensions{2}.typeCastFunc(1);
          else
              sample_data.dimensions{1}.name = 'MAXZ';
              sample_data.dimensions{1}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.dimensions{1}.name, 'type')));
              sample_data.dimensions{1}.data = sample_data.dimensions{1}.typeCastFunc(1:1:MAXZ);
              
              sample_data.dimensions{2}.data = sample_data.dimensions{2}.typeCastFunc([1, 2]);
              disp(['Warning : ' sample_data.toolbox_input_file ...
                  ' is not IMOS CTD profile compliant. See ' ...
                  'http://imos.org.au/fileadmin/user_upload/shared/' ...
                  'IMOS%20General/documents/Facility_manuals/' ...
                  'NRS_sampling_Manual_Data_Processing_Guide_Draftv1_5b_IngletonMorris.pdf']);
          end
          
          % Add TIME, DIRECTION and POSITION infos
          descendingTime = data.time(iD);
          descendingTime = descendingTime(1);
          
          if nA == 0
              ascendingTime = [];
          else
              ascendingTime = data.time(~iD);
              ascendingTime = ascendingTime(1);
          end
          
          sample_data.variables{1}.dimensions   = 2;
          sample_data.variables{1}.name         = 'TIME';
          sample_data.variables{1}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.variables{1}.name, 'type')));
          sample_data.variables{1}.data         = sample_data.variables{1}.typeCastFunc([descendingTime, ascendingTime]);
          sample_data.variables{1}.comment      = 'First value over profile measurement';
          
          sample_data.variables{2}.dimensions   = 2;
          sample_data.variables{2}.name         = 'DIRECTION';
          sample_data.variables{2}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.variables{2}.name, 'type')));
          if nA == 0
              sample_data.variables{2}.data     = {'D'};
          else
              sample_data.variables{2}.data     = {'D', 'A'};
          end
          
          sample_data.variables{3}.dimensions   = 2;
          sample_data.variables{3}.name         = 'LATITUDE';
          sample_data.variables{3}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.variables{3}.name, 'type')));
          if nA == 0
              sample_data.variables{3}.data     = sample_data.variables{3}.typeCastFunc(NaN);
          else
              sample_data.variables{3}.data     = sample_data.variables{3}.typeCastFunc([NaN, NaN]);
          end
          
          sample_data.variables{4}.dimensions   = 2;
          sample_data.variables{4}.name         = 'LONGITUDE';
          sample_data.variables{4}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.variables{4}.name, 'type')));
          if nA == 0
              sample_data.variables{4}.data     = sample_data.variables{4}.typeCastFunc(NaN);
          else
              sample_data.variables{4}.data     = sample_data.variables{4}.typeCastFunc([NaN, NaN]);
          end
          
          sample_data.variables{5}.dimensions   = 2;
          sample_data.variables{5}.name         = 'BOT_DEPTH';
          sample_data.variables{5}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.variables{5}.name, 'type')));
          if nA == 0
              sample_data.variables{5}.data     = sample_data.variables{5}.typeCastFunc(NaN);
          else
              sample_data.variables{5}.data     = sample_data.variables{5}.typeCastFunc([NaN, NaN]);
          end
          
          % Manually add variable DEPTH if multiprofile and doesn't exit
          % yet
          if isnan(iVarDEPTH) && (nA ~= 0)
              sample_data.variables{end+1}.dimensions = [1 2];
              
              sample_data.variables{end  }.name       = 'DEPTH';
              sample_data.variables{end}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.variables{end}.name, 'type')));
              
              % we need to padd data with NaNs so that we fill MAXZ
              % dimension
              sample_data.variables{end  }.data       = sample_data.variables{end}.typeCastFunc([[depthData(iD); dNaN], [depthData(~iD); aNaN]]);
              
              sample_data.variables{end  }.comment    = depthComment;
          end
          
          % scan through the list of parameters that were read
          % from the file, and create a variable for each
          for k = 1:nVars
              % we skip TIME and DEPTH
              if strcmpi('TIME', vars{k}), continue; end
              if strcmpi('DEPTH', vars{k}) && (nA == 0), continue; end
              
              sample_data.variables{end+1}.dimensions = [1 2];
              
              comment.(vars{k}) = '';
              switch vars{k}
                  
                  %Conductivity (mS/cm) = 10-1*(S/m)
                  case 'Cond'
                      name = 'CNDC';
                      data.(vars{k}) = data.(vars{k})/10;
                      
                      %Temperature (Celsius degree)
                  case 'Temp', name = 'TEMP';
                      
                      %Pressure (dBar)
                  case 'Pres', name = 'PRES';
                      
                      %Fluorometry-chlorophyl (ug/l) = (mg.m-3)
                  case 'FlCa'
                      name = 'CPHL';
                      comment.(vars{k}) = ['Artificial chlorophyll data computed from ' ...
                          'fluorometry sensor raw counts measurements. Originally ' ...
                          'expressed in ug/l, 1l = 0.001m3 was assumed.'];
              end
              
              sample_data.variables{end  }.name       = name;
              sample_data.variables{end}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.variables{end}.name, 'type')));
              if nA == 0
                  sample_data.variables{end  }.data   = sample_data.variables{end}.typeCastFunc(data.(vars{k})(iD));
              else
                  % we need to padd data with NaNs so that we fill MAXZ
                  % dimension
                  sample_data.variables{end  }.data   = sample_data.variables{end}.typeCastFunc([[data.(vars{k})(iD); dNaN], [data.(vars{k})(~iD); aNaN]]);
              end
              sample_data.variables{end  }.comment    = comment.(vars{k});
              
              if all(~strcmpi({'TIME', 'DEPTH'}, vars{k}))
                  sample_data.variables{end  }.coordinates = 'TIME DEPTH LATITUDE LONGITUDE';
              end
          end
          
      otherwise
          % dimensions definition must stay in this order : T, Z, Y, X, others;
          % to be CF compliant
          sample_data.dimensions{1}.name = 'TIME';
          sample_data.dimensions{1}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.dimensions{1}.name, 'type')));
          sample_data.dimensions{1}.data = sample_data.dimensions{1}.typeCastFunc(data.time);
          sample_data.dimensions{2}.name = 'LATITUDE';
          sample_data.dimensions{2}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.dimensions{2}.name, 'type')));
          sample_data.dimensions{2}.data = sample_data.dimensions{2}.typeCastFunc(NaN);
          sample_data.dimensions{3}.name = 'LONGITUDE';
          sample_data.dimensions{3}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.dimensions{3}.name, 'type')));
          sample_data.dimensions{3}.data = sample_data.dimensions{3}.typeCastFunc(NaN);
          
          % copy variable data over
          data = rmfield(data, 'time');
          fields = fieldnames(data);
          
          for k = 1:length(fields)
              comment.(fields{k}) = '';
              switch fields{k}
                  
                  %Conductivity (mS/cm) = 10-1*(S/m)
                  case 'Cond'
                      name = 'CNDC';
                      data.(fields{k}) = data.(fields{k})/10;
                      
                      %Temperature (Celsius degree)
                  case 'Temp', name = 'TEMP';
                      
                      %Pressure (dBar)
                  case 'Pres', name = 'PRES';
                      
                      %Fluorometry-chlorophyl (ug/l) = (mg.m-3)
                  case 'FlCa'
                      name = 'CPHL';
                      comment.(fields{k}) = ['Artificial chlorophyll data computed from ' ...
                          'fluorometry sensor raw counts measurements. Originally ' ...
                          'expressed in ug/l, 1l = 0.001m3 was assumed.'];
              end
              
              sample_data.variables{k}.name       = name;
              sample_data.variables{k}.typeCastFunc = str2func(netcdf3ToMatlabType(imosParameters(sample_data.variables{k}.name, 'type')));
              sample_data.variables{k}.data       = sample_data.variables{k}.typeCastFunc(data.(fields{k}));
              sample_data.variables{k}.dimensions = [1 2 3];
              sample_data.variables{k}.comment    = comment.(fields{k});
          end
  end
end
  
function header = readHeader(fid)
%READHEADER Reads the header section from the top of the file.

  header = struct;
  lines  = {};
  
  line = fgetl(fid);
  
  % a single blank line separates the header from the data
  while ~isempty(line)
    
    lines = [lines line];
    line  = fgetl(fid);
  end
  
  % use regexp to read in all the important header information
  exprs = {
     '^([^ ]+) +([^ ]+) +([\d\.]+) +(\d+) '
    ['^Logging start +' '(\d\d/\d\d/\d\d \d\d:\d\d:\d\d)$']
    ['^Logging end +'   '(\d\d/\d\d/\d\d \d\d:\d\d:\d\d)$']
    ['^Sample period +'                '(\d\d:\d\d:\d\d)$']
     '^Correction to conductivity: (.*)$'
     '^Number of channels = +(\d)+, number of samples = +(\d)+'
  };
  
  for k = 1:length(lines)
    
    % try exprs until we get a match
    for m = 1:length(exprs)
    
      % check for the line containing start sample time
      tkns = regexp(lines{k}, exprs{m}, 'tokens');
      
      if isempty(tkns), continue; end
      
      switch m
        % instrument information
        case 1, header.make     = tkns{1}{1};
                header.model    = tkns{1}{2};
                header.firmware = tkns{1}{3};
                header.serial   = tkns{1}{4};
        
        % start of sampling
        case 2, header.start    = datenum(tkns{1}{1},   'yy/mm/dd HH:MM:SS');
        
        % end of sampling
        case 3, header.end      = datenum(tkns{1}{1},   'yy/mm/dd HH:MM:SS');
        
        % sample interval
        case 4, tkns{1}{1}      = ['0000/01/00 ' tkns{1}{1}];
                header.interval = datenum(tkns{1}{1}, 'yyyy/mm/dd HH:MM:SS');
        
        % comment
        case 5, header.correction  = tkns{1}{1};
        
        % number of channels, number of samples
        case 6, header.channels = str2double(tkns{1}{1});
                header.samples  = str2double(tkns{1}{2});
      end
    end
  end
end

function data = readData(fid, header)
%READDATA Reads the sample data from the file.

  data = struct;
  
  fmt  = '';
  
  % figure out number of columns from the number of channels
  for k = 1:header.channels, fmt = [fmt '%n']; end
  
  cols = {};
  
  % get the column names
  colLine = fgetl(fid);
  [col, colLine] = strtok(colLine);
  while ~isempty(colLine)
    
    cols           = [cols col];
    [col, colLine] = strtok(colLine);
  end
  cols{4}='FlCa'; %renaim FlC-a to FlCa because Matlbal doesn't understand - whitin a structure name
  % read in the sample data
  samples = textscan(fid, fmt);
  
  % save sample data into the data struct, 
  % using  column names as struct field names
  for k = 1:length(cols), data.(cols{k}) = samples{k}; end
  
  % regenerate interval from start/end time, and number of 
  % samples, rather than using the one listed in the header
  nSamples = length(samples{1});
  
 %This section is overwriting the interval with an incorrect value so can
 %we comment it out
 % header.interval = (header.end - header.start) / (nSamples-1); 
  
  % generate time stamps from start/interval/end
  data.time = header.start:header.interval:header.end;
  data.time = data.time(1:length(samples{1}))';
end