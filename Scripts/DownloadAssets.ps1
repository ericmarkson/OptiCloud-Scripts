#---------------------------------------------------------------------------
# Name:        DownloadAssets.ps1
#
# Summary:     This script will tell you all of the asset folders that
#              you have within Azure Blob Storage, and will allow you
#              to download whichever one you want/need.
#
# Version:     1.0 - Initial
#
# Last Updated: 6/30/2021
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

Write-Host "Installing Azure.Storage Powershell Module"
Install-Module -Name Azure.Storage -Scope CurrentUser -Repository PSGallery -Force -AllowClobber

Write-Host "Validation passed. Starting Asset Downloading Process."
#If the Module for EpiCloud is not found, install it using the force switch
if (-not (Get-Module -Name EpiCloud -ListAvailable)) {
    Write-Host "Installing EpiServer Cloud Powershell Module"
    Install-Module EpiCloud -Scope CurrentUser -Force
}

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

Write-Host "Authenticated"


function Test-IsNonInteractiveShell {
    if ([Environment]::UserInteractive) {
        foreach ($arg in [Environment]::GetCommandLineArgs()) {
            # Test each Arg for match of abbreviated '-NonInteractive' command.
            if ($arg -like '-NonI*') {
                return $true
            }
        }
    }

    return $false
}

$IsInTheCloud = $true#Test-IsNonInteractiveShell

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

    if($IsInTheCloud){
        throw "Please see above for container names. The PowerShell environment is non-interactive. Please supply a name via the invocation."
    }

[int]$containerInput = Read-Host "Please select which number storage container you want to download"

if (($containerInput -eq $null) -or ($containerInput -cgt $containerLength) -or ($containerInput -le 0)){
    Throw 'Your selection is not valid. Please try again.'
    exit
}

$StorageContainerName = $containersForEnv.StorageContainers[$containerInput-1]
}
Write-Host "`n$StorageContainerName has been selected as the Storage Container to download"

#Setting up the object for getting the SAS Link
$startOptiSASLink = @{
    Environment = "$TargetEnvironment"
    StorageContainer = "$StorageContainerName"
    RetentionHours = "$RetentionHours"
}

Write-Host "Getting the SAS Link"

#Starting the Export
$saslink = Get-EpiStorageContainerSasLink @startOptiSASLink

$saslink

$saslink.sasLink -match "^(https://)?([^.]+)\.blob\.core([^?]*)?([^.]*)" | Out-Null

$storageAccountName = $Matches[2]
$sasToken = $Matches[4]

## Function to dlownload all blob contents  
Function DownloadBlobContents  
{  
    Write-Host -ForegroundColor Green "Download blob contents from storage container.."    
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken

    ## check if folder exists
    $destination=$DownloadLocation+"\"+$StorageContainerName 
    $folderExists=Test-Path -Path $destination 

    if($folderExists)  
    {  
        Write-Host -ForegroundColor Magenta $StorageContainerName "- folder exists"    
    }  
    else  
    {        
        Write-Host -ForegroundColor Magenta $StorageContainerName "- folder does not exist"  
        ## Create the new folder  
        New-Item -ItemType Directory -Path $destination               
    }    
    
    ## Get the blob contents from the container  
    $blobContents=Get-AzStorageBlob -Container $StorageContainerName  -Context $ctx  

    $counter = 0
    foreach($blobContent in $blobContents)  
    {  
        $counter++
        $percentComplete = (($counter / $blobContents.count) * 100)
        Write-Progress -Activity "Downloading $($blobContent.Name)" -PercentComplete $percentComplete
        Write-Output "##vso[task.setprogress value=$percentComplete]Percent Complete: $percentComplete%"
        ## Download the blob content  
        Get-AzStorageBlobContent -Container $StorageContainerName  -Context $ctx -Blob $blobContent.Name -Destination $destination -Force | Out-Null
    } 
}   
  
DownloadBlobContents  
 
## Disconnect from Azure Account  
Disconnect-AzAccount