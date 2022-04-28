% Pretty please do NOT edit anything here unless you know what you are doing!
function acquireData(boardCount, boardHandleArray,AcqParameters)

global GalvoResMonitorPhaseDelay LissaJousFastMirrorDelay LissaJousSlowMirrorDelay

%call mfile with library definitions
AlazarDefs

%%%%%%%%%%%%%%%%%%Set Alazar Sampling Parameters%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%The number of samples per record (samples per frame) is dependent upon the imaging method 
if AcqParameters.LissaJous
    samplesPerRecord = lcm(AcqParameters.ShotsPerSlowMirrorPeriod,AcqParameters.ShotsPerFastMirrorPeriod); %One LissaJous Period
else %GalvoRes
    samplesPerRecord = AcqParameters.ShotsPerMirrorPeriodGalvoRes*AcqParameters.HPixels; %I.E. Number of Galvo Steps/Lines    
end

if mod(samplesPerRecord,AcqParameters.SubFrames) ~= 0
    disp('ERROR:The number of subframes specified does not evenly divide a frame! Adjust the number of subframes specified.')
    return;
end

if mod(samplesPerRecord,AcqParameters.TotalCycledPolarizations ~= 0)
    disp('Warning: The number of cycled polarizations does not evenly divide into the number of samples per frame. Polarization data will not be properly separated!');
    disp(['The number of samples per frame is: ', num2str(samplesPerRecord)]);
end

%Set some variables to make Alazar Functions happy
preTriggerSamples = 0;
postTriggerSamples = samplesPerRecord;

%One large record per buffer
recordsPerBuffer = 1;

%Specifiy the total number of buffers to capture
buffersPerAcquisition = AcqParameters.NumberOfFramesPerImage*AcqParameters.NumberOfImages;
% NOTENOTE

%This is the amount of time to wait for for each buffer to be filled. If this time is exceeded, the program
%will error out; erroring in this way usually means that trigger events are not being observed. 
bufferTimeout_ms = 5000;

%In an attempt to speed up the process as much as possible, I'm only going to process data only from boards with enabled channel(s).
ActiveBoards = [any(AcqParameters.Channel(1:2))*1 , any(AcqParameters.Channel(3:4))*2];
ActiveBoards = ActiveBoards(ActiveBoards > 0);

%The channels which we are pulling data from (though not necessarily the channels we are processing data from, since we must always pull from both channels of a card)
ReadChannels = find([any(ActiveBoards==1) any(ActiveBoards==1) any(ActiveBoards==2) any(ActiveBoards==2)]);

%The channels which we will process the data from
ActiveChannels = find(AcqParameters.Channel);

%To specify which column the data goes in, which is ideally specified by channel number from 1 to 4, I will specify by ChannelOrder(Channel) 
ChannelOrder = cumsum([any(ActiveBoards==1) any(ActiveBoards==1) any(ActiveBoards==2) any(ActiveBoards==2)]);

%Select the number of DMA buffers to allocate. The number of DMA buffers must be greater than 2 to allow a board to DMA into
%one buffer while, at the same time, your application processes another buffer.
buffersPerBoard = uint32(round(AcqParameters.BufferSize*2^30/samplesPerRecord/2/4)); 

%%%%%%Initialize variables, figures, and waitbar before start capture%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%If we are saving the raw data, create file identifiers for each
%datachannel to be saved. RawDataFID is vector of 4 elements containing
%file identifiers for channels. Inactive channels have 0's instead of FIDs.
if AcqParameters.SaveRawData
    AcqParameters.RawDataChanFID = OpenRawDataFiles(AcqParameters);
end

if AcqParameters.SaveProcessedData
    AcqParameters.ProcessedDataChanPolAnalysisFID = OpenProcessedDataFiles(AcqParameters);
end

%Create a plot window with 2 subplots, save plothandles as imagePlot1 and imagePlot2, save plot datahandles as p1 and p2
LiveImagePlot.FigureHandle = -1;
if AcqParameters.NumChannelsToDisplay > 0;
    LiveImagePlot.FigureHandle = figure;
    for SubPlotNum = 1:AcqParameters.NumChannelsToDisplay
        ImageSubPlot(SubPlotNum) = subplot(1,AcqParameters.NumChannelsToDisplay,SubPlotNum);
        LiveImagePlot.Data(:,:,SubPlotNum) = imagesc(rand(AcqParameters.VPixels,AcqParameters.HPixels),'Parent', ImageSubPlot(SubPlotNum));
        colorbar('peer',ImageSubPlot(SubPlotNum),'location','southoutside') 
    end
    colormap(AcqParameters.ColorMap)
    axis(ImageSubPlot,'image','xy','off')
end

if ~exist('AcqParameters.Auto_Rotation')
    %Simulate the lissajous trajectory & recover all of the information we need to efficiently process the incoming data 
    %I've tested with minor timeit() functions that GPU variables in class structures are just as fast as normal variables 
    [AcqParameters.SamplesPerPixel AcqParameters.HighSamplePixelGroupDataIndex ...
        AcqParameters.HighSamplePixelGroupMatrixIndex AcqParameters.MidSamplePixelGroupDataIndex ...
        AcqParameters.MidSamplePixelGroupMatrixIndex AcqParameters.LowSamplePixelGroupDataIndex ...
        AcqParameters.LowSamplePixelGroupMatrixIndex AcqParameters.HighSampleFinalPixelIndex ...
        AcqParameters.MidSampleFinalPixelIndex AcqParameters.LowSampleFinalPixelIndex ...
        AcqParameters.SamplesPerCutOff AcqParameters.PixelsPerCutOff] ...
        = CalculateSamplesPerPixel(AcqParameters,samplesPerRecord);
end

%Initialize the image variables. ImageData is organized as [Channel, Vpixels, Hpixels, Polarizations, SubFrames]
%If HybridAvgCount is enabled, then always performing counting and averaging
if AcqParameters.LissaJous
    if any(AcqParameters.Counting) || any(AcqParameters.HybridAvgCount)
        ImageCounting = zeros(AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations,AcqParameters.SubFrames,'single');
        RawDataCounting = zeros(samplesPerRecord,numel(ReadChannels),'single');
        AcqParameters.Threshold_Channel = repmat(AcqParameters.Threshold_Channel(ReadChannels),[samplesPerRecord,1]);
    end
    if any(AcqParameters.Averaging) || any(AcqParameters.HybridAvgCount)
        ImageAveraging = zeros(AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations,AcqParameters.SubFrames,'single');
        RawDataAveraging = zeros(samplesPerRecord,numel(ReadChannels),'single');
    end
    if any(AcqParameters.HybridAvgCount) 
        ImageHybrid = zeros(AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations,AcqParameters.SubFrames,'single');
    end
else %GalvoRes
    if any(AcqParameters.Counting) || any(AcqParameters.HybridAvgCount)
        ImageCounting = zeros(AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations,1,'single');
        RawDataCounting = zeros(samplesPerRecord,numel(ReadChannels),'single');
        AcqParameters.Threshold_Channel = repmat(AcqParameters.Threshold_Channel(ReadChannels),[samplesPerRecord,1]);
    end
    if any(AcqParameters.Averaging) || any(AcqParameters.HybridAvgCount)
        ImageAveraging = zeros(AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations,1,'single');
        RawDataAveraging = zeros(samplesPerRecord,numel(ReadChannels),'single');
    end
    if any(AcqParameters.HybridAvgCount) 
        ImageHybrid = zeros(AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations,1,'single');
    end
end
RawDataTemp = zeros(samplesPerRecord,numel(ReadChannels),'uint16');

%Dimension the three matrices which will be used as intermediates to perform efficient summing in 3 large chunks 
HighSampleImageArray = zeros(AcqParameters.SamplesPerCutOff(3),AcqParameters.PixelsPerCutOff(3),'single');
MidSampleImageArray = zeros(AcqParameters.SamplesPerCutOff(2),AcqParameters.PixelsPerCutOff(2),'single');
LowSampleImageArray = zeros(AcqParameters.SamplesPerCutOff(1),AcqParameters.PixelsPerCutOff(1),'single');

% Create a progress window
waitbarHandle = waitbar(0,'Captured 0 buffers','Name','Capturing ...','CreateCancelBtn','setappdata(gcbf,''canceling'',1)');
setappdata(waitbarHandle, 'canceling', 0);

% Wait for sufficient data to arrive to fill a buffer, process the buffer, and repeat until the acquisition is complete
startTickCount = tic;
updateTickCount = tic;
updateInterval_sec = 0.1;
buffersPerBoardCompleted = 0;
captureDone = false;

%%%%%%%%%%%%%%%%%%%%%%%Alazar Hardware Setup%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%Select which channels in each board to acquire data from. This was specified by the user in SDImaging. 
for boardId = 1:boardCount
    % TODO: Select which channels in this board (A, B, or A + B)
    enabledChannelMask = CHANNEL_A + CHANNEL_B;
    enabledChannelMaskArray(1, boardId) = enabledChannelMask;
end

% Find the total number of enabled channels in this board system
channelsPerBoard = 2;
enabledChannelsThisSystem = 0;
for boardId = 1 : boardCount
    % Find the number of enabled channesl from the channel mask
    enabledChannelMask = enabledChannelMaskArray(1, boardId);
    enabledChannelsThisBoard = 0;    
    for channel = 0 : channelsPerBoard - 1
        channelId = 2^channel;
        if bitand(channelId, enabledChannelMask)
            enabledChannelsThisBoard = enabledChannelsThisBoard + 1;
        end
    end    
    if (enabledChannelsThisBoard < 1) || (enabledChannelsThisBoard > channelsPerBoard)
        fprintf('Error: Invalid channel mask %08X\n', enabledChannelMask);
        return
    end      
    
    % Save channel info for this board
    enabledChannelCountArray(1, boardId) = enabledChannelsThisBoard;
    enabledChannelsThisSystem = enabledChannelsThisSystem + enabledChannelsThisBoard;
end

% Get the sample and memory size
systemHandle = boardHandleArray{1, 1};
[retCode, systemHandle, maxSamplesPerRecord, bitsPerSample] = calllib('ATSApi', 'AlazarGetChannelInfo', systemHandle, 0, 0);
if retCode ~= ApiSuccess
    fprintf('Error: AlazarGetChannelInfo failed -- %s\n', errorToText(retCode));
    return
end

% Calculate the size of each buffer in bytes
bytesPerSample = floor((double(bitsPerSample) + 7) / double(8));

% Create an array of DMA buffers for each board
bufferArray = cell(boardCount, buffersPerBoard);
for boardId = 1 : boardCount    
   samplesPerBuffer = samplesPerRecord * recordsPerBuffer * enabledChannelCountArray(1, boardId);
   bytesPerBufferArray(1, boardId) = bytesPerSample * samplesPerBuffer;        
    for bufferId = 1 : buffersPerBoard
        bufferArray(boardId, bufferId) = { libpointer('uint16Ptr', 1 : samplesPerBuffer) };
    end       
end

% ADMA_TRIGGERED_STREAMING - Acquire a continuos stream of records upon a trigger event
% ADMA_EXTERNAL_STARTCAPTURE - call AlazarStartCapture to begin the acquisition
admaFlags = ADMA_EXTERNAL_STARTCAPTURE + ADMA_TRIGGERED_STREAMING;

% Configure each board to make an AutoDMA acquisition
for boardId = 1 : boardCount
    boardHandle = boardHandleArray{1, boardId};
	
	% Set the record size 
	retCode = calllib('ATSApi', 'AlazarSetRecordSize', boardHandle, preTriggerSamples, postTriggerSamples);
	if retCode ~= ApiSuccess
		fprintf('Error: AlazarSetRecordSize failed -- %s\n', errorToText(retCode));
		return
	end
	
    enabledChannelMask = enabledChannelMaskArray(1, boardId);
    recordsPerAcquisition =  recordsPerBuffer*buffersPerAcquisition;
    retCode = calllib('ATSApi', 'AlazarBeforeAsyncRead', boardHandle, enabledChannelMask, -int32(preTriggerSamples), samplesPerRecord, recordsPerBuffer, recordsPerAcquisition, admaFlags);
    if retCode ~= ApiSuccess
    fprintf('Error: AlazarBeforeAsyncRead failed -- %s\n', errorToText(retCode));
    return
    end
end

% Post buffers to each board
for boardId = 1 : boardCount
    for bufferId = 1 : buffersPerBoard
        boardHandle = boardHandleArray{1, boardId};
        pbuffer = bufferArray{boardId, bufferId};
        bytesPerBuffer = bytesPerBufferArray(1, boardId);
        retCode = calllib('ATSApi', 'AlazarPostAsyncBuffer', boardHandle, pbuffer, bytesPerBuffer);
        if retCode ~= ApiSuccess
            fprintf('Error: AlazarPostAsyncBuffer failed -- %s\n', errorToText(retCode));
            return
        end        
    end
end

% Update status
if buffersPerAcquisition == hex2dec('7FFFFFFF')
    fprintf('Capturing buffers until aborted...\n');
else
    fprintf('Capturing %u buffers ...\n', boardCount * buffersPerAcquisition);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%Start Capture%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Arm the board system to begin the acquisition 
retCode = calllib('ATSApi', 'AlazarStartCapture', systemHandle);
if retCode ~= ApiSuccess
    fprintf('Error: AlazarStartCapture failed -- %s\n', errorToText(retCode));
    return;
end

tic
while ~captureDone
	% Wait for the buffer at the head of list of availalble buffers for each board to be filled.
    
    bufferId = mod(buffersPerBoardCompleted, buffersPerBoard) + 1;
%     % debug - Shijie - 1/22/2016
%     fprintf('buffersPerBoardCompleted:\t%d\n', buffersPerBoardCompleted);
%     fprintf('buffersPerBoard:\t%d\n', buffersPerBoard);
%     % end of debug - Shijie - 1/22/2016
    
    %Detect if I'm processing the last buffer in a frame. I've integrated the data
    %for all the previous buffers, and I'll need to perform signal averaging or 
    %counting conversions on this iteration.
    if mod((buffersPerBoardCompleted+1),AcqParameters.NumberOfFramesPerImage) == 0
        LastBufferInImage = 1;
    else
        LastBufferInImage = 0;
    end
    
    %Detect if I'm on the last buffer in the acquisition. If so, then avoid clearing my data
    %so that I can show the image at the end of the program
    if (buffersPerBoardCompleted+1) == buffersPerAcquisition
        LastBufferInAcquisition = 1;
    else
        LastBufferInAcquisition = 0;
    end
    
    for boardId = ActiveBoards

        boardHandle = boardHandleArray{1, boardId};
        pbuffer = bufferArray{boardId, bufferId};
        bytesPerBuffer = bytesPerBufferArray(1, boardId);        

        [retCode, boardHandle, bufferOut] = calllib('ATSApi', 'AlazarWaitAsyncBufferComplete', boardHandle, pbuffer, bufferTimeout_ms);
        if retCode == ApiSuccess 
            % This buffer is full
            bufferFull = true;
            captureDone = false;
        elseif retCode == ApiWaitTimeout 
            % The wait timeout expired before this buffer was filled. The timeout period may be too short.
            fprintf('Error: AlazarWaitAsyncBufferComplete timeout!\n');
            bufferFull = false;
            captureDone = true;
        else
            % The acquisition failed
            fprintf('Error: AlazarWaitAsyncBufferComplete failed -- %s\n', errorToText(retCode));
            bufferFull = false;
            captureDone = true;
        end
        
        if bufferFull
            % Get data off Alazar card buffers into reserved DMA RAM   
            setdatatype(bufferOut, 'uint16Ptr', 1, samplesPerBuffer);   
            %Transfer the data from DMA protected RAM into free RAM. For whatever reason, reading from DMA protected RAM is slow. Reading from it only once is fastest.
            RawDataTemp(:,ChannelOrder(boardId*2-1:boardId*2)) = reshape(bufferOut.Value,[samplesPerRecord,2]);
            %Make the buffer available to be re-filled by the board
            retCode = calllib('ATSApi', 'AlazarPostAsyncBuffer', boardHandle, pbuffer, bytesPerBuffer);
            if retCode ~= ApiSuccess
                fprintf('Error: AlazarPostAsyncBuffer failed -- %s\n', errorToText(retCode));
                captureDone = true;
            end
        end % if bufferFull
    end % for boardId = 1 : boardCount
    
    %Detect & warn if any voltages are at or near the rails. Despite that this bit of code was speed optimized, it still takes ~half the time of an image compilation to execute. 
    if AcqParameters.VoltageClippingAlert && (mod(buffersPerBoardCompleted,AcqParameters.CheckForClippingEveryNBuffers) == 0) 
        if (sum(min(RawDataTemp) < 35) || sum(max(RawDataTemp) > 65500)); %This line is written strangely, but provides a very fast & parallelized comparison.
            disp(['WARNING:ADC Voltage Clipping Detected! Adjust laser power or ADC range!']);
        end
    end

    %It would be more elegant to write a program without creating separate names for RawDataCounting and RawDataAveraging, 
    %such as creating a class, but matlab executes faster if these are kept as separate low-level variables.
    if any((AcqParameters.Counting | AcqParameters.HybridAvgCount) & AcqParameters.Channel)
        
        if AcqParameters.FlipCountingPolarity
            RawDataCounting = RawDataCounting + single(RawDataTemp > AcqParameters.Threshold_Channel);
        else
            RawDataCounting = RawDataCounting + single(RawDataTemp < AcqParameters.Threshold_Channel);
        end
    end
    if any((AcqParameters.Averaging | AcqParameters.HybridAvgCount) & AcqParameters.Channel)
        RawDataAveraging = RawDataAveraging + single(RawDataTemp);
    end

    %Only process data from channels we want to acquire. Intuition says that the program may run faster if I parallelized this process
    %across all channels, but my tests of that idea show that this may actually decrease the performance of reorganizing the data. Keeping
    %the channel loop makes things easier to program anyway, so I'll just leave it in place.
    for Channel = ActiveChannels

        if AcqParameters.SaveRawData  %Save raw data to RAMDisk by Channel
            fwrite(AcqParameters.RawDataChanFID(Channel),RawDataTemp(:,ChannelOrder(Channel)), 'uint16');
        end
        
        if LastBufferInImage %Then compile the image and save the data

            if AcqParameters.Counting(Channel) || AcqParameters.HybridAvgCount(Channel)
                
                %Transfer the data into the three matrices. I played with separating the rawdata by channel into a new variable rawdatachan, but found that the below implementation was slightly faster. 
                HighSampleImageArray(AcqParameters.HighSamplePixelGroupMatrixIndex) = RawDataCounting(AcqParameters.HighSamplePixelGroupDataIndex,ChannelOrder(Channel));
                MidSampleImageArray(AcqParameters.MidSamplePixelGroupMatrixIndex) = RawDataCounting(AcqParameters.MidSamplePixelGroupDataIndex,ChannelOrder(Channel));
                LowSampleImageArray(AcqParameters.LowSamplePixelGroupMatrixIndex) = RawDataCounting(AcqParameters.LowSamplePixelGroupDataIndex,ChannelOrder(Channel));

                %Sum the data and transfer it to the FinalImageMatrix
                ImageCounting(AcqParameters.HighSampleFinalPixelIndex) = sum(HighSampleImageArray);
                ImageCounting(AcqParameters.MidSampleFinalPixelIndex) = sum(MidSampleImageArray);
                ImageCounting(AcqParameters.LowSampleFinalPixelIndex) = sum(LowSampleImageArray);

                %Process the accumulated data to its final form image and throw it on the main system RAM as a local variable
                if AcqParameters.Lambda(ChannelOrder(Channel)) || AcqParameters.HybridAvgCount(ChannelOrder(Channel))
                    NormalizedCountingImage = -1*log(1-ImageCounting./(AcqParameters.SamplesPerPixel*AcqParameters.NumberOfFramesPerImage)); 
                    NormalizedCountingImage(isinf(NormalizedCountingImage)) = 15; %Any saturated pixels will have a value of inf
                else
                    NormalizedCountingImage = ImageCounting./(AcqParameters.SamplesPerPixel*AcqParameters.NumberOfFramesPerImage); 
                end

                %Any pixel that didn't get sampled will be a NaN value after normalization. For counting, turn all NaNs into -1 values before displaying or saving.
                NormalizedCountingImage(isnan(NormalizedCountingImage)) = -1;

                %Detect and report if counting saturation occurred
                if AcqParameters.CountSaturationAlert
                    if any(ImageCounting == (AcqParameters.SamplesPerPixel*AcqParameters.NumberOfFramesPerImage))
                        disp('WARNING:Counting saturation detected! Increase frames per image, and make sure all pixels are sampled!');
                    end
                end
                
            end
            if AcqParameters.Averaging(Channel) || AcqParameters.HybridAvgCount(Channel)
                
                %Transfer the data into the three matrices. I played with separating the rawdata by channel into a new variable rawdatachan, but found that the below implementation was faster. 
                HighSampleImageArray(AcqParameters.HighSamplePixelGroupMatrixIndex) = RawDataAveraging(AcqParameters.HighSamplePixelGroupDataIndex,ChannelOrder(Channel));
                MidSampleImageArray(AcqParameters.MidSamplePixelGroupMatrixIndex) = RawDataAveraging(AcqParameters.MidSamplePixelGroupDataIndex,ChannelOrder(Channel));
                LowSampleImageArray(AcqParameters.LowSamplePixelGroupMatrixIndex) = RawDataAveraging(AcqParameters.LowSamplePixelGroupDataIndex,ChannelOrder(Channel));

                %Sum the data and transfer it to the FinalImageMatrix
                ImageAveraging(AcqParameters.HighSampleFinalPixelIndex) = sum(HighSampleImageArray);
                ImageAveraging(AcqParameters.MidSampleFinalPixelIndex) = sum(MidSampleImageArray);
                ImageAveraging(AcqParameters.LowSampleFinalPixelIndex) = sum(LowSampleImageArray);
                NormalizedAveragingImage = ImageAveraging./(AcqParameters.SamplesPerPixel*AcqParameters.NumberOfFramesPerImage);
                
            end
            
            %If its time to recalibrate the hybrid detection, then do so. Determines the offset and slope to lineary transform averaging data to Lambda
            if AcqParameters.HybridAvgCount(Channel) && (mod(buffersPerBoardCompleted,AcqParameters.HybridCalibrateEveryNFrames) < AcqParameters.NumberOfFramesPerImage)
                %A fast and accurate way of finding what ADC value corresponds to 0V is to take the mode of the captured voltages in the johnson noise region. After averaging
                %an entire image's worth of data together, it is quite reproduceable, has an inconsequentially small bias, and doens't require lengthy fitting to get an answer.
                %Further, the johnson noise is likely the most sampled voltage level (sample when a photon is not present), and will have a very intense peak (a very noticeable
                %mode) that will have a larger value than any of the n-photon modes; it's a point in the entire PDF that can't be mistaken with anything else. 
                [~,JohnsonNoiseMode] = max(histc(RawDataTemp(:,ChannelOrder(Channel)),(2^15-400:2^15+400)));
                ADCZero(ChannelOrder(Channel)) = JohnsonNoiseMode + 2^15-400 - 1;
                
                %The amount of voltage per photon can be correlated to the lambda recovered by counting. For mathematically mysterious reasons, the recovered voltage per photon
                %has a large and positively skewed variance. Taking the average across all pixels is therefore a biased measurement! Performing a rigorous nonlinear fit can
                %recover a highly accurate value, though taking the mode of this distribution can evade *most* of the bias to recover values that are typically within 5% of the ideal
                %value in simulation. It's also rather fast. I estimate the region that I expect to find the mode to be in as being between 0.3*guessvoltageperphoton to 
                %1.5*guessvoltage per photon, since the mean is always positively biased. I take care to prune out all counting lambda values that are NaNs or INFs. 
                %I force the ADCUnitsPerPhoton to be positive, since PMTs provide a negative voltage. 
                GuessVoltsPerPhotonImage = -1*(NormalizedAveragingImage-ADCZero(ChannelOrder(Channel)))./NormalizedCountingImage;
                MeanGuessVoltsPerPhotonImage = mean(GuessVoltsPerPhotonImage);
                HistRange = linspace(0.3*MeanGuessVoltsPerPhotonImage,1.5*MeanGuessVoltsPerPhotonImage,1000);
                [~,VoltsPerPhotonMode] = max(histc(GuessVoltsPerPhotonImage(isfinite(GuessVoltsPerPhotonImage)), HistRange));
                ADCUnitsPerPhoton(ChannelOrder(Channel)) = HistRange(VoltsPerPhotonMode);
            end
            
            if AcqParameters.HybridAvgCount(Channel)
                %Store averaging data converted to lambda into ImageHybrid
                ImageHybrid = -1*(NormalizedAveragingImage - ADCZero(ChannelOrder(Channel)))/ADCUnitsPerPhoton(ChannelOrder(Channel));

                %For lambda values less than user defined S/N cutoff (typically lambda = 0.5), substitute lambda values recovered from counting 
                ImageHybrid(NormalizedCountingImage < AcqParameters.HybridLambdaThreshold) = NormalizedCountingImage(NormalizedCountingImage < AcqParameters.HybridLambdaThreshold);
            end
            
            %Call a function to reshape the image data, display it, and save the final image. The display may be unique per analysis and scanning method! 
            if AcqParameters.Counting(Channel)
                if AcqParameters.LissaJous
                    LissaJousCountingLastFrame(AcqParameters,NormalizedCountingImage,Channel,LiveImagePlot,LastBufferInAcquisition);
                else %Galvo/Resonant
                    GalvoResonantCountingLastFrame(AcqParameters,NormalizedCountingImage,Channel,LiveImagePlot,LastBufferInAcquisition);
                end
            end
            if AcqParameters.Averaging(Channel)
                if AcqParameters.LissaJous
                    LissaJousAveragingLastFrame(AcqParameters,NormalizedAveragingImage,Channel,LiveImagePlot,LastBufferInAcquisition);
                else %Galvo/Resonant
                    GalvoResonantAveragingLastFrame(AcqParameters,NormalizedAveragingImage,Channel,LiveImagePlot,LastBufferInAcquisition);
                end
            end
            if AcqParameters.HybridAvgCount(Channel)
                if AcqParameters.LissaJous
                    LissaJousHybridLastFrame(AcqParameters,ImageHybrid,Channel,LiveImagePlot,LastBufferInAcquisition);
                else %Galvo/Resonant
                    GalvoResonantHybridLastFrame(AcqParameters,ImageHybrid,Channel,LiveImagePlot,LastBufferInAcquisition);
                end
            end
            
        end
    end

       
    % Update progress
    buffersPerBoardCompleted = buffersPerBoardCompleted + 1;
    if buffersPerBoardCompleted >= buffersPerAcquisition
        
        % debug - Shijie - 1/22/2016
        disp('Exiting: buffersPerBoardCompleted >= buffersPerAcquisition');
        fprintf('buffersPerBoardCompleted:\t%d\n', buffersPerBoardCompleted);
        fprintf('buffersPerAcquisition:\t%d\n', buffersPerAcquisition);
        % end of debug - Shijie - 1/22/2016
        
        captureDone = true;
    elseif toc(updateTickCount) > updateInterval_sec
        updateTickCount = tic;
        
        % Update waitbar progress. Also redraws realtime figure plots. 
        waitbar(double(buffersPerBoardCompleted) / double(buffersPerAcquisition),waitbarHandle,sprintf('Completed %u buffers', buffersPerBoardCompleted ));
            
        % Check if waitbar cancel button was pressed
        if getappdata(waitbarHandle,'canceling')
            break
        end               
        
        %It's a little silly to invoke this nested loop again. However, it is most resource efficient
        %to re-assign the entire RawDataCounting/Averaging as zeros a single time, instead of
        %clearing them a single channel at a time. Clears the variables if this is not the last capture.
        %If this is not the last capture, then this is not invoked, and data is preserved for later
        %Phase calibration
        if LastBufferInImage 
            if any((AcqParameters.Counting | AcqParameters.HybridAvgCount) & AcqParameters.Channel)
                %Clear the data for the next image
                RawDataCounting = zeros(size(RawDataCounting),'single');
            end    
            if any((AcqParameters.Averaging | AcqParameters.HybridAvgCount) & AcqParameters.Channel)
                %Clear the data for the next image
                RawDataAveraging = zeros(size(RawDataAveraging),'single');
            end
        end
        
    end
    
end % while ~captureDone
outofloop = toc

%%%%%%%Alazar Diagnostics and Cleanup%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%Close all data files
fclose all

% Save the transfer time
transferTime_sec = toc(startTickCount);

% Close progress window
delete(waitbarHandle);

% Abort the acquisition
for boardId = 1 : boardCount
    boardHandle = boardHandleArray{1, boardId};
    retCode = calllib('ATSApi', 'AlazarAbortAsyncRead', boardHandle);
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarAbortAsyncRead failed -- %s\n', errorToText(retCode));
    end
end

% Release buffers
for boardId = 1:boardCount
    for bufferId = 1:buffersPerBoard
        clear bufferArray{boardId, bufferId};
    end
end

% Display results
if buffersPerBoardCompleted > 0 
    bytesTransferred = double(buffersPerBoardCompleted) * bytesPerSample * double(postTriggerSamples) * enabledChannelsThisSystem;
    if transferTime_sec > 0 
        buffersPerSec = boardCount * buffersPerBoardCompleted / transferTime_sec;
        bytesPerSec = bytesTransferred / transferTime_sec;
    else
        buffersPerSec = 0;
        bytesPerSec = 0;
    end
    fprintf('Captured %u buffers from %u boards in %g sec (%g buffers per sec)\n', ...
        buffersPerBoardCompleted, boardCount, transferTime_sec, buffersPerSec);
    fprintf('Transferred %u bytes (%.4g  per sec)\n', bytesTransferred, bytesPerSec);   
end


%Determine the phase of the resonant mirror, which will be used for the next image capture.
%This uses signal averaging or Counting, depending upon which one the user selected. If the 
%User selected neither, then the user is not viewing images, and determining the phase of the
%mirror is irrelevant. Counting data was chosen to be favored over averaging data, and overrides 
%averaging anaswers, since counting data should be good enough to get a decent phase in almost any situation,
%whereas averaging may not have enough signal to do so. All channels and sweeps are averaged together 
%while measuring phase. This is not ideal, and results in lower quality fits to the phase. However, 
%this strategy makes lissajous phase measurement easier, and also performs orders of magnitude faster
%than fitting the entire flapjack. If the signal to background of the total measurement is too low,
%assessed in the code as minval/mean(SSE), then signal is considered too weak to get a decent
%measurement, and the phase is not updated. Qualitatively, this threshold is around 0.97 (no signal
%results in minval/mean(SSE) = 1). For counting, the number of counts in the flapjack must be a minimum
%of ~10,000.

if AcqParameters.LissaJous
%     debug - Shijie - 1/22/2016
    disp('Entering Lissajous');
%     end of debug - Shijie - 1/22/2016
    if any((AcqParameters.Averaging | AcqParameters.HybridAvgCount))
        RawDataAveraging_1 = sum(reshape(RawDataAveraging,AcqParameters.ShotsPerFastMirrorPeriod,[]),2);
        DoubledFlippedRawDataAveraging = flipud([RawDataAveraging_1;RawDataAveraging_1]);
        for i = 0:size(RawDataAveraging_1,1)-1;
            Error = RawDataAveraging_1 - DoubledFlippedRawDataAveraging((1:size(RawDataAveraging_1,1))+i,:);
            SSEAvg(i+1) = norm(Error(:));
        end
        [minval,phase] = min(SSEAvg);
        if minval/mean(SSEAvg) < .97
            LissaJousFastMirrorDelay = -(phase-1)/2;
        end
    end
    if any((AcqParameters.Counting | AcqParameters.HybridAvgCount))
        RawDataCounting = sum(reshape(RawDataCounting,AcqParameters.ShotsPerFastMirrorPeriod,[]),2);
        DoubledFlippedRawDataCounting = flipud([RawDataCounting;RawDataCounting]);
        for i = 0:size(RawDataCounting,1)-1;
            Error = RawDataCounting - DoubledFlippedRawDataCounting((1:size(RawDataCounting,1))+i,:);
            SSECount(i+1) = norm(Error(:));
        end
        [minval,phase] = min(SSECount);
        if (minval/mean(SSECount) < .97) && sum(RawDataCounting(:) > 10000)
            LissaJousFastMirrorDelay = -(phase-1)/2;
        end
    end
%     if any((AcqParameters.Averaging | AcqParameters.HybridAvgCount))
%         RawDataAveraging = sum(reshape(RawDataAveraging,AcqParameters.ShotsPerSlowMirrorPeriod,[]),2);
%         DoubledFlippedRawDataAveraging = flipud([RawDataAveraging;RawDataAveraging]);
%         for i = 0:size(RawDataAveraging,1)/10 - 1;
%             waitbar(i*10/size(RawDataAveraging,1))
%             Error = RawDataAveraging - DoubledFlippedRawDataAveraging((1:size(RawDataAveraging,1))+i*10,:);
%             SSEAvg(i+1) = norm(Error(:));
%         end
%         [minval,phase] = min(SSEAvg);
%         if minval/mean(SSEAvg) < .97
%             LissaJousSlowMirrorDelay = -(phase*10-1)/2;
%         end
%     end
    if any((AcqParameters.Counting | AcqParameters.HybridAvgCount))
        RawDataCounting = sum(reshape(RawDataCounting,AcqParameters.ShotsPerSlowMirrorPeriod,[]),2);
        DoubledFlippedRawDataCounting = flipud([RawDataCounting;RawDataCounting]);
        for i = 0:size(RawDataCounting,1)-1;
            Error = RawDataCounting - DoubledFlippedRawDataCounting((1:size(RawDataCounting,1))+i,:);
            SSECount(i+1) = norm(Error(:));
        end
        [minval,phase] = min(SSECount);
        if (minval/mean(SSECount) < .97) && sum(RawDataCounting(:) > 10000)
            LissaJousSlowMirrorDelay = -(phase-1)/2;
        end
    end
else %GalvoRes
    
    % debug - Shijie - 1/22/2016
    disp('Entering GalvoRes');
    % end of debug - Shijie - 1/22/2016
    
    try
        disp('size of RawDataAvearaging is')
    %     size(RawDataAveraging)
        disp('size of Acqparametres.averaging is')
        size(AcqParameters.Averaging)
        if any((AcqParameters.Averaging | AcqParameters.HybridAvgCount))
            RawDataAveraging = bsxfun(@times,RawDataAveraging,(AcqParameters.Averaging|AcqParameters.HybridAvgCount));
            RawDataAveraging = sum(reshape(RawDataAveraging,AcqParameters.ShotsPerMirrorPeriodGalvoRes,[]),2);
            DoubledFlippedRawDataAveraging = flipud([RawDataAveraging;RawDataAveraging]);
            for i = 0:size(RawDataAveraging,1)-1;
                Error = RawDataAveraging - DoubledFlippedRawDataAveraging((1:size(RawDataAveraging,1))+i,:);
                SSEAvg(i+1) = norm(Error(:));
            end
            [minval,phase] = min(SSEAvg);
            FrequencyDomain = abs(fft(SSEAvg-mean(SSEAvg)));
            FrequencyDomain = FrequencyDomain - 1000;
    %         figure
    %         plot(FrequencyDomain)
    %         title('freqdomain')
            RelSignalPower = sum(abs(FrequencyDomain(1:70)))/sum(abs(FrequencyDomain(71:round(end/2))));
            if RelSignalPower > 1
                GalvoResMonitorPhaseDelay = -(phase-1)/2;
            end
        end
        
    catch
        disp('bah');
    end
try
    if any((AcqParameters.Counting | AcqParameters.HybridAvgCount))
        RawDataCounting = bsxfun(@times,RawDataCounting,(AcqParameters.Counting|AcqParameters.HybridAvgCount));
        RawDataCounting = sum(reshape(RawDataCounting,AcqParameters.ShotsPerMirrorPeriodGalvoRes,[]),2);
        DoubledFlippedRawDataCounting = flipud([RawDataCounting;RawDataCounting]);
        for i = 0:size(RawDataCounting,1)-1;
            Error = RawDataCounting - DoubledFlippedRawDataCounting((1:size(RawDataCounting,1))+i,:);
            SSECount(i+1) = norm(Error(:));
        end
        [minval,phase] = min(SSECount);
        FrequencyDomain = fft(SSECount-mean(SSECount));
        RelSignalPower = sum(abs(FrequencyDomain(1:round(end/4))))/sum(abs(FrequencyDomain(round(end/4):round(end/2))))
        sumRawDataCounting = sum(RawDataCounting(:))
        if (RelSignalPower > 1) && sum(RawDataCounting(:)) > 10000
            disp('countupdate')
            GalvoResMonitorPhaseDelay = -(phase-1)/2;
        end
%         figure
%         plot(SSECount)
%         title('ssecount')
    end
    
catch
    
    disp('bah')
end

end
end