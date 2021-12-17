#---------------------------------------------------------------------------
# Name:        UploadEpiPackage.ps1
#
# Summary:     This script will take an artifact from an Azure Devops
#              release and push it up to a selected environment. This is
#              developed to be used in the DevOps Release Pipeline.
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
    [string]$ArtifactPath
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

Write-Host "Validation passed. Starting Deployment"

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

#Getting the latest Azure Storage Module
$env:PSModulePath = "C:\Modules\azurerm_6.7.0;" + $env:PSModulePath

Write-Host "Searching for NUPKG file..."

#From the Artifact Path, getting the nupkg file
$packagePath = Get-ChildItem -Path $ArtifactPath -Filter *.nupkg

#If no NUPKG file is found, throw error and exit
if($packagePath.Length -eq 0){
    throw "No NUPKG files were found. Please ensure you're passing the correct path."
}

Write-Host "Package Found. Name: " $packagePath.Name



Write-Host "Setting up the deployment configuration"
#Setting up the object for the Epi Deployment. This is found in the PAAS portal settings.
$getEpiDeploymentPackageLocationSplat = @{
    ClientKey = "$ClientKey"
    ClientSecret = "$ClientSecret"
    ProjectId = "$ProjectID"
}

Write-Host "Finding deployment location..."

#Generating the Blob storage location URL to upload the package
$packageLocation = Get-EpiDeploymentPackageLocation @getEpiDeploymentPackageLocationSplat

Write-Host "Blob Location Found: " $packageLocation 
Write-Host "Starting Upload..." 

#Uploading the package to the Blob location
$deploy = Add-EpiDeploymentPackage -SasUrl $packageLocation -Path $packagePath.FullName

$deploy

Write-Host "Upload Success. Files are ready for deploy into environments."


