#---------------------------------------------------------------------------
# Name:        DeployToEnvironment.ps1
#
# Summary:     This script will take a previously-uploaded package and
#              deploy it to the selected environment. A CMS, Commerce,
#              Blob, or DB file must be uploaded using the
#              Add-EpiDeploymentPackage command.
#
# Last Updated: 12/8/2021
#
# Author: Eric Markson - eric.markson@perficient.com | eric@ericmarkson.com | https://optimizelyvisuals.dev/
#
# License: GNU/GPLv3 http://www.gnu.org/licenses/gpl-3.0.html
#---------------------------------------------------------------------------

#Setting up Parameters 
#Setting each Paramater has Mandatory, as they are not optional
#Validating each paramarer for being Null or Empty, using the built in Validator
param
  (
    [Parameter(Position=0, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientKey,
    [Parameter(Position=1, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientSecret,
    [Parameter(Position=2, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectID,
    [Parameter(Position=3, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactPath,
    [Parameter(Position=4, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Integration", "Preproduction", "Production")]
    [string]$TargetEnvironment,
    [Parameter(Position=5, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet($true, $false, 0, 1)]
    [bool]$UseMaintenancePage,
    [Parameter(Position=6)]
    [ValidateSet("ReadOnly", "ReadWrite")]
    [string]$ZeroDowntimeMode,
    [Parameter(Position=7)]
    [ValidateSet($true, $false, 0, 1)]
    [bool]$DirectDeploy = 0
  )

#Checking that the required params exist and are not white space
if([string]::IsNullOrWhiteSpace($ClientKey)){
    throw "A Client Key is needed. Please supply one."
}
if([string]::IsNullOrWhiteSpace($ClientSecret)){
    throw "A Client Secret Key is needed. Please supply one."
}
if([string]::IsNullOrWhiteSpace($ProjectID)){
    throw "A Project ID GUID is needed. Please supply one."
}
if([string]::IsNullOrWhiteSpace($ArtifactPath)){
    throw "A path for the NUPKG file location is needed. Please supply one."
}
if([string]::IsNullOrWhiteSpace($TargetEnvironment)){
    throw "A target deployment environment is needed. Please supply one."
}
if([string]::IsNullOrWhiteSpace($UseMaintenancePage)){
    throw "Please provide an option for if the maintenance page should be shown. Correct values are true or false."
}
if($DirectDeploy -eq $true -and $TargetEnvironment.ToLower() -ne "integration"){
    throw "Direct Deploy only works for deployments to the Integration environment."
}

#Checking for Non-Interactive Shell
function Test-IsNonInteractiveShell {
    if ([Environment]::UserInteractive) {
        foreach ($arg in [Environment]::GetCommandLineArgs()) {
            #Test each Arg for match of abbreviated '-NonInteractive' command.
            if ($arg -like '-NonI*') {
                return $true
            }
        }
    }

    return $false
}

$IsInTheCloud = Test-IsNonInteractiveShell

if($IsInTheCloud -eq  $true)
{
   Write-Host "Non-Interactive and/or Cloud shell detected. Force Installing EpiCloud Powershell Module"
   Install-Module EpiCloud -Scope CurrentUser -Repository PSGallery -AllowClobber -MinimumVersion 1.0.0 -Force
}  
else
{
   Write-Host "Installing EpiCloud Powershell Module"
   Install-Module EpiCloud -Scope CurrentUser -Repository PSGallery -AllowClobber -MinimumVersion 1.0.0     
}

Write-Host "Validation passed. Starting Deployment to" $TargetEnvironment 
Write-Host "Searching for NUPKG file..."

#From the Artifact Path, getting the nupkg file
$packagePath = Get-ChildItem -Path $ArtifactPath -Filter *.nupkg

#If no NUPKG file is found, throw error and exit
if($packagePath.Length -eq 0){
    throw "No NUPKG files were found. Please ensure you're passing the correct path."
}

Write-Host "Package Found. Name:" $packagePath.Name


Write-Host "Setting up the deployment configuration"

#Setting up the object for the EpiServer environment deployment
$startEpiDeploymentSplat = @{
    DeploymentPackage = $packagePath.Name
    ProjectId = "$ProjectID"
    Wait = $false
    TargetEnvironment = "$TargetEnvironment"
    UseMaintenancePage = $UseMaintenancePage
    ClientSecret = "$ClientSecret"
    ClientKey = "$ClientKey"
}

if($DirectDeploy -eq $true){
    $startEpiDeploymentSplat.Add("DirectDeploy", $true)
}


if(![string]::IsNullOrWhiteSpace($ZeroDownTimeMode)){
    $startEpiDeploymentSplat.Add("ZeroDownTimeMode", $ZeroDownTimeMode)
}

Write-Host "Starting the Deployment to" $TargetEnvironment

#Starting the Deployment
$deploy = Start-EpiDeployment @startEpiDeploymentSplat

$deployId = $deploy | Select -ExpandProperty "id"

#Setting up the object for the EpiServer Deployment Updates
$getEpiDeploymentSplat = @{
    ProjectId = "$ProjectID"
    ClientSecret = "$ClientSecret"
    ClientKey = "$ClientKey"
    Id = "$deployId"
}

#Setting up Variables for progress output
$percentComplete = 0
$currDeploy = Get-EpiDeployment @getEpiDeploymentSplat | Select-Object -First 1
$status = $currDeploy | Select -ExpandProperty "status"
$exit = 0

Write-Host "Percent Complete: $percentComplete%"
Write-Output "##vso[task.setprogress value=$percentComplete]Percent Complete: $percentComplete%"

#While the exit flag is not true
while($exit -ne 1){

#Get the current Deploy
$currDeploy = Get-EpiDeployment @getEpiDeploymentSplat | Select-Object -First 1

#Set the current Percent and Status
$currPercent = $currDeploy | Select -ExpandProperty "percentComplete"
$status = $currDeploy | Select -ExpandProperty "status"

#If the current percent is not equal to what it was before, send an update
#(This is done this way to prevent a bunch of messages to the screen)
if($currPercent -ne $percentComplete){
    Write-Host "Percent Complete: $currPercent%"
    Write-Output "##vso[task.setprogress value=$currPercent]Percent Complete: $currPercent%"
    #Set the overall percent complete variable to the new percent complete
    $percentComplete = $currPercent
}

#If the Percent Complete is equal to 100%, Set the exit flag to true
if($percentComplete -eq 100){
    $exit = 1    
}

#If the status of the deployment is not what it should be for this scipt, Set the exit flad to true
if($status -ne 'InProgress'){
    $exit = 1
}

#Wait 1 second between checks
start-sleep -Milliseconds 1000

}

#If the status is set to Failed, throw an error
if($status -eq "Failed"){
    Write-Output "##vso[task.complete result=Failed;]"
    throw "Deployment Failed. Errors: \n" + $deploy.deploymentErrors
}

Write-Host "Deployment Complete"

#Set the Output variable for the Deployment ID, if needed
Write-Output "##vso[task.setvariable variable=DeploymentId;]'$deployId'"
Write-Verbose "Output Variable Created. Name: DeploymentId | Value: $deployId"
Write-Output "##vso[task.complete result=Succeeded;]"