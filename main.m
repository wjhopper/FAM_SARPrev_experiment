function exit_stat = main(varargin)

exit_stat = 1; % assume that we exited badly if ever exit before this gets reassigned
% use the inputParser class to deal with arguments
ip = inputParser;
%#ok<*NVREPL> dont warn about addParamValue
addParamValue(ip,'email', 'will@fake.com', @validate_email);
addParamValue(ip,'sessions_completed', 0, @(x) x <= 4);% Assuming 4 is the maximum number of sessions
addParamValue(ip,'debugLevel',1, @isnumeric);
parse(ip,varargin{:}); 
input = ip.Results;
defaults = ip.UsingDefaults;

constants.exp_onset = GetSecs; % record the time the experiment began
KbName('UnifyKeyNames') % use a standard set of keyname/key positions
rng('shuffle'); % set up and seed the randon number generator, so lists get properly permuted

% Get full path to the directory the function lives in, and add it to the path
constants.root_dir = fileparts(mfilename('fullpath'));
path(path,constants.root_dir);
constants.lib_dir = fullfile(constants.root_dir, 'lib');
path(path, genpath(constants.lib_dir));

% Make the data directory if it doesn't exist (but it should!)
if ~exist(fullfile(constants.root_dir, 'data'), 'dir')
    mkdir(fullfile(constants.root_dir, 'data'));
end

% Define the location of some directories we might want to use
constants.stimDir=fullfile(constants.root_dir,'db');
constants.savePath=fullfile(constants.root_dir,'data');

%% Connect to the database

setdbprefs('DataReturnFormat', 'dataset'); % Retrieved data should be a dataset object
setdbprefs('ErrorHandling', 'report'); % Throw runtime errors when a db error occurs

try
    % instance must be a predefined datasource at the OS level
    db_conn = database.ODBCConnection('fam_sarp', 'will', ''); % Connect to the db
catch db_error
   database_error(db_error)
end
% When cleanupObj is destroyed, it will execute the close(db_conn) statement
% This ensures we don't leave open db connections lying around somehow
cleanupObj = onCleanup(@() close(db_conn)); 

%% -------- GUI input option ----------------------------------------------------
% list of input parameters while may be exposed to the gui
% any input parameters not listed here will ONLY be able to be set via the
% command line
expose = {'email'};
valid_input = false;
while ~valid_input
    if any(ismember(defaults, expose))
    % call gui for input
        guiInput = getSubjectInfo('email', struct('title', 'E-Mail', ...
                                                   'type', 'textinput', ...
                                                   'validationFcn', @validate_email));
        if isempty(guiInput)
            exit(exit_stat);
        else   
            input = filterStructs(guiInput,input);
        end
    end

    session = fetch(exec(db_conn, ...
                         sprintf('select sessions_completed from participants where email like ''%s''', ...
                                 input.email)));
    if strcmp(session.Data, 'No Data')

        rng('shuffle');
        rng_state = rng;
        try
            insert(db_conn, 'participants', ...
                   {'email', 'sessions_completed', 'rng_seed'}, ...
                   {input.email, 0, double(rng_state.Seed)});
        catch db_error
           database_error(db_error)
        end

    else
        input.sessions_completed = session.Data.sessions_completed;
    end

    valid_input = true;
end

[window, constants] = windowSetup(constants, input);

%% end of the experiment %%
windowCleanup(constants)
exit_stat=0;
end % end main()

function overwriteCheck = makeSubjectDataChecker(directory, extension, debugLevel) %#ok<DEFNU>
    % makeSubjectDataChecker function closer factory, used for the purpose
    % of enclosing the directory where data will be stored. This way, the
    % function handle it returns can be used as a validation function with getSubjectInfo to 
    % prevent accidentally overwritting any data. 
    function [valid, msg] = subjectDataChecker(value, ~)
        % the actual validation logic
        
        subnum = str2double(value);        
        if (~isnumeric(subnum) || isnan(subnum)) && ~isnumeric(value);
            valid = false;
            msg = 'Subject Number must be greater than 0';
            return
        end
        
        filePathGlobUpper = fullfile(directory, ['*Subject', value, '*', extension]);
        filePathGlobLower = fullfile(directory, ['*subject', value, '*', extension]);
        if ~isempty(dir(filePathGlobUpper)) || ~isempty(dir(filePathGlobLower)) && debugLevel <= 2
            valid= false;
            msg = strjoin({'Data file for Subject',  value, 'already exists!'}, ' ');                   
        else
            valid= true;
            msg = 'ok';
        end
    end

overwriteCheck = @subjectDataChecker;
end

function windowCleanup(constants)
    sca; % alias for screen('CloseAll')
    rmpath(constants.lib_dir,constants.root_dir);
end

function [window, constants] = windowSetup(constants, input)
    PsychDefaultSetup(2);
    constants.screenNumber = max(Screen('Screens')); % Choose a monitor to display on
    constants.res=Screen('Resolution',constants.screenNumber); % get screen resolution
    constants.dims = [constants.res.width constants.res.height];
    if any(input.debugLevel == [0 1])
    % Set the size of the PTB window based on screen size and debug level
        constants.screen_scale = [];
    else
        constants.screen_scale = reshape((constants.dims' * [(1/8),(7/8)]),1,[]);
    end

    try
        [window, constants.winRect] = Screen('OpenWindow', constants.screenNumber, (2/3)*WhiteIndex(constants.screenNumber) , round(constants.screen_scale));
    % define some landmark locations to be used throughout
        [constants.xCenter, constants.yCenter] = RectCenter(constants.winRect);
        constants.center = [constants.xCenter, constants.yCenter];
        constants.left_half=[constants.winRect(1),constants.winRect(2),constants.winRect(3)/2,constants.winRect(4)];
        constants.right_half=[constants.winRect(3)/2,constants.winRect(2),constants.winRect(3),constants.winRect(4)];
        constants.top_half=[constants.winRect(1),constants.winRect(2),constants.winRect(3),constants.winRect(4)/2];
        constants.bottom_half=[constants.winRect(1),constants.winRect(4)/2,constants.winRect(3),constants.winRect(4)];

    % Get some the inter-frame interval, refresh rate, and the size of our window
        constants.ifi = Screen('GetFlipInterval', window);
        constants.hertz = FrameRate(window); % hertz = 1 / ifi
        constants.nominalHertz = Screen('NominalFrameRate', window);
        [constants.width, constants.height] = Screen('DisplaySize', constants.screenNumber); %in mm

    % Font Configuration
        Screen('TextFont',window, 'Arial');  % Set font to Arial
        Screen('TextSize',window, 28);       % Set font size to 28
        Screen('TextStyle', window, 1);      % 1 = bold font
        Screen('TextColor', window, [0 0 0]); % Black text
    catch
        psychrethrow(psychlasterror);
        windowCleanup(constants)
    end
end

function [valid_email, msg] = validate_email(email_address, ~)
    valid_email = ~isempty(regexpi(email_address, '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'));
    if ~valid_email
        msg = 'Invalid E-Mail Address';
    else
        msg = '';
    end

end

function [] = database_error(error)
   errordlg({'Unable to connect to database. Specific error was:', ...
            '', ...
            error.message}, ...
            'Database Connection Error', ...
            'modal')
   rethrow(error)
end