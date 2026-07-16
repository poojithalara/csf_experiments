% Behavioural CSF task - 4 alternative forced choice (4IFC) - Quest+ algorithm
% Fixed total trials version with optional break screen between blocks.
% Results are saved incrementally after every trial so partial data is
% preserved if the task is interrupted.
%
% Key differences from CSF_4IFC_QuestPlus_20260506:
%   - Single session with a fixed total number of trials (not multiple runs)
%   - A break screen is shown every N trials; continues only on key press
%   - tmpData / CSV are written to disk after every trial (crash-safe)

%% INITIALISATION AND PATH DEFINITION ================================
clc; clear all; close all;
commandwindow;

format longG

time1 = clock;

RootDirectory = pwd;
[pathstr, ~, ~] = fileparts(which('CSF_4IFC_QuestPlus_FixedTrials_20260716'));
cd(pathstr)
addpath(genpath('resources_SC'));
addpath(genpath('Common_functions_SC'));
addpath(genpath('mQuestPlus'));

disp('%%%%%%%%% Welcome to Contrast Sensitivity Task: Quest+ algorithm %%%%%%%%%')

%% GENERAL EXPERIMENTAL PARAMETERS ================================
DateToday = datetime(floor(now),'ConvertFrom','datenum','Format','dd-MMM-yy');

prompt = {'SUBJECT ID (001)','DOB (DD-MMM-YYYY)','TESTING DATE (DD-MMM-YYYY)',...
    'PATIENT (0/1)?','CHILD (0/1)?','EYE TESTED (LE: 1/ RE: 2/ BINOCULAR: 3)', ...
    'PRACTICE (0/1)','VIEWING DISTANCE (cm)','PROJECTOR (0/1)?',...
    'EYETRACKER (0/1)','SET-UP (BOLD, DisplayPlusPlus, EPSON)','DEBUG MODE (0/1)?'};
definput = {'Test','01-Jan-2000',datestr(DateToday),...
    '0','0','3',...
    '0','51','0',...
    '0','DisplayPlusPlus','0'};

answer = inputdlg(prompt,'Experimental parameters',[1 85],definput);
Parameters.Subj_ID        = answer{1};
Parameters.Subj_DOB       = answer{2};
Parameters.Subj_ScanDate  = answer{3};
Parameters.Subj_Patient   = single(str2double(answer{4}));
Parameters.Subj_AgeGroup  = single(str2double(answer{5}));
EyeTestedLabels = {'LE','RE','BINOCULAR'};
Parameters.Subj_EyeTested = single(str2double(answer{6}));
Parameters.Practice       = single(str2double(answer{7}));
Parameters.ViewingDistance= single(str2double(answer{8}));
Parameters.Projector      = single(str2double(answer{9}));
Parameters.EyeTrack       = single(str2double(answer{10}));
Parameters.SetUp          = answer{11};
Parameters.DebuggingMode  = single(str2double(answer{12}));

if strcmp(Parameters.SetUp,'EPSON')
    rmpath(genpath('Common_functions_SC/optim'))
end

if Parameters.EyeTrack
    answer = input('WHICH EYE TO TRACK (1=LE, 2=RE)? ','s');
    Parameters.EyeToTrack = single(str2num(answer));
end

clear answer prompt definput DateToday

% Create participant's folder
FolderName = sprintf('../data/IndividualDiffs/%s',Parameters.Subj_ID);
if ~exist(FolderName,'dir')
    mkdir(FolderName);
end

%% SCREEN GAMMA CALIBRATION ================================
if contains(Parameters.SetUp,'DisplayPlusPlus')
    load(fullfile(pathstr,'John_CalDataDisplayPlusPlus.mat'),'inCorrected_Spline');
elseif contains(Parameters.SetUp,'BOLD')
    load(fullfile(pathstr,'Luminances_BOLDWhite_Calib_255Steps_20201207_211703.mat'),'inCorrected_Spline');
elseif contains(Parameters.SetUp,'EPSON')
    load(fullfile(pathstr,'Luminances_EPSON_EBL1100U_HalfCalib_512Steps_20210902_210946.mat'),'inCorrected_Spline');
end
gammaTable = inCorrected_Spline;
if size(gammaTable,2) ~= 3
    gammaTable = inCorrected_Spline*[1 1 1];
end
clear inCorrected_Spline;

%% GABOR PARAMETERS ================================
prompt = {'SPATIAL FREQ. TO TEST (cpd)','TOTAL NUMBER OF TRIALS', ...
    'BREAK EVERY N TRIALS (0 = no break)',...
    'SD GAUSSIAN HULL (deg - NaN = no Gaussian Hull)',...
    'TEMPORAL FREQ. (Hz)','PATCH SIZE (deg diameter)', ...
    'LOCATION SUBSET (all / meridians / meridians_obliques / center)',...
    'ESTIMATE SLOPE (0=fixed at 3.5 / 1=estimate free / 2=estimate with Gaussian prior)',...
    'PATCH EXCLUSION (strict = exclude all clipping circle / vertical = exclude only top-bottom clipping)'};
definput = {'3','100','10','NaN','2','6','all','0284897484949787489478447848974498789994484747794','vertical'};
answer = inputdlg(prompt,'Experimental parameters',[1 100],definput);

Gabor.SFcpd               = single(str2num(answer{1}));
Parameters.TotalTrials    = single(str2num(answer{2}));
Parameters.BreakEvery     = single(str2num(answer{3})); % 0 = never
Gabor.SpacialConstant_Deg = single(str2num(answer{4}));
Gabor.TF                  = single(str2num(answer{5}));
Gabor.PatchSize           = single(str2num(answer{6}));
Gabor.LocationSubset      = lower(strtrim(answer{7}));
Parameters.EstimateSlope  = single(str2double(answer{8}));
Gabor.PatchExclusion      = lower(strtrim(answer{9})); % 'strict' or 'vertical'
Gabor.AllowedOri          = [-45 0 45 90];

% RunNumber is always 1 for this script (single continuous session)
Gabor.RunNumber = 1;

clear answer prompt definput

%% SCREEN, SOUND DRIVER & KEYBOARD INITIALISATION =======================
SetUpDisplay
SetUpSound

[KeyBoardIdx, productNames] = GetKeyboardIndices();

if strcmp(Parameters.SetUp,'DisplayPlusPlus')
    ResponsePad = single(KeyBoardIdx(~contains(productNames,'Apple')));
elseif contains(productNames,'Apple Keyboard')
    ResponsePad = single(KeyBoardIdx(contains(productNames,'Apple Keyboard')));
else
    if length(KeyBoardIdx) >= 2
        disp('%%%%%%%%%%%%%%%% KEYBOARD OPTIONS: %%%%%%%%%%%%%%%%')
        disp(char(productNames))
        ExperimenterKeyboard = input('EXPERIMENTER KEYBOARD (c/p keyboard name)? ','s');
        TriggerKeyboard      = input('TRIGGER KEYBOARD (c/p keyboard name)? ','s');
        ResponseKeyboard     = input('RESPONSE KEYBOARD (c/p keyboard name)? ','s');
    else
        disp('%%%%%%%%%%%%%%%% KEYBOARD OPTIONS: %%%%%%%%%%%%%%%%')
        disp(char(productNames))
        ExperimenterKeyboard = input('EXPERIMENTER KEYBOARD (c/p keyboard name)? ','s');
        TriggerKeyboard  = ExperimenterKeyboard;
        ResponseKeyboard = ExperimenterKeyboard;
    end
    ExperimenterPad = single(KeyBoardIdx(strcmp(productNames,ExperimenterKeyboard)));
    TriggerPad      = single(KeyBoardIdx(strcmp(productNames,TriggerKeyboard)));
    ResponsePad     = single(KeyBoardIdx(strcmp(productNames,ResponseKeyboard)));
end

escapeKey = KbName('q');
% Use -1 to check all keyboards for the escape key (experimenter may press
% 'q' on a different device than the response pad).
EscapePad = -1;
if length(KeyBoardIdx) < 2
    AllowedKey = {'6^','7&','8*','9('};
else
    AllowedKey = {'7','8','9','4'};
end
minKey    = min(str2double(AllowedKey));
SubsResp  = minKey-1;
clear productNames

% Set random seed
rSeed = RandStream('mt19937ar','Seed','shuffle');
RandStream.setGlobalStream(rSeed);
clear rSeed

%% Create a list of tested Gabor centres
degdiff = round(6*Parameters.pixperdeg);

rangex = [-18:6:18]*Parameters.pixperdeg;
rangey = rangex;

ypos = [];
for i = 1:length(rangey)
    ypos = [ypos, repmat(rangey(i),1,length(rangex))];
end

Gabor.x_ycoords = [repmat([rangex],1,length(rangey));ypos];

[Gabor.Polar,Gabor.ECC] = cart2pol(Gabor.x_ycoords(1,:),Gabor.x_ycoords(2,:));

patchSizePx  = Gabor.PatchSize * Parameters.pixperdeg;
screenRadius = ScreenRect(4)/2;
if strcmp(Gabor.PatchExclusion, 'strict')
    % Exclude any patch whose centre is too close to the screen edge in any direction
    exclude = Gabor.ECC > screenRadius - patchSizePx/2;
else
    % 'vertical': exclude only patches whose top/bottom edge clips the circle
    % (side patches that clip left/right are kept)
    exclude = abs(Gabor.x_ycoords(2,:)) + patchSizePx/2 > screenRadius;
end
Gabor.x_ycoords(:, exclude) = [];
Gabor.Polar(exclude)         = [];
Gabor.ECC(exclude)           = [];
clear patchSizePx screenRadius exclude

innerEcc = round(6*Parameters.pixperdeg);
if strcmp(Gabor.LocationSubset,'meridians')
    onMeridian = (Gabor.x_ycoords(1,:) == 0) | (Gabor.x_ycoords(2,:) == 0);
    keep = onMeridian;
    Gabor.x_ycoords = Gabor.x_ycoords(:, keep);
    Gabor.Polar     = Gabor.Polar(keep);
    Gabor.ECC       = Gabor.ECC(keep);
elseif strcmp(Gabor.LocationSubset,'center')
    keep = (Gabor.x_ycoords(1,:) == 0) & (Gabor.x_ycoords(2,:) == 0);
    Gabor.x_ycoords = Gabor.x_ycoords(:, keep);
    Gabor.Polar     = Gabor.Polar(keep);
    Gabor.ECC       = Gabor.ECC(keep);
elseif strcmp(Gabor.LocationSubset, 'meridians_obliques')
    % Horizontal and vertical meridians
    onMeridian = (Gabor.x_ycoords(1,:) == 0) | ...
        (Gabor.x_ycoords(2,:) == 0);
    % Diagonal obliques: y = x and y = -x
    onOblique = ...
        (Gabor.x_ycoords(2,:) ==  Gabor.x_ycoords(1,:)) | ...
        (Gabor.x_ycoords(2,:) == -Gabor.x_ycoords(1,:));
    % Keep both meridians and obliques
    keep = onMeridian | onOblique;
    Gabor.x_ycoords = Gabor.x_ycoords(:, keep);
    Gabor.Polar     = Gabor.Polar(keep);
    Gabor.ECC       = Gabor.ECC(keep);
end

nLocs = size(Gabor.x_ycoords,2);
fprintf('\nNUMBER OF POINTS TESTED: %s\n',num2str(nLocs))

% Set up filename for saving
TIMESTAMP = strrep(strrep(datestr(now),' ','_'),':','');
if Parameters.Practice == 1
    SaveName = sprintf('%s/Practice_%s_%s_QuestPlus_%scpd_%s_FixedTrials', ...
        FolderName,Parameters.Subj_ID,EyeTestedLabels{Parameters.Subj_EyeTested}, ...
        num2str(Gabor.SFcpd),num2str(TIMESTAMP));
else
    SaveName = sprintf('%s/%s_%s_QuestPlus_%scpd_%s_FixedTrials', ...
        FolderName,Parameters.Subj_ID,EyeTestedLabels{Parameters.Subj_EyeTested}, ...
        num2str(Gabor.SFcpd),num2str(TIMESTAMP));
end

% Incremental save paths (written after every trial)
SaveNameTmp = sprintf('%s/%s_%s_tmp',FolderName,Parameters.Subj_ID,Parameters.Subj_ScanDate);
CSVSaveNameTmp = [SaveNameTmp '.csv'];
csvHeader = {'TrialNumber','X_coord','Y_coord','Contrast','Orientation','Response','isCorrect','EstimatedCS','isCatchTrial'};

%% GABOR PATCH INITIALISATION =============================================
Gabor_Initialisation
Stimulus = single(Stimulus);

%% SHUFFLE: SPATIAL FREQUENCY, ECCENTRICITY CENTRE, GAUSSIAN HULL ==========
Freq = Gabor.SFcpd;
[Freq,idxFreq]           = Shuffle(Freq);
[Gabor.SCShuffle,idxSCSize] = Shuffle(Gabor.sigmapx);

%% EYELINK PARAMETERS SET-UP & INITIALISATION =============================
if Parameters.EyeTrack

    elparam.expName      = '4AFC_CSF_QuestPlus_FixedTrials';
    elparam.TEST         = 0;
    elparam.viewEL       = 0;
    elparam.expStart     = 1;
    elparam.calibFlag    = 0;
    elparam.calibType    = 2;
    elparam.mkVideo      = 0;
    elparam.expTraining  = 0;
    elparam.feedbackTask = 0;
    elparam.EyeTest      = Parameters.EyeToTrack;

    if Parameters.Subj_Patient == 1
        elparam.CalTarRadVal   = Parameters.FixationSize_Deg;
        elparam.CalTarWidthVal = 0.375;
    else
        elparam.CalTarRadVal   = Parameters.FixationSize_Deg;
        elparam.CalTarWidthVal = 0.25;
    end

    elparam.timeCalibMin = 10;
    elparam.timeCalib    = elparam.timeCalibMin*60;
    elparam.timeFixSec   = 5;

    if Parameters.Subj_Patient == 1
        elparam.FixRadDeg = 5;
    else
        elparam.FixRadDeg = 2;
    end
    elparam.FixRadPix    = elparam.FixRadDeg*Parameters.pixperdeg;
    elparam.MaxInvTrials = 10;

    InitialiseEyeLink_2IFC;

else
    el = [];
    elparam = [];
end

%% EXPERIMENT =========================================================
close all
try
    %% EYE TRACKER CALIBRATION
    if Parameters.EyeTrack
        disp('.............. Calibration Time ..............')
        eyeLinkClearScreen(0);
        if ~elparam.TEST
            eyeLinkClearScreen(0);
            eyeLinkDrawText(ScreenRect(3)/2,ScreenRect(4)/2,el.txtCol,'1st Calibration instruction');
            calibresult = EyelinkDoTrackerSetup(el);
            if calibresult==el.TERMINATE_KEY
                return
            end
        end
        Eyelink('StartRecording');
    end

    pause(0.5);
    Screen('Flip', w);

    %% INITIALISE TIMING PARAMETERS
    timeStamp = [GetSecs 0];

    if Parameters.Practice == 1
        Gabor.stimDuration_secs = single(1);
        Parameters.ISILim       = single([0.5 1]);
    else
        Gabor.stimDuration_secs = single(0.5);
        Parameters.ISILim       = single([0.3 0.5]);
    end
    Gabor.stimDuration_Frame = single(Gabor.stimDuration_secs/ifi);

    Gabor.nFramesRamp = single(3);
    Gabor.stimDurationWithRamp_secs  = single(Gabor.stimDuration_secs);
    Gabor.stimDurationWithRamp_Frame = single(Gabor.stimDurationWithRamp_secs/ifi);
    Gabor.RampVector = getSquaredCosineWindow(Parameters.FrameRate_hz, Gabor.stimDurationWithRamp_secs+0.1, ifi*Gabor.nFramesRamp);

    Gabor.FlipReversalIndex = single([ones(1,Gabor.stimDurationWithRamp_Frame/2),repmat(2,1,Gabor.stimDurationWithRamp_Frame/2)]);
    Gabor.FlipReversalRate  = single(1/Gabor.TF/size(Stimulus,5));
    if Gabor.TF > 0
        Gabor.nFlips    = Gabor.nFramesRamp:Gabor.FlipReversalRate*Parameters.FrameRate_hz:(Gabor.nFramesRamp+Gabor.stimDuration_secs*Parameters.FrameRate_hz);
        Gabor.nFlips(1) = 1;
    end

    [gaborid,dstRect] = MakeGaborContrast(double(Stimulus),1,XYLoc_px_gabor,Parameters,w,ScreenRect,idxFreq,1,idxSCSize,1);

    clear i j

    %% QUEST+ INITIALISATION FOR EACH TESTED LOCATION
    gamma      = 0.25;
    lambda     = 0.05;
    beta       = 3.5;
    pThreshold = gamma^gamma;

    if Parameters.EstimateSlope == 0
        slopeGrid = beta;
    else
        slopeGrid = linspace(1.5, 4, 30);
    end

    slopePriorMu = 3.5;
    slopePriorSD = 1.0;

    contrastDomainLog  = linspace(-80, 0, 1000);
    thresholdGridFull  = linspace(-80, 0, 500);
    thresholdPriorSD   = 20;

    % Location-dependent prior: threshold (linear contrast) = intercept + slope * eccentricity_deg
    % 0.3 cpd: intercept=0.2101, slope=-0.0074
    % 3.0 cpd: intercept=0.0200, slope= 0.0021
    if Gabor.SFcpd <= 0.31
        priorEccIntercept = 0.2101;
        priorEccSlope     = -0.0074;
    else
        priorEccIntercept = 0.0200;
        priorEccSlope     =  0.0021;
    end

    fprintf('\n============= QUEST+ INITIALISATION =============\n')

    questHandles = struct();
    for iLoc = 1:nLocs
        eccDeg = Gabor.ECC(iLoc) / Parameters.pixperdeg;
        priorContrastLinear = priorEccIntercept + priorEccSlope * eccDeg;
        if priorContrastLinear <= 0
            warning('Location %d (ecc=%.1f deg, SF=%.1f cpd): linear prior formula gives contrast=%.4f <= 0. Clamping to 0.001. Check your intercept/slope values.', ...
                iLoc, eccDeg, Gabor.SFcpd, priorContrastLinear);
            priorContrastLinear = 0.001;
        end
        thresholdPriorMu = 20 * log10(priorContrastLinear);

        questHandles(iLoc).q = qpInitialize( ...
            'stimParamsDomainList', {contrastDomainLog}, ...
            'psiParamsDomainList',  {thresholdGridFull, slopeGrid, gamma, lambda}, ...
            'qpPF', @qpPFWeibull, ...
            'nOutcomes', 2);
        nPsi      = questHandles(iLoc).q.nPsiParamsDomain;
        gaussPrior = zeros(nPsi, 1);
        for iPsi = 1:nPsi
            tDb   = questHandles(iLoc).q.psiParamsDomain(iPsi, 1);
            sDb   = questHandles(iLoc).q.psiParamsDomain(iPsi, 2);
            pThresh = normpdf(tDb, thresholdPriorMu, thresholdPriorSD);
            if Parameters.EstimateSlope == 2
                pSlope = normpdf(sDb, slopePriorMu, slopePriorSD);
            else
                pSlope = 1;
            end
            gaussPrior(iPsi) = pThresh * pSlope;
        end
        questHandles(iLoc).q.posterior = qpUnitizeArray(gaussPrior);
        questHandles(iLoc).q.expectedNextEntropiesByStim = ...
            qpUpdateExpectedNextEntropiesByStim(questHandles(iLoc).q);

        fprintf('  Loc %d: ecc=%.1f deg, prior mu=%.2f dB (contrast=%.4f)\n', ...
            iLoc, eccDeg, thresholdPriorMu, priorContrastLinear)
    end

    if Parameters.EstimateSlope == 0
        fprintf('SF=%.1f cpd | prior intercept=%.4f, slope=%.4f (linear contrast) | SD=%.1f dB | slope fixed at %.1f\n\n', ...
            Gabor.SFcpd, priorEccIntercept, priorEccSlope, thresholdPriorSD, beta)
    elseif Parameters.EstimateSlope == 1
        fprintf('SF=%.1f cpd | prior intercept=%.4f, slope=%.4f (linear contrast) | SD=%.1f dB | slope estimated freely over [%.1f %.1f]\n\n', ...
            Gabor.SFcpd, priorEccIntercept, priorEccSlope, thresholdPriorSD, slopeGrid(1), slopeGrid(end))
    else
        fprintf('SF=%.1f cpd | prior intercept=%.4f, slope=%.4f (linear contrast) | SD=%.1f dB | slope estimated with Gaussian prior (mu=%.1f, SD=%.1f) over [%.1f %.1f]\n\n', ...
            Gabor.SFcpd, priorEccIntercept, priorEccSlope, thresholdPriorSD, slopePriorMu, slopePriorSD, slopeGrid(1), slopeGrid(end))
    end

    %% WELCOME SCREEN
    if length(KeyBoardIdx) < 2
        instructionImage = imread('resources_SC/Instructions_single_keyboard.png');
    else
        instructionImage = imread('resources_SC/Instructions.png');
    end
    clear KeyBoardIdx

    instructionTexture = Screen('MakeTexture', w, instructionImage);
    Screen('DrawTexture', w, instructionTexture, [], ScreenRect, 0);
    Screen('Flip', w);

    figure('Color','white','Position',[0 100 ScreenRect(3) ScreenRect(4)/2]);
    subplot(1,3,1); polarscatter(Gabor.Polar,Gabor.ECC,50,'filled'); set(gca,'LineWidth',2);
    for i = 2:3
        subplot(1,3,i); imagesc(squeeze(Stimulus(:,:,:,:,i-1))); axis square;
    end
    colormap gray;

    % Wait for a key press to continue
    pause(0.5);
    KbWait(); close all; clear Stimulus;

    %% Display all locations (tagged with X-Y coords) with an circle outline of 20deg radius
    Screen('TextSize', w, 16);

    for i = 1:size(Gabor.x_ycoords,2)
        % Compute screen centered coordinates
        xpos = double(ScreenRect(3)/2 + Gabor.x_ycoords(1,i));
        ypos = double(ScreenRect(4)/2 + Gabor.x_ycoords(2,i));
        % Draw the Gabor
        Screen('DrawTexture', w, gaborid(1), [], ...
            double(CenterRectOnPoint([0 0 Gabor.Size_px Gabor.Size_px], xpos, ypos)), ...
            0, [], 0.8, [], [], []);
        % Add overlay text with x-y coordinates
        coordText = sprintf('(%.0f, %.0f)', Gabor.x_ycoords(1,i), Gabor.x_ycoords(2,i));
        DrawFormattedText(w, coordText, xpos-25, ypos, [0 0 0]);
    end
    % Circle outline matches the eccentricity filter cutoff (ScreenRect(4)/2)
    circleRadPx = ScreenRect(4)/2;
    Screen('FrameOval', w, [0 0 0], ...
        double([ScreenRect(3)/2 - circleRadPx, ScreenRect(4)/2 - circleRadPx, ...
        ScreenRect(3)/2 + circleRadPx, ScreenRect(4)/2 + circleRadPx]),2);
    Screen('Flip', w);
    KbWait();
    clear xpos ypos coordText

    %% DECOUNT BEFORE STARTING
    Screen('TextSize', w, 64);  % set font size
    DecountStart = 5;
    while DecountStart >= 0
        text = sprintf('Starting in ...\n\n%s',num2str(DecountStart));
        DrawFormattedText(w, text, 'center', 'center', [0 0 0]);
        Screen('Flip', w);
        WaitSecs(1);
        DecountStart = DecountStart - 1;
    end
    clear DecountStart

    %% ACTUAL EXPERIMENT MODULE
    TrialCounter        = 0;
    CompletedTrials     = 0;
    ValidTrialCounter   = 0;
    userAborted         = false;
    NumInvalid          = 0;
    calibReq            = 0;

    % Build catch trial schedule: ~10% catch trials per location, spread evenly
    % within each run (= passes between breaks).
    % catchSchedule(iLoc, trial) == 1 means insert a catch trial for location
    % iLoc after the Quest+ trial on that pass.
    Parameters.CatchContrast = 0.5;
    catchSchedule = false(nLocs, Parameters.TotalTrials);

    % Determine run boundaries
    if Parameters.BreakEvery > 0
        runStarts = 1 : Parameters.BreakEvery : Parameters.TotalTrials;
        runEnds   = [runStarts(2:end)-1, Parameters.TotalTrials];
    else
        runStarts = 1;
        runEnds   = Parameters.TotalTrials;
    end
    nRuns = numel(runStarts);

    % Place at least 1 catch trial per location per run, evenly spaced within
    % the run but with a random offset per location so they don't all fall
    % on the same pass.
    for iRun = 1:nRuns
        runPasses     = runStarts(iRun):runEnds(iRun);
        nRunPasses    = numel(runPasses);
        nCatchThisRun = max(1, round(0.1 * nRunPasses));
        % Divide the run into nCatchThisRun equal bins; pick one pass per bin
        binEdges = round(linspace(0, nRunPasses, nCatchThisRun+1));
        for iLoc = 1:nLocs
            catchIdx = zeros(1, nCatchThisRun);
            for iBin = 1:nCatchThisRun
                binStart = binEdges(iBin) + 1;
                binEnd   = binEdges(iBin+1);
                catchIdx(iBin) = randi([binStart, binEnd]);
            end
            catchSchedule(iLoc, runPasses(catchIdx)) = true;
        end
    end

    nCatchPerLoc = sum(catchSchedule(1,:));
    nCatchTotal  = sum(catchSchedule(:));
    fprintf('Catch trials: %d per location per run x %d runs = %d total\n', ...
        round(nCatchTotal/nRuns/nLocs), nRuns, nCatchTotal)

    totalTrialsAllLocs = Parameters.TotalTrials * nLocs + nCatchTotal;
    tmpData      = single(NaN(totalTrialsAllLocs, 9)); % col 9 = isCatchTrial
    respDuration = single(NaN(1, totalTrialsAllLocs));
    ResponseFbk  = {'Incorrect','Correct'};

    % Queue of location indices for trials invalidated by fixation breaks.
    missedTrialQueue = zeros(0, 1);

    % Each location gets TotalTrials trials, interleaved in shuffled blocks
    for trial = 1:Parameters.TotalTrials
        locIdx = Shuffle(1:size(Gabor.x_ycoords,2));
        for i = locIdx
            TrialCounter = TrialCounter + 1;
            isCatchTrial = false;

        oriIdx          = randi(numel(Gabor.AllowedOri));
        targetOri       = Gabor.AllowedOri(oriIdx);
        correctResponse = oriIdx;

        stimValDb    = qpQuery(questHandles(i).q);
        targContrast = 10^(stimValDb(1)/20);
        targContrast = min(max(targContrast, 0.0001), 1);

        tmpData(TrialCounter,1:5) = [TrialCounter, Gabor.x_ycoords(1,i), Gabor.x_ycoords(2,i), targContrast, targetOri];
        tmpData(TrialCounter,9)   = 0; % Quest+ trial

        %% ISI presentation
        if Parameters.EyeTrack
            Eyelink('message', 'ISI_START');
        end
        % Draw fixation point
        Screen('FillOval', w, [0.4 0.4 0.4], Parameters.FixationPos);
        % Calculate ISI
        ISITime = Parameters.ISILim(1) + (Parameters.ISILim(2)-Parameters.ISILim(1)).*rand(1,1);
        % ISI timestamp
        timeStamp(end+1,1) = GetSecs;
        ISION = timeStamp(end,1);
        % Present ISI
        while ISION-timeStamp(end,1) < ISITime
            ISION = Screen('Flip', w,[],1);
            [kDown, ~, kCode] = KbCheck(EscapePad); % Check if use aborts trial
            if kDown && any(kCode(escapeKey)), userAborted = true; break, end
        end
        if userAborted, break, end
        if Parameters.EyeTrack
            Eyelink('message', 'ISI_END %d', TrialCounter-1);
            if Parameters.Practice
                Eyelink('message', 'PRACTICE_TRIAL %d', TrialCounter);
            else
                Eyelink('message', 'TRIAL_START %d', TrialCounter);
                Eyelink('message', 'VALID_TRIAL %d', ValidTrialCounter);
            end
        end

        %% Stimulus presentation
        validTrial = 1;
        fprintf('Trial: %s; Contrast: %s%% \n', num2str(TrialCounter), num2str(targContrast*100))

        % Gabor presentation ~ 500ms - Initialise
        CurrentFrame = 1; revs = 1; frm = 1;
        % Calculate when to flip
        FlipReversalTime  = 0:Gabor.FlipReversalRate:Gabor.stimDurationWithRamp_secs;
        FlipReversalIndex = repmat([1,2],1,length(FlipReversalTime));

        timeStamp(end+1,1) = GetSecs;
        GratingOn = timeStamp(end,1);
        while GratingOn-timeStamp(end,1) <= Gabor.stimDurationWithRamp_secs
            % Check the closest FlipReversalTime in order to get the FlipReversalIndex
            [~,closestIndex] = min(abs(FlipReversalTime-(GratingOn-timeStamp(end,1))));
            
            % Draw fixation point only if not presented at centre
            Screen('FillOval', w, [0.4 0 0], Parameters.FixationPos);
            % Draw the Gabor
            Screen('DrawTexture', w, gaborid(FlipReversalIndex(closestIndex)), [], ...
                double(CenterRectOnPoint([0 0 Gabor.Size_px Gabor.Size_px], ...
                ScreenRect(3)/2 + Gabor.x_ycoords(1,i), ...
                ScreenRect(4)/2 + Gabor.x_ycoords(2,i))), ...
                0+targetOri, [], abs(targContrast), [], [], []);
            GratingOn = Screen('Flip', w);

            [kDown, ~, kCode] = KbCheck(EscapePad); % Check if was aborted
            if kDown && any(kCode(escapeKey)), userAborted = true; break, end

            if Parameters.EyeTrack && validTrial
                if frm==1
                    Eyelink('message', 'STIMULUS_START');
                end
                [x,y] = CheckEyePos(w,elparam); %gives estimate of eye position
                [inside] = CheckFixRad(x,y,[ScreenRect(3)/2 ScreenRect(4)/2], elparam.FixRadPix);
                if ~inside && validTrial
                    Eyelink('message', 'FIXATION_BREAK');
                    validTrial = 0;
                    NumInvalid = NumInvalid+1;
                    missedTrialQueue(end+1) = i;
                    PsychPortAudio('FillBuffer', pahandle, double(EyeBeep));
                    PsychPortAudio('Start', pahandle);
                    PsychPortAudio('Stop', pahandle,1);
                    Screen('FillRect', w, [1,0,0], Parameters.FixationPos);
                    Screen('Flip',w);
                end
            elseif Parameters.EyeTrack && ~validTrial
                Screen('FillRect', w, [1,0,0], Parameters.FixationPos);
                Screen('Flip',w);
            end
            frm = frm+1;
        end
        if userAborted, break, end


        if validTrial==1
            if Parameters.EyeTrack
                Eyelink('message', 'TRIAL_END %d',TrialCounter);
            end
        else
            if Parameters.EyeTrack
                Eyelink('message', 'TRIAL_END_BROKEN %d',TrialCounter);
            end
        end
        
        % Re-calibrate if too many consecutive invalid trials
        if Parameters.EyeTrack && NumInvalid >= elparam.MaxInvTrials
            Eyelink('message', 'RECALIBRATION_START');
            eyeLinkClearScreen(0);
            calibresult = EyelinkDoTrackerSetup(el);
            if calibresult == el.TERMINATE_KEY
                userAborted = true;
            end
            % EyelinkDoTrackerSetup stops recording internally; restart it
            WaitSecs(0.05);
            Eyelink('StartRecording');
            WaitSecs(0.05);
            NumInvalid = 0;
            calibReq   = 0;
        end
        if userAborted, break, end

        % Display fixation point
        Screen('FillOval', w, [0.6 0.6 0.6], Parameters.FixationPos);
        Screen('Flip', w);

        %% RESPONSE & QUEST+ UPDATE
        if validTrial==1
            if Parameters.EyeTrack
                Eyelink('message', 'RESP_START');
            end
            % Get participant's response
            respTimeStart = GetSecs;
            timeStamp(end+1,1) = respTimeStart;
            keyIsDown = 0;
            while ~keyIsDown
                [keyIsDown, secs, keyCode] = KbCheck(double(ResponsePad));
                [~, ~, escCode] = KbCheck(EscapePad);
                if any(escCode(escapeKey)), userAborted = true; break, end
                reply = KbName(keyCode);
                if iscell(reply), reply = reply{1}; end
                if keyIsDown
                    if ismember(reply,AllowedKey)
                        switch reply
                            case AllowedKey{1}; response = 1;
                            case AllowedKey{2}; response = 2;
                            case AllowedKey{3}; response = 3;
                            case AllowedKey{4}; response = 4;
                        end
                        respTimeEnd = GetSecs;
                        break
                    else
                        keyIsDown = 0;
                    end
                end
            end
            if userAborted, break, end
            timeStamp(end+1,1) = respTimeEnd;
            respDuration(TrialCounter) = single(respTimeEnd - respTimeStart);
            
            % Participant's response in tmpData matrix
            tmpData(TrialCounter,6) = Gabor.AllowedOri(single(response));
            
            %% Check correctness and update QUEST (skip update for catch trials)
            isCorrect = (response == correctResponse);
            if ~isCatchTrial
                questHandles(i).q = qpUpdate(questHandles(i).q, 20*log10(targContrast), isCorrect+1);
                psiIdx = qpListMaxArg(questHandles(i).q.posterior);
                psiDb  = questHandles(i).q.psiParamsDomain(psiIdx, 1);
                tmpData(TrialCounter,8) = single(1 / (10^(psiDb/20)));
            end

            tmpData(TrialCounter,7) = single(isCorrect);

            CompletedTrials   = CompletedTrials + 1;
            ValidTrialCounter = ValidTrialCounter + 1;
            catchTag = ''; if isCatchTrial, catchTag = ' [CATCH]'; end
            fprintf('Target Contrast: %s%%, Target Ori: %sdeg, Response: %sdeg (%ss) - %s%s\n\n', ...
                num2str(targContrast*100), num2str(targetOri), ...
                num2str(tmpData(TrialCounter,6)), ...
                num2str(round(respDuration(TrialCounter)+0.5,3)), ResponseFbk{isCorrect+1}, catchTag);
        end

        end % inner location loop
        if userAborted, break, end

        %% Insert catch trials scheduled for this pass (shuffled order across locations)
        catchLocsThisPass = find(catchSchedule(:, trial))';
        catchLocsThisPass = Shuffle(catchLocsThisPass);
        for i = catchLocsThisPass
            TrialCounter = TrialCounter + 1;
            isCatchTrial = true;

            oriIdx          = randi(numel(Gabor.AllowedOri));
            targetOri       = Gabor.AllowedOri(oriIdx);
            correctResponse = oriIdx;
            targContrast    = Parameters.CatchContrast;

            tmpData(TrialCounter,1:5) = [TrialCounter, Gabor.x_ycoords(1,i), Gabor.x_ycoords(2,i), targContrast, targetOri];
            tmpData(TrialCounter,9)   = 1; % catch trial

            %% ISI
            if Parameters.EyeTrack, Eyelink('message', 'ISI_START'); end
            Screen('FillOval', w, [0.4 0.4 0.4], Parameters.FixationPos);
            ISITime = Parameters.ISILim(1) + (Parameters.ISILim(2)-Parameters.ISILim(1)).*rand(1,1);
            timeStamp(end+1,1) = GetSecs; ISION = timeStamp(end,1);
            while ISION-timeStamp(end,1) < ISITime
                ISION = Screen('Flip', w,[],1);
                [kDown, ~, kCode] = KbCheck(EscapePad);
                if kDown && any(kCode(escapeKey)), userAborted = true; break, end
            end
            if userAborted, break, end

            %% Stimulus presentation
            validTrial = 1;
            fprintf('Trial: %s; Contrast: %s%% [CATCH]\n', num2str(TrialCounter), num2str(targContrast*100))
            CurrentFrame = 1; revs = 1; frm = 1;
            FlipReversalTime  = 0:Gabor.FlipReversalRate:Gabor.stimDurationWithRamp_secs;
            FlipReversalIndex = repmat([1,2],1,length(FlipReversalTime));

            timeStamp(end+1,1) = GetSecs; GratingOn = timeStamp(end,1);
            while GratingOn-timeStamp(end,1) <= Gabor.stimDurationWithRamp_secs
                [~,closestIndex] = min(abs(FlipReversalTime-(GratingOn-timeStamp(end,1))));
                Screen('FillOval', w, [0.4 0 0], Parameters.FixationPos);
                Screen('DrawTexture', w, gaborid(FlipReversalIndex(closestIndex)), [], ...
                    double(CenterRectOnPoint([0 0 Gabor.Size_px Gabor.Size_px], ...
                    ScreenRect(3)/2 + Gabor.x_ycoords(1,i), ...
                    ScreenRect(4)/2 + Gabor.x_ycoords(2,i))), ...
                    0+targetOri, [], abs(targContrast), [], [], []);
                GratingOn = Screen('Flip', w);
                [kDown, ~, kCode] = KbCheck(EscapePad);
                if kDown && any(kCode(escapeKey)), userAborted = true; break, end
                frm = frm+1;
            end
            if userAborted, break, end

            Screen('FillOval', w, [0.6 0.6 0.6], Parameters.FixationPos);
            Screen('Flip', w);

            %% Response (no Quest+ update)
            respTimeStart = GetSecs;
            timeStamp(end+1,1) = respTimeStart;
            keyIsDown = 0;
            while ~keyIsDown
                [keyIsDown, secs, keyCode] = KbCheck(double(ResponsePad));
                [~, ~, escCode] = KbCheck(EscapePad);
                if any(escCode(escapeKey)), userAborted = true; break, end
                reply = KbName(keyCode);
                if iscell(reply), reply = reply{1}; end
                if keyIsDown
                    if ismember(reply,AllowedKey)
                        switch reply
                            case AllowedKey{1}; response = 1;
                            case AllowedKey{2}; response = 2;
                            case AllowedKey{3}; response = 3;
                            case AllowedKey{4}; response = 4;
                        end
                        respTimeEnd = GetSecs;
                        break
                    else
                        keyIsDown = 0;
                    end
                end
            end
            if userAborted, break, end
            timeStamp(end+1,1) = respTimeEnd;
            respDuration(TrialCounter) = single(respTimeEnd - respTimeStart);

            tmpData(TrialCounter,6) = Gabor.AllowedOri(single(response));
            isCorrect = (response == correctResponse);
            tmpData(TrialCounter,7) = single(isCorrect);
            % col 8 (estimated CS) left as NaN for catch trials

            CompletedTrials   = CompletedTrials + 1;
            ValidTrialCounter = ValidTrialCounter + 1;
            fprintf('Target Contrast: %s%%, Target Ori: %sdeg, Response: %sdeg (%ss) - %s [CATCH]\n\n', ...
                num2str(targContrast*100), num2str(targetOri), ...
                num2str(tmpData(TrialCounter,6)), ...
                num2str(round(respDuration(TrialCounter)+0.5,3)), ResponseFbk{isCorrect+1});
        end
        if userAborted, break, end

        %% Break screen after every BreakEvery passes through all locations
        if Parameters.BreakEvery > 0 && mod(trial, Parameters.BreakEvery) == 0 && trial < Parameters.TotalTrials
            Screen('TextSize', w, 48);
            breakTextWait = sprintf('Break!\n\n%d trials per location completed.', ...
                trial);
            DrawFormattedText(w, breakTextWait, 'center', 'center', [0 0 0]);
            Screen('Flip', w);
            breakStamp = strrep(strrep(datestr(now),' ','_'),':','');
            SaveNameBreak    = sprintf('%s/%s_%s_break%02d_%s', FolderName, Parameters.Subj_ID, Parameters.Subj_ScanDate, trial, breakStamp);
            CSVSaveNameBreak = [SaveNameBreak '.csv'];
            validRows = ~isnan(tmpData(:,1));
            csvData   = [csvHeader; num2cell(double(tmpData(validRows,:)))];
            writecell(csvData, CSVSaveNameBreak);
            save(SaveNameBreak, 'Parameters','Gabor','tmpData','timeStamp','respDuration', ...
                'questHandles','SaveName','SaveNameTmp', '-v7.3');
            pause(1);
            breakTextReady = sprintf('Break!\n\n%d trials completed.\n\nPress any key to continue.', ...
                trial);
            DrawFormattedText(w, breakTextReady, 'center', 'center', [0 0 0]);
            Screen('Flip', w);
            KbWait();
            Screen('TextSize', w, 64);
            for c = 3:-1:1
                DrawFormattedText(w, num2str(c), 'center', 'center', [0 0 0]);
                Screen('Flip', w);
                WaitSecs(1);
            end
        end
    end % outer repetition loop

    %% RESCHEDULED TRIALS (fixation-break replay)
    % Trials invalidated by fixation breaks are replayed here in shuffled
    % order. If a replay trial is also broken, it is re-queued; this
    % continues until the queue is empty.
    while ~isempty(missedTrialQueue) && ~userAborted
        % Shuffle the current queue so retries are interleaved
        missedTrialQueue = Shuffle(missedTrialQueue);

        nextQueue = zeros(0, 1); % accumulate re-broken trials
        for qIdx = 1:numel(missedTrialQueue)
            if userAborted, break, end
            i            = missedTrialQueue(qIdx);
            isCatchTrial = false;

            oriIdx          = randi(numel(Gabor.AllowedOri));
            targetOri       = Gabor.AllowedOri(oriIdx);
            correctResponse = oriIdx;

            % Query Quest+ fresh — uses all data collected so far
            stimValDb    = qpQuery(questHandles(i).q);
            targContrast = 10^(stimValDb(1)/20);
            targContrast = min(max(targContrast, 0.0001), 1);

            TrialCounter = TrialCounter + 1;
            % Grow tmpData if needed
            if TrialCounter > size(tmpData, 1)
                tmpData      = [tmpData;      single(NaN(100, 9))];
                respDuration = [respDuration, single(NaN(1, 100))];
            end
            tmpData(TrialCounter, 1:5) = [TrialCounter, Gabor.x_ycoords(1,i), Gabor.x_ycoords(2,i), targContrast, targetOri];
            tmpData(TrialCounter, 9)   = 0;

            fprintf('RESCHEDULED Trial: %s; Contrast: %s%%\n', num2str(TrialCounter), num2str(targContrast*100))

            %% ISI
            if Parameters.EyeTrack, Eyelink('message', 'ISI_START'); end
            Screen('FillOval', w, [0.4 0.4 0.4], Parameters.FixationPos);
            ISITime = Parameters.ISILim(1) + (Parameters.ISILim(2)-Parameters.ISILim(1)).*rand(1,1);
            timeStamp(end+1,1) = GetSecs; ISION = timeStamp(end,1);
            while ISION-timeStamp(end,1) < ISITime
                ISION = Screen('Flip', w,[],1);
                [kDown, ~, kCode] = KbCheck(EscapePad);
                if kDown && any(kCode(escapeKey)), userAborted = true; break, end
            end
            if userAborted, break, end
            if Parameters.EyeTrack
                Eyelink('message', 'ISI_END %d', TrialCounter-1);
                Eyelink('message', 'TRIAL_START %d', TrialCounter);
            end

            %% Stimulus
            validTrial = 1;
            frm = 1;
            FlipReversalTime  = 0:Gabor.FlipReversalRate:Gabor.stimDurationWithRamp_secs;
            FlipReversalIndex = repmat([1,2],1,length(FlipReversalTime));
            timeStamp(end+1,1) = GetSecs; GratingOn = timeStamp(end,1);
            while GratingOn-timeStamp(end,1) <= Gabor.stimDurationWithRamp_secs
                [~,closestIndex] = min(abs(FlipReversalTime-(GratingOn-timeStamp(end,1))));
                Screen('FillOval', w, [0.4 0 0], Parameters.FixationPos);
                Screen('DrawTexture', w, gaborid(FlipReversalIndex(closestIndex)), [], ...
                    double(CenterRectOnPoint([0 0 Gabor.Size_px Gabor.Size_px], ...
                    ScreenRect(3)/2 + Gabor.x_ycoords(1,i), ...
                    ScreenRect(4)/2 + Gabor.x_ycoords(2,i))), ...
                    0+targetOri, [], abs(targContrast), [], [], []);
                GratingOn = Screen('Flip', w);
                [kDown, ~, kCode] = KbCheck(EscapePad);
                if kDown && any(kCode(escapeKey)), userAborted = true; break, end

                if Parameters.EyeTrack && validTrial
                    if frm==1, Eyelink('message', 'STIMULUS_START'); end
                    [x,y] = CheckEyePos(w,elparam);
                    [inside] = CheckFixRad(x,y,[ScreenRect(3)/2 ScreenRect(4)/2], elparam.FixRadPix);
                    if ~inside
                        Eyelink('message', 'FIXATION_BREAK');
                        validTrial = 0;
                        NumInvalid = NumInvalid+1;
                        nextQueue(end+1) = i;
                        PsychPortAudio('FillBuffer', pahandle, double(EyeBeep));
                        PsychPortAudio('Start', pahandle);
                        PsychPortAudio('Stop', pahandle,1);
                        Screen('FillRect', w, [1,0,0], Parameters.FixationPos);
                        Screen('Flip',w);
                    end
                elseif Parameters.EyeTrack && ~validTrial
                    Screen('FillRect', w, [1,0,0], Parameters.FixationPos);
                    Screen('Flip',w);
                end
                frm = frm+1;
            end
            if userAborted, break, end

            if Parameters.EyeTrack
                if validTrial
                    Eyelink('message', 'TRIAL_END %d', TrialCounter);
                else
                    Eyelink('message', 'TRIAL_END_BROKEN %d', TrialCounter);
                end
            end

            Screen('FillOval', w, [0.6 0.6 0.6], Parameters.FixationPos);
            Screen('Flip', w);

            %% Response & Quest+ update
            if validTrial
                if Parameters.EyeTrack, Eyelink('message', 'RESP_START'); end
                respTimeStart = GetSecs;
                timeStamp(end+1,1) = respTimeStart;
                keyIsDown = 0;
                while ~keyIsDown
                    [keyIsDown, secs, keyCode] = KbCheck(double(ResponsePad));
                    [~, ~, escCode] = KbCheck(EscapePad);
                    if any(escCode(escapeKey)), userAborted = true; break, end
                    reply = KbName(keyCode);
                    if iscell(reply), reply = reply{1}; end
                    if keyIsDown
                        if ismember(reply, AllowedKey)
                            switch reply
                                case AllowedKey{1}; response = 1;
                                case AllowedKey{2}; response = 2;
                                case AllowedKey{3}; response = 3;
                                case AllowedKey{4}; response = 4;
                            end
                            respTimeEnd = GetSecs;
                            break
                        else
                            keyIsDown = 0;
                        end
                    end
                end
                if userAborted, break, end
                timeStamp(end+1,1) = respTimeEnd;
                respDuration(TrialCounter) = single(respTimeEnd - respTimeStart);

                tmpData(TrialCounter,6) = Gabor.AllowedOri(single(response));
                isCorrect = (response == correctResponse);
                questHandles(i).q = qpUpdate(questHandles(i).q, 20*log10(targContrast), isCorrect+1);
                psiIdx = qpListMaxArg(questHandles(i).q.posterior);
                psiDb  = questHandles(i).q.psiParamsDomain(psiIdx, 1);
                tmpData(TrialCounter,7) = single(isCorrect);
                tmpData(TrialCounter,8) = single(1 / (10^(psiDb/20)));

                CompletedTrials   = CompletedTrials + 1;
                ValidTrialCounter = ValidTrialCounter + 1;
                fprintf('Target Contrast: %s%%, Target Ori: %sdeg, Response: %sdeg (%ss) - %s [RESCHEDULED]\n\n', ...
                    num2str(targContrast*100), num2str(targetOri), ...
                    num2str(tmpData(TrialCounter,6)), ...
                    num2str(round(respDuration(TrialCounter)+0.5,3)), ResponseFbk{isCorrect+1});
            end

            % Re-calibrate if too many invalid trials (same check as main loop)
            if Parameters.EyeTrack && NumInvalid >= elparam.MaxInvTrials
                Eyelink('message', 'RECALIBRATION_START');
                eyeLinkClearScreen(0);
                calibresult = EyelinkDoTrackerSetup(el);
                if calibresult == el.TERMINATE_KEY
                    userAborted = true;
                end
                WaitSecs(0.05);
                Eyelink('StartRecording');
                WaitSecs(0.05);
                NumInvalid = 0;
                calibReq   = 0;
            end
            if userAborted, break, end
        end
        missedTrialQueue = nextQueue;
    end

    %% END SCREEN
    Screen('TextSize', w, 64);
    if userAborted
        text = sprintf('Task stopped.\n\n%d trials completed.', round(CompletedTrials/nLocs));
    else
        text = sprintf('Thank you ... Task complete!\n\n%d trials done.', CompletedTrials);
    end
    DrawFormattedText(w, text, 'center', 'center', [0 0 0]);
    Screen('Flip', w);
    WaitSecs(5);

    %% FOR EACH LOCATION: ESTIMATE THRESHOLD, EXTRACT QUEST+ DATA & PLOT ===
    thresholds = zeros(1,size(Gabor.x_ycoords,2)); % To store estimated contrast thresholds
    slopes = zeros(1,size(Gabor.x_ycoords,2)); % To store estimated contrast thresholds
    ResponseProp = zeros(1,size(Gabor.x_ycoords,2)); % To store proportions of correct responses
    contrasts = linspace(0,1,1000); % Range of contrast levels
    proportions = zeros(size(Gabor.x_ycoords,2),100); % To store predicted proportions for each location
    
    for iLoc = 1:size(Gabor.x_ycoords,2)
        trialOutcomes    = questHandles(iLoc).q.trialData;
        nTrialsTotal     = length(trialOutcomes);
        ResponseProp(iLoc) = sum([trialOutcomes.outcome] == 2) / nTrialsTotal * 100;

        psiParamsIndex   = qpListMaxArg(questHandles(iLoc).q.posterior);
        psiParamsQuest   = questHandles(iLoc).q.psiParamsDomain(psiParamsIndex,:);
        thresholds(iLoc) = 10^(psiParamsQuest(1)/20);
        slopes(iLoc)     = psiParamsQuest(2);

        for c = 1:length(contrasts)
            proportions(iLoc,c) = lambda*gamma + (1-lambda)*(1-(1-gamma)*exp(-10.^(slopes(iLoc)*(log10(contrasts(c))-log10(thresholds(iLoc))))));
        end
    end

    clc;
    for iLoc = 1:nLocs
        if Parameters.EstimateSlope
            fprintf('Location %d: MAP threshold = %.4f (CS = %.1f), MAP slope = %.2f, %% correct = %.1f%%\n', ...
                iLoc, thresholds(iLoc), 1/thresholds(iLoc), slopes(iLoc), ResponseProp(iLoc));
        else
            fprintf('Location %d: MAP threshold = %.4f (CS = %.1f), slope fixed at %.1f, %% correct = %.1f%%\n', ...
                iLoc, thresholds(iLoc), 1/thresholds(iLoc), slopes(iLoc), ResponseProp(iLoc));
        end
    end

    %% PLOT DATA ============================================================
    close all;
    figure('Color','white','Position',[0 0 ScreenRect(3) ScreenRect(4)/2]); hold on;

    eccRange = max(Gabor.ECC) - min(Gabor.ECC);
    if eccRange == 0
        distNorm = zeros(size(Gabor.ECC));
    else
        distNorm = (Gabor.ECC - min(Gabor.ECC)) ./ eccRange;
    end
    cmap   = turbo(256);
    colors = cmap( round(distNorm * 255) + 1 , : );

    for iLoc = 1:nLocs
        subplot(2,3,1); hold on;
        scatter(Gabor.x_ycoords(1,iLoc),Gabor.x_ycoords(2,iLoc),200,...
            'filled','MarkerFaceColor',colors(iLoc,:),'MarkerEdgeColor','k');
        title('Tested Locations');
        axis([-ScreenRect(3)/2 ScreenRect(3)/2 -ScreenRect(4)/2 ScreenRect(4)/2]);
        set(gca,'FontSize',20,'LineWidth',2,'YDir','reverse')

        subplot(2,3,2); hold on;
        semilogx(contrasts, proportions(iLoc,:), 'Color',colors(iLoc,:), 'LineWidth',2);
        semilogx(contrasts, ones(1,length(contrasts))*pThreshold,'k--','LineWidth',1);
        xlabel('Contrast'); ylabel({'Proportion','Correct'}); grid on; axis square;
        title({'Psychometric Functions','by Location'});
        axis([1e-4 1 0 1])
        set(gca,'FontSize',20,'LineWidth',2)
    end

    subplot(2,3,3); hold on;
    scatter(Gabor.x_ycoords(1,:), Gabor.x_ycoords(2,:), 200, ResponseProp, ...
        'filled','MarkerEdgeColor','k');
    colormap(parula); colorbar; caxis([0 100]); ylabel(colorbar,'% Correct Response');
    title('% Correct Responses');
    axis([-ScreenRect(3)/2 ScreenRect(3)/2 -ScreenRect(4)/2 ScreenRect(4)/2]);
    set(gca,'FontSize',20,'LineWidth',2,'YDir','reverse')

    ciWidth_dB = zeros(1,nLocs);
    for iLoc = 1:nLocs
        p     = questHandles(iLoc).q.posterior;
        tGrid = questHandles(iLoc).q.psiParamsDomain(:,1);
        if Parameters.EstimateSlope
            nT    = numel(thresholdGridFull);
            nS    = numel(slopeGrid);
            pMat  = reshape(p, nT, nS);
            pMarg = sum(pMat, 2);
        else
            pMarg = p;
        end
        pNorm = pMarg / sum(pMarg);
        cdf   = cumsum(pNorm);
        lo    = tGrid(find(cdf >= 0.025, 1, 'first'));
        hi    = tGrid(find(cdf >= 0.975, 1, 'first'));
        ciWidth_dB(iLoc) = hi - lo;
    end
    subplot(2,3,4); hold on;
    scatter(Gabor.x_ycoords(1,:), Gabor.x_ycoords(2,:), 200, ciWidth_dB, ...
        'filled', 'MarkerEdgeColor','k');
    colormap(parula); colorbar; ylabel(colorbar,'95% CI width (dB)');
    title('Threshold uncertainty (95% CI)');
    axis([-ScreenRect(3)/2 ScreenRect(3)/2 -ScreenRect(4)/2 ScreenRect(4)/2]);
    set(gca,'FontSize',20,'LineWidth',2,'YDir','reverse')

    csValues = 1./thresholds;
    subplot(2,3,5); hold on;
    scatter(Gabor.x_ycoords(1,:), Gabor.x_ycoords(2,:), 200, csValues, ...
        'filled', 'MarkerEdgeColor','k');
    csLims = [floor(min(csValues)), ceil(max(csValues))];
    if csLims(1) == csLims(2), csLims = csLims + [-1 1]; end
    colormap(parula); colorbar; caxis(csLims);
    ylabel(colorbar,'CS = 1/Threshold');
    title('Contrast Sensitivity (MAP)');
    axis([-ScreenRect(3)/2 ScreenRect(3)/2 -ScreenRect(4)/2 ScreenRect(4)/2]);
    set(gca,'FontSize',20,'LineWidth',2,'YDir','reverse')

    %% CLEAN UP AND FINAL DATA SAVING =======================================
    WaitSecs(5);

    disp('Writing RawData');
    RawData = struct('SF',[],'SC',[],'Run',[],'RespDuration',[]);
    RawData.SF           = Freq;
    RawData.SC           = Gabor.SpacialConstant_Deg(idxSCSize);
    RawData.Run          = tmpData;
    RawData.RespDuration = respDuration;

    for i = 1:length(timeStamp)
        if i > 1
            timeStamp(i,2) = timeStamp(i)-timeStamp(i-1);
        end
    end

    Priority(0);

catch ME
    Priority(0);
    Screen('CloseAll');
    Screen('LoadNormalizedGammaTable', Parameters.scrnNum, oldtable);
    PsychPortAudio('Close', pahandle);
    save(SaveNameTmp, 'Parameters','Gabor','tmpData','timeStamp','respDuration', ...
        'questHandles','SaveName','SaveNameTmp');
    rethrow(ME)
end

%% Save data & close screen ==============================================
% Close screen
sca

time2 = clock;
Parameters.TimeTakenMins = etime(time2,time1)/60;
fprintf('Time spent: %s minutes\n',num2str(Parameters.TimeTakenMins,'%0.2f'))
% Restore original gamma & close PsychPortAudio
Screen('LoadNormalizedGammaTable', Parameters.scrnNum, oldtable);
PsychPortAudio('Close', pahandle);

fprintf('\n')

disp('Saving final mat file...')
save(SaveNameTmp, '-v7.3');
% save(SaveNameTmp, 'Parameters','Gabor','RawData','tmpData','timeStamp','respDuration', ...
%     'questHandles','thresholds','slopes','ResponseProp','SaveName','SaveNameTmp', '-v7.3');

disp('Renaming workspace ...')
movefile([SaveNameTmp '.mat'],[SaveName '.mat']);

disp('Saving final CSV ...')
CSVSaveName = [SaveName '.csv'];
validRows   = ~isnan(tmpData(:,1));
csvData     = [csvHeader; num2cell(double(tmpData(validRows,:)))];
writecell(csvData, CSVSaveName);

% Remove incremental tmp CSV now that we have the final file
if exist(CSVSaveNameTmp,'file')
    delete(CSVSaveNameTmp);
end

% Move all break tmp files into a folder inside the participant's data
% folder
d = dir(sprintf('%s/%s_*break*.*', FolderName,Parameters.Subj_ID));
if ~exist(sprintf('%s/breakdata', FolderName),'dir')
    mkdir(sprintf('%s/breakdata', FolderName))
end
for i = 1:size(d,1)
    movefile([d(i).folder filesep d(i).name],sprintf('%s/breakdata', FolderName));
end


% Save EyeLink data, shut down EyeLink connection, and close the display
Priority(0);   % Reset process priority to normal

% EyeLink shutdown and EDF file transfer
if Parameters.EyeTrack
    disp('Shutting down the EyeTracker...')
    
    %Transfer EDF file from the EyeLink host to local storage
    statRecFile = Eyelink('ReceiveFile', ...
        sprintf('%s', elparam.edffilename), ...
        sprintf('%s.edf', SaveName));
    
    % Confirm whether the transfer was successful
    if statRecFile >= 0
        fprintf(1, '\n\tEyelink EDF file successfully transferred');
    else
        fprintf(1, '\n\tERROR: Eyelink EDF file transfer failed');
    end
    
    % Close EDF file and shut down EyeLink connection
    Eyelink('CloseFile');
    Eyelink('ShutDown');
end

disp('Done')
