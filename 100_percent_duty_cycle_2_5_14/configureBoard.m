% Pretty 5please do NOT edit anything here unless you know what you are doing!

function [result] = configureBoard(boardId, boardHandle, ConfigureVariables)
% Configure sample rate, input, and trigger settings

%call mfile with library definitions
AlazarDefs

%Configure board by board Id 
fprintf('Configure board Id %u\n', boardId);

% set default return code to indicate failure
result = false;

if (ConfigureVariables.ClockType == 2) %Fast External Clock
    retCode = calllib('ATSApi', 'AlazarSetCaptureClock', ...
            boardHandle,		...	% HANDLE -- board handle
            FAST_EXTERNAL_CLOCK,		...	% U32 -- clock source id | This is using the 10MHz PLL
            ConfigureVariables.SampleRate,...	% U32 -- sample rate id  
            CLOCK_EDGE_RISING,	...	% U32 -- clock edge id
            0					...	% U32 -- clock decimation 
            );
   retCode =  calllib('ATSApi', 'AlazarSetExternalClockLevel', boardHandle, 0);

elseif (ConfigureVariables.ClockType == 1) % 10MHzPLL
    retCode = calllib('ATSApi', 'AlazarSetCaptureClock', ...
        boardHandle,		...	% HANDLE -- board handle
        EXTERNAL_CLOCK_10MHz_REF,		...	% U32 -- clock source id | This is using the 10MHz PLL
        ConfigureVariables.SampleRate,...	% U32 -- sample rate id | 
        CLOCK_EDGE_RISING,	...	% U32 -- clock edge id
        ConfigureVariables.DecimationValue	...	% U32 -- clock decimation 
        );
elseif (ConfigureVariables.ClockType == 3) % Internal Clock
    retCode = calllib('ATSApi', 'AlazarSetCaptureClock', ...
        boardHandle,		...	% HANDLE -- board handle
        INTERNAL_CLOCK,		...	% U32 -- clock source id | This is using the 10MHz PLL
        SAMPLE_RATE_100MSPS,...	% U3e2 -- sample rate id | 
        CLOCK_EDGE_RISING,	...	% U32 -- clock edge id
        ConfigureVariables.DecimationValue	...	% U32 -- clock decimation 
        );
end
    
if retCode ~= ApiSuccess
    fprintf('Error: AlazarSetCaptureClock failed -- %s\n', errorToText(retCode));
    return
end

if (boardId ==1)
    
    %Select CHA input parameters as required for board 1
    retCode = calllib('ATSApi', 'AlazarInputControl', ...       
            boardHandle,		...	% HANDLE -- board handle
            CHANNEL_A,			...	% U8 -- input channel 
            DC_COUPLING,		...	% U32 -- input coupling id
            ConfigureVariables.ChanInputRange(1), ...	% U32 -- input range id
            IMPEDANCE_50_OHM	...	% U32 -- input impedance id
            );
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarInputControl failed -- %s\n', errorToText(retCode));
        return
    end

    %Select CHA bandwidth limit as required for board 1
    retCode = calllib('ATSApi', 'AlazarSetBWLimit', ...       
            boardHandle,		...	% HANDLE -- board handle
            CHANNEL_A,			...	% U8 -- channel identifier
            0					...	% U32 -- 0 = disable, 1 = enable
            );
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarSetBWLimit failed -- %s\n', errorToText(retCode));
        return
    end

    %Select CHB input parameters as required for board 1
    retCode = calllib('ATSApi', 'AlazarInputControl', ...       
            boardHandle,		...	% HANDLE -- board handle
            CHANNEL_B,			...	% U8 -- channel identifier
            DC_COUPLING,		...	% U32 -- input coupling id
            ConfigureVariables.ChanInputRange(2),	...	% U32 -- input range id
            IMPEDANCE_50_OHM	...	% U32 -- input impedance id
            );
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarInputControl failed -- %s\n', errorToText(retCode));
        return
    end

    %Select CHB bandwidth limit as required for board 1
    retCode = calllib('ATSApi', 'AlazarSetBWLimit', ...       
            boardHandle,		...	% HANDLE -- board handle
            CHANNEL_B,			...	% U8 -- channel identifier
            0					...	% U32 -- 0 = disable, 1 = enable
            );
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarSetBWLimit failed -- %s\n', errorToText(retCode));
        return
    end
end


if (boardId ==2)
    %Select CHC input parameters as required for board 2
    retCode = calllib('ATSApi', 'AlazarInputControl', ...       
            boardHandle,		...	% HANDLE -- board handle
            CHANNEL_A,			...	% U8 -- input channel 
            DC_COUPLING,		...	% U32 -- input coupling id
            ConfigureVariables.ChanInputRange(3), ...	% U32 -- input range id
            IMPEDANCE_50_OHM	...	% U32 -- input impedance id
            );
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarInputControl failed -- %s\n', errorToText(retCode));
        return
    end

    %Select CHA bandwidth limit as required for board 2
    retCode = calllib('ATSApi', 'AlazarSetBWLimit', ...       
            boardHandle,		...	% HANDLE -- board handle
            CHANNEL_A,			...	% U8 -- channel identifier
            0					...	% U32 -- 0 = disable, 1 = enable
            );
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarSetBWLimit failed -- %s\n', errorToText(retCode));
        return
    end

    %Select CHD input parameters as required for board 2
    retCode = calllib('ATSApi', 'AlazarInputControl', ...       
            boardHandle,		...	% HANDLE -- board handle
            CHANNEL_B,			...	% U8 -- channel identifier
            DC_COUPLING,		...	% U32 -- input coupling id
            ConfigureVariables.ChanInputRange(4),	...	% U32 -- input range id
            IMPEDANCE_50_OHM	...	% U32 -- input impedance id
            );
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarInputControl failed -- %s\n', errorToText(retCode));
        return
    end

    %Select CHB bandwidth limit as required for board 2
    retCode = calllib('ATSApi', 'AlazarSetBWLimit', ...       
            boardHandle,		...	% HANDLE -- board handle
            CHANNEL_B,			...	% U8 -- channel identifier
            0					...	% U32 -- 0 = disable, 1 = enable
            );
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarSetBWLimit failed -- %s\n', errorToText(retCode));
        return
    end
end

if (boardId == 1)
%Select trigger inputs and levels as required for master
retCode = calllib('ATSApi', 'AlazarSetTriggerOperation', ...       
        boardHandle,		...	% HANDLE -- board handle
        TRIG_ENGINE_OP_J,	...	% U32 -- trigger operation 
        TRIG_ENGINE_J,		...	% U32 -- trigger engine id
        TRIG_EXTERNAL,		...	% U32 -- trigger source id  
        TRIGGER_SLOPE_NEGATIVE,	... % U32 -- trigger slope id
        ConfigureVariables.TriggerLevel,				...	% U32 -- trigger level from 0 (-range) to 255 (+range) 
        TRIG_ENGINE_K,		...	% U32 -- trigger engine id
        TRIG_DISABLE,		...	% U32 -- trigger source id for engine K
        TRIGGER_SLOPE_POSITIVE, ...	% U32 -- trigger slope id
        128					...	% U32 -- trigger level from 0 (-range) to 255 (+range)
        );
end


if (boardId == 2)
%Select trigger inputs and levels as required for slave
retCode = calllib('ATSApi', 'AlazarSetTriggerOperation', ...       
        boardHandle,		...	% HANDLE -- board handle
        TRIG_ENGINE_OP_J,	...	% U32 -- trigger operation 
        TRIG_ENGINE_J,		...	% U32 -- trigger engine id
        TRIG_DISABLE,		...	% U32 -- trigger source id  | Set to disable to make it behave as slave
        TRIGGER_SLOPE_NEGATIVE,	... % U32 -- trigger slope id
        128,				...	% U32 -- trigger level from 0 (-range) to 255 (+range) | This value is not used, only triggering off card 1
        TRIG_ENGINE_K,		...	% U32 -- trigger engine id
        TRIG_DISABLE,		...	% U32 -- trigger source id for engine K
        TRIGGER_SLOPE_POSITIVE, ...	% U32 -- trigger slope id
        128					...	% U32 -- trigger level from 0 (-range) to 255 (+range)
        );
end
    
if retCode ~= ApiSuccess
    fprintf('Error: AlazarSetTriggerOperation failed -- %s\n', errorToText(retCode));
    return
end

%Select external trigger parameters as required
if (boardId == 1)
    retCode = calllib('ATSApi', 'AlazarSetExternalTrigger', ...       
            boardHandle,		...	% HANDLE -- board handle
            DC_COUPLING,		...	% U32 -- external trigger coupling id
            ConfigureVariables.TriggerLevel	...	% U32 -- external trigger range id
            );
end
if retCode ~= ApiSuccess
    fprintf('Error: AlazarSetExternalTrigger failed -- %s\n', errorToText(retCode));
    return
end
    
%Set trigger delay as required. 
triggerDelay_samples = uint32(0);
retCode = calllib('ATSApi', 'AlazarSetTriggerDelay', boardHandle, triggerDelay_samples);
if retCode ~= ApiSuccess
    fprintf('Error: AlazarSetTriggerDelay failed -- %s\n', errorToText(retCode));
    return;
end

% NOTE:
% The board will wait for a for this amount of time for a trigger event. 
% If a trigger event does not arrive, then the board will automatically 
% trigger. Set the trigger timeout value to 0 to force the board to wait 
% forever for a trigger event.
triggerTimeout_clocks = uint32(0); 
retCode = calllib('ATSApi', 'AlazarSetTriggerTimeOut', ...       
        boardHandle,            ...	% HANDLE -- board handle
        triggerTimeout_clocks	... % U32 -- trigger timeout in clock ticks (0 == wait forever)
        );
if retCode ~= ApiSuccess
    fprintf('Error: AlazarSetTriggerTimeOut failed -- %s\n', errorToText(retCode));
    return
end

if (boardId == 1)


    if ConfigureVariables.ForcePacerOnCard1
        %Configure AUX I/O connector on board 1 to pacer 
        disp('pacer out')

        retCode = calllib('ATSApi', 'AlazarConfigureAuxIO', ...       
        boardHandle,		...	% HANDLE -- board handle
        AUX_OUT_PACER,	...	% U32 -- mode    4760+2^31 ... (pacerValue+2^31)
        ConfigureVariables.PacerValue + 2^31 ... 	% U32 --For ~7.8KHz with MSB set to 1 (160,000,000 / 20320 = 7,847 for the 9462 system)
        ); %parameter numerically of 20320/4 for ~7.8KHz with MSB set to 1 (160,000,000 / 20320/4 = 7,847 for the 9350 system (the pacer works off a /4 clock of the ADC on this card, that is why /4))
        %This is undocumented in the 6.03 SDK. Alazar made this firware custom for us, so the pacer out would not get interupted
        %every time a new acquisition was started. To do this, we set the pacer out divide by what is required, but then set the MSB
        %(most significant bit) to 1. This tells the Alazar cards to not interupt the pacer at the beginning of each acquisition. This
        %is VERY important.
        if retCode ~= ApiSuccess
            fprintf('Error: AlazarConfigureAuxIO failed -- %s\n', errorToText(retCode));
            return 
        end  
    else
        %Configure AUX I/O connector on board 1 to high 
        retCode = calllib('ATSApi', 'AlazarConfigureAuxIO', ...       
        boardHandle,		...	% HANDLE -- board handle
        AUX_OUT_BUSY,	...	% U32 -- mode    AUX_OUT_BUSY undocumented in 6.03 SDK, but sets auxout to high
        1					...	% U32 -- parameter
        );	
        if retCode ~= ApiSuccess
            fprintf('Error: AlazarConfigureAuxIO failed -- %s\n', errorToText(retCode));
            return 
        end  
    end
end

if (boardId == 2)
    %Configure AUX I/O connector on board 2 to pacer 
    retCode = calllib('ATSApi', 'AlazarConfigureAuxIO', ...       
            boardHandle,		...	% HANDLE -- board handle
            AUX_OUT_PACER,	...	% U32 -- mode    4760+2^31 ... (pacerValue+2^31)
            ConfigureVariables.PacerValue + 2^31 ... 	% U32 --For ~7.8KHz with MSB set to 1 (160,000,000 / 20320 = 7,847 for the 9462 system)
            ); %parameter numerically of 20320/4 for ~7.8KHz with MSB set to 1 (160,000,000 / 20320/4 = 7,847 for the 9350 system (the pacer works off a /4 clock of the ADC on this card, that is why /4))
               %This is undocumented in the 6.03 SDK. Alazar made this firware custom for us, so the pacer out would not get interupted
               %every time a new acquisition was started. To do this, we set the pacer out divide by what is required, but then set the MSB
               %(most significant bit) to 1. This tells the Alazar cards to not interupt the pacer at the beginning of each acquisition. This
               %is VERY important.
    if retCode ~= ApiSuccess
        fprintf('Error: AlazarConfigureAuxIO failed -- %s\n', errorToText(retCode));
        return 
    end  
end
    

result = true;