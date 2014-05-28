#
# xWaitForAzureClusterQuorumShare: DSC Resource that will wait for quorum file share to get created, it checks the accessibility of the cluster quorum share for given # interval until the cluster quorum share is found or the number of retries is reached.
#
# 


#
# The Get-TargetResource cmdlet.
#
function Get-TargetResource
{
    param
    (	
        [parameter(Mandatory)][string] $QuorumShare,

        [UInt64] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 50,
		
		[parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    @{
        QuorumShare = $QuorumShare
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
        [parameter(Mandatory)][string] $QuorumShare,

        [UInt64] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 50,
		
		[parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    $quorumShareFound = $false
    Write-Verbose -Message "Checking for cluster qourum share $QuorumShare ..."

	try
	{
		($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
		for ($count = 0; $count -lt $RetryCount; $count++)
		{		
			If(Test-Path $QuorumShare -PathType Container -ErrorAction Ignore)
			{
				$quorumShareFound = $true
				break
			}
							
			Write-Verbose -Message "Cluster quorum share $QuorumShare not found. Will retry again after $RetryIntervalSec sec"
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
    if (! $quorumShareFound)
    {
        throw "Cluster quorum share $QuorumShare not found after $count attempts with $RetryIntervalSec sec interval"
    }
}

#
# The Test-TargetResource cmdlet.
#
function Test-TargetResource
{
    param
    (	
        [parameter(Mandatory)][string] $QuorumShare,

        [UInt64] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 50,
		
		[parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    Write-Verbose -Message "Checking for Cluster quorum share $QuorumShare ..."

    try
    {  
		($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
        if (Test-Path $QuorumShare -PathType Container -ErrorAction Ignore)
        {
			Write-Verbose -Message "Cluster quorum share $QuorumShare found... returning true .."            
            $true
        }
        else
        {
            Write-Verbose -Message "Cluster quorum share $QuorumShare not found... returning false .."
            $false
        }
    }
    catch
    {
        Write-Verbose -Message "Cluster quorum share $QuorumShare not found"
        $false
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
