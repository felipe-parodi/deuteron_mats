function [Spike_rasters, labels, labels_partner, behav_categ, block_times, monkey,...
    unit_count, groom_labels_all, brain_label, behavior_log, behav_categ_original] = ...
    log_GenerateDataToRes_function(filePath, temp_resolution, channel_flag, is_mac,...
    with_MUC, isolatedOnly, smooth, sigma, threat_precedence, exclude_sq)

%This function allows loading the data from Offline sorter (OFS),
%deuteron and behavioral annotation files, converting the data into
%data formats easily manipulable in matlab.

%Created by C. Testard in Dec. 2021
%Last reviewed by C. Testard in Jan. 2024

%Log GenerateDataToRes_function
% Input data:
%   1. Behavior of the subject: "EVENTLOG_restructured.csv"
%   2. Behavior of the partner: "EVENTLOG_restructured_partner.csv"
%   3. Spike sorted neural data: "Neural_data_*sessionname*.mat" OR
%   "Neural_data_*sessionname*_isolatedunits.mat"
%   4. Block info: "session_block_schedule.csv"

% Arguments:
%   filePath: is the experimental data path
%   Temp_resolution: is the temporal resolution at which we would like to
%   analyze the data. 1:1sec; 10:100msec; 0.1:10sec
%   Channel_flag: specifies with channels to include: only "TEO" array, only
%   "vlPFC" array or "all" channels
%   is_mac: specifies whether the code is run on a mac or pc
%   with_MUC: specifies whether the "multi-unit cluster" (or the first cell of
%   every channel) is included (1) or not (0). If with_MUC=2 then we only
%   include the multi-unit cluster (not well-isolated neurons).
%   isolatedOnly: specifies if only the well isolated units are considered.
%   smooth: is the data smoothed using function conv.
%   sigma: size of smoothing
%   threat_precedence: do threat event labels take over other behavior lbls.
%   exclude_sq: exclude squeeze events

% Specifically, this function formats the raw input data to have the following elements (output data):
% 1. Spike_rasters: Neural data matrix, size [Time (to chosen resolution) x #neurons]
% 2. labels: Label vector which describes the behavior at time t [Time (to chosen resolution) x 13]
%       1st column includes all behaviors in "plain english"
%       2nd column behavior number code
%       3rd column unique behavior code (when two occur
%       simultaneously, we chose one, see below for details)
%       4th column whether behavior happens in isolation or co-occurs
%       with another. String description.
%       5th column numerical code for the type of co-occurrence
%       6th column is the behavior "reciprocal" (i.e. partner behavior can
%       be 100% predicted by subject behavior and vice-versa)
%       7th column binary code reciprocal (1) vs. not (0)
%       8th column is the behavior "social" or not (i.e. done with a
%       conspecific)
%       9th column binary code for social (1) or not (0).
%       10th column indicates the block ID in which we are
%       (Paired, "female" neighbor; Paired, "male" neighbor or "alone")
%       11th column gives a corresponding numerical value to the block order in time (1st, 2nd 3rd).
%       12th column is a numerical version of block ID (social context).
%       13th column whether individual is paired (1) or alone (0)
% 3. labels_partner: same as above but for the partner [in this version
% left  blank since we did not consider the partner behavior in the study]
% 4. behav_categ: behavioral categories
% 5. block_times: Order and timing of blocks during the session
% 6. monkey: ID of the subject monkey
% 7. reciprocal_set: Set of reciprocal behaviors
% 8. social_set: Set of social behaviors
% 9. unit_count: Number of units per brain area
% 10.groom_labels_all: Label of grooming category. Columns correspond to:
%       1. Behavior label. If not grooming (7 groom give, 8 groom receive),
%       then all categories below will be 0. If grooming, the bout can be
%       qualified as:
%       2. Is it the start (1), end (2) or middle (3) of grooming bout
%       3. Grooming after a threat (2) or not (1)
%       4. Grooming reciprocated (2) or not (1)
%       5. Grooming initiated by subject (2) or not (1)
% 11.brain_label: brain area label for each unit
% 12.behavior_log: raw behavioral log
% 13.behav_categ_original: original category labeling

% Camille Testard - Created Nov. 2021
% Last update - Jan. 2024

%% Load data

cd(filePath)

if is_mac
    split = '/';
else
    split = '\';
end
split_file_name = strsplit(filePath,split); full_session_name = split_file_name{end}; session_name_split = strsplit(full_session_name,'_');
session = session_name_split{2};
monkey = session_name_split{1};

%Load neural data
if isolatedOnly==1
    load(['Neural_data_' session '_IsolatedUnits.mat'])%only including well isolated units (available for certain sessions only)
else
    load(['Neural_data_' session '.mat']) % Load neural data; array1 is in TEO and array2 is in vlPFC
end
length_recording = size(Unit_rasters,2); %Unit rasters in second resolution

%get unit count
num_unit_allsessions = readtable('~/Dropbox (Penn)/Datalogger/Results/All_sessions/Number of units/Session_log_num_units.csv');% Load number of unit data
session_idx = find(~cellfun(@isempty,(strfind(num_unit_allsessions.session_name,session))));
unit_count = [num_unit_allsessions.num_units_vlPFC(session_idx), num_unit_allsessions.num_units_TEO(session_idx), num_unit_allsessions.num_units(session_idx)];

%Load behavioral data
behavior_log = readtable('EVENTLOG_restructured.csv');% for subject
block_log = readtable('session_block_schedule.csv');% for block info

% Assign threat to partner and threat to subject labels to sq events.
if exclude_sq
    index=find(strcmp('SS',behavior_log{:,'Behavior'}));
    behavior_log{index,'Behavior'}={'HIS'};
    index=find(strcmp('SP',behavior_log{:,'Behavior'}));
    behavior_log{index,'Behavior'}={'HIP'};
end


%% Preprocessing: behavioral log and neural data at specified resolution

%Round times and get duration for behavioral logs (subject & partner)
behavior_log{:,'start_time_round'}=round(behavior_log{:,'start_time'}*temp_resolution);
behavior_log{:,'end_time_round'}=round(behavior_log{:,'end_time'}*temp_resolution);
behavior_log{:,'duration_round'}=behavior_log{:,'end_time_round'}-behavior_log{:,'start_time_round'};

%Eliminate behaviors that do not meet the minimum length
%Note that this will be an issue only for time resolution >1sec
min_length = 1/temp_resolution;
idx = find(behavior_log{:,'duration_round'}<min_length);
behavior_log{idx,'start_time_round'} = 0; behavior_log{idx,'end_time_round'} = 0;

%Get block times (at the end of the EventLog_Restructured)
block_times = behavior_log(end-2:end,:);
behavior_log(end-2:end,:) = [];
labels_partner=[];


%% Neural data

Chan_name = fieldnames(SpikeData); %Identify channel names
C = regexp(Chan_name,'\d*','Match');
C_char = cellfun(@char, C{:}, 'UniformOutput', false);
Chan_num = str2num(C_char{1, 1});

%Separate channels by array
%IMPORTANT NOTE: the channel mapping is reversed for each monkey
if strcmp(monkey,'Hooke')

    TEO_chan = [1,2,5,6,9,10,13,14,17,18,21,22,25,26,29,30,33,34,37,38,41,...
        42,45,46,49,50,53,54,57,58,61,62,65,66,69,70,73,74,77,78,81,82,85,86,...
        89,90,93,94,97,98,101,102,105,106,109,110,113,114,117,118,121,122,125,126];

    vlPFC_chan = [3,4,7,8,11,12,15,16,19,20,23,24,27,28,31,32,35,36,39,40,...
        43,44,47,48,51,52,55,56,59,60,63,64,67,68,71,72,75,76,79,80,83,84,...
        87,88,91,92,95,96,99,100,103,104,107,108,111,112,115,116,119,120,123,124,127,128];

elseif strcmp(monkey,'Amos')

    vlPFC_chan = [1,2,5,6,9,10,13,14,17,18,21,22,25,26,29,30,33,34,37,38,41,...
        42,45,46,49,50,53,54,57,58,61,62,65,66,69,70,73,74,77,78,81,82,85,86,...
        89,90,93,94,97,98,101,102,105,106,109,110,113,114,117,118,121,122,125,126];

    TEO_chan = [3,4,7,8,11,12,15,16,19,20,23,24,27,28,31,32,35,36,39,40,...
        43,44,47,48,51,52,55,56,59,60,63,64,67,68,71,72,75,76,79,80,83,84,...
        87,88,91,92,95,96,99,100,103,104,107,108,111,112,115,116,119,120,123,124,127,128];

end

chan_idx_TEO = find(ismember(Chan_num,TEO_chan))';
chan_idx_vlPFC = find(ismember(Chan_num,vlPFC_chan))';

%Select channels
if strcmp(channel_flag,'TEO')
    channels = chan_idx_TEO;
elseif strcmp(channel_flag,'vlPFC')
    channels = chan_idx_vlPFC;
elseif strcmp(channel_flag,'all')
    channels = 1:length(fields(SpikeData)); %all channels
end

%Create spike matrix structure

if with_MUC==0 %If don't include multi-unit cluster
    unit=1;
    for i = channels %For all channels
        if length(SpikeData.(Chan_name{i}))>1 %If there are sorted units on this channel
            for j = 2:length(SpikeData.(Chan_name{i})) %For all units except Noise cluster

                Spike_rasters(unit,:) = zeros(1,round(length_recording*temp_resolution)); %Fill the line with zeros to initiate raster for that trial (IMPORTANT NOTE: removed +1)
                ticks = round(SpikeData.(Chan_name{i}){j}*temp_resolution);
                Spike_counts = hist(ticks, 1:round(length_recording*temp_resolution));
                Spike_rasters(unit, :) = Spike_counts; %Fill in spikes in the raster
                clear ticks Spike_counts

                if ismember(Chan_num(i),TEO_chan)
                    brain_label(unit) = "TEO";
                else
                    brain_label(unit) = "vlPFC";
                end

                unit = unit+1;
            end
        end
    end
elseif with_MUC==2 %if ONLY include the noise cluster
    unit=1;
    for i = channels %For all channels
        if ~isempty(SpikeData.(Chan_name{i})) %If there are sorted units on this channel
            for j = 1 %For the first channel only

                Spike_rasters(unit,:) = zeros(1,round(length_recording*temp_resolution)); %Fill the line with zeros to initiate raster for that trial (IMPORTANT NOTE: removed +1)
                ticks = round(SpikeData.(Chan_name{i}){j}*temp_resolution);
                Spike_counts = hist(ticks, 1:round(length_recording*temp_resolution));
                Spike_rasters(unit, :) = Spike_counts; %Fill in spikes in the raster

                if ismember(Chan_num(i),TEO_chan)
                    brain_label(unit) = "TEO";
                else
                    brain_label(unit) = "vlPFC";
                end

                clear ticks Spike_counts

                unit = unit+1;
            end
        end
    end
else %include multi-unit cluster (or first channel)
    unit=1;
    for i = channels %For all channels
        if ~isempty(SpikeData.(Chan_name{i})) %If there are sorted units on this channel
            for j = 1:length(SpikeData.(Chan_name{i})) %For all units

                Spike_rasters(unit,:) = zeros(1,round(length_recording*temp_resolution)); %Fill the line with zeros to initiate raster for that trial (IMPORTANT NOTE: removed +1)
                ticks = round(SpikeData.(Chan_name{i}){j}*temp_resolution);
                Spike_counts = hist(ticks, 1:round(length_recording*temp_resolution));
                Spike_rasters(unit, :) = Spike_counts; %Fill in spikes in the raster

                if ismember(Chan_num(i),TEO_chan)
                    brain_label(unit) = "TEO";
                else
                    brain_label(unit) = "vlPFC";
                end

                clear ticks Spike_counts

                unit = unit+1;
            end
        end
    end
end

%Exclude very low or very high firing units
include_neurons = find(mean(Spike_rasters,2)>0.1./temp_resolution & mean(Spike_rasters,2)<150./temp_resolution);
Spike_rasters=Spike_rasters(include_neurons,:);
brain_label=brain_label(include_neurons);

length_recording = size(Spike_rasters,2);

%% Smooth data

if smooth
    %sigma = 20;% 0.045 * opts.Fs; %og SDF window was 45 ms, so simply mutiply 45 ms by fs
    gauss_range = -3*sigma:3*sigma; %calculate 3 stds out, use same resolution for convenience
    smoothing_kernel = normpdf(gauss_range,0,sigma); %Set up Gaussian kernel
    smoothing_kernel = smoothing_kernel/sum(smoothing_kernel);
    smoothing_kernel = smoothing_kernel * 1; %Rescale to get correct firing rate
    Spike_rasters_smooth = conv2(Spike_rasters, smoothing_kernel,'same');
    Spike_rasters = Spike_rasters_smooth;
end

%% Get behavior label vector for each time bin at specified resolution

%Create behavior key
%Set it constant across sessions.
behav_categ = ["Aggression","Proximity","Groom Give", "HIP","Foraging", "Vocalization", "Masturbating",...
    "Submission", "Approach","Yawning","Self-groom","HIS","Other monkeys vocalize", "Lip smack",...
    "Groom Receive","Leave","Drinking","Pacing/Travel","Scratch","RR", "Butt sniff","Grm prsnt","Mounting","SS","SP"];
behav_categ = sort(behav_categ);

behav_categ{length(behav_categ)+1}='Rest'; %Add rest as a behavior (no defined behavior ongoing)

%For behaviors that often co-occur with other behaviors, determine priority
double_behav_set = [find(matches(behav_categ,'Proximity')), find(matches(behav_categ,"RR")), find(matches(behav_categ,'Other monkeys vocalize'))];% When co-occurring, other behaviors will take precedence over these ones

%annotation: omv = other monkeys vocalize
%            grmpr = groom presentation
grmpr = find(matches(behav_categ,'Grm prsnt'));
omv = find(matches(behav_categ,'Other monkeys vocalize'));

%Create set of reciprocal behaviors (i.e. behavior of partner can be 100%
%predicted by behavior of subject)
reciprocal_set = [find(matches(behav_categ,'RR')), find(matches(behav_categ,'Other monkeys vocalize')), ...
    find(matches(behav_categ,'Proximity')), find(matches(behav_categ,"Groom Give")), find(matches(behav_categ,"Groom Receive")),...
    find(matches(behav_categ,"HIP")), find(matches(behav_categ,"HIS"))];

%Create set of social behaviors (which happen with conspecifics)
social_set = [find(matches(behav_categ,'Proximity')), find(matches(behav_categ,"Groom Give")), find(matches(behav_categ,"Groom Receive")),...
    find(matches(behav_categ,"Submission")), find(matches(behav_categ,"Approach")), find(matches(behav_categ,"Leave")), find(matches(behav_categ,"Butt sniff")),...
    find(matches(behav_categ,"Grm prsnt")), find(matches(behav_categ,"Aggression"))];


%% Create behavior label vector (label every window of the session)
% This cell matrix will have six columns. The first column is the full
% name of the behavior label

%Create event time intervals:
start_times = behavior_log{:,'start_time_round'};
end_times = behavior_log{:,'end_time_round'};
Intervals = [start_times end_times];
Intervals(strcmp(behavior_log{:,'Behavior'},"Camera Sync"),2) =Intervals(strcmp(behavior_log{:,'Behavior'},"Camera Sync"),1);


%%%%%% Create labels vector for SUBJECT monkey %%%%%%
labels = cell(length_recording,12); %initialize dataframe
for s = 1:length_recording %for all secs in a session
    % this finds the index of the rows(2) that have x in between
    idx = find(s >= Intervals(:,1) & s < Intervals(:,2)); %find if this second belong to any interval
    %IMPORTANT note: interval includes lower bound but excludes upper boundary as is.
    if ~isempty(idx)%if it belongs to an interval
        labels{s,1} = behavior_log{idx,'Behavior'}; %add behavior label in [plain english]
        labels{s,2} = find(matches(behav_categ,labels{s,1})); %add behavior label in [number]

        if all(~strcmp(labels{s,1},"Camera Sync")) %if not camera sync

            if length(labels{s,2})>1 %If one behavior co-occurs with other behavior(s)
                if ~isempty(setdiff(labels{s,2}, double_behav_set)) %If behavior co-occurs with proximity, other monkeys vocalize or RR
                    labels{s,3} = setdiff(labels{s,2}, double_behav_set); % only consider the other behavior (it takes precedence over proximity, OMV and RR)
                    labels{s,4} = 'co-occur with prox, omv or RR';
                    labels{s,5} = 2;
                elseif isempty(setdiff(labels{s,2}, double_behav_set(1:2))) && any(labels{s,3}==omv) %if RR or proximity co-occur with omv
                    labels{s,3}=omv; % prioritize Other monkeyz vocalize
                    labels{s,4} = 'omv co-occurs with prox & RR';
                    labels{s,5} = 3;
                else
                    isempty(setdiff(labels{s,2}, double_behav_set(1:2)));%If proximity and RR co-occur
                    labels{s,3}=find(matches(behav_categ,'RR')); % prioritize Rowdy Room
                    labels{s,4} = 'prox & RR co-occur';
                    labels{s,5} = 4;
                end
            else %If only one behavior happens in that sec OR if other types of co-occurrence happen
                labels{s,3} = labels{s,2};
                labels{s,4} = 'single';
                labels{s,5} = 1;
            end


            if length(labels{s,3})~=1 %If two behaviors are co-occurring which do not include omv, proximity or RR

                if any(labels{s,3}==grmpr) % if one of the behavior includes groom present
                    labels{s,3}=grmpr; %Keep groom present
                    labels{s,4} = 'grmpr co-occur';
                    labels{s,5} = 5;
                elseif any(labels{s,3}==find(matches(behav_categ,'Scratch'))) %if on of the behavior includes scratch
                    labels{s,3}=setdiff(labels{s,3}, find(matches(behav_categ,'Scratch'))); %Consider the other behavior
                    labels{s,4} = 'scratch co-occur';
                    labels{s,5} = 6;
                    if length(labels{s,3})~=1 %there are more than 2 behaviors that co-occur with scratch,
                        labels{s,3}= labels{s,3}(2); %choose 2nd behavior
                    end
                elseif any(labels{s,3}==find(matches(behav_categ,'Aggression'))) %If one of the behavior includes aggression
                    labels{s,3}=find(matches(behav_categ,'Aggression')); %keep aggression
                    labels{s,4} = 'aggression co-occur';
                    labels{s,5} = 7;
                elseif any(labels{s,3}==find(matches(behav_categ,'Submission'))) %If one of the behavior includes submission
                    labels{s,3}=find(matches(behav_categ,'Submission')); %keep submission
                    labels{s,4} = 'submission co-occur';
                    labels{s,5} = 8;
                elseif any(labels{s,3}==find(matches(behav_categ,'Masturbating'))) %If one of the behavior includes masturbation
                    labels{s,3}=find(matches(behav_categ,'Masturbating')); %keep masturbation
                    labels{s,4} = 'masturbating co-occur';
                    labels{s,5} = 9;
                elseif any(labels{s,3}==find(matches(behav_categ,'Mounting'))) %If one of the behavior includes Mounting
                    labels{s,3}=find(matches(behav_categ,'Mounting')); %keep mounting
                    labels{s,4} = 'mounting co-occur';
                    labels{s,5} = 10;
                elseif any(labels{s,3}==find(matches(behav_categ,'Approach'))) %If one of the behavior includes Approach
                    labels{s,3}=find(matches(behav_categ,'Approach')); %keep approach
                    labels{s,4} = 'approach co-occur';
                    labels{s,5} = 11;
                elseif any(labels{s,3}==find(matches(behav_categ,'Leave'))) %If one of the behavior includes Leave
                    labels{s,3}=find(matches(behav_categ,'Leave')); %keep leave
                    labels{s,4} = 'leave co-occur';
                    labels{s,5} = 12;
                else %Otherwise just choose the second behavior for now...
                    %                 error('More than one behavior simultansouly')
                    %                 return
                    labels{s,3}= labels{s,3}(2);
                    labels{s,4} = 'Other key behav co-occur';
                    labels{s,5} = 13;
                end

            end

            %%%%%%%%%%%%  THREAT PRECEDENCE CLAUSE %%%%%%%%%%%%
            if threat_precedence == 1
                if any(labels{s,2}==find(matches(behav_categ,'HIP'))) %If one of the behavior includes threat to partner
                    labels{s,3}=find(matches(behav_categ,'HIP')); %Keep HIP
                    labels{s,4} = 'HIP co-occur';
                    labels{s,5} = 14;
                elseif any(labels{s,2}==find(matches(behav_categ,'HIS'))) %If one of the behavior includes threat to subject
                    labels{s,3}=find(matches(behav_categ,'HIS')); %Keep HIS
                    labels{s,4} = 'HIS co-occur';
                    labels{s,5} = 15;
                end
            end

        else
            labels{s,1} = NaN; labels{s,2} = length(behav_categ); labels{s,3} = length(behav_categ); labels{s,4} = 'NA'; labels{s,5} = 0;%Set behavior category to "NaN" and label to rest
        end

    else %if second belongs to no interval, set it to "rest"
        labels{s,1} = NaN; labels{s,2} = length(behav_categ); labels{s,3} = length(behav_categ); labels{s,4} = 'NA'; labels{s,5} = 0;%Set behavior category to "NaN" and label to rest

    end

    %%%%%%%%%%%%%%%%%%%%%%%%
    %Add behavior information: reciprocal vs non-reciprocal. Reciprocal
    %behavior is the exact reverse of the subject behavior (i.e. we can
    %100% predict the behavior label of the partner based on the behavior label
    %of the subject)
    if any(reciprocal_set == labels{s,3}) %if behavior is reciprocal
        labels{s,6} = "reciprocal";
        labels{s,7} = 1;
    else
        labels{s,6} = "non-reciprocal";
        labels{s,7} = 0;
    end

    %Add behavior information: social vs. non-social
    if any(social_set == labels{s,3})
        labels{s,8} = "social"; %if behavior is social
        labels{s,9} = 1;
    else
        labels{s,8} = "non-social";
        labels{s,9} = 0;
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%
    %Add block information
    if s<=block_times{1,'end_time_round'}
        labels{s,10} = string(block_log{strcmp(full_session_name, block_log{:,'session_name'}),2}); %identity of block (female neighbor, male neighbor or alone block)
        labels{s,11} = 1; %block order

        if labels{s,10}=="female"
            labels{s,12} = 1;%numerical form of block identity
            labels{s,13} = 1; %paired block
        elseif labels{s,10}=="male"
            labels{s,12} = 2;
            labels{s,13} = 1;%paired block
        else
            labels{s,12} = 3;
            labels{s,13} = 0;%alone block
        end

    elseif s>block_times{1,'end_time_round'} && s<=block_times{2,'end_time_round'}
        labels{s,10} = string(block_log{strcmp(full_session_name, block_log{:,'session_name'}),3});
        labels{s,11} = 2;

        if labels{s,10}=="female"
            labels{s,12} = 1;%numerical form
            labels{s,13} = 1; %paired block
        elseif labels{s,10}=="male"
            labels{s,12} = 2;
            labels{s,13} = 1; %paired block
        else
            labels{s,12} = 3;
            labels{s,13} = 0;%alone block
        end

    elseif s>block_times{2,'end_time_round'}
        labels{s,10} = string(block_log{strcmp(full_session_name, block_log{:,'session_name'}),4});
        labels{s,11} = 3;

        if labels{s,10}=="female"
            labels{s,12} = 1;%numerical form
            labels{s,13} = 1; %paired block
        elseif labels{s,10}=="male"
            labels{s,12} = 2;
            labels{s,13} = 1; %paired block
        else
            labels{s,12} = 3;
            labels{s,13} = 0;%alone block
        end

    end

end

%Rename behavior category to not have acronyms
behav_categ_original = behav_categ;
behav_categ{find(matches(behav_categ,'HIP'))}='Threat to partner';
behav_categ{find(matches(behav_categ,'HIS'))}='Threat to subject';
behav_categ{find(matches(behav_categ,'Pacing/Travel'))}='Travel';
behav_categ{find(matches(behav_categ,'RR'))}='Rowdy Room';
behav_categ{find(matches(behav_categ,'Grm prsnt'))}='Groom sollicitation';
behav_categ{find(matches(behav_categ,'Groom Give'))}='Groom partner';
behav_categ{find(matches(behav_categ,'Groom Receive'))}='Getting groomed';


%% Create grooming label

groom_labels_all=zeros(size(labels,1),5); %Initiliaze
%First row: label of all behavior
%2nd row: Is start (1, first half or first 20sec) or end (2, 2nd half or last 20sec) of grooming bout
%3rd row: Is grooming bout after a threat event (within 1min after threat)
%4th row: Is grooming bout reciprocated (within 30sec of previous grooming bout)
%5th row: Is grooming bout sollicited (within 30sec of an approach or groom present)
%6th row: Neighbor ID

%set paramaters:
time_start_end = round(5*temp_resolution); %in sec
time_postthreat = round(45*temp_resolution);
time_recip = round(10*temp_resolution);
time_postrecip = round(20*temp_resolution);
time_sollicited = round(5*temp_resolution);
time_postsollicit = round(20*temp_resolution);

%Set first column as the behavior labels
groom_labels_all(:,1) = cell2mat({labels{:,3}}');

%Set last column as the neighbor ID
groom_labels_all(:,6)=cell2mat({labels{:,12}}');

%get all grooming bouts
all_groom_bouts = sort([find(strcmp(table2array(behavior_log(:,'Behavior')),'Groom Give'));...
    find(strcmp(table2array(behavior_log(:,'Behavior')),'Groom Receive'))]);

%Get human threat times and intervals considered "post-threat"
all_threat_end_times = table2array(behavior_log([find(strcmp(table2array(behavior_log(:,'Behavior')),'HIS'));...
    find(strcmp(table2array(behavior_log(:,'Behavior')),'HIP'))],"end_time_round")); %Get threat times
threat_interval=[]; %Initialize
for n=1:length(all_threat_end_times) %For all threat times
    threat_interval = [threat_interval, all_threat_end_times(n):all_threat_end_times(n)+time_postthreat]; %Get all indices consideres as "post-threat"
end

%Get sollicitation times and intervals considered "post-sollicitation"
all_sollicit_end_times = table2array(behavior_log([find(strcmp(table2array(behavior_log(:,'Behavior')),'Grm prsnt'));...
    find(strcmp(table2array(behavior_log(:,'Behavior')),'Approach'))],"end_time_round"));
sollicit_interval=[];
for n=1:length(all_sollicit_end_times)
    sollicit_interval = [sollicit_interval, all_sollicit_end_times(n):all_sollicit_end_times(n)+time_sollicited];
end

%Create grooming label matrix
if temp_resolution >= 1
    for g = 1:length(all_groom_bouts) %For all grooming bouts

        bout_behav = table2array(behavior_log(all_groom_bouts(g),"Behavior")); %Groom give or groom receive
        bout_start_time = table2array(behavior_log(all_groom_bouts(g),"start_time_round"));%Start time
        bout_end_time = table2array(behavior_log(all_groom_bouts(g),"end_time_round"))-1;%End time

        if g>1 %If not first bout
            previous_bout_behav = table2array(behavior_log(all_groom_bouts(g-1),"Behavior"));%Grooming behavior of previous bout
            previous_bout_end_time = table2array(behavior_log(all_groom_bouts(g-1),"end_time_round"));%End time previous bout
            previous_bout_start_time = table2array(behavior_log(all_groom_bouts(g-1),"start_time_round"));%Start time previous bout

            %If there is less than 5sec between two bouts of the SAME grooming
            %behavior
            if bout_start_time - previous_bout_end_time < 5 && isequal(bout_behav, previous_bout_behav)
                %Consider this bouts to be the same as the previous bout.
                diff_bout =0; %Set bout as NOT different
                bout_start_time = previous_bout_start_time; %Change start time to be the start time of the previous bout.
            else
                diff_bout =1; %Set bout as different.
            end
        end

        bout_length = bout_end_time - bout_start_time+1; %Set bout length in sec
        bout_idx = bout_start_time:bout_end_time;%Get bout indices

        %Label start and end of bout
        if bout_length > time_start_end*2 %If bout is longer than twice the start/end time
            idx_start = bout_start_time:bout_start_time+time_start_end-1; %First 20s is "start" of grooming bout
            idx_end = bout_end_time-time_start_end+1:bout_end_time;%Last 20s is "end" of grooming bout
            idx_middle = setdiff(bout_start_time:bout_end_time, [idx_start idx_end]);%Rest is middle
        else %If bout is shorter
            idx_start = bout_start_time:bout_start_time+round(bout_length/2);%Consider the first half of the bout as start
            idx_end = bout_start_time+round(bout_length/2)+1:bout_end_time;%Last half of the bout as end
            idx_middle =[];%No middle
        end
        groom_labels_all(idx_start,2)=1; groom_labels_all(idx_end,2)=2; groom_labels_all(idx_middle,2)=3;

        %Label post-threat status
        idx_postthreat=intersect(bout_idx, threat_interval);%Indices that occur during the "post-threat" interval
        idx_nothreat = setdiff(bout_idx,idx_postthreat);%The rest is not "post-threat"
        groom_labels_all(idx_nothreat,3)=1; groom_labels_all(idx_postthreat,3)=2;

        %Label reciprocated status
        if g>1 %If this is not the first grooming bout
            if diff_bout==1 %If it is a different bout (i.e. there is at least 3sec between the two bouts)
                if bout_start_time-previous_bout_end_time <= time_recip && ~ismember(previous_bout_behav,bout_behav)
                    %If there is less than Xsec between a groom receive and a groom give
                    if length(bout_idx)>time_postrecip
                        idx_recip = bout_start_time:bout_start_time+time_postrecip;
                        idx_nonrecip = setdiff(bout_idx,idx_recip);
                        groom_labels_all(idx_recip,4)=2; groom_labels_all(idx_nonrecip,4)=1;
                    else
                        groom_labels_all(bout_idx,4)=2;%Label the whole bout as reciprocated
                    end
                else
                    groom_labels_all(bout_idx,4)=1;%Label the whole bout as non-reciprocated
                end
            else % If it is actually the same bout (not enough difference between the bouts)
                groom_labels_all(bout_idx,4)=groom_labels_all(bout_idx(1),4);%Label the same way as the previous bout
            end
        else %If it is the first grooming bout of the session
            groom_labels_all(bout_idx,4)=1;%Label as non-reciprocal
        end

        %Label initiated status
        idx_initiated=intersect(bout_idx, sollicit_interval);%Indices that occur during the "post-sollicitation" interval
        if ~isempty(idx_initiated)
            if length(bout_idx)>time_postsollicit
                idx_sollicited = bout_start_time:bout_start_time+time_postsollicit;
                idx_nonsollicited = setdiff(bout_idx,idx_sollicited);
                groom_labels_all(idx_sollicited,5)=2; groom_labels_all(idx_nonsollicited,5)=1;
            else
                groom_labels_all(bout_idx,5)=2;%Label the whole bout as sollicited
            end
            %groom_labels_all(bout_idx,5)=2;
        else
            groom_labels_all(bout_idx,5)=1;
        end
        %     idx_not_initiated = setdiff(bout_idx,idx_initiated);%The rest is not post-sollicitation
        %     groom_labels_all(idx_not_initiated,5)=1; groom_labels_all(idx_initiated,5)=2;

    end

    groom_labels_all(find(groom_labels_all(:,1)~=7 & groom_labels_all(:,1)~=8),2:end)=0; %Make all non-groom indices as "0".
end

end