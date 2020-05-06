#---------------------------------------------------------------------------
# Name:        ExportDatabase.ps1
#
# Summary:     This script will take the a database (CMS or Commerce) for the
#              specified environment and begin the export, and return a
#              download link for the bacpac file.
#
# Version:     1.0g
#
# Last Updated: 5/6/2020
#
# Author: Eric Markson - eric.markson@perficient.com | eric@ericmarkson.com | https://www.epivisuals.dev
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
    [string]$TargetEnvironment,
    [Parameter(Position=4, Mandatory)]
    [ValidateSet('epicms','epicommerce')]
    [String] $DatabaseName,
    [Parameter(Position=5)]
    [ValidateSet($true, $false, 0, 1)]
    [bool] $Wait = 0,
    [Parameter(Position=6)]
    [ValidateSet($true, $false, 0, 1)]
    [bool] $VerboseLogging = 0
    
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


Write-Host "Validation passed. Starting Database Export Process."
#If the Module for EpiCloud is not found, install it using the force switch
if (-not (Get-Module -Name EpiCloud -ListAvailable)) {
    Write-Host "Installing EpiServer Cloud Powershell Module"
    Install-Module EpiCloud -Scope CurrentUser -Force
}

Write-Host "Setting up the export configuration"

#Setting up the object for the EpiServer environment export
$startEpiExportmentSplat = @{
    ProjectId = "$ProjectID"
    Wait = $Wait
    Environment = "$TargetEnvironment"
    DatabaseName = "$DatabaseName"
    ClientSecret = "$ClientSecret"
    ClientKey = "$ClientKey"
    Verbose = $VerboseLogging
}

Write-Host "Starting the Export. Environment: $TargetEnvironment | DB Name: $DatabaseName"

#Starting the Export
$export = Start-EpiDatabaseExport @startEpiExportmentSplat


if($Wait -eq $false){
$exportId = $export | Select -ExpandProperty "id"

#Setting up the object for the EpiServer Export Updates
$getEpiExportSplat = @{
    ProjectId = "$ProjectID"
    ClientSecret = "$ClientSecret"
    ClientKey = "$ClientKey"
    Id = "$exportId"
    Environment = "$TargetEnvironment"
    DatabaseName = "$DatabaseName"
}

#Setting up Variables for progress output
$timesRun = 0
$currExport = Get-EpiDatabaseExport @getEpiExportSplat | Select-Object -First 1
$status = $currExport | Select -ExpandProperty "status"
$exit = 0

#While the exit flag is not true
while($exit -ne 1){

#Get the current Export
$currExport = Get-EpiDatabaseExport @getEpiExportSplat | Select-Object -First 1

$status = $currExport | Select -ExpandProperty "status"

Write-Host "Exporting In Progress. Elapsed time -"$timesRun":00"

#If the status of the export is not what it should be for this scipt, Set the exit flad to true
if($status -ne 'InProgress'){
    $exit = 1
}
$timesRun = $timesRun + 1;
#Wait 1 minute between checks
start-sleep -Milliseconds 60000

}


#If the status is set to Failed, throw an error
if($status -eq "Failed"){
    throw "Export Failed."
}

        }
    else{
    $currExport = $export
    }

$downloadLink = $currExport | Select -ExpandProperty "downloadLink"

Write-Host "Export Finished. Download URL is: $downloadLink `n"

#Set the Output variable for the Export URL, if needed
Write-Host "##vso[task.setvariable variable=ExportDownload;]'$downloadLink'"
Write-Host "Output Variable Created. `nName: ExportDownload | Value: $downloadLink"