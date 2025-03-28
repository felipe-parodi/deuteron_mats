%% log_Read_sorted_NEX_file_CombinedChannels.m
%This script reads in a NEX file that has been created from the Deuteron logger system and sorted by OFS.
%It assumes an input that is Spike sorted in Offline Sorter and the unsorted cluster is present.
%It will output the standard SpikeData structures used in all of Sebastien's neural data scripts. Note however that the unsorted cluster has
%been excluded from the structure, which is untypical for my scripts.
%Created by SDT 20-10-30
%Updated by FP 24-10-07


clear Unit_rasters SpikeData neural_dir

%% Initialize data
%%cd('F:\EnclosureProjects\inprep\freemat\ephys_tests\240510_intan_spikesLFPs')
%cd('C:\Users\GENERAL\Dropbox (Penn)\Datalogger\Deuteron_Data_Backup\Sorted output')
filePath = uigetdir('', 'Please select the experiment directory'); % Enter the path for the location of your Deuteron sorted neural .nex files (one per channel)

%cd('C:\Users\GENERAL\Dropbox (Penn)\Datalogger\Deuteron_Data_Backup\Ready to analyze output')
%cd('F:\EnclosureProjects\inprep\freemat\ephys_tests\240424_mat2_spikesLFPs\hooke_1to7khz\nex5\spikedata')
outputPath = uigetdir('', 'Please select the output directory'); % Enter the path for the location of your data output
cd(filePath);
neural_dir = dir('*.nex*'); % Identify the files that correspond to each sorted channel. Note that this ordering is not linear using dir. This should be corrected. Its annoying, but functional.

for neural_file = 1:length(neural_dir) %[1:22, 32, 43, 54, 65, 67:69] % [11,22,32:52,61,71,83,93,104,114,125] % 
    
    fileName = neural_dir(neural_file).name; % Identify filename
    disp(fileName)
    Channel_number = regexp(fileName, '\d*', 'match'); %Identify number in file name, which corresponds to channel ID
    
    % Read in sorted NEX file into Matlab using this routine provided by NeuroExplorer.
    nex = readNexFile([filePath '/' fileName]);
    length_recording = nex.tend; %Define length of recording.
    
    %% Extract spike timings (Sorted neurons in Offline Sorter)

    %if length(nex.neurons) > 1 %If there are sorted units on this channel apart from the unsorted cluster
    if length(nex.neurons) > 0 %If there are only sorted units on this channel and no unsorted cluster
        
        %for i = 2:length(nex.neurons) %Unsorted cluster occupies the first position, discard.
        for i = 1:length(nex.neurons) 
            
            %timestamps_units{i-1} = nex.neurons{i}.timestamps;
            timestamps_units{i} = nex.neurons{i}.timestamps;
            unit_name =  nex.neurons{i}.name;
            channel_num = regexp(unit_name, '\d*', 'match');
           
            SpikeData.(['Channel_' channel_num{1}]){i} = timestamps_units{i};
            SpikeData.(['Channel_' channel_num{1}]) = SpikeData.(['Channel_' channel_num{1}])(~cellfun('isempty',SpikeData.(['Channel_' channel_num{1}])));
        end
        

    
    else
    
        SpikeData.(['Channel_' channel_num{1}]) = {};
        
    end
        
    clearvars -except SpikeData filePath neural_dir length_recording outputPath
    
end


%% Create structure with rasters over time for each neuron
temp_resolution = 1; %1 for second resolution, 1000 for msec resolution. etc.

Chan_name = fieldnames(SpikeData); %Identify channel names
C = regexp(Chan_name,'\d*','Match');
C_char = cellfun(@char, C{:}, 'UniformOutput', false);
Chan_num = str2num(C_char{1, 1});

% % % %Separate channels by array
% % % array1_chan = [1,2,5,6,9,10,13,14,17,18,21,22,25,26,29,30,33,34,37,38,41,...
% % %     42,45,46,49,50,53,54,57,58,61,62,65,66,69,70,73,74,77,78,81,82,85,86,...
% % %     89,90,93,94,97,98,101,102,105,106,109,110,113,114,117,118,121,122,125,126];
% % % 
% % % array2_chan = [3,4,7,8,11,12,15,16,19,20,23,24,27,28,31,32,35,36,39,40,...
% % %     43,44,47,48,51,52,55,56,59,60,63,64,67,68,71,72,75,76,79,80,83,84,...
% % %     87,88,91,92,95,96,99,100,103,104,107,108,111,112,115,116,119,120,123,124,127,128];
% % % 
% % % chan_idx_array1 = find(ismember(Chan_num,array1_chan))';
% % % chan_idx_array2 = find(ismember(Chan_num,array2_chan))';

unit=1;
for i = 1:length(fields(SpikeData)) %For all channels
    
    if ~isempty(SpikeData.(Chan_name{i})) %If there are sorted units on this channel
        for j = 1:length(SpikeData.(Chan_name{i})) %For all units
            
            Unit_rasters(unit,:) = zeros(1,round(length_recording*temp_resolution)); %Fill the line with zeros to initiate raster for that trial
            ticks = round(SpikeData.(Chan_name{i}){j}*temp_resolution);
            Spike_counts = hist(ticks, round(length_recording*temp_resolution));
            Unit_rasters(unit, :) = Spike_counts; %Fill in spikes in the raster
            clear ticks Spike_counts
            
            unit = unit+1;
        end
    end
    
end

% % % % %Correlation between units check
corr_matrix = corrcoef(Unit_rasters');
corr_matrix = corr_matrix.*~eye(size(corr_matrix));
heatmap(corr_matrix); colormap(jet)
% % % % 
threshold = 0.60;
corr_matrix_bin = zeros(size(corr_matrix));
corr_matrix_bin(find(abs(corr_matrix>threshold))) = corr_matrix(find(abs(corr_matrix>threshold)));
heatmap(corr_matrix_bin); colormap(jet)


%% Sanity check 
%Look at each traces in Unit_rasters and detect presence of abnormal signal drops or bursts of noise.
% close all
% for i = 1:size(Unit_rasters,1)
%     figure; plot(Unit_rasters(i,:)); title(['Unit',num2str(i)]) 
%     pause(1)
%     close
% end
% 
% flagged_units = [];
% %flagged_units = [55, 97, 84, 152, 275]; %Amos_2021_07_29
% 
% %Remove units which were visually flagged from Unit_rasters
% Unit_rasters(flagged_units,:)=[];

%% Save variables
[~, basename, ~] = fileparts(outputPath);
save(fullfile(outputPath, ['Neural_data_' basename '.mat']), 'Unit_rasters', 'SpikeData', 'neural_dir');

%save([outputPath '\Neural_data' outputPath(end-10:end) '.mat'],'Unit_rasters', 'SpikeData', 'neural_dir')

clear Unit_rasters SpikeData neural_dir