%% SDImaging Version 07-30-2013 is a general script for capturing saving microscopy image data for later analysis. Setup the Alazar timing and ADC parameters using
% initAlazar script before running this function. 

%This system captures data with continuous streaming, 100% duty cycle. This inherently means that the edges of the image will have more samples and
%higher S/N than the center of the image. Please consider this when analyzing the data!

%PLEASE INITIALIZE ALAZAR CARDS FIRST BEFORE USING THIS FUNCTION. 
clc; pause on; clearvars -except ConfigureVariables GalvoResMonitorPhaseDelay LissaJousFastMirrorDelay LissaJousSlowMirrorDelay

global GalvoResMonitorPhaseDelay LissaJousFastMirrorDelay LissaJousSlowMirrorDelay
%% Configuration of acquisition

%Set filepath location where to save data, folder must already exist, and must have single quote mark around it!
%You can add a file name at the beginning of the file, after the last \
%If you are just saving to a folder with just the time stamp name, the path must end in a \
AcqParameters.FilePath = 'F:\Shane\9.8.2014\Leucine\D\';  %If this path is not in purple, something is wrong!

%Choose whether or not to save the averaged and/or counted data. For purposes of aligning
%The microscope or performing other simple diagnostics, it may be desireable to not save the data.
%Images can be opened in ImageJ by importing | Raw|  32bit real, little-endian byte order
%Data will be saved as (DateTime)(Galvo/Res or LissaJous)(Chan(A,B,C,D))(AVG or Counting)(Pol#)(#Images)(#SubFrames, if > 1).bin.
AcqParameters.SaveProcessedData = 0;

%Save Raw Data, this is a very large file with each individual laser pulse in sequence (for more complex analysis later).
%If you wish to do new and experimental measu rements, you likely wish to do a unique analysis that is not currently implemented. This is the option
%you're looking for! These files will be VERY large. Because writing to the hard drive is slow,
%currently you can not do more then 256 FramesPerBin and save the raw data for 4 channels at once directly to hard drive. You can however,
%create a RAMDisk, and write to it. This data will be 16bit unsigned integer, little endian format.
% The file is saved as RawDataChanX.bin
AcqParameters.SaveRawData = 0; 

%% General Capture & Imaging Parameters %%%%%%%%%%%%%%
%Amount of RAM in GB to buffer the streamed data. Larger amounts of RAM will let you buffer more data before
%maxing out the buffer limit. If matlab is crashing with AlazarPostAsyncBuffer failed, try increasing this value. 
%Note that it is most resource efficient to consolidate all data collection to a single card, if possible.
%Large values will require a long time to setup the acquisition. Don't set larger than the amount of RAM in the system! 
AcqParameters.BufferSize = 1      ; % Units in gigabytes

%Number of pixels in the horizontal direction. For galvo/resonantmirror scanning as well 
%as LissaJous scanning, this is fully user defined. 
AcqParameters.VPixels = 512; % Resonant Mirror % 415 for 8 pol

%Number of pixels in the vertical direction. For galvo/resonantmirror scanning, this is fixed 
%as the number of galvo steps per image. For lissajous scanning, this is fully user defined.
AcqParameters.HPixels = 512; % Galvo

%Separates each polarization into N different images, where N is the total number of cycled polarizations before repeating. For example:
%Not using pulse pair generator or EOM: 1
%Using pulse pair generator: 2
%Using EOM without pulse pair generator: LaserFrequency/EOMFrequency
%Using EOM with pulse pair generator: 2*LaserFrequency/EOMFrequency
%Simply, this function separates every N laser pulses into separate images. This may be used simultaneously with SubFrames.
AcqParameters.TotalCycledPolarizations = 1   ;

%Separates each frame into the specified number of subframes. This is particularly useful for Lissajous imaging,
%where a movie's worth of data can be separated into a low resolution & high framerate movie. 
%Note that this is typically used with NumberOfFramesPerImage = 1 for capturing high speed movies. 
%For NumberOfFramesPerImage > 1o, the subframes will be appropriately averaged across frames. When creating subframes,
%the number of subframes must be an integer divisor of the number of laser shots per frame.
%Note that if you are making a high speed movie with a very large number of subframes, such that the majority 
%of the pixels are not sampled, this will take more space than saving the raw data! 
%This may be used simultaneously with TotalCycledPolarizations.
AcqParameters.SubFrames = 1 ; %If separation into subframes is not desired, then set SubFrames = 1.

%Number of frames of raw data to be binned per generated image. For galvo/resonant scanning, this is 
%equivalent to the number of sweeps per line. For LissaJous scanning, this is equal to the number of LissaJous periods
AcqParameters.NumberOfFramesPerImage = 1         ;

%Number of images to be captured. Images will be captured without interruption or delay between images. 
%For video rate imaging, set NumberOfFramesPerImage = 1. For performing microscope diagnostics where an 
%unsaved live feed is desired, set save parameters to false and this value large.
AcqParameters.NumberOfImages = 100000;
%% Channels To Acquire%%%%%%%%%
%Set the channels to acquire and indicate signal processing preferences. Images may simultaneously be generated 
%by photon counting, signal averaging, and hybrid counting/averaging per pixel. The PMT counting threshold is 
%specified in units of mV. Note that PMTs have negative voltage as signal! 

%Lambda (Poisson mean) is returned instead of the raw counts for counting data (though overriding with parameter
%'Lambda' will cause a P value to be returned for counting data). This is because pixels are not uniformally 
%sampled, and raw counts are not a sensible metric. Any unsampled pixels will be assigned a value of -1. If counting 
%saturation occurs, saturated values will be set to a ceiling of 15, which is an unattainably large value in most 
%imaging applications.

%Averaging data will average the raw ADC data. Note that 0V is approximately 2^15 = 32,768. Unsampled pixels
%will be assigned a value of -1.

%Hybrid counting/averaging will report Lambda (Poisson mean) for all pixels. All images will be measured with
%counting and averaging, and a linear conversion to lambda from averaging data will be quickly approximated 
%self-consistently within each image for averaging data. Count data will be preserved below a defined threshold Lambda,
%and averaging data will be preserved above this threshold. This maximizes S/N across a PMT's full dynamic range. 
%Uses the specified threshold setting for counting. Forces Lambda to be used for counting. 

%It is highly computationally advantageous to consolidate all data collection to a single card, if possible. 

%Channel A     
CaptureChannelA = 1;
ChannelACount = 0;     ChannelAThreshold = -8;     ChannelALambda = 0;
ChannelAAvg = 1;       ChannelAHybridAvgCount = 0;
                                             
%Channel B   
CaptureChannelB = 0;
ChannelBCount = 0;     ChannelBThreshold = -4;     ChannelBLambda = 0;
ChannelBAvg = 0;       ChannelBHybridAvgCount = 0;

%Channel C    
CaptureChannelC = 0 ;
ChannelCCount =0;     ChannelCThreshold = -6;     ChannelCLambda = 0;
ChannelCAvg = 0;       ChannelCHybridAvgCount = 0;

%Channel D 
CaptureChannelD = 1;
ChannelDCount = 0;     ChannelDThreshold = -7;       ChannelDLambda = 0;
ChannelDAvg = 1;       ChannelDHybridAvgCount = 0;

%%%%%%%%%%Realtime and Post-Acquisition Display Options%%%%%%%%%%%%%
%Shows the last frame (or last LissaJousSubFrame) of each polarization from all count and/or average images from each recorded channel 
%after acquisition. Note, if you have all channels on and averaging and counting, with multiple polarizations this could be >16 images!
AcqParameters.ShowImages = 0 ;

%Up to two images can be chosen to be displayed in realtime during acquisition. If input polarization 
%is not being modulated, still specify 'Pol1'. If SubFrames are being made, displays the last SubFrame of each Image.
%Setting this value to 0 will prevent the realtime display window from showing. 
AcqParameters.NumChannelsToDisplay = 1;

    %Choose the information to display on the liveupdate figures. To disable liveupdate of either channel, enter 'None'.  
    %If NumChannelsToDisplay = 1, then SecondChannelToDisplay is ignored.
    AcqParameters.FirstChannelToDisplay = 'a-avg-pol1'; % A-Count-Pol1,B-Avg-Pol2, etc.
    AcqParameters.SecondChannelToDisplay = 'c-count-pol1'; 
    
    %Choose the colormap that you would like to view the images with. 
    %Options are Jet, HSV, Hot, Cool, Spring, Summer, Autumn, Winter, Gray, Bone, Copper, Pink
    AcqParameters.ColorMap = 'gray'; 
    
    %Choose which channels you would like to have the data values inverted for signal averaging images.
    %That is, mark which channels produce negative voltage as signal using a 1. Note that this inverts
    %only the displayed data in matlab; the saved data will be preserved in its original form! Further, 
    %this inverts only signal averaging images; counting images and hybrid images will be unaffected. 
    InvChanA = 1;       InvChanB = 0;       InvChanC = 1;       InvChanD =1;
   
%% Diagnostic Parameters Parameters%%%%%%%%%%%

%Choose after how many frames the hybrid counting/averaging should recalibrate the detector. It must calibrate on the first frame. 
%If calibration is desired only once per capture, set this number to be very large.
AcqParameters.HybridCalibrateEveryNFrames = 10000;

%Choose the Lambda (avg photons/sample) threshold value. Below this Lambda value, counting data will be used. Above this value, 
%averaging data will be used. For modern PMTs at maximum gain powered by a clean voltage supply, a good estimate of this value
%is ~0.5 photons/sample.
AcqParameters.HybridLambdaThreshold = 0.5;

%Give a visual notification if counting saturation occurs. This will alert the user to adjust the laser power, 'lest
%their images provide quantitatively unusable data! Disable for sparsely sampled images or movies. Hybrid counting/averaging
%cannot be count saturated.
AcqParameters.CountSaturationAlert = 0;

%Give a visual notification if ADC voltage clipping occurs. This will alert the user to adjust the ADC range or PMT gain, 'lest
%their images provide quantitatively unusable data! This is particularly useful for long captures and realtime imaging. 
%Unless the user is starving for the maximum amount of resources available, IT IS RECOMMENDED THAT THIS FEATURE REMAIN ENABLED! 
AcqParameters.VoltageClippingAlert = 0;

%Checks for voltage clipping on the first frame and then every N frames, and is used to minimize the computational load of voltage 
%clipping checking. It is recommended that this value be kept greater than ~30, or else the computational load becomes noticeable. 
%NOTE: Since voltage clipping is not checked every frame, it is possible that some bright pixel(s) measured with a PMT 
%may generate voltage transients that clip without notifying the user. When highly quantitative data is absolutely necessary,
%staring at a particular field of view with a realtime acquisition for at least N*10 frames (buffers) without a clipping warning 
%should assure the user that at least 1/11 = 91% of the samples are unclipped (assuming an empirically measured binomial random variable). 
AcqParameters.CheckForClippingEveryNBuffers = 10000;

%%%%%%%%%%%Galvo/ResonantMirror Scanning Data Processing Parameters%%%%%%%%%%%
%This is the default scanning method; unless LissaJous = 1, this method is assumed to be used. 
%For this scanning, the X-feedback out should be sent into the slow clock of the black-box, with a slow out going into the trigger of the alazar
%card. The following parameter should be adjusted until the image converges to a crisp, high contrast image. Negative and decimal values are acceptable.

AcqParameters.ShotsPerMirrorPeriodGalvoRes = 5130*2; % Same value as in resonant mirror control box software, (off by factor of 2)
             % || 5153 for 1 micron; 5130 for 800 nm ||

%This software automatically measures and sets the resonant mirror phase. However, in situations where the automated measurement fails,  
%The user may choose to override the automatically measured phase in favor of some static manual phase. 
%NOTE: CERTAIN CONDITIONS ARE KNOWN TO CAUSE THE PHASE TO BE MEASURED INCORRECTLY, AND ARE MOST TYPICALLY PROBLEMS WITH THE IMAGING
%SETUP RATHER THAN THE FIDELITY OF THE PHASE MEASURMENT ALGORITHM. THE FOLLOWING CONDITIONS WILL CAUSE 'SHADOWS' ALONG THE FAST AXIS
%OF THE IMAGE THAT MAKE THE PHASE MEASURE INCORRECTLY:
%1) Imaging with a photodiode that is being saturated with optical signal
%2) Saturating the Alazar channel input range
%The algorithm is quite robust to noisy signal, and can still accurately measure and fit phase beyond human capabilities. However, 
%for absent signal or weak signal, the algorithm chooses to not update phase instead of providing an uncertain measurement. Measuring
%phase from a portion of a frame acquisition, such as canceling an acquisition early, may trigger this scenario.
OverrideMeasuredGalvoResMirrorPhase = 1;           ManualGalvoResMirrorPhase = 2290; %-2550 %-2589 2590
       
%% Long Duration Experiment Imaging Parameters %%%%%%%%
%For sessions requiring data capture over hours or days, these parameters can be set to initiate data captures automatically.
%Use an associated excel file to specify the filepaths, number of images, time delay, and prior x,y,z position for each image. 

%Indicate if multiple imaging sessions will be automatically performed. Set to 0 for normal operation (a single imaging session), or 1 to load the excel file. 
AcqParameters.MultipleImagingSessions = 0;

%Com Port Prior is connected to
ComPort = 'COM4'; % 'COM4', 'COM3', etc, depends on which USB plug you have it in.

%Sequence Excel File Path. Find a template in the SDImaging folder, 'ExampleSequence.xlsx.'
%Note that the time delay must be sufficiently long between each imaging session for the prior stage to move/focus to its new location!
%Note also that the filepath specified in the excel file will override the filepath specified in this script! All other functions, 
%including SaveProcessedData and SaveRawData, function as normal. 
SequenceExcelFilePath = 'F:\Azhad\2014.07.03\Dehydration of trehalose\ExampleSequence.xlsx';

%% LissaJous Scanning Data Processing Parameters%%%%%%%%%%%%%%
%For this scanning, the Epoch pulse should be hooked into the external trigger input.  
AcqParameters.LissaJous = 0; %Indicates that this was a LissaJous scanned image

    %Number of 80MHz Laser shots per fast and slow resonant mirror period. These are copied & pasted from the Labview
    %parameters specified for the LissaJous controller box. 
    AcqParameters.ShotsPerFastMirrorPeriod = 2627*2;
    AcqParameters.ShotsPerSlowMirrorPeriod = 2967*2;

%This software automatically measures and sets the resonant mirror phase. However, in situations where the automated measurement fails,  
%The user may choose to override the automatically measured phase in favor of some static manual phase. 
%NOTE: CERTAIN CONDITIONS ARE KNOWN TO CAUSE THE PHASE TO BE MEASURED INCORRECTLY, AND ARE MOST TYPICALLY PROBLEMS WITH THE IMAGING
%SETUP RATHER THAN THE FIDELITY OF THE PHASE MEASURMENT ALGORITHM. THE FOLLOWING CONDITIONS WILL CAUSE 'SHADOWS' ALONG THE FAST AXIS
%OF THE IMAGE THAT MAKE THE PHASE MEASURE INCORRECTLY:
%1) Imaging with a photodiode that is being saturated with optical signal
%2) Saturating the Alazar channel input range
%The algorithm is quite robust to noisy signal, and can still accurately measure and fit phase beyond human capabilities. However, 
%for absent signal or weak signal, the algorithm chooses to not update phase instead of providing an uncertain measurement. Measuring
%phase from a portion of a frame acquisition, such as canceling an acquisition early, may trigger this scenario.
OverrideMeasuredLissajousMirrorPhase = 1;  ManualLissajousFastMirrorPhase = -2175;  ManualLissajousSlowMirrorPhase = -2375;
    
 %% Developer Section      
%PLEASE DO NOT EDIT ANYTHING BELOW THIS LINE UNLESS YOU ARE A DEVELOPER!
%
%
%
%
%
%
%
%
%
%
%
%
%

AcqParameters.Channel = [CaptureChannelA CaptureChannelB CaptureChannelC CaptureChannelD];
AcqParameters.HybridAvgCount = [ChannelAHybridAvgCount ChannelBHybridAvgCount ChannelCHybridAvgCount ChannelDHybridAvgCount].*AcqParameters.Channel;
AcqParameters.Averaging = [ChannelAAvg ChannelBAvg ChannelCAvg ChannelDAvg].*AcqParameters.Channel;
AcqParameters.Counting = [ChannelACount ChannelBCount ChannelCCount ChannelDCount].*AcqParameters.Channel;
AcqParameters.Lambda = [ChannelALambda ChannelBLambda ChannelCLambda ChannelDLambda];
AcqParameters.Threshold_Channel = [ChannelAThreshold, ChannelBThreshold, ChannelCThreshold, ChannelDThreshold];
AcqParameters.PolOrder = [1:AcqParameters.TotalCycledPolarizations]'; %Specifies the order in which the polarizations are observed
AcqParameters.FirstChannelToDisplay = upper(AcqParameters.FirstChannelToDisplay);
AcqParameters.SecondChannelToDisplay = upper(AcqParameters.SecondChannelToDisplay);
AcqParameters.InvChanColorMap = [InvChanA InvChanB InvChanC InvChanD];

if OverrideMeasuredGalvoResMirrorPhase
    GalvoResMonitorPhaseDelay = ManualGalvoResMirrorPhase;
end
if OverrideMeasuredLissajousMirrorPhase
    LissaJousFastMirrorDelay = ManualLissajousFastMirrorPhase;
    LissaJousSlowMirrorDelay = ManualLissajousSlowMirrorPhase;
end

%If this is a galvo/res image, then determine the number of laser shots per res mirror period from the pacervalue 
% if AcqParameters.LissaJous == 0 
% %     if ConfigureVariables.CardType == 1
% %         AcqParameters.ShotsPerMirrorPeriodGalvoRes = ConfigureVariables.PacerValue;
% %     elseif (ConfigureVariables.CardType == 2) 
% %         AcqParameters.ShotsPerMirrorPeriodGalvoRes = ConfigureVariables.PacerValue;        
% %     end
% end

 % Calculate proper threshold based off of input ranges and set mV level 
for i = 1:numel(ConfigureVariables.ChanInputRange)   
    if ConfigureVariables.ChanInputRange(i) == 6, AcqParameters.Threshold_Channel(i) = (2^15)-(2^15*(abs(AcqParameters.Threshold_Channel(i))/200)); end
    if ConfigureVariables.ChanInputRange(i) == 7, AcqParameters.Threshold_Channel(i) = (2^15)-(2^15*(abs(AcqParameters.Threshold_Channel(i))/400)); end
    if ConfigureVariables.ChanInputRange(i) == 9, AcqParameters.Threshold_Channel(i) = (2^15)-(2^15*(abs(AcqParameters.Threshold_Channel(i))/800)); end
    if ConfigureVariables.ChanInputRange(i) == 10, AcqParameters.Threshold_Channel(i) = (2^15)-(2^15*(abs(AcqParameters.Threshold_Channel(i))/1000)); end
    if ConfigureVariables.ChanInputRange(i) == 12, AcqParameters.Threshold_Channel(i) = (2^15)-(2^15*(abs(AcqParameters.Threshold_Channel(i))/4000)); end 
    if ConfigureVariables.ChanInputRange(i) == 11, AcqParameters.Threshold_Channel(i) = (2^15)-(2^15*(abs(AcqParameters.Threshold_Channel(i))/2000)); end
    if ConfigureVariables.ChanInputRange(i) == 12, AcqParameters.Threshold_Channel(i) = (2^15)-(2^15*(abs(AcqParameters.Threshold_Channel(i))/4000)); end 
          
end


%If we have the PulsePair in our system, we are getting twice as many laser shots. Adjust the 
%variables defined by number of laser shots for this contingency. 
AcqParameters.ShotsPerFastMirrorPeriod = AcqParameters.ShotsPerFastMirrorPeriod*(ConfigureVariables.PulsePair + 1);
AcqParameters.ShotsPerSlowMirrorPeriod = AcqParameters.ShotsPerSlowMirrorPeriod*(ConfigureVariables.PulsePair + 1);

if (AcqParameters.SubFrames > 1) && (AcqParameters.NumberOfFramesPerImage ~= 1)
    disp('WARNING:LissaJous subframes for high speed imaging are being generated, but multiple LissaJous periods are being binned per frame, resulting in slow speed images!')
end

if AcqParameters.ShowImages
    disp('You can close all images loaded by typing in "close all" in the command window (that means where you are reading this).');
end

if str2double(AcqParameters.FirstChannelToDisplay(strfind(AcqParameters.FirstChannelToDisplay,'POL')+3:end)) > AcqParameters.TotalCycledPolarizations
    disp('ERROR:The specified polarization to be displayed in the first realtime image is greater than the total number of incoming polarizations. Adjust the polarization to be displayed.');
end

if str2double(AcqParameters.SecondChannelToDisplay(strfind(AcqParameters.FirstChannelToDisplay,'POL')+3:end)) > AcqParameters.TotalCycledPolarizations
    disp('ERROR:The specified polarization to be displayed in the second realtime image is greater than the total number of incoming polarizations. Adjust the polarization to be displayed.');
end

% Find the number of boards in the board system
boardCount = calllib('ATSApi', 'AlazarBoardsInSystemBySystemID', int32(1));
if boardCount < 1
    fprintf('Error: No boards found in system Id %d\n', int32(1));
    return
end
fprintf('System Id %u has %u boards\n', int32(1), boardCount);

%Get a handle to each board in the board system
for boardId = 1:boardCount
    boardHandle = calllib('ATSApi', 'AlazarGetBoardBySystemID', int32(1), boardId);
    setdatatype(boardHandle, 'voidPtr', 1, 1);
    if boardHandle.Value == 0
        fprintf('Error: Unable to open board system ID %u board ID %u\n', int32(1), boardId);
    end
    boardHandleArray(1, boardId) = { boardHandle };
end


%If we are going to have multiple imaging sessions, then acquire the
%parameters from the associated excel file and perform a multiple imaging
%session
if AcqParameters.MultipleImagingSessions == 1;
    [A,B,C] = xlsread(SequenceExcelFilePath);
    tempHolder = size(A);
    numOfPicsInSequence = tempHolder(1);

    for SessionNum = 1:numOfPicsInSequence

        sequenceTimeDelay = A(SessionNum,6);
        AcqParameters.NumberOfFramesPerImage = A(SessionNum,4);
        AcqParameters.FilePath = char(B(SessionNum+1,5));
        X = A(SessionNum,1);
        Y = A(SessionNum,2);
        Z = A(SessionNum,3);
        movementParamaters = strcat('GR,',num2str(X),',',num2str(Y), ',', num2str(Z));

        if numOfPicsInSequence > 1
            fprintf('\nMoving Prior Stage X %u, Y %u, Z %u relative units\n', X,Y,Z)
            fprintf('\nWaiting %u seconds before acquiring next image\n' , sequenceTimeDelay)

            serialOne=serial(ComPort, 'BaudRate', 9600, 'Terminator','CR/LF');
            fopen(serialOne);
            fprintf(serialOne,movementParamaters);
            fclose(serialOne);

            pause(sequenceTimeDelay)
            close all;  
        end

        acquireData(boardCount, boardHandleArray,AcqParameters)
        fprintf('\n\nWaiting %u seconds before acquiring next image\n\n' , sequenceTimeDelay)
    end
else %Take a single image
    acquireData(boardCount, boardHandleArray,AcqParameters)
end
    