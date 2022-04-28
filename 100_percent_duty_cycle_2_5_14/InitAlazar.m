
%% Run this once to initialize the Alazar cards. This sets up the clock, channel input ranges, etc). 
%BEFORE EDITING THIS CODE, MAKE SURE YOU ARE NOT EDITING ANY VARIABLES THAT ARE PRESERVED FOR USE WITH SDImaging.m! 
ClockType = 1; % 1 for 10MHzPLL, 2 for Direct Fast External Clock         
CardType = 1; % 1 for the 9350 cards, 2 for the 9462 cards 
    % Channel Input Ranges.  
    % 0 for +- 200mV        2 for +- 800mV/1V (9350 +-1 / 9462 +-800)
    % 1 for +- 400mV        3 for +- 2V
    % 4 for +- 4V
ChanAInputRange = 0;        ChanBInputRange = 0;
ChanCInputRange = 2;        ChanDInputRange = 0;


%% Advanced Configuration Section
PulsePair = 0; % I.E. if you are sampling at 80MHz or 160MHz
TriggerLevel = 145; % Only edit these if you know what you are doing, else leave at ~ 135, (8 bit number, 128 = 0V)
TriggerRange = 0; % 0 = ±5V Trigger Range, 1 = ±1V Trigger Range
DecimationValue = 0; % Divides Alazar clock frequency by specific integer.

PacerValue = 1  ; % This is for generating a square wave, of some integer division of the sampling frequency, on Aux I/O card 2. Currently not used for anything.
ConfigureVariables.ForcePacerOnCard1 = false;

SampleRate = 80000000*1;  %You only need to change the SampleRate if you laser is not 80MHz. For use with 10MHz PLL.

if PulsePair % Double digitization rate
    SampleRate = SampleRate *2; 
    PacerValue = PacerValue *2;                             
end

if ~PulsePair                   
    if CardType == 2 % 9462 can only range 10MHz PLL from 150-180, so setting rate to 160 and dividing. 
        SampleRate = SampleRate*2; % For 9462, this final value must be between 150-180 MHz.
         DecimationValue = 1; % Actual decimation value is one unit higher then shown here.
    end
end



%% End Use Configuration Section, do not edit anything beyond this unless you are a developer.
global GalvoResMonitorPhaseDelay LissaJousFastMirrorDelay LissaJousSlowMirrorDelay

%Initial guess values for mirror phase in Galvo/ResMirror scanning relative to trigger, in units of 
%number of samples from trigger until fast and slow mirror zero degree crossings. These values 
%will be updated automatically at the end of every capture.
GalvoResMonitorPhaseDelay = 5154; 

%Initial guess values for LissaJous mirror phases relative to trigger, in units of number of samples 
%from trigger until fast and slow mirror zero degree crossings. These values will be updated automatically 
%at the end of every capture.
LissaJousFastMirrorDelay = 50;
LissaJousSlowMirrorDelay = 50;

ConfigureVariables.PulsePair = PulsePair;
ConfigureVariables.ClockType = ClockType;
ConfigureVariables.SampleRate = SampleRate;
ConfigureVariables.PacerValue =PacerValue;
ConfigureVariables.CardType= CardType;
ConfigureVariables.ChanInputRange = [ChanAInputRange ChanBInputRange ChanCInputRange ChanDInputRange];
ConfigureVariables.DecimationValue = DecimationValue;
ConfigureVariables.TriggerRange = TriggerRange;
ConfigureVariables.TriggerLevel = TriggerLevel;


if CardType == 2 && ClockType == 1 && ConfigureVariables.SampleRate > 180000000 
   fprintf('\n!! Warning,  SampleRate for 9562 cards is to large !!\n\n'); 
end
if CardType == 2 && ClockType == 1 && ConfigureVariables.SampleRate < 150000000 
   fprintf('\n!! Warning,  SampleRate for 9562 cards is to small !!\n\n'); 
end


% Add path to AlazarTech mfiles
addpath('C:\DIRAC\Matlab Include')

% Call mfile with library definitions
AlazarDefs

for Chan = 1:4
    switch ConfigureVariables.ChanInputRange(Chan)
        case 0
            ConfigureVariables.ChanInputRange(Chan) = 6;
        case 1
            ConfigureVariables.ChanInputRange(Chan) = 7;
        case 2
            if CardType == 1
                ConfigureVariables.ChanInputRange(Chan) = 10;
            end
            if CardType == 2
                ConfigureVariables.ChanInputRange(Chan) = 9;
            end
        case 3
            ConfigureVariables.ChanInputRange(Chan) = 11;
        case 4
            ConfigureVariables.ChanInputRange(Chan) = 12;
    end
end

% Load driver library 
if ~alazarLoadLibrary()
    fprintf('Error: ATSApi.dll not loaded\n');
    return
end

% TODO: Select a board system
systemId = int32(1);

% Find the number of boards in the board system
boardCount = calllib('ATSApi', 'AlazarBoardsInSystemBySystemID', systemId);
if boardCount < 1
    fprintf('Error: No boards found in system Id %d\n', systemId);
    return
end
fprintf('System Id %u has %u boards\n', systemId, boardCount);

% Get a handle to each board in the board system
for boardId = 1:boardCount
    boardHandle = calllib('ATSApi', 'AlazarGetBoardBySystemID', systemId, boardId);
    setdatatype(boardHandle, 'voidPtr', 1, 1);
    if boardHandle.Value == 0
        fprintf('Error: Unable to open board system ID %u board ID %u\n', systemId, boardId);
        return
    end
    boardHandleArray(1, boardId) = { boardHandle };
end

% Configure the sample rate, input, and trigger settings of each board
for boardId = 1:boardCount
    boardHandle = boardHandleArray{ 1, boardId };
    if ~configureBoard(boardId, boardHandle, ConfigureVariables)
        fprintf('Error: Configure sytstemId %d board Id %d failed\n', systemId, boardId);
        return
    end
end