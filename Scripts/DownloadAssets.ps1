#---------------------------------------------------------------------------
# Name:        DownloadAssets.ps1
#
# Summary:     This script will tell you all of the asset containers that
#              you have within Azure Blob Storage, and will allow you to
#              download whichever one you want/need, in full.
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
    [String]$DownloadLocation,
    [Parameter(Position=5)]
    [String]$StorageContainerName,
    [Parameter(Position=6)]
    [String]$RetentionHours=5
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

if($IsInTheCloud -eq  $true -and -not [string]::IsNullOrWhiteSpace($StorageContainerName)){
    Write-Warning "Non-Interactive and/or Cloud shell detected. Functions may be limited for this script based on the parameters passed in."
}


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

if (-not (Get-Module -Name Azure.Storage -ListAvailable)) {
Write-Host "Installing Azure.Storage Powershell Module"
Install-Module -Name Azure.Storage -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -MinimumVersion 4.4.0
}

#Turning off warnings about Azure Retirement, for now...
Set-Item Env:\SuppressAzureRmModulesRetiringWarning "true"

Write-Host "Validation passed. Starting Asset Downloading Process."

Write-Host "Setting up the export configuration"

#Setting up the object for the Authentication
$startOptiAuth = @{
    ProjectId = "$ProjectID"
    ClientSecret = "$ClientSecret"
    ClientKey = "$ClientKey"
}

Write-Host "Starting the Auth."

#Starting the Export
$authenticated = Connect-EpiCloud @startOptiAuth

Write-Host "Authenticated. Ready to query Azure."

#Setting up the object for looking for the storage container
$startOptiStorageContainerSeek = @{
    Environment  = "$TargetEnvironment"
}
if([string]::IsNullOrWhiteSpace($StorageContainerName)){
Write-Host "Storage Container name not supplied.`nLooking at the storage containers for the following environment: $TargetEnvironment" 

#Starting the Export
$containersForEnv = Get-EpiStorageContainer @startOptiStorageContainerSeek

$containerLength = $containersForEnv.StorageContainers.Length

if($containerLength -eq 0){
exit
}

Write-Host "`nThe following Storage Containers Exist:"
$counter = 1;
foreach($c in $containersForEnv.StorageContainers){
    Write-Host "$counter) $c"
    $counter++;
    }
    Write-Host "0) ~~Exit Script~~`n"

    if($IsInTheCloud){
        throw "Please see above for container names. The PowerShell environment is non-interactive. Please supply a name via the invocation."
    }

[int]$containerInput = Read-Host "Please select which number storage container you want to download"

if($containerInput -eq 0){
    exit
}

if (($containerInput -eq $null) -or ($containerInput -cgt $containerLength) -or ($containerInput -le 0)){
    Throw 'Your selection is not valid. Please try again.'
    exit
}

$StorageContainerName = $containersForEnv.StorageContainers[$containerInput-1]
}
Write-Host "`nStorage Container selected to download: $StorageContainerName"

#Setting up the object for getting the SAS Link
$startOptiSASLink = @{
    Environment = "$TargetEnvironment"
    StorageContainer = "$StorageContainerName"
    RetentionHours = "$RetentionHours"
}

Write-Host "Getting the SAS Link for download permissions"

#Starting the Export
$saslink = Get-EpiStorageContainerSasLink @startOptiSASLink

$saslink.sasLink -match "^(https://)?([^.]+)\.blob\.core([^?]*)?([^.]*)" | Out-Null

$storageAccountName = $Matches[2]
$sasToken = $Matches[4]

#Function to download all blob contents  
Function DownloadBlobContents  
{  
    Write-Host "Creating Azure context based on SAS link and the account name: $storageAccountName"    
    $ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken

    #check if folder exists
    $destination=$DownloadLocation+"\"+$StorageContainerName 
    $folderExists=Test-Path -Path $destination 

    if($folderExists -eq $false)  
    {  
        Write-Host "`nDownload Location does not exist. Creating it now!"  
        #Create the new folder  
        $newStructure = New-Item -ItemType Directory -Path $destination
        Write-Host "Folder Structure Created At $($newStructure.FullName)"
    }     
    
    Write-Host "`nGetting the blob contents from the container: $StorageContainerName"
    $blobContents=Get-AzureStorageBlob -Container $StorageContainerName  -Context $ctx  

    $counter = 0
    $numberOfFiles = $blobContents.count
    
    $elapsedTime = [system.diagnostics.stopwatch]::StartNew()
    $startTime = Get-Date
    Write-Host "`nDownload Starting...Started at: $startTime"
    foreach($blobContent in $blobContents)  
    {  
        $counter++
        $percentComplete = [Math]::Round((($counter / $numberOfFiles) * 100), 2)
        #do the ratios and "the math" to compute the Estimated Time Of Completion 
        $elapsedTimeRatio = $(get-date) - $startTime 
        $estimatedTotalSeconds = $numberOfFiles / $counter * $elapsedTimeRatio.TotalSeconds 
        $estimatedTotalSecondsTS = New-TimeSpan -seconds $estimatedTotalSeconds
        $estimatedCompletionTime = $startTime + $estimatedTotalSecondsTS
        Write-Progress -Activity "Downloading Blobs from $storageAccountName\$StorageContainerName to $destination - $percentComplete% Complete" -Status "Downloading $($blobContent.Name)" -PercentComplete $percentComplete -CurrentOperation "$counter of $numberOfFiles Files Downloaded - Elapsed Time: $([string]::Format("{0:d2}:{1:d2}:{2:d2}", $elapsedTime.Elapsed.hours, $elapsedTime.Elapsed.minutes, $elapsedTime.Elapsed.seconds)) - Estimated Completion at $estimatedCompletionTime"
        Write-Output "##vso[task.setprogress value=$percentComplete]Percent Complete: $percentComplete%" | Out-Null
        #Download the blob content  
        & {
            $ProgressPreference = "SilentlyContinue"
            Get-AzureStorageBlobContent -Container $StorageContainerName  -Context $ctx -Blob $blobContent.Name -Destination $destination -Force | Out-Null
        }
    }
    $elapsedTime.stop()

    Write-Host "Download Completed Successfully!`n`nStorage Account Name: $storageAccountName`nContainer Name: $StorageContainerName`nNumber of Files: $numberOfFiles`nStarted at: $startTime`nCompleted at: $(Get-Date)`nTime to Download: $([string]::Format("{0:d2}:{1:d2}:{2:d2}", $elapsedTime.Elapsed.hours, $elapsedTime.Elapsed.minutes, $elapsedTime.Elapsed.seconds))`nDownload Location: $destination"

    #Set the Output variable for the Download Location, if needed
    Write-Host "##vso[task.setvariable variable=DownloadLocation;]'$destination'" | Out-Null
    Write-Host "`nOutput Variable Created. `nName: DownloadLocation | Value: $destination"
}   
  
DownloadBlobContents

