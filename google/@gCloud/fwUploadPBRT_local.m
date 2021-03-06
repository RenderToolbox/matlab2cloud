function [sceneSession,current_id] = fwUploadPBRT_local(obj, thisR, varargin )
% Copy a pbrt scene directory to FORUPLOAD foder, then flywheel CLI is used
% to import files to flywheel.
%
% Syntax
%   [sceneSession,current_id] = gcp.fwUploadPBRT(thisR, ...)
%
% Description:
%   The piWrite function places a number of files in the rendering
%   directory.  These include the scene, geometry, material, and lens file
%   and texture files. The scene, geometry, and material files are.
%   fundamental. We call the other files (textures, lens, spds, ...other)
%   resources. 
%
%   This function collects the resources into a single zip file.  It then
%   uploads the scene, geometry, materials and zipped resources to the
%   gcloud bucket.
%
% Input
%   thisR:  A render recipe.
%
% Optional key/value pairs
%
%   materials - upload materials.pbrt, default is true
%   geometry  - upload geomety.pbrt, default is true
%   resources - upload rendering dependent files, default is true
%
% Returns
%   sceneSession - The bucket where the files were copied
%
% Descriptions
%  Using the information in the render recipe (thisR), we find and zip
%  the resource files.  The zip file is placed inside the data
%  directory.
%
%
%  The 'target' field of the gcp object is modified to specify the
%
% See examples in source code
%
% See also: s_gCloud
%
% ZL,  Vistasoft
% 
% We assume gcp is initialized
%
% Example 1
%{
  % The chess set scene has resource files
  fname = fullfile(piRootPath,'data','ChessSet','chessSet.pbrt');
  if ~exist(fname,'file'), error('File not found'); end
  thisR = piRead(fname);
  cloudFolder = gcp.uploadPBRT(thisR);
  gcp.ls(cloudFolder)
%}

% Example 2
%{
  % No resources files for teapot case
  fname = fullfile(piRootPath,'data','teapot-area','teapot-area-light.pbrt');
  if ~exist(fname,'file'), error('File not found'); end
  thisR = piRead(fname);
  cloudFolder = gcp.uploadPBRT(thisR);
  gcp.ls(cloudFolder)
%}

%%
p = inputParser;

varargin = ieParamFormat(varargin);  % Allow spaces and capitalization

p.addRequired('recipe',@(x)(isa(x,'recipe')));

% Specify whether we upload a *_materials.pbrt
p.addParameter('materials',true,@islogical);  

% Specify whether we upload a *_geometry.pbrt
p.addParameter('geometry',true,@islogical); 

p.addParameter('road',[]);

% flywheel 
p.addParameter('scitran',[],@(x)(isa(x,'scitran')));

p.parse(thisR,varargin{:});

materials    = p.Results.materials;     % Upload materials files (logical)
geometry     = p.Results.geometry;      % Upload geometry files (logical)
road         = p.Results.road;
st           = p.Results.scitran;     % flywheel
%% Write out the depth file, if required
if(obj.renderDepth)
    
    depthRecipe = piRecipeConvertToMetadata(thisR,'metadata','depth');
    index_m = piContains(depthRecipe.world,'_materials.pbrt');
    depthRecipe.world(index_m) = []; 
    % Always overwrite the depth file, but don't copy over the whole directory
    piWrite(depthRecipe,...
        'overwritepbrtfile',true,...
        'overwritelensfile',false,...
        'overwriteresources',false,...
        'overwritematerials',false,...
        'creatematerials',false,...
        'overwritegeometry',false);
end

%% Write out the mesh file, if required
if(obj.renderMesh)
    
    meshRecipe = piRecipeConvertToMetadata(thisR,'metadata','mesh');
    index_m = piContains(meshRecipe.world,'_materials.pbrt');
    meshRecipe.world(index_m) = []; 
    % Always overwrite the mesh file, but don't copy over the whole directory
    piWrite(meshRecipe,...
        'overwritepbrtfile',true,...
        'overwritelensfile',false,...
        'overwriteresources',false,...
        'overwritematerials',false,...
        'creatematerials',false,...
        'overwritegeometry',false);
end

%% These are the PBRT scene file and resources
% pbrtScene = thisR.get('input file');
%% Render recipe is created by json file on flywheel, so no input pbrtScene file for this case --zhenyi0908
% if ~exist(pbrtScene,'file')
%     error('PBRT scene not found %s\n',pbrtScene);
% else
%     [sceneFolder, sceneName] = fileparts(pbrtScene);
% end

%%  Copy the local data to flywheel 'scenes_pbrt' session, create an acquisition named by scene name;
pbrtSceneFile = thisR.get('output file');
[sceneFolder,sceneName,~]= fileparts(pbrtSceneFile);

if ~exist(pbrtSceneFile,'file')
    error('Could not find pbrt scene file %s\n',pbrtSceneFile);
end

%
hierarchy = st.projectHierarchy('Renderings');
sessions = hierarchy.sessions;

for ii=1:length(sessions)
    if isequal(lower(sessions{ii}.label),'scenes_pbrt')
        sceneSession = sessions{ii};
        break;
    end
end
% create an acquisition
current_id = st.containerCreate('Wandell Lab', 'Renderings',...
    'session','scenes_pbrt','acquisition',sceneName);
% Assign flywheel information to gcp
obj.fwAPI.sceneFilesID  = current_id;
obj.fwAPI.key = st.showToken;
obj.fwAPI.InfoList = road.fwList;
fwproject = st.search('project','project label exact','Renderings');
obj.fwAPI.projectID = fwproject{1}.project.id;

if ~isempty(current_id.acquisition)
    fprintf('%s acquisition created \n',sceneName);
end
%% Create a local folder
fwLocalDir = fullfile(piRootPath,'local','FORUPLOAD','wandell', 'Renderings','pbrt','scenes_pbrt',sprintf('%s',sceneName));
if ~exist(fwLocalDir,'dir'), mkdir(fwLocalDir);end
%% Copy scene file

[SUCCESS]=copyfile(pbrtSceneFile,fwLocalDir);
% status= st.fileUpload(pbrtSceneFile,current_id.acquisition,'acquisition');
if SUCCESS
    fprintf('%s.pbrt uploaded \n',sceneName);
else
    error('cp scene file to flywheel failed\n');
end

%% Copy geometry and material files
 
pbrtMaterialFile = fullfile(sceneFolder,sprintf('%s_materials.pbrt',sceneName));
pbrtGeometryFile = fullfile(sceneFolder,sprintf('%s_geometry.pbrt',sceneName));
[SUCCESS]=copyfile(pbrtGeometryFile,fwLocalDir);
if SUCCESS
    fprintf('%s_geometry.pbrt copied \n',sceneName);
else
    error('cp scene file to flywheel failed\n');
end
[SUCCESS]=copyfile(pbrtMaterialFile,fwLocalDir);
if SUCCESS
    fprintf('%s_material.pbrt copied \n',sceneName);
else
    error('cp scene file to flywheel failed\n');
end

%% Copy depth file
if(obj.renderDepth)
    f_depth  = sprintf('%s_depth.pbrt',sceneName);
    pbrtDepthFile = fullfile(sceneFolder,f_depth);
    status= copyfile(pbrtDepthFile,fwLocalDir);
    if status
        fprintf('%s copied \n',f_depth);
    else
        error('cp Depth scene file to flywheel failed\n');
    end
end

%% Copy mesh file
if(obj.renderDepth)
    
    f_mesh  = sprintf('%s_mesh.pbrt',sceneName);
    pbrtMeshFile = fullfile(sceneFolder,f_mesh);
    status= copyfile(pbrtMeshFile,fwLocalDir);
    if  status
        fprintf('%s copied \n',f_mesh);
    else
        error('cp Mesh scene file to flywheel failed\n');
    end
end
%% piGeometryRead creates a json file of current recipe, upload recipe.
recepeJson = sprintf('%s.json',sceneName);
pbrtRecipeJson = fullfile(sceneFolder,recepeJson);
% save target information in recipe.metadata,and overwrite recipe json
target.camera    = thisR.camera;
target.local     = thisR.outputFile;
target.remote    = obj.fwAPI.projectID;
target.fwAPI     = obj.fwAPI;
target.depthFlag = obj.renderDepth;
target.meshFlag  = obj.renderMesh;
thisR.metadata.cgresource = target;
jsonwrite(pbrtRecipeJson,thisR);
status= copyfile(pbrtRecipeJson,fwLocalDir);
if  status
    fprintf('%s copied \n',recepeJson);
else
    error('cp recipeJson of scene file to flywheel failed\n');
end

disp('All files copied!')
end

