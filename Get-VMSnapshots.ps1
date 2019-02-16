Param
(
    [Array]        $Server,
    [PSCredential] $Credential,
    [String]       $VM,
    [String]       $VMHost,
    [String]       $Cluster,
    [String]       $Datacenter,
    [String]       $EmailServer,
    [Int32]        $EmailServerPort = 25,
    [Array]        $EmailReceipients
)

Function Get-VMFolderPath( [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine] $VirtualMachine, [Switch] $ExcludeHiddenRootFolder )
{
    [String] $folderInterface = "VMware.VimAutomation.ViCore.Types.V1.Inventory.Folder";
    [Array]  $folderList = @();

    $currentInventoryOjbect = $virtualMachine.Folder;

    # Stop when current inventory object is of type VMware.VimAutomation.ViCore.Types.V1.Inventory.Datacenter
    # Continue as long as current inventory object is of type VMware.VimAutomation.ViCore.Types.V1.Inventory.Folder

    while ( $currentInventoryOjbect -is $folderInterface )
    {
        $folderList += $currentInventoryOjbect;
        $currentInventoryOjbect = $currentInventoryOjbect.Parent;
    }

    [Array]::Reverse( $folderList );

    [String] $fullFolderPath = "";

    foreach ( $folderItem in $folderList )
    {
        if ( $ExcludeHiddenRootFolder -and ($folderItem.Name -eq "vm") -and ($folderItem.Parent -is [VMware.VimAutomation.ViCore.Types.V1.Inventory.Datacenter]) )
        {
            continue;
        }

        $fullFolderPath = $fullFolderPath + "/" + $folderItem.Name;
    }

    return $fullFolderPath;
}

$ErrorActionPreference = "Continue";

# Collection of all VM snapshot records from all specified vCenter servers.
[Array] $outputList = @();

foreach ( $serverItem in $Server )
{
    if ( $Credential )
    {
        $vCenterServer = Connect-VIServer -Server $serverItem -Credential $Credential;
    }
    else
    {
        $vCenterServer = Connect-VIServer -Server $serverItem;
    }

    # Capture vCenter Name for applicable output records.
    $vCenterServerName = $Global:DefaultVIServer.Name;

    # Compile list of VMs to check based on parameters specified.
    [Array] $vmList = @();

    if ( $VM )
    {
        $vmList = @( Get-VM -Name $VM );
    }
    elseif ( $VMHost )
    {
        $vmList = @( Get-VM -Location (Get-VMHost -Name $VMHost) );
    }
    elseif ( $Cluster )
    {
        $vmList = @( Get-VM -Location (Get-Cluster -Name $Cluster) );
    }
    elseif ( $Datacenter )
    {
        $vmList = @( Get-VM -Location (Get-Datacenter -Name $Datacenter) );
    }
    else
    {
        $vmList = @( Get-VM );
    }

    $vmList = $vmList | Sort-Object -Property Name;

    foreach ( $vmItem in $vmList )
    {
        [Array] $vmSnapshotList = @( Get-Snapshot -VM $vmItem );

        if ( $vmSnapshotList.Count -gt 0 )
        {
            $vmCluster = Get-Cluster -VM $vmItem;
            $vmFolder  = Get-VMFolderPath -VirtualMachine $vmItem -ExcludeHiddenRootFolder;

            foreach ( $snapshotItem in $vmSnapshotList )
            {
                $vmProvisionedSpaceGB = [Math]::Round( $vmItem.ProvisionedSpaceGB, 2 );
                $vmUsedSpaceGB        = [Math]::Round( $vmItem.UsedSpaceGB,        2 );
                $snapshotSizeGB       = [Math]::Round( $snapshotItem.SizeGB,       2 );
                $snapshotAgeDays      = ( (Get-Date) - $snapshotItem.Created ).Days;

                $output = New-Object -TypeName PSObject;

                $output | Add-Member -MemberType NoteProperty -Name VM                 -Value $vmItem;
                $output | Add-Member -MemberType NoteProperty -Name Folder             -Value $vmFolder;
                $output | Add-Member -MemberType NoteProperty -Name Cluster            -Value $vmCluster;
                $output | Add-Member -MemberType NoteProperty -Name Server             -Value $vCenterServerName;
                $output | Add-Member -MemberType NoteProperty -Name Snapshot           -Value $snapshotItem.Name;
                $output | Add-Member -MemberType NoteProperty -Name Description        -Value $snapshotItem.Description;
                $output | Add-Member -MemberType NoteProperty -Name Created            -Value $snapshotItem.Created;
                $output | Add-Member -MemberType NoteProperty -Name AgeDays            -Value $snapshotAgeDays;
                $output | Add-Member -MemberType NoteProperty -Name ParentSnapshot     -Value $snapshotItem.ParentSnapshot.Name;
                $output | Add-Member -MemberType NoteProperty -Name IsCurrentSnapshot  -Value $snapshotItem.IsCurrent;
                $output | Add-Member -MemberType NoteProperty -Name SnapshotSizeGB     -Value $snapshotSizeGB;
                $output | Add-Member -MemberType NoteProperty -Name ProvisionedSpaceGB -Value $vmProvisionedSpaceGB;
                $output | Add-Member -MemberType NoteProperty -Name UsedSpaceGB        -Value $vmUsedSpaceGB;
                $output | Add-Member -MemberType NoteProperty -Name PowerState         -Value $snapshotItem.PowerState;

                $outputList += $output;

                $output;
            }
        }
    }

    Disconnect-VIServer -Server $vCenterServer -Confirm:$False -ErrorAction SilentlyContinue;
}

if ( $outputList.Count -gt 0 -and $EmailServer -and $EmailReceipients )
{
    # Reference: https://technet.microsoft.com/en-us/library/ff730936.aspx for help with formatting an Array of PowerShell objects
    # into an HTML table and adjusting the CSS style of the table and injecting content into the HTML body just above the the table.

    $htmlHeader = "<style>";
    $htmlHeader = $htmlHeader + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}";
    $htmlHeader = $htmlHeader + "TH{text-align: left;border-width: 1px;padding: 3px;border-style: solid;border-color: black;}";
    $htmlHeader = $htmlHeader + "TD{text-align: left;border-width: 1px;padding: 3px;border-style: solid;border-color: black;}";
    $htmlHeader = $htmlHeader + "</style>";

    $htmlBodyHeader = "<h3>VM Snapshot Report</h3>";
    $htmlBodyHeader = $htmlBodyHeader + "The following VMs were detected having snapshots. Review and maintain awareness of any large or very old snapshots. ";
    $htmlBodyHeader = $htmlBodyHeader + "VMware's guidance of snapshots, reference <a href=`"https://kb.vmware.com/s/article/1025279`">VMware KB 1025279.</a> ";
    $htmlBodyHeader = $htmlBodyHeader + "Note that snapshots on vSAN have a different architecture than block-storage SAN, and therefore the best practices ";
    $htmlBodyHeader = $htmlBodyHeader + "from KB 1025279 are not all applicable to vSAN sparse-based snapshots.<br><br>";

    $body = $outputList | ConvertTo-Html -Head $htmlHeader -Body $htmlBodyHeader | Out-String -Width 2048;
    
    Send-MailMessage -SmtpServer $EmailServer                   `
                     -Port       $EmailServerPort               `
                     -From       "snapshot-admin@vsphere.local" `
                     -To         $EmailReceipients              `
                     -Subject    "VM Snapshot Report"           `
                     -Body       $body                          `
                     -BodyAsHtml;
}