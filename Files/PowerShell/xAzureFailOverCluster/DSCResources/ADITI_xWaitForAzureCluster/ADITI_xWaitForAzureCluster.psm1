#
# xWaitForAzureCluster: DSC Resource that will wait for given name of Cluster, it checks the state of the cluster for given # interval until the cluster is #  found or the number of retries is reached.
#

#
# The Get-TargetResource cmdlet.
#
function Get-TargetResource
{
    param
    (	
        [parameter(Mandatory)]
        [string] $Name,
		
		[UInt32] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 50,
        
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    @{
        Name = $Name
        RetryIntervalSec = $RetryIntervalSec
        RetryCount = $RetryCount
    }
}

#
# The Set-TargetResource cmdlet.
#
function Set-TargetResource
{
    param
    (	
        [parameter(Mandatory)]
        [string] $Name,

		[UInt32] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 50,
        
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )    

    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential        		
			
		for ($count = 0; $count -lt $RetryCount; $count++)
		{
            $clusterFound = CheckIfClusterExists -ClusterName $Name
			if ($clusterFound)
			{
				Write-Verbose -Message "Found cluster $Name"
				break;
			}
				
			Write-Verbose -Message "Cluster $Name not found. Will retry again after $RetryIntervalSec sec"
			Start-Sleep -Seconds $RetryIntervalSec
		}
    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }
	
	if (!$clusterFound)
    {
        throw "Cluster $Name not found after $count attempts with $RetryIntervalSec sec interval"
    }
}

# 
# Test-TargetResource
#
function Test-TargetResource  
{
    param
    (	
        [parameter(Mandatory)]
        [string] $Name,

		[UInt32] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 50,
        
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    # Set-TargetResource is idempotent.. return false
    return $false
}


function Get-ImpersonatetLib
{
    if ($script:ImpersonateLib)
    {
        return $script:ImpersonateLib
    }

    $sig = @'
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);

[DllImport("kernel32.dll")]
public static extern Boolean CloseHandle(IntPtr hObject);
'@ 
   $script:ImpersonateLib = Add-Type -PassThru -Namespace 'Lib.Impersonation' -Name ImpersonationLib -MemberDefinition $sig 

   return $script:ImpersonateLib
    
}

function ImpersonateAs([PSCredential] $cred)
{
    [IntPtr] $userToken = [Security.Principal.WindowsIdentity]::GetCurrent().Token
    $userToken
    $ImpersonateLib = Get-ImpersonatetLib

    $bLogin = $ImpersonateLib::LogonUser($cred.GetNetworkCredential().UserName, $cred.GetNetworkCredential().Domain, $cred.GetNetworkCredential().Password, 
    9, 0, [ref]$userToken)
    
    if ($bLogin)
    {
        $Identity = New-Object Security.Principal.WindowsIdentity $userToken
        $context = $Identity.Impersonate()
    }
    else
    {
        throw "Can't Logon as User $cred.GetNetworkCredential().UserName."
    }
    $context, $userToken
}

function CloseUserToken([IntPtr] $token)
{
    $ImpersonateLib = Get-ImpersonatetLib

    $bLogin = $ImpersonateLib::CloseHandle($token)
    if (!$bLogin)
    {
        throw "Can't close token"
    }
}

function CheckIfClusterExists([string] $ClusterName)
{
    $cluster = Get-Cluster -ErrorAction Ignore
    if ($cluster -ne $null -and $cluster.Name -eq $ClusterName)
    {
        return $true
    }
    if($cluster -eq $null)
    {
        $ComputerInfo = Get-WmiObject Win32_ComputerSystem
		if (($ComputerInfo -eq $null) -or ($ComputerInfo.Domain -eq $null))
		{
			Write-Verbose -Message "Can't find machine's domain name"
			return $false;
		}
        $cluster = Get-Cluster -Name $ClusterName -Domain $ComputerInfo.Domain -ErrorAction Ignore
        if($cluster -ne $null)
        {
            return $true
        }
    }
    return $false
}