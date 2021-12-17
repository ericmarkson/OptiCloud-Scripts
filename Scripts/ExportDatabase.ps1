#---------------------------------------------------------------------------
# Name:        ExportDatabase.ps1
#
# Summary:     This script will take the a database (CMS or Commerce) for the
#              specified environment and begin the export, and return a
#              download link for the bacpac file. This will also download
#              the database file based on the input params.
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
    [string]$TargetEnvironment,
    [Parameter(Position=4, Mandatory)]
    [ValidateSet('epicms','epicommerce')]
    [String] $DatabaseName,
    [Parameter(Position=5)]
    [String] $DownloadLocation,
    [Parameter(Position=6)]
    [String] $DownloadFileName,
    [Parameter(Position=7)]
    [ValidateSet($true, $false, 0, 1)]
    [bool] $Wait = 0,
    [Parameter(Position=8)]
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

if($IsInTheCloud -eq  $true -and -not [string]::IsNullOrWhiteSpace($DownloadLocation)){
    Write-Warning "Non-Interactive and/or Cloud shell detected. Functions may be limited for this script based on the parameters passed in."
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

Write-Host "Validation passed. Starting Database Export Process."


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

Write-Host "`nExport Finished. Download URL is: $downloadLink `n"

#Set the Output variable for the Export URL, if needed
Write-Output "##vso[task.setvariable variable=ExportDownload;]'$downloadLink'" | Out-Null
Write-Host "Output Variable Created. `nName: ExportDownload | Value: $downloadLink"

if(-not [string]::IsNullOrWhiteSpace($DownloadLocation)){
    
    Write-Host "`n`nStarting the download process..."

    $downloadLink -match "^(https://)?([^.]+)\.blob\.core([^?]*)/([^?]*)?([^.]*)" | Out-Null

    $fileName = "{0}_{1}" -f $Matches[2],$Matches[4]
    if(-not [string]::IsNullOrWhiteSpace($DownloadFileName)){
        if($DownloadFileName -like "*.bacpac"){
            $fileName = $DownloadFileName
            } 
        else{
            $fileName = "{0}{1}" -f $DownloadFileName, ".bacpac"
            }
    }

    $fileContext = $Matches[2]

    #Function to download Database
    Function DownloadDatabaseFile 
    {  
   
        #check if folder exists
        $destination=$DownloadLocation+"\"+$fileContext
        $folderExists=Test-Path -Path $destination 

        if($folderExists -eq $false)  
        {  
            Write-Host "`nDownload Location does not exist. Creating it now!"  
            #Create the new folder  
            $newStructure = New-Item -ItemType Directory -Path $destination
            Write-Host "Folder Structure Created At $($newStructure.FullName)"
        }     
    
        $elapsedTime = [system.diagnostics.stopwatch]::StartNew()
        $startTime = Get-Date
        Write-Host "`nDownload Starting...Started at: $startTime"

        Invoke-WebRequest $downloadLink -OutFile $("{0}\{1}" -f $destination,$fileName)

        $elapsedTime.stop()

        Write-Host "Download Completed Successfully!`n`nDownload Location: $destination`nFile Name: $fileName`nStarted at: $startTime`nCompleted at: $(Get-Date)`nTime to Download: $([string]::Format("{0:d2}:{1:d2}:{2:d2}", $elapsedTime.Elapsed.hours, $elapsedTime.Elapsed.minutes, $elapsedTime.Elapsed.seconds))"

        #Set the Output variable for the Download Location, if needed
        Write-Output "##vso[task.setvariable variable=DownloadLocation;]'$destination'" | Out-Null
        Write-Host "`nOutput Variable Created. `nName: DownloadLocation | Value: $destination"

        #Set the Output variable for the Saved Filename, if needed
        Write-Output "##vso[task.setvariable variable=FileName;]'$fileName'" | Out-Null
        Write-Host "`nOutput Variable Created. `nName: FileName | Value: $fileName"
    }   
  
    DownloadDatabaseFile

}