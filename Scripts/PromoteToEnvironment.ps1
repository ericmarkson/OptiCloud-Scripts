#---------------------------------------------------------------------------
# Name:        PromoteToEnvironment.ps1
#
# Summary:     This script will take the Code, Database, and/or the Blobs 
#              from an environment and promote them to another environment
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
    [ValidateSet("Integration", "Preproduction", "Production")]
    [string]$SourceEnvironment,
    [Parameter(Position=4, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Integration", "Preproduction", "Production")]
    [string]$TargetEnvironment,
    [Parameter(Position=5)]
    [ValidateSet($true, $false, 0, 1)]
    [bool]$UseMaintenancePage = 0,
    [Parameter(Position=6)]
    [ValidateSet($true, $false, 0, 1)]
    [bool]$IncludeCode = 1,
    [Parameter(Position=7)]
    [ValidateSet($true, $false, 0, 1)]
    [bool]$IncludeBlobs = 0,
    [Parameter(Position=8)]
    [ValidateSet($true, $false, 0, 1)]
    [bool]$IncludeDb = 0,
    [Parameter(Position=9)]
    [ValidateSet('cms','commerce')]
    [String]$SourceApp,
    [Parameter(Position=10)]
    [ValidateSet("ReadOnly", "ReadWrite")]
    [String]$ZeroDowntimeMode,
    [Parameter(Position=11)]
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
if([string]::IsNullOrWhiteSpace($TargetEnvironment)){
    throw "A target deployment environment is needed. Please supply one."
}
if([string]::IsNullOrWhiteSpace($SourceEnvironment)){
    throw "A source deployment environment is needed. Please supply one."
}
if($DirectDeploy -eq $true -and $TargetEnvironment.ToLower() -ne "integration"){
    throw "Direct Deploy only works for deployments to the Integration environment."
}

if($SourceEnvironment -eq $TargetEnvironment){
    throw "The source environment cannot be the same as the target environment."    
}

if(![string]::IsNullOrWhiteSpace($ZeroDowntimeMode) -and ($IncludeCode -ne $true -or [string]::IsNullOrWhiteSpace($SourceApp))){
    throw "Zero Downtime Deployment requires code to be pushed. Please use the -IncludeCode flag, and also include the -SourceApp flag"
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

Write-Host "Validation passed. Starting Deployment from $SourceEnvironment to $TargetEnvironment"

Write-Host "Setting up the deployment configuration"

$startEpiDeploymentSplat = @{
            ProjectId = "$ProjectID"
            Wait = $false
            TargetEnvironment = "$TargetEnvironment"
            SourceEnvironment = "$SourceEnvironment"
            IncludeBlob = $IncludeBlobs
            IncludeDb = $IncludeDb
            ClientSecret = "$ClientSecret"
            ClientKey = "$ClientKey"
}

if($IncludeCode){
    $startEpiDeploymentSplat.Add("SourceApp", $SourceApp)
    $startEpiDeploymentSplat.Add("UseMaintenancePage", $UseMaintenancePage)
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
    throw "Deployment Failed. Errors: \n" + $deploy.deploymentErrors
}

Write-Host "Deployment Complete"

#Set the Output variable for the Deployment ID, if needed
Write-Output "##vso[task.setvariable variable=DeploymentId;]'$deployId'"
Write-Verbose "Output Variable Created. Name: DeploymentId | Value: $deployId"
Write-Output "##vso[task.complete result=Succeeded;]"