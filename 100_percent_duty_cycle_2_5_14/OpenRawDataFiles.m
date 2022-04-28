function [RawDataChanFID] = OpenRawDataFiles(AcqParameters)

if AcqParameters.LissaJous
    ScanMode = ' LissaJous';
else
    ScanMode = ' GalvoRes';
end

RawDataChanFID = -1*ones(1,numel(AcqParameters.Channel));
for i = 1:numel(AcqParameters.Channel)
    if AcqParameters.Channel(i)
        RawDataChanFID(i) = fopen([AcqParameters.FilePath,regexprep(datestr(now),':','_'),ScanMode,' RawDataChan',char(64+i),'.bin'], 'w');
        if RawDataChanFID(i) == -1
            fprintf('Error: Unable to create data file\n');        
        end
    end
end