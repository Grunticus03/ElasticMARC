#DMARC No Mailbox Access Script
#Use this script if you are pulling DMARC aggregate reports from a non-Microsoft Exchange hosted mailbox.
#This script will decompress .zip/.gz compressed archives, modify the XML structure, and save the
#resulting file.

$downloadDirectory = Read-Host "Folder path to downloaded attachments"
$outfile = Read-Host "Folder Path to save extracted files to"
$Ingest = Read-Host "Folder Path to save modified XML reports to"
$Cleanup = Read-Host "Cleanup attachments and unmodified reports? (y|n)"
Clear-Host

###########Decompress Archives###########
Function DeGZip-File{
    Param(
        $infile,
        $outfile       
        )

    $input = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $output = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $input, ([IO.Compression.CompressionMode]::Decompress)

    $buffer = New-Object byte[](1024)
    while($true){
        $read = $gzipstream.Read($buffer, 0, 1024)
        if ($read -le 0){break}
        $output.Write($buffer, 0, $read)
        }

    $gzipStream.Close()
    $output.Close()
    $input.Close()
}
$degz = Get-ChildItem $downloadDirectory | Where-Object {$_.name -match ".*\.gz$"}
$dezip = Get-ChildItem $downloadDirectory | Where-Object {$_.name -match ".*\.zip$"}
#Moved to line 5
if ((Test-Path $outfile) -eq $false) {
  New-Item -ItemType Directory -Force -Path $outfile | Out-Null
}
foreach ($file in $degz) {
    $of = $file.name.Replace(".xml.gz","")
    DeGZip-File  $downloadDirectory\$file $outfile\$of".xml"
    $gz++
    Write-Progress -activity "Decompressing GZ files" -status "Decompressed: $gz of $($degz.Count)"
    }
foreach ($infile in $dezip) {
    Expand-Archive -Path $downloadDirectory\$infile -DestinationPath $outfile
    $gzi++
    Write-Progress -activity "Decompressing zip files" -status "Decompressed: $gzi of $($dezip.Count)"
}


###########Modify XML Files###########
#Moved to line 6
if ((Test-Path $Ingest) -eq $false) {
  New-Item -ItemType Directory -Force -Path $Ingest | Out-Null
}
#XML Restructure
$XMLRepo = Get-Childitem $outfile -Recurse | Where-Object {$_.Name -match ".*\.xml$"}
foreach ($xmlfile in $xmlrepo) {
  [xml]$xml = Get-Content -Path $xmlfile.VersionInfo.FileName
  $xmlrecord = $xml.feedback.record
  foreach ($record in $xmlrecord) {
    $xmlreport = $xml.SelectSingleNode("//feedback/report_metadata").Clone()
    $xmlpolicy = $xml.SelectSingleNode("//feedback/policy_published").Clone()
    $record.AppendChild($xmlreport) | Out-Null
    $record.AppendChild($xmlpolicy) | Out-Null
  }
  $xmlpolicy = $xml.SelectSingleNode("//feedback/policy_published")
  $xmlreport = $xml.SelectSingleNode("//feedback/report_metadata")
  $xml.feedback.RemoveChild($xmlreport) | Out-Null
  $xml.feedback.RemoveChild($xmlpolicy) | Out-Null
#Save to ingest point
  $xml.Save("$Ingest\$xmlfile")
  $xmlprogress++
  Write-Progress -activity "Modifying XML Structures" -status "Modified: $xmlprogress of $($xmlrepo.Count)"
}
Clear-Host
Write-Host "Modification process complete!"
Start-Sleep -Seconds 3

###########File Cleanup###########
#Moved to line 7
if ($cleanup -eq "y") {
    #Remove downloaded email attachments
    Get-ChildItem $downloadDirectory | Where-Object {$_.name -match ".*\.gz$|.*\.zip$"} | Remove-Item -Force -Confirm:$false
    $dlc = Get-ChildItem $downloadDirectory
    if ($dlc.count -lt 1) {
        Remove-Item $downloadDirectory
    }
    #Remove decompressed, unmodified XML files
    Get-ChildItem $outfile | Where-Object {$_.name -match ".*\.xml$"} | Remove-Item -Force -Confirm:$false
    $dcx = Get-ChildItem $outfile
    if ($dcx.count -lt 1) {
        Remove-Item $outfile
    }
}
if ($cleanup -eq "n") {
exit
}
#Remove modified XML files
$Cleanup = Read-Host "Remove modified files? (y|n)"
if ($cleanup -eq "y") {
    Get-ChildItem $ingest | Where-Object {$_.name -match ".*\.xml$"} | Remove-Item -Force -Confirm:$false
    $modx = Get-ChildItem $ingest
    if ($modx.count -lt 1) {
        Remove-Item $ingest
    }
}
Clear-Host
Write-Host "Cleanup process complete!"
Start-Sleep -Seconds 3