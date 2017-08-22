<#
.SYNOPSIS
    
.DESCRIPTION

.NOTES
    File Name  : app_deploy.ps1
    Author     : kadodds@microsoft.com
    Company    : Starbucks Corporation (Copyright (c) 2017 Starbucks Corporation. All rights reserved.)

#>

# Modules ------------------------------------------------------------------------------------------>
Import-Module AzureRM.Resources


# Helper Functions --------------------------------------------------------------------------------->
function WriteTitle($message)
{
    Write-Host "***** $($message) *****" -ForegroundColor Cyan
}

function WriteText($message)
{
    Write-Host $message -ForegroundColor Yellow
}

function WriteSuccess()
{
    Write-Host "[Done]" -ForegroundColor Green
    Write-Host
    Write-Host
}

function WriteError($message)
{
    Write-Host $message -ForegroundColor Red
}

function WriteFailure()
{
    Write-Host "[Failed]" -ForegroundColor DarkRed
    Write-Host
    Write-Host
}


# Variables ---------------------------------------------------------------------------------------->
$PathToApp = "C:\Users\kadodds\Source\Repos\CertificateDistributionTracking\install-certificate-app"
$PathToCsproj = ".\install-certificate-app.csproj"
$PathToPublishedApps = ".\bin\Release\netcoreapp2.0"
$PathToZipArchives = ".\bin\Release\netcoreapp2.0\zip-archive"
$PathToWebAppZipArchive = "\CertificateDistribution\Distribution_Apps"

$PathToWebApp = "C:\Users\kadodds\Source\Repos\CertificateDistributionTracking\CertificateDistribution"
$deploymentBranch = "master"

$certTypes = @("admin", "readonly")

# Get the Runtime Identifiers from csproj file ----------------------------------------------------->
WriteTitle("FINDING APP");
cd $PathToApp
WriteSuccess

# Get the Runtime Identifiers from csproj file ----------------------------------------------------->
WriteTitle("GETTING RUNTIME IDENTIFIERS")
WriteText("Parsing .csproj runtime identifiers")
$proj = [xml] (Get-Content -Path $PathToCsproj)
$identifiersString = [string] ($proj.Project.PropertyGroup.RuntimeIdentifiers)
$identifiersString = $identifiersString.Trim()
$identifiersArray = $identifiersString -split ";"
WriteSuccess


foreach($type in $certTypes)
{

# Set Cert type from App Settings file ------------------------------------------------------------->
WriteTitle("SETTING CERTIFICATION TYPE TO $type")
WriteText("Writing to appsettings.json")
$jsonObj = Get-Content -Path .\appsettings.json | ConvertFrom-Json 
$jsonObj.certificate_info.cert_prefix = $type
$jsonString = $jsonObj | ConvertTo-Json | Out-File -FilePath .\appsettings.json
WriteSuccess


# Adjust certificate file based on certificate type
WriteTitle("SETTING 'CopyToOutputDirectory' FOR $type CERTIFICATE")
$proj = [xml] (Get-Content -Path $PathToCsproj)
$itmGroup = $proj.Project.ItemGroup.None
foreach($itm in $itmGroup)
{
    if ($itm.Include -ne "${type}_certificate.cer" -and $itm.Include -ne "appsettings.json")
    {
        WriteText("Setting 'CopyToOutputDirectory' to Never for $itm.Include")
        $itm.CopyToOutputDirectory = "Never"
    } else 
    {
        WriteText("Setting 'CopyToOutputDirectory' to Always for $itm.Include")
        $itm.CopyToOutputDirectory = "Always"
    }
}

$proj.Save("$PathToApp\$PathToCsproj")
WriteSuccess


# restore the dependencies specified in project ---------------------------------------------------->
WriteTitle("RESTORING DEPENDENCIES")
dotnet restore
WriteSuccess 


# create debug build ------------------------------------------------------------------------------->
WriteTitle("BUILDING PROJECT")
dotnet build
WriteSuccess

# Publish according to runtime --------------------------------------------------------------------->
WriteTitle("PUBLISHING TO RUNTIMES")
foreach ($runtime in $identifiersArray) 
{
    Write-Host
    Write-Host
    WriteText("Publishing to $runtime")
    dotnet publish -c Release -r $runtime
}
WriteSuccess


# Compress published apps to distributable zip archives ------------------------------------------->
WriteTitle("COMPRESSING DISTRIBUTABLE APPS")
foreach ($runtime in $identifiersArray) 
{
    Write-Host
    Write-Host
    WriteText("Compressing $runtime app")
    Compress-Archive -Path $PathToPublishedApps\$runtime -DestinationPath $PathToZipArchives\$type\cert-install-$runtime.zip -Force
}
WriteSuccess


# Copy Zip Archives to Cert Distribution Web App -------------------------------------------------->
WriteTitle("TRANSFERING ZIP ARCHIVES TO WEB APP")
foreach ($zip in (Get-ChildItem $PathToZipArchives\$type)) 
{
    WriteText("Sending '$zip' to Web App")
    Copy-Item -Path $PathToZipArchives\$type\$zip -Destination $PathToWebApp\$PathToWebAppZipArchive\$type\
}
WriteSuccess

} # end foreach


# Change to Web App Directory --------------------------------------------------------------------->
WriteTitle("MOVING TO WEB APP")
cd $PathToWebApp
WriteSuccess


# Authenticate to GitHub
WriteTitle("CHECKING GIT")
$current = git rev-parse --abbrev-ref HEAD
WriteText("Current Branch: $current")
git status

# Check if on master branch ----------------------------------------------------------------------->
WriteTitle("CHECKING BRANCH")
If ($current -ne $deploymentBranch)
{
    WriteError("Currently on branch $current. Unable to continue.")
    WriteFailure
    exit
}

WriteText("Current branch is $deploymentBranch")
WriteSuccess


# Do pull request, check for merge conflicts ------------------------------------------------------>
WriteTitle("PERFORM GIT PULL")
git pull
WriteSuccess


# Git push changes -------------------------------------------------------------------------------->
WriteTitle("PUSH NEW DISTRIBUTION FILES")
WriteText("Adding...")
git add . 

$dateTime = Get-Date -Format g
$commitMsg = "Updating distribution files: $dateTime"

WriteText("Commiting - '$commitMsg'")
git commit -am $commitMsg

WriteText("Pushing...")
git push -q

WriteText("Status:")
git status

WriteSuccess










