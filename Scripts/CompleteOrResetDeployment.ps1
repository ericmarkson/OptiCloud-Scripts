#---------------------------------------------------------------------------
# Name:        CompleteOrResetDeployment.ps1
#
# Summary:     This script will complete or Reset an in-progress deployment
#              that is waiting on the second-stage approval to push live.
#              (Swapping the App Service slot)
#
# Version:     1.1 - Added Fix for Azure.Storage Error
#
# Last Updated: 4/2/2021
#
# Author: Eric Markson - eric.markson@perficient.com | eric@ericmarkson.com | https://optimizelyvisuals.dev/
#
# License: GNU/GPLv3 http://www.gnu.org/licenses/gpl-3.0.html
#---------------------------------------------------------------------------

#Setting up Parameters 
#Setting each Paramater has Mandatory, as they are not optional
#Validating each parameter for being Null or Empty, using the built in Validator
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
    [ValidateSet("Reset","Complete")]
    [string]$Action,
    [Parameter(Position=4)]
    [string]$DeploymentId,
    [Parameter(Position=5, Mandatory)]
    [ValidateSet("Integration", "Preproduction", "Production")]
    [ValidateNotNullOrEmpty()]
    [string]$targetEnvironment
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

Write-Host "Installing Azure.Storage Powershell Module"
Install-Module -Name Azure.Storage -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -MinimumVersion 4.4.0

#If the Module for EpiCloud is not found, install it using the force switch
if (-not (Get-Module -Name EpiCloud -ListAvailable)) {
    Write-Host "Installing EpiServer Cloud Powershell Module"
    Install-Module EpiCloud -Scope CurrentUser -Force
}

Write-Host "Validation passed. Starting $Action"

#Setting up the object for the EpiServer Deployment Updates
#If Deployment ID is specified, input it into the object.
#Otherwise, create object without itif([string]::IsNullOrWhiteSpace($DeploymentId)){
if([string]::IsNullOrWhiteSpace($DeploymentId)){
    $getEpiDeploymentSplat = @{
        ProjectId = "$ProjectID"
        ClientSecret = "$ClientSecret"
        ClientKey = "$ClientKey"
        id = ""
}
    }else{
        $getEpiDeploymentSplat = @{
            ProjectId = "$ProjectID"
            ClientSecret = "$ClientSecret"
            ClientKey = "$ClientKey"
            id = "$DeploymentId"
        }
}

#Search for Deployment based on the provided object
$currDeploy = Get-EpiDeployment @getEpiDeploymentSplat  

#If DeploymentID is not set, search for it using the previously found deployment
if([string]::IsNullOrWhiteSpace($DeploymentId)){
    Write-Host "No Deployment ID Supplied. Searching for In-Progress Deployment..."
    $currDeploy = $currDeploy | Where-Object {$_.endTime -eq $null} | Where-Object {$_.parameters.targetEnvironment -eq $targetEnvironment -and $_.percentComplete -eq "100"} | Sort-Object -Property startTime -Descending | Select-Object -First 1
    $DeploymentId = $currDeploy | Select -ExpandProperty "id"
    Write-Host "Deployment ID Found: $DeploymentId"
    $getEpiDeploymentSplat.id = $DeploymentId
}

Write-Host "Setting up the deployment configuration"

#Setting up the object for the EpiServer environment deployment completion
$completeOrResetEpiDeploymentSplat = @{
    ProjectId = "$ProjectID"
    Id = "$DeploymentId"
    Wait = $false
    ClientSecret = "$ClientSecret"
    ClientKey = "$ClientKey"
}

Write-Host "Starting the Process. Action: $Action..."

if($Action -eq "Complete"){
    #Starting the Deployment
    $deploy = Complete-EpiDeployment @completeOrResetEpiDeploymentSplat
}
else {
    #Starting the Deployment
    $deploy = Reset-EpiDeployment @completeOrResetEpiDeploymentSplat
}


#Setting up Variables for progress output
$percentComplete = 0
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

#If the status of the deployment is not what it should be for this scipt, Set the exit flag to true
if($action -eq 'Complete' -and $status -ne 'Completing'){
    $exit = 1
}

if($action -eq 'Reset' -and $status -ne 'Resetting'){
    $exit = 1
}

#Wait 1 second between checks
start-sleep -Milliseconds 1000

}

Write-Host "Process Completed Successfully. Action: $Action"