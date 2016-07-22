function sample_data = echoviewParse( filename, platform, config )
%ECHOVIEWPARSE Parses EchoView results CSV file.
%
% This is an early draft attempt to parse an echoview results
% comma separated variable (CSV) file into a sample_data struct.
%
% This function is almost a generic CSV Parser.
% The list of fields to define and the column names that populate those
% fields are defined in a text file './Parser/echoview_config.txt' or the
% file specified by the property 'echoview.config' if defined.
%
% Limitations:
%   Text quoting is not properly supported (fields cannot contain ,)
%   Dates are only supported in the format yyyymmdd
%   Times are only supported in the format HH:MM:SS.ss
%   Timestamps are only supported as a date field followed by a time field
%   yyyymmdd, HH:MM:SS.ss
%
% Inputs:
%   filename    - CSV results file generated by echoview.
%   platform    - Platform code  
% 
% Outputs:
%   sample_data - Struct containing sample data.
%
% Externals:
%   Property 'echoview.config' and the file it specifies or
%   the file './Parser/echoview_config.txt'
%
% Author: Gordon Keith <gordon.keith@csiro.au>
% 

% Copyright (c) 2010, CSIRO.
% This source is based on and uses code fragments from code that is:
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
  narginchk(1,3);

  if ~iscellstr(filename), error('filename must be a cell array of strings'); end

  % only one file supported
  filename = filename{1};

  [voyage_path, fname, ext] = fileparts(filename);

  sample_data.toolbox_input_file                = filename;
  sample_data.meta.instrument_make              = 'Simrad';
  sample_data.meta.instrument_model             = 'ES60';
  sample_data.meta.instrument_serial_no         = '';
  sample_data.meta.instrument_sample_interval   = NaN;
  sample_data.meta.featureType                  = mode;
  
  sample_data.site_code='SOOP-BA';
  sample_data.meta.level=2;
  sample_data.EV_csv_file = [ fname ext ];
  
  %
  % Assume site/vessel/voyage directory structure and check for global
  % attribute files
  %
  
  [vessel_path, voyage] = fileparts(voyage_path);
  [site_path, vessel] = fileparts(vessel_path);
  
  sample_data = getAttributes(sample_data, fullfile(voyage_path, 'voyage_attributes.txt'));
  sample_data = getAttributes(sample_data, fullfile(vessel_path, 'vessel_attributes.txt'));
  sample_data = getAttributes(sample_data, fullfile(site_path, 'site_attributes.txt'));
  
  % Get platform attributes
  
  if nargin == 1 || isempty(platform)
    platform = getPlatform();
  end
  
  path = '';
  if ~isdeployed, [path, ~, ~] = fileparts(which('imosToolbox.m')); end
  if isempty(path), path = pwd; end
  sample_data = getAttributes(sample_data, ...
      fullfile(path, 'NetCDF', 'platform', [ platform '_attributes.txt' ] ));
  
  %
  % map maps CSV columns to sample_data variables and dimensions
  %
  
  if nargin < 3 || isempty(config)
  % get path to config file
    try
      config = readProperty('echoview.config');
    catch e
      config ='';
    end
  end
  
  if isempty(config) || ~exist(config, 'file')
    config = fullfile(path, 'Parser', 'echoview_config.txt');
  end
  
 map = getFieldMap(config);
  
  % open the file, and read in the header and data
  try 
    sample_data.dimensions = {};
    sample_data.variables  = {};
  
    fid    = fopen(filename, 'rt');
    
    %
    % read in and parse header
    %
    line = fgetl(fid);
    line(line > 127) = 32;
    map = findColumns(map, line);
    
    % extract dimensions
    dimensions = 0;
    for k = 1:length(map)
       if (map(k).column > 0) && isempty(map(k).dimension) 
           dimensions = dimensions + 1;
           sample_data.dimensions{dimensions}.name = map(k).name;
           sample_data.dimensions{dimensions}.column = map(k).column;
           sample_data.dimensions{dimensions}.type = map(k).type;
           if isfield(map(k), 'qc')
               sample_data.dimensions{dimensions}.qcexp = map(k).qc;
           end
           if map(k).type == 'S'
               sample_data.dimensions{dimensions}.data = '';
           else
               sample_data.dimensions{dimensions}.data = [ ];
           end
       end
    end
    
    % extract variables
    variables = 0;
    for k = 1:length(map)
       if (map(k).column > 0) && ~ isempty(map(k).dimension)
           variables = variables + 1;
           sample_data.variables{variables}.name = map(k).name;
           sample_data.variables{variables}.column = map(k).column;
           sample_data.variables{variables}.type = map(k).type;
           if isfield(map(k), 'qc')
               sample_data.variables{variables}.qcexp = map(k).qc;
           end
           sample_data.variables{variables}.dimensions = [];
           if map(k).type == 'S'
               sample_data.variables{dimensions}.data = '';
           else
               sample_data.variables{dimensions}.data = [ ];
           end
           dims = regexp(map(k).dimension, '\s', 'split');
           for d = 1:length(sample_data.dimensions)
               for dd = 1:length(dims)
                 if strcmp(sample_data.dimensions{d}.name, dims(dd))
                    sample_data.variables{variables}.dimensions(dd) = d;
                 end
               end
           end
       end
    end
    
    index = zeros(1,length(sample_data.dimensions));
    
    %
    % read in and parse each line
    %
    line = fgetl(fid);
    while ischar(line)
      fields = getCSVfields(line);
      if length(fields) < 4
          line = fgetl(fid);
          continue;
      end
      
      % read dimensions
      for k = 1:length(sample_data.dimensions)
          column = sample_data.dimensions{k}.column ;
          type = sample_data.dimensions{k}.type;
          value = getValue(fields, column, type);

          % find value in existing data
          index(k) = 0;
          if type == 'S'
              % text string
              for d = 1:size(sample_data.dimensions{k}.data,1)
                  if strcmp(value, char(sample_data.dimensions{k}.data(d,:)))
                      index(k) = d;
                  break;
                  end
              end
              if index(k) == 0
                  % new value
                  index(k) = size(sample_data.dimensions{k}.data,1) + 1;
                  sample_data.dimensions{k}.data(end + 1,:) = value;
              end
          else
              % numeric scalar
              match = find(value == sample_data.dimensions{k}.data,1);
              if isempty(match)
                  % new value
                  index(k) = length(sample_data.dimensions{k}.data) +1;
                  sample_data.dimensions{k}.data(index(k)) = value;
              else
                  index(k) = match(1);
              end
          end
          
      end
      
      % get the next line
      line = fgetl(fid);
        
    end
    
    fclose(fid);
 
    % pre-allocate space for variables
    
    for k = 1:length(sample_data.variables)
        type = sample_data.variables{k}.type;
        dimensions = sample_data.variables{k}.dimensions;
        if type == 'S'
            switch size(dimensions,2)
                case 1
                    sample_data.variables{k}.data = ...
                        cell(length(sample_data.dimensions{dimensions(1)}.data), 1);
                    
                case 2
                    sample_data.variables{k}.data = ...
                        cell(length(sample_data.dimensions{dimensions(1)}.data), ...
                              length(sample_data.dimensions{dimensions(2)}.data));
                    
                case 3
                    sample_data.variables{k}.data = ...
                        cell(length(sample_data.dimensions{dimensions(1)}.data), ...
                              length(sample_data.dimensions{dimensions(2)}.data), ...
                              length(sample_data.dimensions{dimensions(3)}.data));
                    
                case 4
                    sample_data.variables{k}.data = ...
                        cell(length(sample_data.dimensions{dimensions(1)}.data), ...
                              length(sample_data.dimensions{dimensions(2)}.data), ...
                              length(sample_data.dimensions{dimensions(3)}.data), ...
                              length(sample_data.dimensions{dimensions(4)}.data));
                    
            end
        else
            switch size(dimensions,2)
                case 1
                    sample_data.variables{k}.data = ...
                        zeros(length(sample_data.dimensions{dimensions(1)}.data), 1);
                    
                case 2
                    sample_data.variables{k}.data = ...
                        zeros(length(sample_data.dimensions{dimensions(1)}.data), ...
                              length(sample_data.dimensions{dimensions(2)}.data));
                    
                case 3
                    sample_data.variables{k}.data = ...
                        zeros(length(sample_data.dimensions{dimensions(1)}.data), ...
                              length(sample_data.dimensions{dimensions(2)}.data), ...
                              length(sample_data.dimensions{dimensions(3)}.data));
                    
                case 4
                    sample_data.variables{k}.data = ...
                        zeros(length(sample_data.dimensions{dimensions(1)}.data), ...
                              length(sample_data.dimensions{dimensions(2)}.data), ...
                              length(sample_data.dimensions{dimensions(3)}.data), ...
                              length(sample_data.dimensions{dimensions(4)}.data));
                    
            end
        end
    end
    
    % read variables
    fid    = fopen(filename, 'rt');
    fgetl(fid);  % header
    line = fgetl(fid);
    while ischar(line)
      fields = getCSVfields(line);
      if length(fields) < 4
          line = fgetl(fid);
          continue;
      end
      
      for k = 1:length(sample_data.dimensions)
          column = sample_data.dimensions{k}.column ;
          type = sample_data.dimensions{k}.type;
          value = getValue(fields, column, type);

          % find value in existing data
          index(k) = 0;
          if type == 'S'
              % text string
              for d = 1:size(sample_data.dimensions{k}.data,1)
                  if strcmp(value, char(sample_data.dimensions{k}.data(d,:)))
                      index(k) = d;
                  break;
                  end
              end
          else
              % numeric scalar
              match = find(value == sample_data.dimensions{k}.data,1);
              index(k) = match(1);
          end
      end
      
      % read variables
      for k = 1:length(sample_data.variables)
          column = sample_data.variables{k}.column ;
          type = sample_data.variables{k}.type;
          dimensions = sample_data.variables{k}.dimensions;
          value = getValue(fields, column, type);

        if type == 'S'
          switch size(dimensions,2)
              case 1
                sample_data.variables{k}.data{index(dimensions)} = value;
                
              case 2
                  sample_data.variables{k}.data{index(dimensions(1)), ...
                                                index(dimensions(2))} = value;
              case 3
                  sample_data.variables{k}.data{index(dimensions(1)), ...
                                                index(dimensions(2)), ...
                                                index(dimensions(3))} = value;
              case 4
                  sample_data.variables{k}.data{index(dimensions(1)), ...
                                                index(dimensions(2)), ...
                                                index(dimensions(3)), ...
                                                index(dimensions(4))} = value;
          end
        else
          switch size(dimensions,2)
              case 1
                sample_data.variables{k}.data(index(dimensions)) = value;
                
              case 2
                  sample_data.variables{k}.data(index(dimensions(1)), ...
                                                index(dimensions(2))) = value;
              case 3
                  sample_data.variables{k}.data(index(dimensions(1)), ...
                                                index(dimensions(2)), ...
                                                index(dimensions(3))) = value;
              case 4
                  sample_data.variables{k}.data(index(dimensions(1)), ...
                                                index(dimensions(2)), ...
                                                index(dimensions(3)), ...
                                                index(dimensions(4))) = value;
          end
        end
      end
      
      % get the next line
      line = fgetl(fid);
        
    end
    
    fclose(fid);
  
  catch e
    if fid ~= -1, fclose(fid); end
    rethrow(e);
  end
  
  %
  % apply quality control formulae
  %
  sample_data = evalQC(sample_data);
   
  %
  % get global bouds
  %
  sample_data = getBounds(sample_data);
  
  %
  % Convert singletons to globals.
  %
  remove = [];
  remove_var = [];
  for k = 1:length(sample_data.dimensions)
      dimension = sample_data.dimensions{k};
      if (dimension.type == 'S')
          if size(dimension.data,1) == 1
              sample_data.(dimension.name) = char(dimension.data);
              remove(end + 1) = k;
          end
      else
          if length(dimension.data) == 1
              sample_data.(dimension.name) = dimension.data;
              remove(end + 1) = k;
          end
      end
  end
 
  % remove singleton dimensions from variables and renumber remaining dimensions
  for k = 1:length(sample_data.variables)
      dd = sample_data.variables{k}.dimensions;
      dd(ismember(dd,remove)) = [];
      if isempty(dd)
          % variable is also a singleton
          if sample_data.variables{k}.type == 'S'
              sample_data.(sample_data.variables{k}.name) = ...
                  char(sample_data.variables{k}.data);
          else
              sample_data.(sample_data.variables{k}.name) = ...
                  sample_data.variables{k}.data;
          end
          remove_var(end + 1) = k;
      else
          for ddd = 1:length(dd)
              dd(ddd) = dd(ddd) - sum(dd(ddd) > remove);
          end
          sample_data.variables{k}.dimensions = dd;
      end
  end
  sample_data.dimensions(remove) = [];
  sample_data.variables(remove_var) = [];
  
  %
  % remove column and type
  %
  for k = 1:length(sample_data.dimensions)
      sample_data.dimensions{k} = rmfield(sample_data.dimensions{k}, 'column');
      sample_data.dimensions{k} = rmfield(sample_data.dimensions{k}, 'type');
  end
  for k = 1:length(sample_data.variables)
      sample_data.variables{k} = rmfield(sample_data.variables{k}, 'column');
      sample_data.variables{k} = rmfield(sample_data.variables{k}, 'type');
  end

  %
  % transpose non-time vectors
  %
  for k = 1:length(sample_data.variables)
      if length(sample_data.variables{k}.dimensions) == 1
          sample_data.variables{k}.data = sample_data.variables{k}.data';
      end
  end
  
  %
  % Populate variables need for file name generation
  %
  
  if isfield(sample_data, 'vessel_name')
      sample_data.meta.site_name = sample_data.vessel_name;
  end
  
  if isfield(sample_data, 'frequency')
      sample_data.meta.depth = sample_data.frequency;
  end
  
  if isfield(sample_data, 'make')
      sample_data.meta.instrument_make = sample_data.make;
  end

  if isfield(sample_data, 'sounder')
      sample_data.meta.instrument_model = sample_data.sounder;
  end

  if isfield(sample_data, 'channel')
      sample_data.meta.instrument_serial_no = sample_data.channel;
  end

end

function field_map = getFieldMap( config )
%GETFIELDMAP returns a map of Variables. 
% Each entry has :
% - the variable name as it will appear in sample_data, 
% - the variables column name as it will appear in the CSV file,
% - the variable's dimension(s), 
% - the variable's type, 
% - quality control formula
% 

  try
      
    fid = fopen(config, 'rt');
    k = 1;
    field_map = struct;
    
    % read in and parse each line
    line = fgetl(fid);
    while ischar(line)
      
      fields = strtrim(regexp(line, ',', 'split'));
      if length(fields) < 4 || line(1) == '#' || line(1) == '%'
          line = fgetl(fid);
          continue;
      end
      
      field_map(k).name = fields{1};
      field_map(k).column_name = fields{2};
      field_map(k).dimension = fields{3};
      field_map(k).type = fields{4};
      if length(fields) > 4
          field_map(k).qc = fields{5};
      end
      
      k = k + 1;
      
      % get the next line
      line = fgetl(fid);
    end
    
    fclose(fid);
  catch e
    if fid ~= -1, fclose(fid); end
    rethrow(e);
  end

end

function field_map = findColumns(field_map, line)
%FINDCOLUMNS takes a CSV header line and matches the column names with
% the column names listed in the field_map.
% The matching column number is stored in the field_map.

    columns = getCSVfields(line);
    
    for k = 1:length(field_map)
        field_map(k).column = 0;
       for j = 1:length(columns)
           if strcmp(columns{j}, field_map(k).column_name)
              field_map(k).column = j; 
           end
       end
       if field_map(k).column == 0
           error(['Could not locate column ' field_map(k).column_name]);
       end
    end

end

function value = getValue(fields, column, type)
%GETVALUE get a value from the indicated column of the specified type
%
% TODO current support for date and time is only yyyymmdd, HH:MM:SS.ss
% it would be nice to support more date/time formats

    value = fields{column};
    if type == 'S'
        if value(1) == '"' && value(end) == '"'
            value([1 end]) = '';
        end
    elseif type == 'N'
        value = str2double(value);
    elseif type == 'D'
        value = datenum(value, 'yyyymmdd');
    elseif type == 'T'
        value = datenum([value '0'], 'HH:MM:SS.FFF');
    elseif strcmp(type,'DT')
        % performance bottleneck
        %value = strcat(value,  fields(column +1), '0');
        %value = datenum(value, 'yyyymmddHH:MM:SS.FFF');
        yr = str2double(value(1:4));
        mm = str2double(value(5:6));
        dd = str2double(value(7:8));
        value = fields{column +1};
        hh = str2double(value(1:2));
        mn = str2double(value(4:5));
        ss = str2double(value(7:end));
        value = datenum(yr, mm, dd, hh, mn, ss);
    end
end

function fields = getCSVfields(line)
%GETCSVFIELDS convert a line of a comma separated variable line to an array
% of string fields.
%
% This function is responsible for handling quoted fields etc, 
% which this version doesn't do.
%
% TODO handle text fields that contain commas

    fields = strtrim(regexp(line, ',', 'split'));
    
end

function sample_data = getAttributes(sample_data, file)
%GETATTRIBUTES reads global attributes from the specified file and adds
% them to sample_data

listing = dir(file);
if length(listing) == 1 && listing(1).isdir == 0
    try
        globAtts = parseNetCDFTemplate(file, sample_data);
        sample_data = mergeAtts(sample_data, globAtts);
    catch e
        warning('PARSE:bad_attr_file', ...
            ['Unable to read attributes from ' file ' : ' e.identifier]);
    end
end
end

function platform = getPlatform
%GETPLATFORM gets a platform code, possibly from the user.

path = '';
if ~isdeployed, [path, ~, ~] = fileparts(which('imosToolbox.m')); end
if isempty(path), path = pwd; end
path = fullfile(path, 'NetCDF', 'platform');

pattern = '^(.+)_attributes\.txt$';

platforms = listFiles(path, pattern);

if isempty(platforms)
    error ('PARSE:no_platforms', 'No platforms found in %s', path);
else
platform = optionDialog('Select platform', ...
    'Select the platform on which this data was collected', platforms, 1);
end
end

function sample_data = getBounds(sample_data)
%GETBOUNDS reads data limits from the data and assigns the corresponding
% global attributes.

  % set the time range
  mintime = NaN;
  maxtime = NaN;
  time = getVar(sample_data.dimensions, 'TIME');
  if time ~= 0
      mintime = min(sample_data.dimensions{time}.data);
      maxtime = max(sample_data.dimensions{time}.data);
  else
      time = getVar(sample_data.variables, 'TIME');
      if time ~= 0
          mintime = min(sample_data.variables{time}.data);
          maxtime = max(sample_data.variables{time}.data);
      end
  end
  
  if ~ isfield(sample_data, 'time_coverage_start') && ~ isnan(mintime)
      sample_data.time_coverage_start = mintime;
  end
  if ~ isfield(sample_data, 'time_coverage_end') && ~ isnan(maxtime)
      sample_data.time_coverage_end = maxtime;
  end

  % set the geographic range
  goodlon = [];
  lon = getVar(sample_data.dimensions, 'LONGITUDE');
  if lon ~= 0
      goodlon = sample_data.dimensions{lon}.data;
  else
      lon = getVar(sample_data.variables, 'LONGITUDE');
      if lon ~= 0
          goodlon = sample_data.variables{lon}.data;
      end
  end
  goodlon = goodlon(goodlon >= -360 & goodlon <= 360);
  
  if ~ isempty(goodlon)
      minlon = min(goodlon);
      maxlon = max(goodlon);
      if (maxlon - minlon > 350)
          minlon = min(goodlon(goodlon > 0));
          maxlon = max(goodlon(goodlon < 0));
      end
      sample_data.geospatial_lon_min = minlon;
      sample_data.geospatial_lon_max = maxlon;
  end
  
  goodlat = [];
  lat = getVar(sample_data.dimensions, 'LATITUDE');
  if lat ~= 0
      goodlat = sample_data.dimensions{lat}.data;
  else
      lat = getVar(sample_data.variables, 'LATITUDE');
      if lat ~= 0
          goodlat = sample_data.variables{lat}.data;
      end
  end
  goodlat = goodlat(goodlat >= -90 & goodlat <= 90);
  
  if ~ isempty(goodlat)
      minlat = min(goodlat);
      maxlat = max(goodlat);
      sample_data.geospatial_lat_min = minlat;
      sample_data.geospatial_lat_max = maxlat;
  end

  
  % set the depth range
  mindepth = NaN;
  maxdepth = NaN;
  depth = getVar(sample_data.dimensions, 'DEPTH');
  if depth ~= 0
      mindepth = min(sample_data.dimensions{depth}.data);
      maxdepth = max(sample_data.dimensions{depth}.data);
  else
      depth = getVar(sample_data.variables, 'DEPTH');
      if depth ~= 0
          mindepth = min(sample_data.variables{depth}.data);
          maxdepth = max(sample_data.variables{depth}.data);
      end
  end
  
  if ~ isfield(sample_data, 'geospatial_vertical_min') && ~ isnan(mindepth)
      sample_data.geospatial_vertical_min = mindepth;
  end
  if ~ isfield(sample_data, 'geospatial_vertical_max') && ~ isnan(maxdepth)
      sample_data.geospatial_vertical_max = maxdepth;
  end

end


function target = mergeAtts ( target, atts )
%MERGEATTS copies the fields in the given atts struct into the given target
%struct.
%

  fields = fieldnames(atts);
  
  for m = 1:length(fields)
    
    % don't overwrite existing fields in the target
    if isfield(target, fields{m}), continue; end;
    
    target.(fields{m}) = atts.(fields{m});
  end
end

function sample_data = evalQC(sample_data)
%EVALQC evaluates the expression in the context where each dimension and
%variable name represents its data.

if isfield(sample_data.dimensions{1}, 'qcexp') || isfield(sample_data.variables{1}, 'qcexp')
    
    % put existing dimensions and variables into eval environment
    for k = 1:length(sample_data.dimensions)
        eval([sample_data.dimensions{k}.name ' = sample_data.dimensions{k}.data;']);
    end
    for k = 1:length(sample_data.variables)
        eval([sample_data.variables{k}.name ' = sample_data.variables{k}.data;']);
    end
    
    %
    % apply quality control formulae
    %
    for k = 1:length(sample_data.dimensions)
        if isfield(sample_data.dimensions{k}, 'qcexp') && ...
                ~isempty(sample_data.dimensions{k}.qcexp)
            sample_data.dimensions{k}.flags = eval(sample_data.dimensions{k}.qcexp);
            sample_data.dimensions{k} = rmfield(sample_data.dimensions{k}, 'qcexp');
        end
    end
    
    for k = 1:length(sample_data.variables)
        if isfield(sample_data.variables{k}, 'qcexp') && ...
                ~isempty(sample_data.variables{k}.qcexp)
            sample_data.variables{k}.flags = eval(sample_data.variables{k}.qcexp);
            sample_data.variables{k} = rmfield(sample_data.variables{k}, 'qcexp');
        end
    end
end

end

