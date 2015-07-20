
[Array] $dataCenterList = @( Get-Datacenter | Sort-Object -Property Name );

foreach ( $dataCenter in $dataCenterList )
{
    [Array] $clusterList = @( Get-Cluster -Location $dataCenter | Sort-Object -Property Name );

    foreach ( $cluster in $clusterList )
    {
        [Array] $hostList = @( Get-VMHost -Location $cluster | Sort-Object -Property Name );

        # TODO Wrap into a function.
        foreach ( $vmHost in $hostList )
        {
            # NTP code based on some info found on this blog: https://psvmware.wordpress.com/tag/generate-report-on-vmhost-esx-esxi-date-time-using-powercli/
            $vmHostDateTimeSystem   = Get-View -Id $vmHost.ExtensionData.ConfigManager.DateTimeSystem;
            $vmHostServiceSystem    = Get-View -Id $vmHost.ExtensionData.ConfigManager.ServiceSystem;
            $vmHostNtpService       = $vmHostServiceSystem.ServiceInfo.Service | ? { $_.Key -eq 'ntpd' };
            
            if ( $vmHostNtpService.Running -eq $True ) 
            { 
                $vmHostNtpServiceStatus = "Running";
            } 
            else 
            { 
                $vmHostNtpServiceStatus = "Not Running";
            }

            # Info on getting HA status: https://communities.vmware.com/message/2463493
            $vmHostDasHostState = $vmHost.ExtensionData.Runtime.DasHostState.State;

            if ( $vmHostDasHostState -eq "connectedToMaster" )
            {
                $vmHostDasHostStateOutput = "Connected (Slave)";
            }
            elseif ( $vmHostDasHostState -eq "master" )
            {
                $vmHostDasHostStateOutput = "Running (Master)";
            }
            else
            {
                # Unknown HA Status String, Capture As-Is
                $vmHostDasHostStateOutput = $vmHostDasHostState;
            }

            $vmHostPowerSystem = Get-View -Id $vmHost.ExtensionData.ConfigManager.PowerSystem;
            $vmHostPowerProfile = $vmHostPowerSystem.Info.CurrentPolicy.ShortName;

            switch ( $vmHostPowerProfile )
            {
                "static"  { $vmHostPowerProfileOutput = "High Performance (static)"; }
                "dynamic" { $vmHostPowerProfileOutput = "Balanced (dynamic)";        }
                "low"     { $vmHostPowerProfileOutput = "Low Power (low)";           }
                "custom"  { $vmHostPowerProfileOutput = "Custom (custom)";           }
                default   { $vmHostPowerProfileOutput = $vmHostPowerProfile;         }
            }

            # Info on getting ESXi image profile name: http://www.virtuallyghetto.com/2013/06/quick-tip-listing-image-profiles-from.html
            $vmHostEsxCli = Get-EsxCli -VMHost $vmHost;
            $vmHostImageProfileName = $vmHostEsxCli.software.profile.get().Name;
            $vmHostImageAcceptanceLevel = $vmHostEsxCli.software.acceptance.get();

            [Object] $reportOutput = New-Object System.Object;

            $reportOutput | Add-Member -MemberType NoteProperty -Name "Data Center" -Value $dataCenter.Name;
            # TODO: Add vCenter Version to Output
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Cluster"          -Value $cluster.Name;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "VMHost"           -Value $vmHost.Name;
            # TDOD: Lookup human-readable outputs for ConnectionState and PowerState to improve reporting.
            $reportOutput | Add-Member -MemberType NoteProperty -Name "ConnectionState"  -Value $vmHost.ExtensionData.Runtime.ConnectionState;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "PowerState"       -Value $vmHost.ExtensionData.Runtime.PowerState;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Boot Time"        -Value $vmHost.ExtensionData.Runtime.BootTime;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Hardware"         -Value ( $vmHost.Manufacturer + " " + $vmHost.Model );
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Version"           -Value $vmHost.Version;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Build"            -Value $vmHost.Build;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "NumCpu"           -Value $vmHost.NumCpu;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Cpu"              -Value $vmHost.ProcessorType;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Hyperthreading"   -Value $vmHost.HyperthreadingActive;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Power Profile"    -Value $vmHostPowerProfileOutput;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "EVC Mode"         -Value $vmHost.MaxEVCMode;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "MemoryGB"         -Value ( [Math]::Round( $vmHost.MemoryTotalGB, 0 ) );
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Timezone"         -Value $vmHost.ExtensionData.Config.DateTimeInfo.TimeZone.Name;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "DateTime"         -Value $vmHostDateTimeSystem.QueryDateTime();
            $reportOutput | Add-Member -MemberType NoteProperty -Name "NTP Status"       -Value $vmHostNtpServiceStatus;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "NTP Servers"      -Value $vmHost.ExtensionData.Config.DateTimeInfo.NtpConfig.Server;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "HA Status"        -Value $vmHostDasHostStateOutput;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Image Profile"    -Value $vmHostImageProfileName;
            $reportOutput | Add-Member -MemberType NoteProperty -Name "Acceptance Level" -Value $vmHostImageAcceptanceLevel;

            # TODO: Add Host Profile Name ... Have to combine Host-ID from each ESXi host with Get-VMHostProfile (which returns an array of host profiles), iterate through each host profile
            # and find the one that has a matching Host-ID via .ExtensionData.Entity (array.)

            $reportOutput;

            
        }
    }
    
    # TODO Get standalone hosts that are not a member of any cluster ... 
    [Array] $standaloneHostList = @();
}

# TODO: Review vCheck Script

# 4 TODO: Add ESXi Service / Firewall Settings ... $vmHost.ExtensionData.ConfigManager.FirewallSystem
# 2 TODO: Get ESXi Host Networking
# 3 TODO: Get ESXi Host Storage Mapping

# 1 TODO: Get ESXi Host VIB / Driver Info ....
    # Use Get-ESXCli ... $esxcli.software.vib.list() | Select-Object -Property Name, Version, Vendor, InstallDate, AcceptanceLevel
    # Flatten on per host / cluster basis to make it easier to compare VIBs installed per host.
    # Possible issue is need to build a comprehensive list of VIBs across all hosts to build column headers.

# 6 TODO: Get cluster properties.
# 7 TODO: Get vCenter properties.

# TODO: Modules / solutions to send output to Excel / Spreadsheet.

# 5 TODO: Get ESXi Host Advanced Settings
    # Issue to consider ... different patch levels can introduce new advanved settings ... e.g. TPS changes added new settings not found in earlier versions.
    # ExtensionData.Config.Option

# TODO: Get ESXi Hardware Health Status
    # $vmHostView.ExtensionData.Runtime.HealthSystemRuntime.SystemHealthInfo.NumericSensorInfo