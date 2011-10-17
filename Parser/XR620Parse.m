function sample_data = XR620Parse( filename )
%XR620PARSE Parses a data file retrieved from an RBR XR620 depth logger.
%
% This function is able to read in a single file retrieved from an RBR
% XR620 data logger in Engineering unit .txt format. The pressure data 
% is returned in a sample_data struct.
%
% Inputs:
%   filename    - Cell array containing the name of the file to parse.
%
% Outputs:
%   sample_data - Struct containing imported sample data.
%
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
 error(nargchk(1,1,nargin));
  
  if ~iscellstr(filename)  
    error('filename must be a cell array of strings'); 
  end
  
  % only one file supported
  filename = filename{1};
  
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
  
  sample_data.meta.instrument_make      = header.make;
  sample_data.meta.instrument_model     = header.model;
  sample_data.meta.instrument_firmware  = header.firmware;
  sample_data.meta.instrument_serial_no = header.serial;
  if header.interval > 0
      sample_data.meta.instrument_sample_interval = header.interval;
  else
      sample_data.meta.instrument_sample_interval = median(diff(data.time*24*3600));
  end
  
  % dimensions definition must stay in this order : T, Z, Y, X, others;
  % to be CF compliant
  sample_data.dimensions{1}.name = 'TIME';
  sample_data.dimensions{1}.data = datenum(data.Date, 'yy/mm/dd') + datenum(data.Time, 'HH:MM:SS.FFF') - datenum('00:00:00', 'HH:MM:SS');
  sample_data.dimensions{2}.name = 'LATITUDE';
  sample_data.dimensions{2}.data = NaN;
  sample_data.dimensions{3}.name = 'LONGITUDE';
  sample_data.dimensions{3}.data = NaN;
  
  % copy variable data over
  data = rmfield(data, 'Date');
  data = rmfield(data, 'Time');
  fields = fieldnames(data);
  
  l = 1;
  for k = 1:length(fields)
    
      name = '';
      comment = '';
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
          case 'FlC'
              name = 'CPHL';
              comment = ['Artificial chlorophyll data '...
            'computed from bio-optical sensor raw counts fluorometry. '...
            'Originally expressed in ug/l, 1l = 0.001m3 was assumed.'];
              
          %Turbidity (NTU)
          case 'Turb', name = 'TURB'; 
              
          %Rinko temperature (Celsius degree)    
          case 'R_Temp'
              name = '';
              comment = 'Corrected temperature.';
          
          %Rinko dissolved O2 (%)
          case 'R_D_O2', name = 'DOXS';
              
          %Depth (m)    
          case 'Depth', name = 'DEPTH';
              
          %Salinity (PSU)
          case 'Salin', name = 'PSAL';
              
          %Specific conductivity (uS/cm) = 10-4 * (S/m)
          case 'SpecCond'
              name = 'SPEC_CNDC';
              data.(fields{k}) = data.(fields{k})/10000;
              
          %Density anomaly (n/a)
          case 'DensAnom', name = '';
              
          %Speed of sound (m/s)
          case 'SoSUN', name = 'SSPD';
              
          %Rinko dissolved O2 concentration (mg/l) => (umol/l)
          case 'rdO2C'
              name = 'DOX1';
              comment = 'Originally expressed in mg/l, 1mg/l = 31.25umol/l was assumed.';
              data.(fields{k}) = data.(fields{k}) * 31.25;
      end
    
      if ~isempty(name)
          sample_data.variables{l}.name       = name;
          sample_data.variables{l}.data       = data.(fields{k});
          sample_data.variables{l}.dimensions = [1 2 3];
          sample_data.variables{l}.comment    = comment;
          l = l+1;
      end
      
      % Let's add a new parameter if DOX1, PSAL/CNDC, TEMP and PRES are present
      dox1 = getVar(sample_data.variables, 'DOX1');
      if dox1 ~= 0
          dox1 = sample_data.variables{dox1};
          name = 'DOX2';
          
          % umol/l -> umol/kg
          %
          % to perform this conversion, we need to calculate the
          % density of sea water; for this, we need temperature,
          % salinity, and pressure data to be present
          temp = getVar(sample_data.variables, 'TEMP');
          pres = getVar(sample_data.variables, 'PRES');
          psal = getVar(sample_data.variables, 'PSAL');
          cndc = getVar(sample_data.variables, 'CNDC');
          
          % if any of this data isn't present,
          % we can't perform the conversion to umol/kg
          if temp ~= 0 && pres ~= 0 && (psal ~= 0 || cndc ~= 0)
              temp = sample_data.variables{temp};
              pres = sample_data.variables{pres};
              if psal ~= 0
                  psal = sample_data.variables{psal};
              else
                  cndc = sample_data.variables{cndc};
                  % conductivity is in S/m and sw_c3515 in mS/cm
                  crat = 10*cndc.data ./ sw_c3515;
                  
                  psal.data = sw_salt(crat, temp.data, pres.data);
              end
              
              % calculate density from salinity, temperature and pressure
              dens = sw_dens(psal.data, temp.data, pres.data);
              
              % umol/l -> umol/kg (dens in kg/m3 and 1 m3 = 1000 l)
              data = dox1.data .* 1000.0 ./ dens;
              comment = ['Originally expressed in mg/l, assuming 1mg/l = 31.25umol/l '...
                  'and using density computed from Temperature, Salinity and Pressure '...
                  'using the Seawater toolbox.'];
              
              sample_data.variables{l}.dimensions             = [1 2 3];
              sample_data.variables{l}.comment                = comment;
              sample_data.variables{l}.name                   = name;
              sample_data.variables{l}.data                   = data;
          end
      end
  end
end
  
function header = readHeader(fid)
%READHEADER Reads the header section from the top of the file.

  header = struct;
  lines  = {};
  
  line = fgetl(fid);
  
  while isempty(strfind(line, 'Date & Time'))
    lines = [lines line];
    line  = fgetl(fid);
  end
  
  header.variables = strtrim(line);
  
  % use regexp to read in all the important header information
  exprs = {
    ['^Model=+' '(\S+)$']
    ['^Firmware=+' '(\S+)$']
    ['^Serial=+' '(\S+)$']
    ['^LoggingStartDate=+' '(\S+)$']
    ['^LoggingStartTime=+' '(\S+)$']
    ['^LoggingEndDate=+' '(\S+)$']
    ['^LoggingEndTime=+' '(\S+)$']
    ['^LoggingSamplingPeriod=+' '(\d+)Hz']
    ['^NumberOfChannels=+' '(\d+)']
    ['^CorrectionToConductivity=+' '(\d+)']
    ['^NumberOfSamples=+' '(\d+)']
  };
  
  startDate = '';
  startTime = '';
  endDate = '';
  endTime = '';

  for k = 1:length(lines)
    
    % try exprs until we get a match
    for m = 1:length(exprs)
    
      % check for the line containing start sample time
      tkns = regexp(lines{k}, exprs{m}, 'tokens');
      
      if isempty(tkns), continue; end
      
      header.make     = 'RBR';
      
      switch m
          % instrument information
          case 1
              header.model    = tkns{1}{1};
          case 2
              header.firmware = tkns{1}{1};
          case 3
              header.serial   = tkns{1}{1};
              
          % start of sampling
          case 4
              startDate    = tkns{1}{1};
          case 5
              startTime    = tkns{1}{1};
              
          % end of sampling
          case 6
              endDate    = tkns{1}{1};
          case 7
              endTime    = tkns{1}{1};
              
          % sample interval
          case 8
              header.interval = 1/str2double(tkns{1}{1});
              
          % number of channels
          case 9
              header.channels = str2double(tkns{1}{1});
          
          % correction to conductivity
          case 10
              header.correction  = tkns{1}{1};
              
          % number of samples
          case 11
              header.samples  = str2double(tkns{1}{1});
      end
    end
  end
  
  if ~isempty(startDate) && ~isempty(startTime)
      header.start    = datenum([startDate ' ' startTime],  'yy/mm/dd HH:MM:SS.FFF');
  end
  if ~isempty(endDate) && ~isempty(endTime)
      header.end      = datenum([endDate   ' ' endTime],    'yy/mm/dd HH:MM:SS.FFF');
  end
end

function data = readData(fid, header)
%READDATA Reads the sample data from the file.

  data = struct;
  
  % get the column names
  header.variables = strrep(header.variables, ' & ', '|');
  header.variables = strrep(header.variables, '  ', '|');
  while ~strcmpi(header.variables, strrep(header.variables, '||', '|'))
      header.variables = strrep(header.variables, '||', '|');
  end
  cols = textscan(header.variables, '%s', 'Delimiter', '|');
  cols = cols{1};
  
  % rename variables with '-', ' ', '&', '(', ')' as Matlab doesn't allow 
  % them within a structure name
  cols = strrep(cols, '-', '');
  cols = strrep(cols, ' ', '');
  cols = strrep(cols, '(', '');
  cols = strrep(cols, ')', '');
  cols = strrep(cols, '&', '');
  
  % first 2 columns are date and time
  fmt  = '%s %s';
  
  % figure out number of columns from the number of channels
  for k = 1:length(cols)-1, fmt = [fmt ' %f']; end
  
  % read in the sample data
  samples = textscan(fid, fmt);
  
  for k = 1:length(cols)
      % check that all columns have the same length. If not correct it.
      if k>1
          while length(samples{k}) < lenData
              samples{k}(end+1) = NaN;
          end
      else
          lenData = length(samples{k});
      end
      
      % save sample data into the data struct, 
      % using  column names as struct field names
      data.(cols{k}) = samples{k}; 
  end
end