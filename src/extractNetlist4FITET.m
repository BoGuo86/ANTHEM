function extractNetlist4FITET(filename,msh,idx,excitation,materials,tEnd,Tinit)
% EXTRACTNETLIST4FITET automatically generates a SPICE netlist modeling the
% electrothermal behavior of a given 3D structure. The netlist is optimized
% for LTspice syntax.
%
% Input:
%   filename     name of file to save netlist in
%   msh          struct as defined by src/msh.txt
%                required fields: np,Mx,My,Mz,ipnXmin,ipnXmax,ipnYmin,
%                                 ipnYmax,ipnZmin,ipnZmax,ipeGhost
%   idx          struct as defined by src/idx.txt
%                required fields: elect.excitation,elect.gnd,
%                                 therm.excitation,therm.gnd
%   excitation   struct as defined by src/excitation.txt
%                required fields: amplitude,delay,freq,phi,tau,type,t_rise
%   materials    struct as defined by src/materials.txt
%                required fields: Msigma,Mlambda,Meps,Mrhoc
%   tEnd         end time (scalar)
%   Tinit        initial temperature (optional,default: 293)
%                (scalar or np-by-1)
%
% See also createQJ4edge, createQJ4point, createResistor,
% createSPICEsignal, runLTspice
%
% authors:
% Thorben Casper, David Duque, Victoria Heinz, Abdul Moiz,
% Herbert De Gersem, Sebastian Schoeps
% Institut fuer Theorie Elektromagnetischer Felder
% Graduate School of Computational Engineering
% Technische Universitaet Darmstadt

if nargin < 7, Tinit = 293;     end

% broadcase Tinit if scalar is given
if isscalar(Tinit), Tinit = Tinit*ones(msh.np,1); end

tstart = tic;
fprintf('extracting electrothermal netlist ...\n');

% open netlist file
fileID = fopen([filename '.cir'],'w');
fprintf(fileID,'This electrothermal netlist was generated by ANTHEM (https://github.com/tc88/ANTHEM)\n');

% iterate over edges Lm of the grid
for m = 1:3*msh.np
    if ~ismember(m,msh.ipeGhost)
        % find indices of primary nodes that are connected by edge of index m
        temp = ipe2ipn(msh,m);
        i = temp(1); j = temp(2);
        clear temp

        % possibly nonlinear electric resistor
        GelmString = createResistor(m,i,j,materials,'sigma');
        fprintf(fileID,'%s%d\t%d\t%d\t%s%d%s%d%s%s\n','BGel',m,i,j,'I=(V(',i,')-V(',j,'))*',GelmString);

        % electric capacitor
        Celm = full(materials.Meps(m,m));
        fprintf(fileID,'%s%d\t\t%d\t%d\t%d\t%s\n','Cel',m,i,j,Celm,'ic=0');

        % linear thermal resistor
        Rthm = full(1/materials.Mlambda(m,m));
        fprintf(fileID,'%s%d%s\t\t%d%s\t%d%s\t%d\n','Rth',m,'T',i,'T',j,'T',Rthm);
    end
end

% initialize strings that shall contain all potentials and temperatures
allPots  = '';
allTemps = '';
% iterate over points Pi of the grid
for i=1:msh.np
    % capacitor for thermal circuit
    Cthi = full(materials.Mrhoc(i,i));
    fprintf(fileID,'%s%d%s\t%d%s\t%d\t%d\t%s%d\n','Cth',i,'T',i,'T',0,Cthi,'ic=',Tinit(i));

    % Joule losses QJ for node i
    QJistring = createQJ4point(i,msh,materials);
    QJi = sprintf('%s%s','I=',QJistring);
    fprintf(fileID,sprintf('%s%d\t\t%d\t%d%s\t%s\n','BLoss',i,0,i,'T',QJi));

    % boundary conditions
    if ismember(i,idx.elect.excitation)
        fprintf(fileID,'%s%d\t%d\t%d\t%s\n','VDirEl',i,i,0,createSPICEsignal(tEnd,excitation));
    end
    if ismember(i,idx.elect.gnd)
        fprintf(fileID,'%s%d\t%d\t%d\t%d%s\n','VDirEl',i,i,0,0,'Vdc');
    end
    if ismember(i,idx.therm.excitation)
        fprintf(fileID,'%s%d\t%d%s\t%d\t%s\n','VDirTh',i,i,'T',0,createSPICEsignal(tEnd,excitation));
    end
    if ismember(i,idx.therm.gnd)
        fprintf(fileID,'%s%d\t%d%s\t%d\t%d%s\n','VDirTh',i,i,'T',0,0,'Vdc');
    end

    % fill strings to print all potentials and temperatures
    allPots  = strcat(allPots ,sprintf('%s%d%s',' V(',i,',0)' ));
    allTemps = strcat(allTemps,sprintf('%s%d%s',' V(',i,'T,0)'));
end

% time settings
fprintf(fileID,'%s\t%d\t%s\n','.tran',tEnd,'uic');

% print potentials and temperatures
fprintf(fileID,'%s\t%s\t%s\n','.print','tran',allPots );
fprintf(fileID,'%s\t%s\t%s'  ,'.print','tran',allTemps);

% disable direct Newton iteration and Gmin stepping for faster init DC solution
fprintf(fileID,'.option gminsteps 0');

% close netlist file
fclose(fileID);

fprintf('finished extracting electrothermal netlist after %d seconds.\n',toc(tstart));

end