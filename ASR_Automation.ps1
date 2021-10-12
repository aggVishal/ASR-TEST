$serverType = read-host "Are you running this script on Host Server or a remote server (HS/RS)"
$serverType = $serverType.ToLower()

# Variables entered by user
if($serverType -eq 'hs'){
    $locationOfTool = Read-Host "Enter the directory location (remote or local) where you want to download the ASR Deployment Planner Tool"
    $hostUsername = Read-Host "Enter account username"
    $hostPassword = Read-Host "Enter account password"
    $hostname = hostname
}
if($serverType -eq 'rs'){
    $hostname = Read-Host "Enter host server name (example: HOST01)"
    $locationOfTool = Read-Host "Enter the remote directory location where you want to download the ASR Deployment Planner Tool (example: \\DC01\sampleFolder)"
    $hostUsername = Read-Host "Enter account username (Account should have read/write access to remote directory. Example: domain\user1)"
    $hostPassword = Read-Host "Enter account password"

    $ExistingAcl1 = (Get-Acl $locationOfTool).Access
    $flag = $false
    foreach ($entry in $ExistingAcl1)
    {
        if ((($entry.IdentityReference -eq $user) -or ($entry.IdentityReference -eq "Everyone")) -and ($entry.FileSystemRights -eq "FullControl")){
            # write-host "Access verified for user account" $user
            $flag = $true
        }
    }
    if ($flag -eq $false){
        write-host "`nUser account does not have required access to remote directory" $locationOfTool -ForegroundColor Red
        Break
    }
}
if($serverType -ne 'rs'){
    if($serverType -ne 'hs'){
        write-host "`nPlease enter valid selection." -ForegroundColor Red
        Break
    }
}

# Variables entered by developers
$NoOfHoursToProfile = 1
$GrowthFactor = 30
$DesiredRPO = 15
$projectName = 'testProject1'
$SASToken = '?sv=2020-08-04&ss=bfqt&srt=sco&sp=rwdlacuptfx&se=2021-09-29T20:31:52Z&st=2021-09-29T12:31:52Z&spr=https&sig=hW1qsLOGlLMNKIJ347e7vqrltFKfq%2Fi%2FdrRcljNJ1bA%3D'

# PowerShell Commands
$source = 'https://aka.ms/asr-deployment-planner'
$destinationFolder = $locationOfTool
$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace “:”, “.” }
$zipName = '\ASRDeploymentPlanner-v2.52-' + $timestamp + '.zip'
$zipFile = $destinationFolder + $zipName
Invoke-RestMethod  -Uri $source -OutFile $zipFile
Expand-Archive -LiteralPath $zipFile -DestinationPath $destinationFolder -Force | Out-Null
Remove-Item -Path $zipFile -Force
$directoryLocation = $destinationFolder + '\ASRDeploymentPlanner'

Set-Location -Path $directoryLocation | Out-Null
$profiledData = $directoryLocation + '\ProfiledData'
New-Item -Path $profiledData -ItemType Directory | Out-Null
$ServerListFile = $profiledData + '\ServerListFile.txt'
Set-Content $ServerListFile $hostname | Out-Null
$VMListFile = $profiledData + '\VMListFile.txt'

.\ASRDeploymentPlanner.exe -Operation GetVMlist -Virtualization Hyper-V -Directory $profiledData -ServerListFile $ServerListFile -User $hostUsername -OutputFile $VMListFile -Password $hostPassword
.\ASRDeploymentPlanner.exe -Operation StartProfiling -Virtualization Hyper-V -Directory $profiledData -VMListFile $VMListFile -NoOfHoursToProfile $NoOfHoursToProfile -User $hostUsername -Password $hostPassword
.\ASRDeploymentPlanner.exe -Operation GenerateReport -virtualization Hyper-V -Directory $profiledData -VMListFile $VMListFile -GrowthFactor $GrowthFactor -DesiredRPO $DesiredRPO

# PowerShell Command to push the reports to Storage Account
$files = Get-ChildItem -Path $profiledData
$array = @()
foreach ($file in $files)
{
    $array=$array + $file.Name
}
$HTTPSStorageHost = "https://dfsvdzcdfs.blob.core.windows.net"
$container = "testcontainer"
foreach ($ele in $array)
{
    $name = $ele
    $path = $profiledData+'\'+$name
    $URI = "$($HTTPSStorageHost)/$($container)/$projectName/$($name)$($SASToken)"
    $header = @{
        'x-ms-blob-type' = 'BlockBlob'
    }
    Invoke-RestMethod -Method PUT -Uri $URI -Headers $header -InFile $path
}
