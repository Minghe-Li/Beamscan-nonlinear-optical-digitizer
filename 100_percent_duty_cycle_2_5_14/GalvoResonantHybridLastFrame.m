function GalvoResonantHybridLastFrame(AcqParameters,ImageData,Channel,LiveImagePlot,LastBufferInAcquisition)

FinalImage = reshape(ImageData, [AcqParameters.VPixels,AcqParameters.HPixels,AcqParameters.TotalCycledPolarizations,AcqParameters.SubFrames]);

if LastBufferInAcquisition && AcqParameters.ShowImages
    for Pol = 1:AcqParameters.TotalCycledPolarizations
        figure
        %Using imshow instead of ImageSC, because we can afford to be inefficient at the last image, and because I can use a tight border 
        imshow(FinalImage(:,:,Pol,end),[],'border','tight')
        colormap(AcqParameters.ColorMap)
        axis('xy')
        colorbar('location','southoutside') 
    end
end

if ishandle(LiveImagePlot.FigureHandle)
    if strfind(AcqParameters.FirstChannelToDisplay,[char(64+Channel),'-HYBRID']) == 1
        Pol = str2double(AcqParameters.FirstChannelToDisplay(13:end));
        if Pol <= AcqParameters.TotalCycledPolarizations
            set(LiveImagePlot.Data(:,:,1), 'CData', (FinalImage(:,:,Pol,end)));
        end    
    end

    if AcqParameters.NumChannelsToDisplay == 2
        if strfind(AcqParameters.SecondChannelToDisplay,[char(64+Channel),'-HYBRID']) == 1
            Pol = str2double(AcqParameters.SecondChannelToDisplay(13:end)); 
            if Pol <= AcqParameters.TotalCycledPolarizations
                set(LiveImagePlot.Data(:,:,2), 'CData', (FinalImage(:,:,Pol,end)));
            end
        end
    end
end

%Save the data, if the user selected to do so.
%Data will be saved as (DateTime)(Galvo/Res or LissaJous)(Chan(A,B,C,D))(AVG, Counting, or Hybrid)(Pol#)(#Images)(#SubFrames, if > 1).bin.
%                                                              1 2 3 4    1       2           3    Pol#              
if AcqParameters.SaveProcessedData
    for Pol = 1:AcqParameters.TotalCycledPolarizations
        fwrite(AcqParameters.ProcessedDataChanPolAnalysisFID(Channel,Pol,3),FinalImage(:,:,Pol,:), 'float32');
    end
end    