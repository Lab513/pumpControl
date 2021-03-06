function varargout = pumpControl(varargin)
% PUMPCONTROL MATLAB code for pumpControl.fig
%      PUMPCONTROL, by itself, creates a new PUMPCONTROL or raises the existing
%      singleton*.
%
%      H = PUMPCONTROL returns the handle to a new PUMPCONTROL or the handle to
%      the existing singleton*.
%
%      PUMPCONTROL('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in PUMPCONTROL.M with the given input arguments.
%
%      PUMPCONTROL('Property','Value',...) creates a new PUMPCONTROL or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before pumpControl_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to pumpControl_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help pumpControl

% Last Modified by GUIDE v2.5 23-Oct-2015 12:01:08

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @pumpControl_OpeningFcn, ...
                   'gui_OutputFcn',  @pumpControl_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


function pumpControl_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to pumpControl (see VARARGIN)

% Choose default command line output for pumpControl
handles.output = hObject;

global pumpguihs
COMPORT = 'COM1';

pumpguihs.serial = serial(COMPORT);
fopen(pumpguihs.serial)
set(pumpguihs.serial,'Terminator',13)

% Handshake:
fprintf(pumpguihs.serial,sprintf('1#\n')); 
ret = fscanf(pumpguihs.serial);
if pumpguihs.serial.BytesAvailable
    dump = char(fread(pumpguihs.serial,pumpguihs.serial.BytesAvailable)'); % Just to get rid ofthe last byte
end
while ~strfind('REGLO DIGITAL',ret)
    fclose(pumpguihs.serial);
    
    cpcell = inputdlg({sprintf('The pump can not be found on the serial port, please specify a new port:\nP.S: Maybe you forgot to turn the pump on?')},'Handshake error',1,{COMPORT});
    COMPORT = cpcell{1};
    
    pumpguihs.serial = serial(COMPORT);
    fopen(pumpguihs.serial)
    set(pumpguihs.serial,'Terminator',13)
    fprintf(pumpguihs.serial,sprintf('1#\n')); 
    ret = fscanf(pumpguihs.serial);
    if pumpguihs.serial.BytesAvailable
        dump = char(fread(pumpguihs.serial,pumpguihs.serial.BytesAvailable)'); % Just to get rid ofthe last byte
    end
end

% Find out how the pump is calibrated:
fprintf(pumpguihs.serial,sprintf('1!\n'));
ret = fscanf(pumpguihs.serial);
indmlmin = strfind(ret,'ml/min');
pumpguihs.calib = str2double(ret(1:(indmlmin-1)));
if pumpguihs.serial.BytesAvailable
    dump = char(fread(pumpguihs.serial,pumpguihs.serial.BytesAvailable)'); % Just to get rid ofthe last byte
end

% Find out the current speed:
fprintf(pumpguihs.serial,sprintf('1S\n'));
ret = fscanf(pumpguihs.serial);
pumpguihs.speedPer = str2double(ret);
if pumpguihs.serial.BytesAvailable
    dump = char(fread(pumpguihs.serial,pumpguihs.serial.BytesAvailable)'); % Just to get rid ofthe last byte
end

pumpguihs.speedFR = (pumpguihs.speedPer/100)*pumpguihs.calib;

% Find out whether the pump is currently running:
fprintf(pumpguihs.serial,sprintf(['1E\n']));
while(~pumpguihs.serial.BytesAvailable) end
ret = fread(pumpguihs.serial,1);

switch ret
    case '+' % running
        pumpguihs.running = true;
        togglebutton(handles);
    case '-' % not running
        pumpguihs.running = false;
        togglebutton(handles);
    otherwise % kewa?
        pumpguihs.running = false;
        togglebutton(handles);
end

% Set the values in teh GUI
set(handles.editPercent,'String',num2str(pumpguihs.speedPer,'% .2f'));
set(handles.mainslider,'Value',pumpguihs.speedPer/100);
set(handles.editFrate,'String',num2str(pumpguihs.speedFR,'% .3f'));

% Start the timer for monitoring the pump:
pumpguihs.timerSerial = timer;
pumpguihs.timerSerial.TimerFcn = {@tmrCLBK,handles};
pumpguihs.timerSerial.ExecutionMode = 'fixedRate';
pumpguihs.timerSerial.Period = 1;
pumpguihs.timerSerial.StartDelay = 1;
start(pumpguihs.timerSerial)

% Create the timer for the flushing events:
pumpguihs.timerFlush = timer;
pumpguihs.timerFlush.ExecutionMode = 'fixedRate';
pumpguihs.timerFlush.StartDelay = 0;
pumpguihs.timerFlush.TimerFcn = {@flushCLBK,handles};
pumpguihs.timerFlush.UserData = struct();

pumpguihs.timerRevert = timer;
pumpguihs.timerRevert.ExecutionMode = 'SingleShot';

% Update handles structure
guidata(hObject, handles);

function varargout = pumpControl_OutputFcn(hObject, eventdata, handles) 
varargout{1} = handles.output;

function tmrCLBK(obj,evt,handles) % This function monitors the speed in the pump.
global pumpguihs

if pumpguihs.serial.BytesAvailable
    dump = char(fread(pumpguihs.serial,pumpguihs.serial.BytesAvailable)'); % Just to get rid ofthe first bytes
end

% Find out current speed:
fprintf(pumpguihs.serial,sprintf('1S\n'));
ret = fscanf(pumpguihs.serial);

if (pumpguihs.speedPer~=str2double(ret)) % Speed difference
    Coordinate(ret,'%',handles);
end

if pumpguihs.serial.BytesAvailable
    dump = char(fread(pumpguihs.serial,pumpguihs.serial.BytesAvailable)'); % Just to get rid ofthe last byte
end

fprintf(pumpguihs.serial,sprintf(['1E\n']));
while(~pumpguihs.serial.BytesAvailable) end
ret = fread(pumpguihs.serial,1);

switch ret
    case '+' % running
        pumpguihs.running = true;
        togglebutton(handles);
    case '-' % not running
        pumpguihs.running = false;
        togglebutton(handles);
    otherwise % kewa?
        % Do nothing
end

function flushCLBK(obj,evt,handles) % This function monitors the speed in the pump.
global pumpguihs

% Save old speed: 
RUD= get(pumpguihs.timerRevert,'UserData');
RUD.oldspeed= pumpguihs.speedPer;
set(pumpguihs.timerRevert,'UserData',RUD);
% Flush at user speed:
UD= get(pumpguihs.timerFlush,'UserData');
Coordinate(num2str(UD.speed),'%',handles);

% setup the timer to revert speed back to normal
start(pumpguihs.timerRevert);

function revertCLBK(obj,~,handles) 

UD = get(obj,'UserData');
Coordinate(num2str(UD.oldspeed),'%',handles)



function Coordinate(value,type,handles)
global pumpguihs
switch type
    case '%' % The percent text
        value = str2double(value);
        pumpguihs.speedPer = value;
    case '1' % The slider
        pumpguihs.speedPer = value*100;
    case 'FR' % the flow rate text
        value = str2double(value);
        pumpguihs.speedPer = (value*100)/pumpguihs.calib;
    otherwise
        %nothing
end

pumpguihs.speedFR = (pumpguihs.speedPer/100)*pumpguihs.calib;

% Set the values in teh GUI
set(handles.editPercent,'String',num2str(pumpguihs.speedPer,'% .2f'));
set(handles.mainslider,'Value',pumpguihs.speedPer/100);
set(handles.editFrate,'String',num2str(pumpguihs.speedFR,'% .3f'));

% Send the value to the pump
fprintf(pumpguihs.serial,sprintf(['1S' num2str(100*pumpguihs.speedPer,'%06.f') '\n']));
while(pumpguihs.serial.BytesAvailable==0) pause(.05); end
ret = char(fread(pumpguihs.serial,pumpguihs.serial.BytesAvailable)'); % Just to get rid of it...



function mainslider_Callback(hObject, eventdata, handles)
Coordinate(get(hObject,'Value'),'1',handles);


function mainslider_CreateFcn(hObject, eventdata, handles)
% hObject    handle to mainslider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: slider controls usually have a light gray background.
if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor',[.9 .9 .9]);
end

function pushbutton1_Callback(hObject, eventdata, handles)

function editflushperC_Callback(hObject, eventdata, handles)

function editflushperC_CreateFcn(hObject, eventdata, handles)
% hObject    handle to editflushperC (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function editflushInt_Callback(hObject, eventdata, handles)

function editflushInt_CreateFcn(hObject, eventdata, handles)
% hObject    handle to editflushInt (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function editPercent_Callback(hObject, eventdata, handles)
Coordinate(get(hObject,'String'),'%',handles);

function editPercent_CreateFcn(hObject, eventdata, handles)
% hObject    handle to editPercent (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function editFrate_Callback(hObject, eventdata, handles)
Coordinate(get(hObject,'String'),'FR',handles);

function editFrate_CreateFcn(hObject, eventdata, handles)
% hObject    handle to editFrate (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function editflushDur_Callback(hObject, eventdata, handles)

function editflushDur_CreateFcn(hObject, eventdata, handles)
% hObject    handle to editflushDur (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function pushbuttonRUNSTOP_Callback(hObject, eventdata, handles)
global pumpguihs
if strcmp(pumpguihs.timerFlush.running,'off') % If not already running, start it
    pumpguihs.timerFlush.UserData = struct('speed',str2double(get(handles.editflushperC,'String')));
    pumpguihs.timerFlush.Period = str2double(get(handles.editflushInt,'String'))*60;
    pumpguihs.timerRevert.StartDelay = str2double(get(handles.editflushDur,'String'));
    pumpguihs.timerRevert.TimerFcn = {@revertCLBK,handles};
    start(pumpguihs.timerFlush);
    set(handles.pushbuttonRUNSTOP,'String','STOP');
else % Otherwise just stop the timer.
    stop(pumpguihs.timerFlush);
    set(handles.pushbuttonRUNSTOP,'String','RUN');
end

function pushbuttonSTARTSTOP_Callback(hObject, eventdata, handles)
global pumpguihs
if pumpguihs.running
    pumpguihs.running = false;
    togglebutton(handles);
    fprintf(pumpguihs.serial,sprintf('1I\n'));
else
    pumpguihs.running = true;
    togglebutton(handles);
    fprintf(pumpguihs.serial,sprintf('1H\n'));
end

function togglebutton(handles)
global pumpguihs

if pumpguihs.running
    set(handles.pushbuttonSTARTSTOP,'BackgroundColor',[1 0 0]);
    set(handles.pushbuttonSTARTSTOP,'String','STOP');
else
    set(handles.pushbuttonSTARTSTOP,'BackgroundColor',[0 1 0]);
    set(handles.pushbuttonSTARTSTOP,'String','START');
end

function figure1_CloseRequestFcn(hObject, eventdata, handles)
% hObject    handle to figure1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: delete(hObject) closes the figure
global pumpguihs
fclose(pumpguihs.serial);
delete(pumpguihs.serial);
stop(pumpguihs.timerSerial);
delete(pumpguihs.timerSerial);

if strcmp(pumpguihs.timerFlush.Running,'on')
    button = questdlg('The flush timer is still running, do you want to stop it?','Flush timer running','Yes','No','Yes');
    if strcmp(button,'Yes')
        stop(pumpguihs.timerFlush);
        delete(pumpguihs.timerFlush);
    end
end
delete(hObject);
