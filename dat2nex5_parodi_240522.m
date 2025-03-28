%% log_Prepare_NeuroExplorer_data_for_OFS
% This script takes in Deuteron logger data from the 128-channel Cereport logger and transforms it into .nx5 (Neuroexplorer) data format for
% quick loading into Offline Sorter. (previous attempts at loading .mat continuous files into OFS were too slow). This script assumes that
% Deuteron data is now organized by channel, using the Transposer.exe utility on Windows to concatenate native files from the microSD card.
% The script saves one file per channel, which is a must considering the very large size of Deuteron continuous recording files.
% Created by SdT 10/2020; modified by FP 240517

%% Initialize data
filePath = uigetdir('', 'Please select the experiment directory'); % Enter the path for the location of your Deuteron neural files (one per channel)
cd(filePath)
neural_dir = dir('*.DAT'); % Identify the many 16Mb files that Deuteron saves.

disp(neural_dir)

Sampling_rate = 32000; % in Hertz

if isempty(neural_dir)
    error('no dat files')
end

% Create a new directory 'nex5' at the same level as the 'dat' folder
[parentDir, ~, ~] = fileparts(filePath); % Get the parent directory of the current filePath
[~, baseFolderName, ~] = fileparts(parentDir); % Get the base folder name of the parent directory
nex5_dir = fullfile(parentDir, 'nex5');
if ~exist(nex5_dir, 'dir')
    mkdir(nex5_dir);
end

FirstfileName = neural_dir(1).name; % Identify filename
Firstfile_number = regexp(FirstfileName, '\d*', 'match'); %Identify number in file name, which should correspond to channels

if Firstfile_number{1} == '0'
    index_correct = 1; %Indexing of files starts at 0, let's correct that so it starts at 1.
else
    index_correct = 0;
end

%% Load and save .nex5
channel_num{1} = 1:32;
channel_num{2} = 33:64;
channel_num{3} = 65:96;
channel_num{4} = 97:128;

for part = 1:length(channel_num)
    for neural_file = channel_num{part}
        
        tic
        if neural_file == min(channel_num{part})
            nexFile = nexCreateFileData(Sampling_rate); % Init blank nex.
        end
        
        fileName = neural_dir(neural_file).name; % Identify filename
        file_number = fileName(end-6:end-4); % Identify number in file ~= channels
        
        myFile = fullfile(filePath, fileName);
        fid = fopen(myFile); % Open binary file
        data = fread(fid, 'uint16'); % Each data point of neural data is a 16-bit word
        fclose(fid);
        
        ext = 'DT6'; % For this 128-chan logger specifically
        metaData = log_GetMetaData(ext); % Set its parameters
        
        data = (metaData.voltageRes * (data - 2^(metaData.numADCBits - 1))) * 1e3; % Convert data to neural. *1e3 to convert to mV

        % Replace invalid data at beginning & end with zeros. 
        % Beginning: the amplifier settles; End: incomplete last data
        patched_seconds = 2; % sec
        data(end - Sampling_rate * patched_seconds:end) = 0;
        data(1:Sampling_rate * patched_seconds) = 0;
        %data(data <= -6) = 0; % CT added
        
        % Create continuous channel in the nex file.
        nexFile = nexAddContinuous(nexFile, 1 / Sampling_rate, Sampling_rate, data, ['Chan_' num2str(str2double(file_number) + index_correct)]);
        clear data % These are large files, clear some memory
        
        disp(['Wrote .nex5 file for Chan ' num2str(str2double(file_number) + index_correct) ' in ' num2str(round(toc)) ' seconds'])
    end
    
    % Save .nex5 file to disk
    nex5FilePath = fullfile(nex5_dir, ['Chan_' num2str(min(channel_num{part})) '-' num2str(max(channel_num{part})) '_' baseFolderName '.nex5']);
    disp(nex5FilePath)
    writeNex5File(nexFile, nex5FilePath);
    
    clearvars -except channel_num filePath neural_dir nex5_dir Sampling_rate FirstfileName Firstfile_number index_correct parentDir baseFolderName 
end

