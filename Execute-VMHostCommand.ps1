Param
(
    [String]       $VMHost,
    [String]       $Cluster,
    [String]       $Datacenter,
    [String]       $CommandText = "esxcfg-info",
    [PSCredential] $Credential,
    [String]       $PLinkExecutablePath = "C:\Putty\plink.exe",
    [Switch]       $PLinkVerbose,
    [Switch]       $PLinkAutoAcceptHostKey
)

if ( !$Credential )
{
    $Credential = Get-Credential;
}

[Array] $vmHostList = @();

if ( $VMHost )
{
    $vmHostList = @( Get-VMHost -Name $VMHost );
}
elseif ( $Cluster )
{
    [Array] $sourceClusterList = @( Get-Cluster -Name $Cluster );

    $vmHostList = @( Get-VMHost -Location $sourceClusterList );
}
elseif ( $Datacenter )
{
    [Array] $sourceDatacenterList = @( Get-Datacenter -Name $Datacenter );

    $vmHostList = @( Get-VMHost -Location $sourceDatacenterList );
}
else
{
    $vmHostList = @( Get-VMHost );
}

$vmHostList = $vmHostList | Sort-Object -Property Name;

# Decrypt password for use with plink.exe to SSH into each ESXi host to execute the command text.  This will only live in memory and will be discarded upon completion.
# The ZeroFreeBSTR() method immediatley makes the $BSTR variable useless for decrypting the password again, should any errors occur or the user terminates the script 
# before completion and this variable is left behind in the current session.
$vmHostUser     = $Credential.UserName;
$BSTR           = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR( $Credential.Password );
$vmHostPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto( $BSTR );
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR);

# Set command line switch options for plink.exe ... only enabled ability to adjust the verbose switch via this script.\
# Syntax: plink [options] [user@]host [command]
if ( $PLinkVerbose )
{
    $verboseSwitch = "-v";
}
else
{
    $verboseSwitch = "";
}

$batchSwitch   = "-batch";
$sshSwitch     = "-ssh";

foreach ( $vmHostItem in $vmHostList )
{
    # Temporary file to capture verbose/error output from plink.exe
    $errorOutputTempFile = $env:TEMP + "\" + $vmHostItem.Name + "-err.txt"

    # Obtain the SSH service object from the ESXi host, and if not already running, start it.
    $serviceObjectFromHost = Get-VMHostService -VMHost $vmHostItem | ? { $_.Key -eq "TSM-SSH" };
    [Boolean] $sshServiceOriginallyNotRunning = $False

    if ( $serviceObjectFromHost.Running -eq $False )
    {
        $sshServiceOriginallyNotRunning = $True;
        [void] ( $serviceObjectFromHost | Start-VMHostService -Confirm:$False -ErrorAction SilentlyContinue );
    }

    # If user wishes to auto-accept the SSH host key, initiate an interactive connection and pipe a "y" to accept the host key and cache it, then immediately
    # exit the SSH session and clean up.  We "void" the output because we don't care/expect there to be any.
    if ( $PLinkAutoAcceptHostKey )
    {
        $errorOutputAutoAcceptTempFile       = $env:TEMP + "\" + $vmHostItem.Name + "-autoAcceptKey.txt"
        $pLinkAutoCacheSshFingerPrintCommand = "echo y | " + $PLinkExecutablePath + " " + $verboseSwitch + " " + $sshSwitch + " -l '" + $vmHostUser + "' -pw '" + $vmHostPassword + "' " + $vmHostItem.Name + " 'exit'";
        [void] ( Invoke-Expression -Command $pLinkAutoCacheSshFingerPrintCommand -ErrorAction SilentlyContinue 2>$errorOutputAutoAcceptTempFile );
        Remove-Item $errorOutputAutoAcceptTempFile;
    }

    # Compile plink.exe command to invoke against the current ESXi host and execute it.
    $pLinkCommand     = $PLinkExecutablePath + " " + $verboseSwitch + " " + $sshSwitch + " " + $batchSwitch + " -l '" + $vmHostUser + "' -pw '" + $vmHostPassword + "' " + $vmHostItem.Name + " '" + $CommandText + "'";
    $pLinkOutput      = Invoke-Expression -Command $pLinkCommand 2>$errorOutputTempFile;
    $pLinkDateTime    = Get-Date;
    $pLinkErrorOutput = Get-Content $errorOutputTempFile;
    Remove-Item $errorOutputTempFile; #Immediately cleanup this file after collecting contents into memory.


    # If SSH was not originally running on this ESXi host, then shutdown the service upon completion of executing the plink.exe command.  If the SSH service was
    # already started at the time this script was executed, then we can't assume the user wants the service shutdown.
    if ( $sshServiceOriginallyNotRunning )
    {
        $serviceObjectFromHost = Get-VMHostService -VMHost $vmHostItem | ? { $_.Key -eq "TSM-SSH" };
        [void] ( $serviceObjectFromHost | Stop-VMHostService -Confirm:$False -ErrorAction SilentlyContinue );
    }

    # Verbose / error output will contain the command syntax used to execute plink.exe, which would expose the password and add garbage to the output.
    # Therefore we'll cleanup the output to avoid these issues.  We must do this because capturing verbose output from plink.exe is delivered through the
    # error output pipe, which causes PowerShell to attempt to quality the "error" data and expose the original command compiled for plink.exe (thus exposing
    # the password.)
    [Array] $pLinkErrorOutputArray = @();

    if ( $pLinkErrorOutput -and $pLinkErrorOutput.length -gt 0 )
    {
        $pLinkErrorOutputArray = $pLinkErrorOutput -split "`n";
        $pLinkErrorOutputArray = $pLinkErrorOutputArray | ? { $_.trim().length -gt 0 };             # Remove all blank/empty lines
        $pLinkErrorOutputArray = $pLinkErrorOutputArray | ? { $_.trim() -notmatch "^\+" };          # Remove all PowerShell "error" output lines, which exposes the password in output
        $pLinkErrorOutputArray = $pLinkErrorOutputArray | ? { $_.trim() -notmatch "^At line:\d+" }; # Remove all codestack output lines, where PowerShell is attempting to tell you where the error occurred (even though in this case no true error likely occurred.)
    }

    # For consistency, we'll also break up the output into an array of strings, cleaning out any empty/blank lines to compress the output and improve readability
    # and parsability.
    [Array] $pLinkOutputArray = @();

    if ( $pLinkOutput -and $pLinkOutput.length -gt 0 )
    {
        $pLinkOutputArray = $pLinkOutput -split "`n";
        $pLinkOutputArray = $pLinkOutputArray | ? { $_.trim().length -gt 0 }; # Remove all blank/empty lines
    }

    [Object] $result = New-Object System.Object;

    $result | Add-Member -MemberType NoteProperty -Name VMHost      -Value $vmHostItem.Name;
    $result | Add-Member -MemberType NoteProperty -Name State       -Value $vmHostItem.ConnectionState;
    $result | Add-Member -MemberType NoteProperty -Name Output      -Value $pLinkOutputArray;
    $result | Add-Member -MemberType NoteProperty -Name ErrorOutput -Value $pLinkErrorOutputArray;
    $result | Add-Member -MemberType NoteProperty -Name DateTime    -Value $pLinkDateTime;
    $result | Add-Member -MemberType NoteProperty -Name CommandText -Value $CommandText;
    $result | Add-Member -MemberType NoteProperty -Name User        -Value $vmHostUser;

    $result;
}

# Secure cleanup, remove variables used to extract and decrypt password.
Remove-Variable -Name BSTR;
Remove-Variable -Name vmHostUser;
Remove-Variable -Name vmHostPassword;