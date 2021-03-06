function [ProcessedDataChanPolAnalysisFID] = OpenProcessedDataFiles(AcqParameters)

%Data will be saved as (DateTime)(Galvo/Res or LissaJous)(Chan(A,B,C,D))(AVG, Counting, or Hybrid)(Pol#)(#Images)(#SubFrames, if > 1).bin.
%                                                              1 2 3 4    1       2           3    Pol#              

ProcessedDataChanPolAnalysisFID = -1*ones(numel(AcqParameters.Channel),AcqParameters.TotalCycledPolarizations,2);
for Chan = 1:numel(AcqParameters.Channel)
    for Pol = 1:AcqParameters.TotalCycledPolarizations
        if AcqParameters.Channel(Chan)
            if AcqParameters.LissaJous
                if AcqParameters.Averaging(Chan)
                    filename = [AcqParameters.FilePath,regexprep(datestr(now),':','_'),' LissaJous',' Chan',char(64+Chan),' Averaging',' Pol',int2str(Pol),' ',int2str(AcqParameters.NumberOfImages),'Images'];
                    if AcqParameters.SubFrames > 1;
                        filename = [filename,' ',int2str(AcqParameters.SubFrames),'SubFrames','.bin'];
                    else
                        filename = [filename,'.bin'];
                    end
                    ProcessedDataChanPolAnalysisFID(Chan,Pol,1) = fopen(filename, 'w');
                    if ProcessedDataChanPolAnalysisFID(Chan,Pol,1) == -1
                        fprintf('Error: Unable to create data file\n');        
                    end
                end
                if AcqParameters.Counting(Chan)
                    filename = [AcqParameters.FilePath,regexprep(datestr(now),':','_'),' LissaJous',' Chan',char(64+Chan),' Counting',' Pol',int2str(Pol),' ',int2str(AcqParameters.NumberOfImages),'Images'];
                    if AcqParameters.SubFrames > 1;
                        filename = [filename,' ',int2str(AcqParameters.SubFrames),'SubFrames','.bin'];
                    else
                        filename = [filename,'.bin'];
                    end
                    ProcessedDataChanPolAnalysisFID(Chan,Pol,2) = fopen(filename, 'w');
                    if ProcessedDataChanPolAnalysisFID(Chan,Pol,2) == -1
                        fprintf('Error: Unable to create data file\n');        
                    end
                end
                if AcqParameters.HybridAvgCount(Chan)
                    filename = [AcqParameters.FilePath,regexprep(datestr(now),':','_'),' LissaJous',' Chan',char(64+Chan),' HybridAvgCount',' Pol',int2str(Pol),' ',int2str(AcqParameters.NumberOfImages),'Images'];
                    if AcqParameters.SubFrames > 1;
                        filename = [filename,' ',int2str(AcqParameters.SubFrames),'SubFrames','.bin'];
                    else
                        filename = [filename,'.bin'];
                    end
                    ProcessedDataChanPolAnalysisFID(Chan,Pol,3) = fopen(filename, 'w');
                    if ProcessedDataChanPolAnalysisFID(Chan,Pol,3) == -1
                        fprintf('Error: Unable to create data file\n');        
                    end
                end
            else %Galvo/Res
                if AcqParameters.Averaging(Chan)
                    filename = [AcqParameters.FilePath,regexprep(datestr(now),':','_'),' GalvoRes',' Chan',char(64+Chan),' Averaging',' Pol',int2str(Pol),' ',int2str(AcqParameters.NumberOfImages),'Images'];
                    if AcqParameters.SubFrames > 1;
                        filename = [filename,' ',int2str(AcqParameters.SubFrames),'SubFrames','.bin'];
                    else
                        filename = [filename,'.bin'];
                    end
                    ProcessedDataChanPolAnalysisFID(Chan,Pol,1) = fopen(filename, 'w');
                    if ProcessedDataChanPolAnalysisFID(Chan,Pol,1) == -1
                        fprintf('Error: Unable to create data file\n');        
                    end
                end
                if AcqParameters.Counting(Chan)
                    filename = [AcqParameters.FilePath,regexprep(datestr(now),':','_'),' GalvoRes',' Chan',char(64+Chan),' Counting',' Pol',int2str(Pol),' ',int2str(AcqParameters.NumberOfImages),'Images'];
                    if AcqParameters.SubFrames > 1;
                        filename = [filename,' ',int2str(AcqParameters.SubFrames),'SubFrames','.bin'];
                    else
                        filename = [filename,'.bin'];
                    end
                    ProcessedDataChanPolAnalysisFID(Chan,Pol,2) = fopen(filename, 'w');
                    if ProcessedDataChanPolAnalysisFID(Chan,Pol,2) == -1
                        fprintf('Error: Unable to create data file\n');        
                    end
                end
                if AcqParameters.HybridAvgCount(Chan)
                    filename = [AcqParameters.FilePath,regexprep(datestr(now),':','_'),' GalvoRes',' Chan',char(64+Chan),' HybridAvgCount',' Pol',int2str(Pol),' ',int2str(AcqParameters.NumberOfImages),'Images'];
                    if AcqParameters.SubFrames > 1;
                        filename = [filename,' ',int2str(AcqParameters.SubFrames),'SubFrames','.bin'];
                    else
                        filename = [filename,'.bin'];
                    end
                    ProcessedDataChanPolAnalysisFID(Chan,Pol,3) = fopen(filename, 'w');
                    if ProcessedDataChanPolAnalysisFID(Chan,Pol,3) == -1
                        fprintf('Error: Unable to create data file\n');        
                    end                    
                end
            end
        end
    end
end