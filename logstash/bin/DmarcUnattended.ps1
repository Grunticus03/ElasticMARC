#Set variables on lines 5,7,9,11,13,15 - retain double quotes.
#Ingested files are not deleted until 10 minutes after they've been written to disk.

#Email address of mailbox to connect to.
$MailboxName = "DMARC_RUA@example.com"
#FQDN of CAS server.
$urireq = "https://mail.example.com"
#Where to save attachments.
$downloadDirectory = "D:\Temp\Attachments"
#Where to save extracted XML files.
$outfile = "D:\Temp\Extracted"
#Where to save modified XML files.
$Ingest = "D:\Temp\DMARC"
#Where emails will be read from.
$FolderToRead = "DMARC"

###########Download messages from mailbox###########
$Provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$Compiler=$Provider.CreateCompiler()
$Params=New-Object System.CodeDom.Compiler.CompilerParameters
$Params.GenerateExecutable=$False
$Params.GenerateInMemory=$True
$Params.IncludeDebugInformation=$False
$Params.ReferencedAssemblies.Add("System.DLL") | Out-Null
$TASource=@'
    namespace Local.ToolkitExtensions.Net.CertificatePolicy{
        public class TrustAll : System.Net.ICertificatePolicy {
            public TrustAll() {
            }
            public bool CheckValidationResult(System.Net.ServicePoint sp,
            System.Security.Cryptography.X509Certificates.X509Certificate cert,
            System.Net.WebRequest req, int problem) {
                return true;
            }
        }
    }
'@
$TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
$TAAssembly=$TAResults.CompiledAssembly
$TrustAll=$TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
[System.Net.ServicePointManager]::CertificatePolicy=$TrustAll
if ((Test-Path "C:\Program Files\Microsoft\Exchange\Web Services\2.2\Microsoft.Exchange.WebServices.dll") -eq $true) {
    $API22 = $true
    Add-Type -Path "C:\Program Files\Microsoft\Exchange\Web Services\2.2\Microsoft.Exchange.WebServices.dll"
}
if ($API22 -ne $true -and (Test-Path "C:\Program Files\Microsoft\Exchange\Web Services\1.2\Microsoft.Exchange.WebServices.dll") -eq $true) {
    $API12= $true
    Add-Type -Path "C:\Program Files\Microsoft\Exchange\Web Services\1.2\Microsoft.Exchange.WebServices.dll"
}
if ($API22 -ne $true -and $API12 -ne $true) {
    Exit
}

# Commented out because 365 Cloud doesn't have/use
#$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2013_SP1
$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService()
$uri = [System.URI] "$urireq/ews/Exchange.asmx"
$service.Url = $uri
#$Sfha = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::HasAttachments, $true)

#Find and bind to selected folder
$fvFolderView = new-object Microsoft.Exchange.WebServices.Data.FolderView(1)
$fvFolderView.PropertySet = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.Webservices.Data.BasePropertySet]::FirstClassProperties)
$fvFolderView.PropertySet.Add([Microsoft.Exchange.Webservices.Data.FolderSchema]::DisplayName)
$fvFolderView.Traversal = [Microsoft.Exchange.Webservices.Data.FolderTraversal]::Deep
$SfSearchDMARC = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.FolderSchema]::DisplayName,$FolderToRead)
$FindDMARC = $service.FindFolders($tfTargetFolder.Id,$SfSearchDMARC,$fvFolderView)
$DMARC = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service,$FindDMARC.id)

#Find untagged e-mails to retrieve attachments and copy them to the download directory
$ivItemView = New-Object Microsoft.Exchange.WebServices.Data.ItemView(1)
$ivItemView.OrderBy.Add([Microsoft.Exchange.Webservices.Data.ItemSchema]::DateTimeReceived, [Microsoft.Exchange.Webservices.Data.SortDirection]::Ascending)
$CategoryToFind = "RUA:Treated"
$aqs = "NOT System.Category:'" + $CategoryToFind + "'"
$findItemsResults = $service.FindItems($DMARC.Id,$aqs,$ivItemView)
[Collections.Generic.List[String]]$RUAtreated = "RUA:Treated"

if ((Test-Path $downloadDirectory) -eq $false) {
    New-Item -ItemType Directory -Force -Path $downloadDirectory | Out-Null
}

#Loop through all e-mails found without "RUA:Treated" category/tag
do {
    foreach($miMailItems in $findItemsResults.Items){
        #Bind to each message - changing category tags require this
        $eachMessage = [Microsoft.Exchange.WebServices.Data.Item]::Bind($service,$miMailItems.Id.UniqueId)
        #Loop through attachments and save them to $downloadDirectory
        foreach($attach in $eachMessage.Attachments){
            $attach.Load()
            $filename = $downloadDirectory + "\" + $attach.Name.ToString()
            $fiFile = new-object System.IO.FileStream($filename, [System.IO.FileMode]::Create)
            $fiFile.Write($attach.Content, 0, $attach.Content.Length)
            $fiFile.Close()
        }
        #Add category tag for "RUA:Treated", mark as read and update
        $eachMessage.Categories = $RUAtreated
        $eachMessage.IsRead = $true
        $eachMessage.Update([Microsoft.Exchange.WebServices.Data.ConflictResolutionMode]::AlwaysOverwrite)
        $findItemsResults = $service.FindItems($DMARC.Id,$aqs,$ivItemView)
    }
} while ($findItemsResults.MoreAvailable -eq $true)

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
if ((Test-Path $outfile) -eq $false) {
    New-Item -ItemType Directory -Force -Path $outfile | Out-Null
}
foreach ($file in $degz) {
    $of = $file.name.Replace(".xml.gz","")
    DeGZip-File  $downloadDirectory\$file $outfile\$of".xml"
}
foreach ($infile in $dezip) {
    Expand-Archive -Path $downloadDirectory\$infile -DestinationPath $outfile
}
###########Modify XML Files###########
if ((Test-Path $Ingest) -eq $false) {
    New-Item -ItemType Directory -Force -Path $Ingest | Out-Null
}
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
    $xml.Save("$Ingest\$xmlfile")
}
###########File Cleanup###########
Get-ChildItem $downloadDirectory | Where-Object {$_.name -match ".*\.gz$|.*\.zip$"} | Remove-Item -Force -Confirm:$false
$dlc = Get-ChildItem $downloadDirectory
if ($dlc.count -lt 1) {
    Remove-Item $downloadDirectory
}
Get-ChildItem $outfile | Where-Object {$_.name -match ".*\.xml$"} | Remove-Item -Force -Confirm:$false
$dcx = Get-ChildItem $outfile
if ($dcx.count -lt 1) {
    Remove-Item $outfile
}
#Deletes files from the ingest folder that are older than 10 minutes
Get-ChildItem $ingest | Where-Object {$_.name -match ".*\.xml$" -and $_.LastWriteTime -lt ((Get-Date).AddMinutes(-10))} | Remove-Item -Force -Confirm:$false
