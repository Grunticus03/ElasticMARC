#Email address to retrieve aggregate reports from, user running process must have Full Access rights to mailbox.
$MailboxName = Read-Host "E-mail address of aggregate mailbox"
#FQDN to a CAS server, CAS array URL works.
$urireq = Read-Host "Enter FQDN to CAS(https://mail.example.com)"
$downloadDirectory = Read-Host "Path to save attachments to"
$outfile = Read-Host "Path to save extracted files"
$Ingest = Read-Host "Path to save modified XML reports"
$FolderDest = Read-Host "Name of mailbox folder to move message to (must exist)"
$Cleanup = Read-Host "Cleanup attachments and unmodified reports? (y|n)"
Clear-Host
###########Download messages from mailbox###########
#Accept any certificates presented by the CAS

#Create a compilation environment
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

#We now create an instance of the TrustAll and attach it to the ServicePointManager
$TrustAll=$TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
[System.Net.ServicePointManager]::CertificatePolicy=$TrustAll

#Load the EWS API and connect to the CAS/EWS
#EWS API is found at: https://www.microsoft.com/en-us/download/details.aspx?id=42951
#Load Managed API dll
if ((Test-Path "C:\Program Files\Microsoft\Exchange\Web Services\2.2\Microsoft.Exchange.WebServices.dll") -eq $true) {
  $API22 = $true
  Add-Type -Path "C:\Program Files\Microsoft\Exchange\Web Services\2.2\Microsoft.Exchange.WebServices.dll"
  Write-Host "EWS API 2.2 loaded"
}
if ($API22 -ne $true -and (Test-Path "C:\Program Files\Microsoft\Exchange\Web Services\1.2\Microsoft.Exchange.WebServices.dll") -eq $true) {
  $API12= $true
  Add-Type -Path "C:\Program Files\Microsoft\Exchange\Web Services\1.2\Microsoft.Exchange.WebServices.dll"
  Write-Host "EWS API 1.2 loaded"
}
if ($API22 -ne $true -and $API12 -ne $true) {
  Write-Host "EWS API not detected, quitting in five seconds..."
  Write-Host "EWS API 2.2 can be downloaded from https://www.microsoft.com/en-us/download/details.aspx?id=42951"
  Start-Sleep -Seconds 5
  Exit
}

#Set Exchange Version (Values found here: https://msdn.microsoft.com/en-us/library/microsoft.exchange.webservices.data.exchangeversion(v=exchg.80).aspx)
$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2013_SP1

#Create Exchange Service Object
$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService($ExchangeVersion)

#Set Credentials to use two options are available Option 1 to use explicit credentials or Option 2 use the Default (logged On) credentials
#Credentials Option 1 using UPN for the windows Account
#$creds = New-Object System.Net.NetworkCredential("USERNAME","PASSWORD","DOMAIN")
#$service.Credentials = $creds

#Credentials Option 2
#service.UseDefaultCredentials = $true

#Set the URL of the CAS (Client Access Server) to use three options are available to use Autodiscover to find the CAS URL, Hardcode the CAS to use, or
#prompt user for FQDN.
#Specify mailbox to connect to - Moved to line 1

#CAS URL Option 1 Autodiscover
#$service.AutodiscoverUrl($MailboxName,{$true})
#"Using CAS Server : " + $Service.url

#CAS URL Option 2 Hardcoded
#$uri=[system.URI] "https://owa.stlouisco.com/ews/Exchange.asmx"
#$service.Url = $uri

#CAS URL Option 3 User Prompt
#Moved to line 2
$uri = [System.URI] "$urireq/ews/Exchange.asmx"
$service.Url = $uri

#Bind to the Inbox folder
$Sfha = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.EmailMessageSchema]::HasAttachments, $true)
$folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox,"$MailboxName")
$Inbox = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service,$folderid)

#Find attachments and copy them to the download directory
$ivItemView = New-Object Microsoft.Exchange.WebServices.Data.ItemView(200)
#Moved to line 3
if ((Test-Path $downloadDirectory) -eq $false) {
  New-Item -ItemType Directory -Force -Path $downloadDirectory | Out-Null
}
$findItemsResults = $Inbox.FindItems($Sfha,$ivItemView)
foreach($miMailItems in $findItemsResults.Items){
    $miMailItems.Load()
    foreach($attach in $miMailItems.Attachments){
        $attach.Load()
        $fiFile = new-object System.IO.FileStream(($downloadDirectory + "\" + $attach.Name.ToString()), [System.IO.FileMode]::Create)
        $fiFile.Write($attach.Content, 0, $attach.Content.Length)
        $fiFile.Close()
        $i++
        Write-Progress -activity "Downloading attachments..." -status "Downloaded: $i of $($findItemsResults.Subject.Count)"
    }
}

#This section moves emails from the Inbox to a subfolder of "Inbox" called "Review Completed", make sure to create the folder.
#Get the ID of the folder to move to
#Moved to line 4
$fvFolderView =  New-Object Microsoft.Exchange.WebServices.Data.FolderView(100)
$fvFolderView.Traversal = [Microsoft.Exchange.WebServices.Data.FolderTraversal]::Shallow;
$SfSearchFilter = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.FolderSchema]::DisplayName,"$FolderDest")
$findFolderResults = $Inbox.FindFolders($SfSearchFilter,$fvFolderView)

#Define ItemView to retrieve just 200 Items
$ivItemView =  New-Object Microsoft.Exchange.WebServices.Data.ItemView(200)
$fiItems = $null
do
{
    $fiItems = $Inbox.FindItems($Sfha,$ivItemView)
    #[Void]$service.LoadPropertiesForItems($fiItems,$psPropset)
    foreach($Item in $fiItems.Items) {
        #Mark item as read
        $Item.IsRead = $true
        $item.Update("AlwaysOverwrite")
        #Move the Message
        $Item.Move($findFolderResults.Folders[0].Id) | Out-Null
        $p++
        Write-Progress -activity "Moving messages" -status "Moved: $p of $($fiItems.Subject.Count)"
    }
    $ivItemView.Offset += $fiItems.Items.Count
}while($fiItems.MoreAvailable -eq $true)


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
