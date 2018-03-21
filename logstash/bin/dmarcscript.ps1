#--------------------------------------------------------------------#
#-------Commented out due to unreliable archive decompression.-------#
#--------------------------------------------------------------------#
#PowerShell Version Check
#if ($PSVersionTable.PSVersion.Major -lt "5") {
#  Read-Host "PowerShell 5 required."
#  Exit
#}

#7Zip4PowerShell Check
#--------------------------------------------------------------------#
#-------Commented out due to unreliable archive decompression.-------#
#--------------------------------------------------------------------#
#[System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
#[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
#if (Get-Module 7zip4powershell -ErrorAction SilentlyContinue) {
#  Write-Host "7Zip4PowerShell already installed"
#} else {
#  Write-Host "Installing 7Zip4Powershell Module"
#  Install-Package 7zip4powershell -Force -ErrorAction SilentlyContinue
#  if (Get-Module 7zip4powershell -ErrorAction SilentlyContinue) {
#  } else {
#    Write-Host "Unable to download module."
#    Wait-Event -Timeout 3
#    Exit
#  }
#}

#User Input
Clear-Host
#--------------------------------------------------------------------#
#-------Commented out due to unreliable archive decompression.-------#
#--------------------------------------------------------------------#
#$ARoot = Read-Host "Folder containing archives"
#$FDst = Read-Host "Save extracted files to"
$FDst = Read-Host "Location of XML Files"
$Ingest = Read-Host "Save modified files to"

#--------------------------------------------------------------------#
#-------Commented out due to unreliable archive decompression.-------#
#--------------------------------------------------------------------#
#Directory Creation
#$TDst = Test-Path $FDst
$TIngest = Test-Path $Ingest
#if ($TDst -eq $false) {
#  New-Item -ItemType Directory -Force -Path $FDst | Out-Null
#}
if ($TIngest -eq $false) {
  New-Item -ItemType Directory -Force -Path $Ingest | Out-Null
}

#--------------------------------------------------------------------#
#-------Commented out due to unreliable archive decompression.-------#
#--------------------------------------------------------------------#
#Archive Decompression
#$ARepo = Get-ChildItem $ARoot | Where-Object {$_.Name -like "*.zip" -or $_.Name -like "*.gz"} | Select Name
#foreach ($AFile in $ARepo) {
#  $AName = $AFile | Select -ExpandProperty Name
#  Set-Location $FDst
#  Expand-7zip -Verbose $ARoot\$AName -TargetPath $FDst -ErrorAction Inquire
#}

#File Extension Renaming - During extraction, some file extensions were
#renamed, most likely due to name conflict resolution by 7Zip4PowerShell.
#$NameCheck = Get-Childitem $FDst | Where-Object {$_.Name -notlike "*.xml" -and $_.Mode -like "*a*"}
#foreach ($Name in $NameCheck) {
#  $Name | Rename-Item -NewName {
#  [io.path]::ChangeExtension($_.name, "")
#  }
#}

#XML Restructure
$XMLRepo = Get-Childitem $FDst -Recurse | Where-object {$_.Mode -notlike "d*"}
foreach ($xmlfile in $xmlrepo) {
  [xml]$xml = Get-Content -Path $xmlfile.VersionInfo.FileName
  $xmlrecord = $xml.feedback.record
  foreach ($record in $xmlrecord) {
    $xmlreport = $xml.SelectSingleNode("//feedback/report_metadata").Clone()
    $xmlpolicy = $xml.SelectSingleNode("//feedback/policy_published").Clone()
    $record.AppendChild($xmlreport)
    $record.AppendChild($xmlpolicy)
  }
  $xmlpolicy = $xml.SelectSingleNode("//feedback/policy_published")
  $xmlreport = $xml.SelectSingleNode("//feedback/report_metadata")
  $xml.feedback.RemoveChild($xmlreport)
  $xml.feedback.RemoveChild($xmlpolicy)
#Save to ingest point
  $xml.Save("$Ingest\$xmlfile")
}
