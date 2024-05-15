#---------------------------------------------------------------------------
# Name:        ImportDatabase.ps1
#
# Summary:     This script will take a BACPAC file and import it into the
#              selected environment database. Process will first Upload the
#              BACPAC file to the Azure Blob Storage, then deploy it using DirectDeploy.
#
# Last Updated: 5/15/2024
#
# Author: Eric Markson - eric@optimizelyvisuals.dev | eric@ericmarkson.com | https://optimizelyvisuals.dev/
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
    [Parameter(Position=3)]
    [ValidateNotNullOrEmpty()]
    [string]$ArtifactPath,
    [Parameter(Position=4)]
    [ValidateScript({
      If ($_ -match "^(Integration|Preproduction|Production|ADE\d+)$") {
        $True
      }
      else {
        Throw "Valid environment names are Integration, Preproduction, Production, or ADE#"
      }})]
    [string]$TargetEnvironment,
    [Parameter(Position=5, Mandatory)]
    [ValidateSet('cms','commerce')]
    [String] $DatabaseName
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
if($DirectDeploy -eq $true -and $TargetEnvironment.ToLower() -ne "integration"){
    throw "Direct Deploy only works for deployments to the Integration environment."
}

Write-Warning "If this environment has code on it, this can be destructive."

$confirmation = Read-Host "Do you want to proceed? 'y' to continue. 'n' to quit"
if ($confirmation.ToLower() -ne 'y') {
    exit
}
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Push-Location $dir

.\UploadEpiPackage.ps1 -ClientKey $ClientKey -ClientSecret $ClientSecret -ProjectID $ProjectID -ArtifactPath $ArtifactPath

.\DeployToEnvironment.ps1 -ClientKey $ClientKey -ClientSecret $ClientSecret -ProjectID $ProjectID -ArtifactPath $ArtifactPath -TargetEnvironment $TargetEnvironment -DirectDeploy $true -UseMaintenancePage $false

Pop-Location