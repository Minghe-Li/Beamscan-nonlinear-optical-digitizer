%This function determines the trajectory of the scanning pattern. Once the trajectory is determined,
%every laser shot is assigned to a pixel, based upon the user's description
%of image size in vertical and horizontal pixels. See the manual for a
%detailed description of this code. Briefly, I am coming up with a more
%efficient version of the accumarray() function. I have found that the
%sum() function is incredibly efficient and highly parallelized in matlab.
%However, it is most efficient if it is called once to perform one large
%operation, instead of hundreds or thousands of times to perform smaller
%operations. However, to sum across a matrix padded with 0's is not
%efficient, which is what would happen if I attempted to create just one
%large matrix and sum across one dimension. I have decided that exactly 3
%matrices meets the balance of not calling the sum function repeatedly, as
%well as preventing from summing across vast amounts of 0's. I create these
%three matrices by grouping pixels based upon the number of times that they
%were sampled, with a way of automatically assigning cutoffs for
%which pixel belongs in which group. For images with multiple
%polarizations and/or subframes, I create all images in parallel. 

%For appending the code to accept new scanning trajectories, this is where
%the majority of the code will be generated. 

%This function has been moderately speed optimized and can usually be run in around a
%second for a typical galvo/resonant setup, though large lissajous
%trajectories (around 1/2 a second per frame) can require 5 seconds or more.

function [SamplesPerPixel HighSamplePixelGroupDataIndex HighSamplePixelGroupMatrixIndex MidSamplePixelGroupDataIndex MidSamplePixelGroupMatrixIndex LowSamplePixelGroupDataIndex LowSamplePixelGroupMatrixIndex HighSampleFinalPixelIndex MidSampleFinalPixelIndex LowSampleFinalPixelIndex SamplesPerCutOff PixelsPerCutOff] = CalculateSamplesPerPixel(AcqParameters,samplesPerRecord)

global GalvoResMonitorPhaseDelay LissaJousFastMirrorDelay LissaJousSlowMirrorDelay

if AcqParameters.LissaJous
    
    %Determine the number of Fast and Slow Mirror Periods. Determined by finding the least common multiple
    %of the number of laser shots per period of each mirror to find the number of laser shots per frame,
    %then dividing by the number of laser shots per period of each mirror.
    ShotsPerFrame = samplesPerRecord;
    NumSlowMirrorPeriods = ShotsPerFrame/AcqParameters.ShotsPerFastMirrorPeriod;
    NumFastMirrorPeriods = ShotsPerFrame/AcqParameters.ShotsPerSlowMirrorPeriod;
    
    %Determine the starting phase of each mirror. The user specified the number of laser shots 
    %until 0 degrees crossing of each mirror from start of capture.
    SlowMirrorPhase = 2*pi*LissaJousSlowMirrorDelay/AcqParameters.ShotsPerSlowMirrorPeriod;
    FastMirrorPhase = 2*pi*LissaJousFastMirrorDelay/AcqParameters.ShotsPerFastMirrorPeriod;
    
    %Places laser shots in bins from 1 to HPixels, also adjusts for starting phase of each mirror 
    ShotBinsX = 0.5*cos(linspace(-1*SlowMirrorPhase,(2*pi*NumSlowMirrorPeriods)-SlowMirrorPhase,ShotsPerFrame+1))+0.5;   %A sine wave of amplitude from 1 to 0
    ShotBinsX = round((AcqParameters.HPixels-1)*ShotBinsX(1:(end-1)))+1;  

    %Places laser shots in bins from 1 to VPixels
    ShotBinsY = 0.5*cos(linspace(-1*FastMirrorPhase,(2*pi*NumFastMirrorPeriods)-FastMirrorPhase,ShotsPerFrame+1))+0.5;   %A sine wave of amplitude from 1 to 0
    ShotBinsY = round((AcqParameters.VPixels-1)*ShotBinsY(1:(end-1)))+1;  

    %Determine the total number of times each pixel within each subframe was sampled. This will be used later on for determining P and for Signal averaging 
    SamplesPerPixel = zeros(AcqParameters.VPixels,AcqParameters.HPixels,AcqParameters.TotalCycledPolarizations,AcqParameters.SubFrames);
    for SF = 1:AcqParameters.SubFrames
        for Pol = 1:AcqParameters.TotalCycledPolarizations
            for i = ((SF-1)*ShotsPerFrame/AcqParameters.SubFrames+Pol):AcqParameters.TotalCycledPolarizations:(SF*ShotsPerFrame/AcqParameters.SubFrames)
                SamplesPerPixel(ShotBinsY(i),ShotBinsX(i),AcqParameters.PolOrder(Pol),SF) = SamplesPerPixel(ShotBinsY(i),ShotBinsX(i),AcqParameters.PolOrder(Pol),SF) + 1;
            end
        end
    end

    %Determine the number of pixels that were sampled at least i times. This is used to determine
    %the three cutoff points for which pixels were sampled highly, mid, or lowly.
    NumPixelsSamplediTimes = [0,zeros(1,max(SamplesPerPixel(1:end)))];
    for i = 2:numel(NumPixelsSamplediTimes)
        NumPixelsSamplediTimes(i) = NumPixelsSamplediTimes(i-1) + sum(SamplesPerPixel(1:end) >= (i-1));
    end
    
    %Three points in a logspace from the largest cutoff that contains TotalImagePixels to the point that holds 1% of the pixels provides
    %very efficient cutoffs. For my lissajous trajectory with 1 pol and frame, I came up with about 50MB per group nearly evenly.  For 10pols,
    %it was 45MB,85MB,45MB, which is also quite good! It seems that this solution will be general enough and simple enough.           
    TotalImagePixels = AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations*AcqParameters.SubFrames;
    diffNumPixelsSamplediTimes = [TotalImagePixels,diff(NumPixelsSamplediTimes)];
    ThreeCutOffs = round(logspace(log10(find(diffNumPixelsSamplediTimes == TotalImagePixels,1,'last')),log10(find(diffNumPixelsSamplediTimes < TotalImagePixels*.01,1,'first')),3));
    
    %Used to determine which of the 3 matrices each datapoint in the datastream belongs to 
    HighSamplePixelSelector = (SamplesPerPixel(1:end) >= ThreeCutOffs(3)); 
    MidSamplePixelSelector = ((SamplesPerPixel(1:end) >= ThreeCutOffs(2)) & (SamplesPerPixel(1:end) < ThreeCutOffs(3)));
    LowSamplePixelSelector = (SamplesPerPixel(1:end) < ThreeCutOffs(2)); 

    %If there are no samples in a pixel, change to zero. This is a little silly because element would not be accessed during datastream 
    %assignment anyway, but this instead allows me to perform the following SampleColumn step quickly.  
    LowSamplePixelSelector(SamplesPerPixel(1:end) == 0) = 0; 
    
    %Determine which column of the PixelGroup matrix each datapoint in the datastream should go in
    HighSampleColumn = cumsum(HighSamplePixelSelector); 
    MidSampleColumn = cumsum(MidSamplePixelSelector);
    LowSampleColumn = cumsum(LowSamplePixelSelector); 
    
    %The linear index location of every pixel in the final image for the highest, mid, and lowest sampled pixels. 
    %Used for descrambling the summed PixelGroup matrix to the FinalImage pixels. There is a 1:1 relationship for the pixel in the 
    %final image to column in the PixelGroup matrix
    HighSampleFinalPixelIndex = find(SamplesPerPixel(1:end) >= ThreeCutOffs(3)); 
    MidSampleFinalPixelIndex = find((SamplesPerPixel(1:end) >= ThreeCutOffs(2)) & (SamplesPerPixel(1:end) < ThreeCutOffs(3)));
    LowSampleFinalPixelIndex = find(SamplesPerPixel(1:end) < ThreeCutOffs(2)); 
    
    %Pixels without samples were not given columns in the PixelGroup matrices, so remove these assignments from the lowsample list. 
    LowSampleFinalPixelIndex(SamplesPerPixel(LowSampleFinalPixelIndex) == 0) = [];
    
    %The maximum number of samples considered in each of the three groups
    SamplesPerCutOff(3) = max(SamplesPerPixel(1:end));
    SamplesPerCutOff(2) = ThreeCutOffs(3)-1;
    SamplesPerCutOff(1) = ThreeCutOffs(2)-1;
    
    %The number of pixels included in each of the three groups
    PixelsPerCutOff(3) = HighSampleColumn(end);
    PixelsPerCutOff(2) = MidSampleColumn(end);
    PixelsPerCutOff(1) = LowSampleColumn(end);
    
    %Instantiate the PixelGroup matrix and data arrays. This will be filled with indices. 
    HighSamplePixelGroupDataIndex = zeros(1,sum(SamplesPerPixel(HighSampleFinalPixelIndex)));
    MidSamplePixelGroupDataIndex = zeros(1,sum(SamplesPerPixel(MidSampleFinalPixelIndex)));
    LowSamplePixelGroupDataIndex = zeros(1,sum(SamplesPerPixel(LowSampleFinalPixelIndex)));
    HighSamplePixelGroupMatrixIndex = HighSamplePixelGroupDataIndex;
    MidSamplePixelGroupMatrixIndex = MidSamplePixelGroupDataIndex;
    LowSamplePixelGroupMatrixIndex = LowSamplePixelGroupDataIndex;
    
    %Generate the three sets of three index vectors I will need to reshape and reorganize the data, *MatrixIndex, *DataIndex, and *PixelIndex. 
    CurrentSampleNum = zeros(1,AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations*AcqParameters.SubFrames);
    LowSampleElement = 0;
    MidSampleElement = 0;
    HighSampleElement = 0;
    for SF = 1:AcqParameters.SubFrames
        for Pol = 1:AcqParameters.TotalCycledPolarizations
            %i steps through every VPixel*HPixel element within every SubFrame (SF) and Pol
            for i = ((SF-1)*ShotsPerFrame/AcqParameters.SubFrames+Pol):AcqParameters.TotalCycledPolarizations:(SF*ShotsPerFrame/AcqParameters.SubFrames)
                %I cannot afford the function overhead here, so I implemented my own fast sub2ind routine in a single line.
                CurrentIndex = ShotBinsY(i) + (ShotBinsX(i)-1)*AcqParameters.VPixels + (AcqParameters.PolOrder(Pol)-1)*AcqParameters.HPixels*AcqParameters.VPixels + (SF-1)*AcqParameters.TotalCycledPolarizations*AcqParameters.HPixels*AcqParameters.VPixels;
                CurrentSampleNum(CurrentIndex) = CurrentSampleNum(CurrentIndex) + 1;
                if LowSamplePixelSelector(CurrentIndex)
                    LowSampleElement = LowSampleElement + 1; %The location within the index arrays where the indices should be placed 
                    LowSamplePixelGroupDataIndex(LowSampleElement) = i; % Stores the index of the RawDataChannel array element
                    %I cannot afford the function overhead here, so I implemented my own fast sub2ind routine in a single line.
                    %Stores the index of the location in the GroupMatrix that the current RawDataChannel element should go in. 
                    LowSamplePixelGroupMatrixIndex(LowSampleElement) = CurrentSampleNum(CurrentIndex) + (LowSampleColumn(CurrentIndex)-1)*SamplesPerCutOff(1);
                elseif MidSamplePixelSelector(CurrentIndex)
                    MidSampleElement = MidSampleElement + 1; %The location within the index arrays where the indices should be placed 
                    MidSamplePixelGroupDataIndex(MidSampleElement) = i; % Stores the index of the RawDataChannel array element
                    MidSamplePixelGroupMatrixIndex(MidSampleElement) = CurrentSampleNum(CurrentIndex) + (MidSampleColumn(CurrentIndex)-1)*SamplesPerCutOff(2);
                elseif HighSamplePixelSelector(CurrentIndex)
                    HighSampleElement = HighSampleElement + 1; %The location within the index arrays where the indices should be placed 
                    HighSamplePixelGroupDataIndex(HighSampleElement) = i; % Stores the index of the RawDataChannel array element
                    HighSamplePixelGroupMatrixIndex(HighSampleElement) = CurrentSampleNum(CurrentIndex) + (HighSampleColumn(CurrentIndex)-1)*SamplesPerCutOff(3);
                end
            end
        end
    end
else %Galvo/ResonantMirror Scanning

    %The number of mirror periods per frame is equal to the number of galvo steps (Number of Horizontal Lines)
    NumResMirrorPeriods = AcqParameters.HPixels; 
    ShotsPerFrame = samplesPerRecord;
    
    %Determine the starting phase of each mirror. The user specified the number of laser shots 
    %until 0 degrees crossing of each mirror from start of capture.
    ResMirrorPhase = 2*pi*GalvoResMonitorPhaseDelay/AcqParameters.ShotsPerMirrorPeriodGalvoRes;
    
    %Places laser shots in bins from 1 to VPixels
    ShotBinsY = 0.5*cos(linspace(-1*ResMirrorPhase,(2*pi*NumResMirrorPeriods)-ResMirrorPhase,ShotsPerFrame+1))+0.5;   %A sine wave of amplitude from 1 to 0
    ShotBinsY = round((AcqParameters.VPixels-1)*ShotBinsY(1:(end-1)))+1;  
    
    %Places each laser shot in the correct bin. The galvo steps once after every VPixel sweep. 
    ShotBinsX = repmat(1:AcqParameters.HPixels,[AcqParameters.ShotsPerMirrorPeriodGalvoRes,1]);
    ShotBinsX = ShotBinsX(1:end);
    
    %Determine the total number of times each pixel within each subframe was sampled. This will be used later on for determining P and for Signal averaging 
    SamplesPerPixel = zeros(AcqParameters.VPixels,AcqParameters.HPixels,AcqParameters.TotalCycledPolarizations,AcqParameters.SubFrames);
    for SF = 1:AcqParameters.SubFrames
        for Pol = 1:AcqParameters.TotalCycledPolarizations
            for i = ((SF-1)*ShotsPerFrame/AcqParameters.SubFrames+Pol):AcqParameters.TotalCycledPolarizations:(SF*ShotsPerFrame/AcqParameters.SubFrames)
                SamplesPerPixel(ShotBinsY(i),ShotBinsX(i),AcqParameters.PolOrder(Pol),SF) = SamplesPerPixel(ShotBinsY(i),ShotBinsX(i),AcqParameters.PolOrder(Pol),SF) + 1;
            end
        end
    end
    
    %Determine the number of pixels that were sampled at least i times. This is used to determine
    %the three cutoff points for which pixels were sampled highly, mid, or lowly.
    NumPixelsSamplediTimes = [0,zeros(1,max(SamplesPerPixel(1:end)))];
    for i = 2:numel(NumPixelsSamplediTimes)
        NumPixelsSamplediTimes(i) = NumPixelsSamplediTimes(i-1) + sum(SamplesPerPixel(1:end) >= (i-1));
    end
    
    %Three points in a logspace from the largest cutoff that contains TotalImagePixels to the point that holds 1% of the pixels provides
    %very efficient cutoffs. For my lissajous trajectory with 1 pol and frame, I came up with about 50MB per group nearly evenly.  For 10pols,
    %it was 45MB,85MB,45MB, which is also quite good! It seems that this solution will be general enough and simple enough.           
    TotalImagePixels = AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations*AcqParameters.SubFrames;
    diffNumPixelsSamplediTimes = [TotalImagePixels,diff(NumPixelsSamplediTimes)];
    ThreeCutOffs = round(logspace(log10(find(diffNumPixelsSamplediTimes == TotalImagePixels,1,'last')),log10(find(diffNumPixelsSamplediTimes < TotalImagePixels*.01,1,'first')),3));
    
    %Used to determine which of the 3 matrices each datapoint in the datastream belongs to 
    HighSamplePixelSelector = (SamplesPerPixel(1:end) >= ThreeCutOffs(3)); 
    MidSamplePixelSelector = ((SamplesPerPixel(1:end) >= ThreeCutOffs(2)) & (SamplesPerPixel(1:end) < ThreeCutOffs(3)));
    LowSamplePixelSelector = (SamplesPerPixel(1:end) < ThreeCutOffs(2)); 

    %If there are no samples in a pixel, change to zero. This is a little silly because element would not be accessed during datastream 
    %assignment anyway, but this instead allows me to perform the following SampleColumn step quickly.  
    LowSamplePixelSelector(SamplesPerPixel(1:end) == 0) = 0; 
    
    %Determine which column of the PixelGroup matrix each datapoint in the datastream should go in
    HighSampleColumn = cumsum(HighSamplePixelSelector); 
    MidSampleColumn = cumsum(MidSamplePixelSelector);
    LowSampleColumn = cumsum(LowSamplePixelSelector); 
    
    %The linear index location of every pixel in the final image for the highest, mid, and lowest sampled pixels. 
    %Used for descrambling the summed PixelGroup matrix to the FinalImage pixels. There is a 1:1 relationship for the pixel in the 
    %final image to column in the PixelGroup matrix
    HighSampleFinalPixelIndex = find(SamplesPerPixel(1:end) >= ThreeCutOffs(3)); 
    MidSampleFinalPixelIndex = find((SamplesPerPixel(1:end) >= ThreeCutOffs(2)) & (SamplesPerPixel(1:end) < ThreeCutOffs(3)));
    LowSampleFinalPixelIndex = find(SamplesPerPixel(1:end) < ThreeCutOffs(2)); 
    
    %Pixels without samples were not given columns in the PixelGroup matrices, so remove these assignments from the lowsample list. 
    LowSampleFinalPixelIndex(SamplesPerPixel(LowSampleFinalPixelIndex) == 0) = [];
    
    %The maximum number of samples considered in each of the three groups
    SamplesPerCutOff(3) = max(SamplesPerPixel(1:end));
    SamplesPerCutOff(2) = ThreeCutOffs(3)-1;
    SamplesPerCutOff(1) = ThreeCutOffs(2)-1;
    
    %The number of pixels included in each of the three groups
    PixelsPerCutOff(3) = HighSampleColumn(end);
    PixelsPerCutOff(2) = MidSampleColumn(end);
    PixelsPerCutOff(1) = LowSampleColumn(end);
    
    %Instantiate the PixelGroup matrix and data arrays. This will be filled with indices. 
    HighSamplePixelGroupDataIndex = zeros(1,sum(SamplesPerPixel(HighSampleFinalPixelIndex)));
    MidSamplePixelGroupDataIndex = zeros(1,sum(SamplesPerPixel(MidSampleFinalPixelIndex)));
    LowSamplePixelGroupDataIndex = zeros(1,sum(SamplesPerPixel(LowSampleFinalPixelIndex)));
    HighSamplePixelGroupMatrixIndex = HighSamplePixelGroupDataIndex;
    MidSamplePixelGroupMatrixIndex = MidSamplePixelGroupDataIndex;
    LowSamplePixelGroupMatrixIndex = LowSamplePixelGroupDataIndex;
    
    %Generate the three sets of three index vectors I will need to reshape and reorganize the data, *MatrixIndex, *DataIndex, and *PixelIndex. 
    CurrentSampleNum = zeros(1,AcqParameters.VPixels*AcqParameters.HPixels*AcqParameters.TotalCycledPolarizations*AcqParameters.SubFrames);
    LowSampleElement = 0;
    MidSampleElement = 0;
    HighSampleElement = 0;
    for SF = 1:AcqParameters.SubFrames
        for Pol = 1:AcqParameters.TotalCycledPolarizations
            %i steps through every VPixel*HPixel element within every SubFrame (SF) and Pol
            for i = ((SF-1)*ShotsPerFrame/AcqParameters.SubFrames+Pol):AcqParameters.TotalCycledPolarizations:(SF*ShotsPerFrame/AcqParameters.SubFrames)
                %I cannot afford the function overhead here, so I implemented my own fast sub2ind routine in a single line.
                CurrentIndex = ShotBinsY(i) + (ShotBinsX(i)-1)*AcqParameters.VPixels + (AcqParameters.PolOrder(Pol)-1)*AcqParameters.HPixels*AcqParameters.VPixels + (SF-1)*AcqParameters.TotalCycledPolarizations*AcqParameters.HPixels*AcqParameters.VPixels;
                CurrentSampleNum(CurrentIndex) = CurrentSampleNum(CurrentIndex) + 1;
                if LowSamplePixelSelector(CurrentIndex)
                    LowSampleElement = LowSampleElement + 1; %The location within the index arrays where the indices should be placed 
                    LowSamplePixelGroupDataIndex(LowSampleElement) = i; % Stores the index of the RawDataChannel array element
                    %I cannot afford the function overhead here, so I implemented my own fast sub2ind routine in a single line.
                    %Stores the index of the location in the GroupMatrix that the current RawDataChannel element should go in. 
                    LowSamplePixelGroupMatrixIndex(LowSampleElement) = CurrentSampleNum(CurrentIndex) + (LowSampleColumn(CurrentIndex)-1)*SamplesPerCutOff(1);
                elseif MidSamplePixelSelector(CurrentIndex)
                    MidSampleElement = MidSampleElement + 1; %The location within the index arrays where the indices should be placed 
                    MidSamplePixelGroupDataIndex(MidSampleElement) = i; % Stores the index of the RawDataChannel array element
                    MidSamplePixelGroupMatrixIndex(MidSampleElement) = CurrentSampleNum(CurrentIndex) + (MidSampleColumn(CurrentIndex)-1)*SamplesPerCutOff(2);
                elseif HighSamplePixelSelector(CurrentIndex)
                    HighSampleElement = HighSampleElement + 1; %The location within the index arrays where the indices should be placed 
                    HighSamplePixelGroupDataIndex(HighSampleElement) = i; % Stores the index of the RawDataChannel array element
                    HighSamplePixelGroupMatrixIndex(HighSampleElement) = CurrentSampleNum(CurrentIndex) + (HighSampleColumn(CurrentIndex)-1)*SamplesPerCutOff(3);
                end
            end
        end
    end
end

%Reshape the SamplesPerPixel into matrix dimensions of the image 
SamplesPerPixel = reshape(SamplesPerPixel, [], AcqParameters.SubFrames);
%Sort the data for faster processing
[HighSamplePixelGroupDataIndex,TempIndex] = sort(HighSamplePixelGroupDataIndex);
HighSamplePixelGroupMatrixIndex = HighSamplePixelGroupMatrixIndex(TempIndex);
[MidSamplePixelGroupDataIndex,TempIndex] = sort(MidSamplePixelGroupDataIndex);
MidSamplePixelGroupMatrixIndex = MidSamplePixelGroupMatrixIndex(TempIndex);
[LowSamplePixelGroupDataIndex,TempIndex] = sort(LowSamplePixelGroupDataIndex);
LowSamplePixelGroupMatrixIndex = LowSamplePixelGroupMatrixIndex(TempIndex);

%Cast the indices as uint32 for faster processing
HighSamplePixelGroupDataIndex = uint64(HighSamplePixelGroupDataIndex);
MidSamplePixelGroupDataIndex = uint64(MidSamplePixelGroupDataIndex);
LowSamplePixelGroupDataIndex = uint64(LowSamplePixelGroupDataIndex);
HighSamplePixelGroupMatrixIndex = uint64(HighSamplePixelGroupMatrixIndex);
MidSamplePixelGroupMatrixIndex = uint64(MidSamplePixelGroupMatrixIndex);
LowSamplePixelGroupMatrixIndex = uint64(LowSamplePixelGroupMatrixIndex);
HighSampleFinalPixelIndex = uint64(HighSampleFinalPixelIndex);
MidSampleFinalPixelIndex = uint64(MidSampleFinalPixelIndex);
LowSampleFinalPixelIndex = uint64(LowSampleFinalPixelIndex);