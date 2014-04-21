#
# xAzureCluster: DSC resource to configure quorum of Failover Cluster consisting of Windows Azure VMs.
#

#
# The Get-TargetResource cmdlet.
#
function Get-TargetResource
{
    param
    (	
        [parameter(Mandatory)]
        [string] $QuorumShare,        	
		
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )
     
    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
		$quorum = Get-ClusterQuorum	
		$quorumType = $quorum.QuorumType
		$quorumResource = $quorum.QuorumResource
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
	
	@{ 
		QuorumType = $quorumType
		QuorumResource = $quorumResource
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
        [string] $QuorumShare,		
        
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )
    
    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
		Set-ClusterQuorum -NodeAndFileShareMajority $QuorumShare
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
}

# 
# Test-TargetResource
#
function Test-TargetResource  
{
    param
    (              
		[parameter(Mandatory)]
        [string] $QuorumShare,
		
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )
    
	$bRet = $false
	try
	{
		($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
		$quorum = Get-ClusterQuorum -ErrorAction Ignore
		if($quorum -and $quorum.QuorumType -eq [Microsoft.FailoverClusters.PowerShell.ClusterQuorumType]::NodeAndFileShareMajority)
		{
			$bRet = $true
		}		
	}
	catch
    {
        Write-Verbose -Message "Cluster quorum $QuorumShare is NOT present with Error $_.Message"
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

    return $bRet
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