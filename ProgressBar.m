classdef ProgressBar < handle
%PROGRESSBAR <purpose in one line!>
% -------------------------------------------------------------------------
% <Detailed description of the function>
%
% ProgressBar Properties:
%	propA - <description>
%	propB - <description>
%
% ProgressBar Methods:
%	doThis - <description>
%	doThat - <description>
%
% Author :  J.-A. Adrian (JA) <jens-alrik.adrian AT jade-hs.de>
% Date   :  17-Jun-2016 16:08:45
%

% Version:  v0.1   initial version, 17-Jun-2016 16:08 (JA)
%


properties (Access = private)
    Bar = '';
    IterationCounter = 0;
    
    NumWrittenCharacters = 0;
    LastBlock = 0;
    LastMainBlock = 1;
    FractionMainBlock;
    FractionBlock;
    
    HasTotalIterations = false;
    HasUpdateRate = false;
    
    TimerTagName;
end


properties (SetAccess = private, GetAccess = public)
    Title;
    Total;
    Unit;
    UpdateRate;
end

properties ( Constant, Access = private )
    MinBarLength = 10;
    MaxColumnsOnScreen = 90;
    
    NumBlocks = 8; % HTML 'left blocks' go in eigths
    DefaultUpdateRate = inf; % every iteration gets printed
end



methods
    function [self] = ProgressBar(total, varargin)
        if nargin,
            % parse input arguments
            self.parseInputs(total, varargin{:});
        end
        
        % add a new timer object with unique tag
        self.TimerTagName = char(java.util.UUID.randomUUID);
        timer(...
            'Tag', self.TimerTagName, ...
            'ObjectVisibility', 'off' ...
            );

        % register the new tic object
        ticObj = tic;
        self.addToObjectList(ticObj);
        
        if self.HasTotalIterations,
            % initialize the progress bar and pre-compute some measures
            self.setupBar();
            self.computeBlockFractions();
        end
        
        if self.HasUpdateRate,
            self.startTimer();
        end
    end
    
    function delete(self)
        % when a progress bar has been plot, hit return
        if self.IterationCounter,
            fprintf('\n');
        end
        
        % remove the ticObject from list
        self.removeMeFromObjectList();
        
        % delete timer
        timerObject = self.getTimer();
        delete(timerObject);
    end
    
    
    
    
    function [] = update(self, n, wasSuccessful)
        if nargin < 3 || isempty(wasSuccessful),
            wasSuccessful = true;
        end
        if nargin < 2 || isempty(n),
            n = 1;
        end
        validateattributes(n, ...
            {'numeric'}, ...
            {'scalar', 'positive', 'real', 'nonnan', 'finite', 'nonempty'} ...
            );
        validateattributes(wasSuccessful, ...
            {'logical', 'numeric'}, ...
            {'scalar', 'binary', 'nonnan', 'nonempty'} ...
            );
        
        self.incrementIterationCounter(n);
        
        if ~self.HasUpdateRate,
            self.printProgressBar();
        end
        if self.IterationCounter == self.Total,
            self.stopTimer();
        end
    end
    
    
    
    
    function [] = printMessage(self)
        error('Not yet implemented');
    end
    
    
    
    
    function [] = summary(self)
        error('Not yet implemented');
        
        if self.IterationCounter < self.Total,
            return;
        end
    end
    
    
    
    
    function [] = close(self)
        delete(self);
    end
end





methods (Access = private)
    function [] = parseInputs(self, total, varargin)
        p = inputParser;
        p.FunctionName = mfilename;
        
        % total number of iterations
        p.addRequired('Total', @checkInputOfTotal);
        
        % unit of progress measure
        p.addParameter('Unit', 'Integers', ...
            @(in) any(validatestring(in, {'Integers', 'Bytes'})) ...
            );
        
        % bar title
        p.addParameter('Title', '', ...
            @(in) validateattributes(in, {'char'}, {'nonempty'}) ...
            );
        
        % update rate
        p.addParameter('UpdateRate', self.DefaultUpdateRate, ...
            @(in) validateattributes(in, ...
                {'numeric'}, ...
                {'scalar', 'positive', 'real', 'nonempty', 'nonnan', 'finite'} ...
                ) ...
            );
       
        % parse all arguments...
        p.parse(total, varargin{:});
        
        % ...and grab them
        self.Total = p.Results.Total;
        self.Unit  = p.Results.Unit;
        self.Title = p.Results.Title;
        self.UpdateRate = p.Results.UpdateRate;
        
        if ~isempty(self.Total),
            self.HasTotalIterations = true;
        end
        if ~isinf(self.UpdateRate),
            self.HasUpdateRate = true;
        end
    end
    
    
    
    
    function [] = computeBlockFractions(self)
        self.FractionMainBlock = 1 / length(self.Bar);
        self.FractionBlock = self.FractionMainBlock / self.NumBlocks;
    end
    
    
    
    
    function [format, preString, postString] = returnFormatString(self)
        % this is adapted from tqdm

        if self.HasTotalIterations,
            if ~isempty(self.Title),
                preString  = '%s:  %03.0f%%  ';
            else
                preString  = '%03.0f%%  ';
            end
            
            centerString = '|%s|';

            postString = ' %i/%i [%02.0f:%02.0f:%02.0f<%02.0f:%02.0f:%02.0f, %.2f it/s]';

            format = [preString, centerString, postString];
        else
            preString  = '';
            postString = '';
            
            if ~isempty(self.Title),
                format = '%s:  %iit [%02.0f:%02.0f:%02.0f, %.2f it/s]';
            else
                format = '%iit [%02.0f:%02.0f:%02.0f, %.2f it/s]';
            end
        end
    end

    
    
    
    function [argList] = returnArgumentList(self)
        % 1 : Title
        % 2 : progress percent
        % 3 : progBar string
        % 4 : interationCounter
        % 5 : Total
        % 6 : ET.hours
        % 7 : ET.minutes
        % 8 : ET.seconds
        % 9 : ETA.hours
        % 10: ETA.minutes
        % 11: ETA.seconds
        % 12: it/s

        
        % elapsed time (ET)
        ticObj = self.getTic();
        thisTimeSec = toc(ticObj);
        etHoursMinsSecs = convertTime(thisTimeSec);

        % iterations per second
        iterationsPerSecond = self.IterationCounter / thisTimeSec;
        
        if self.HasTotalIterations,
            % estimated time of arrival (ETA)
            [etaHoursMinsSecs] = self.estimateETA(thisTimeSec);
            
            argList = {
                self.Title
                round(self.IterationCounter / self.Total * 100)
                self.getCurrentBar
                self.IterationCounter
                self.Total
                etHoursMinsSecs(1)
                etHoursMinsSecs(2)
                etHoursMinsSecs(3)
                etaHoursMinsSecs(1)
                etaHoursMinsSecs(2)
                etaHoursMinsSecs(3)
                iterationsPerSecond
                };
        else
            argList = {
                self.Title
                self.IterationCounter
                etHoursMinsSecs(1)
                etHoursMinsSecs(2)
                etHoursMinsSecs(3)
                iterationsPerSecond
                };
        end

        if isempty(self.Title),
            argList = argList(2:end);
        end
    end

    
    
    
    function [] = setupBar(self)
        [~, preBarFormat, postBarFormat] = self.returnFormatString();

        % insert worst case inputs to get (almost) maximum length of bar
        preBar = sprintf(preBarFormat, self.Title, 100);
        postBar = sprintf(postBarFormat, ...
            self.Total, ...
            self.Total, ...
            100, 100, 100, 100, 100, 100, 1e3);
        
        lenBar = self.MaxColumnsOnScreen - length(preBar) - length(postBar);
        lenBar = max(lenBar, self.MinBarLength);
        
        self.Bar = blanks(lenBar);
    end

    
    
    
    function [] = printProgressBar(self)
        fprintf(1, backspace(self.NumWrittenCharacters));
        
        formatString = self.returnFormatString();
        argumentList = self.returnArgumentList();
        
        self.NumWrittenCharacters = fprintf(1, ...
            formatString, ...
            argumentList{:} ...
            );
    end
    
    
    
    
    function [barString] = getCurrentBar(self)
        lenBar = length(self.Bar);
        currProgress = self.IterationCounter / self.Total;
        
        thisMainBlock = min(ceil(currProgress / self.FractionMainBlock), lenBar);
        
        continuousBlockIndex = ceil(currProgress / self.FractionBlock);
        thisBlock = mod(continuousBlockIndex, self.NumBlocks) + 1;
        
        if thisBlock > self.LastBlock || thisMainBlock > self.LastMainBlock,
            % fix for non-full last blocks when steps are large
            self.Bar(1:max(thisMainBlock-1, 0)) = ...
                repmat(getBlock(inf), 1, thisMainBlock - 1);
            
            if self.IterationCounter == self.Total,
                self.Bar = repmat(getBlock(inf), 1, lenBar);
            else
                self.Bar(thisMainBlock) = getBlock(thisBlock);
            end
            
            self.LastBlock = thisBlock;
            self.LastMainBlock = thisMainBlock;
        end
        
        barString = self.Bar;
    end
    
    
    
    
    function [etaHoursMinsSecs] = estimateETA(self, elapsedTime)
        progress = self.IterationCounter / self.Total;
        
        remainingSeconds = elapsedTime * ((1 / progress) - 1);
        
        etaHoursMinsSecs = convertTime(remainingSeconds);
    end
    
    
    
    
    function [timerObject] = getTimer(self)
        timerObject = timerfindall('Tag', self.TimerTagName);
    end
    
    
    
    
    function [] = startTimer(self)
        timerObject = self.getTimer();
        
        timerObject.BusyMode = 'drop';
        timerObject.ExecutionMode = 'fixedSpacing';
        
        timerObject.TimerFcn = @(~, ~) self.printProgressBar();
        timerObject.StopFcn  = @(~, ~) self.printProgressBar();
        
        updatePeriod = round(1 / self.UpdateRate * 1000) / 1000;
        timerObject.Period     = updatePeriod;
        timerObject.StartDelay = updatePeriod;
        
        start(timerObject);
    end
    
    
    
    
    function [] = stopTimer(self)
        timerObject = self.getTimer();
        
        stop(timerObject);
    end
    
    
    
    
    function [] = incrementIterationCounter(self, n)
        self.IterationCounter = self.IterationCounter + n;
    end
    
    function [list] = getObjectList(self) %#ok<MANU>
        list = ProgressBar.objectList();
    end
    
    function [] = addToObjectList(self, newObj) %#ok<INUSL>
        ProgressBar.objectList(newObj, false);
    end
    
    function [] = removeMeFromObjectList(self) %#ok<MANU>
        ProgressBar.objectList(-1, false);
    end
    
    function [] = resetObjectList(self) %#ok<MANU>
        ProgressBar.objectList('Clears the object list', true);
    end
    
    function [tVal] = getTic(self)
        tVal = self.getObjectList();
        tVal = tVal{end};
    end
end

methods (Access = private, Static = true)
    function [list] = objectList(newObject, shouldClearList)
        % Behaviour of a static method inspired by:
        % http://stackoverflow.com/a/14571266
        persistent ProgObjects;
        
        if nargin,
            if nargin < 2 || isempty(shouldClearList),
                shouldClearList = false;
            end
            if shouldClearList,
                ProgObjects = {};
                return;
            end
            
            switch class(newObject),
                case {'timer', 'ProgressBar', 'uint64'},
                    ProgObjects = [ProgObjects; {newObject}];
                case 'double',
                    ProgObjects = ProgObjects(1:end-1);
                otherwise
                    error('Unsupported Option to objectList()');
            end
        end
        
        list = ProgObjects;
    end
end


end



function [thisBlock] = getBlock(idx)
% idx ranges from 1 to 9, since the HTML 'left blocks' range from 1 to 8
% excluding the 'space' but this function also returns the space as first
% block

blocks = [
    char(9615);
    char(9614);
    char(9613);
    char(9612);
    char(9611);
    char(9610);
    char(9609);
    char(9608);
    ];

thisBlock = blocks(min(idx, length(blocks)));
end

function [str] = backspace(numChars)
str = repmat(sprintf('\b'), 1, numChars);
end

function [hoursMinsSecs] = convertTime(secondsIn)
% fast implementation using mod() from
% http://stackoverflow.com/a/21233409

hoursMinsSecs = floor(mod(secondsIn, [0, 3600, 60]) ./ [3600, 60, 1]);
end

function [yesNo] = checkInputOfTotal(total)
isTotalEmpty = isempty(total);

if isTotalEmpty,
    yesNo = isTotalEmpty;
    return;
else
    validateattributes(total, ...
        {'numeric'}, ...
        {'scalar', 'integer', 'positive', 'real', 'nonnan', 'finite'} ...
        );
end

end




% End of file: ProgressBar.m