#
# xSqlAccessControl: DSC resource to enable SQL authentication and the built-in 'sa' account.
#

#
# The Get-TargetResource cmdlet.
#
function Get-TargetResource
{
	param
	(	
		[Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SqlAdminPassword,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $LocalAdministratorCredential
  	)
    
	$saAccount = $null
	try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $LocalAdministratorCredential
		$saAccount = Invoke-SqlCmd -Query \"exec sp_helpsrvrolemember 'sysadmin'\" -ServerInstance '.' -EA Continue | where MemberName -eq 'sa'
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
	
    $returnValue = @{
		SqlAdminAccountEnabled = (!($saAccount -eq $null))
	}
}

#
# The Set-TargetResource cmdlet.
#
function Set-TargetResource
{
	param
	(             
		[Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SqlAdminPassword,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $LocalAdministratorCredential
  	)	   
	
	try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $LocalAdministratorCredential
        
		# Enable SQL Authentication
		[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO')
		$sqlServer = new-object ('Microsoft.SqlServer.Management.Smo.Server') $env:COMPUTERNAME
		$sqlServer.Settings.LoginMode = [Microsoft.SqlServer.Management.SMO.ServerLoginMode]::Mixed
		$sqlServer.Alter()
		$serviceList = Get-Service -Name MSSQL*
		foreach ($svc in $serviceList)
		{
		   Set-Service -Name $svc.Name -StartupType Automatic
		   if ($svc.Status -ne "Stopped")
		   {
			   $svc.Stop()
			   $svc.WaitForStatus("Stopped")
			   $svc.Refresh()
		   }
		   if ($svc.Status -ne "Running")
		   {
			  $svc.Start()
			  $svc.WaitForStatus("Running")
			  $svc.Refresh()
		   }
		}
		
		# Enable the built-in 'sa' account
		Invoke-SqlCmd -Query "ALTER LOGIN sa ENABLE" -ServerInstance "."
		Invoke-SqlCmd -Query "ALTER LOGIN sa WITH PASSWORD = '$SqlAdminPassword'" -ServerInstance "."
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
# The Test-TargetResource cmdlet.
#
function Test-TargetResource
{
	param
	(	
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SqlAdminPassword,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $LocalAdministratorCredential
  	)    

    # Set-TargetResource is idempotent
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