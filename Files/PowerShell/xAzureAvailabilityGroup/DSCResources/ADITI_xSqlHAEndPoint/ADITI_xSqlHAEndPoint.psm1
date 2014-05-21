#
# xSqlHAEndPoint: DSC resource to configure a database mirroring endpoint for Sql High Availability (HA) Group.
#

#
# The Get-TargetResource cmdlet.
#
function Get-TargetResource
{
	param
	(	
		[parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
		[string] $EndPointName,
		
		[parameter(Mandatory)]        
		[UInt32] $EndPointPort,
		
		[parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
		[string] $SqlServerServiceAccount,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $LocalAdministratorCredential
  	)
    
	$configured = $false	
	try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $LocalAdministratorCredential
		$configured = [bool] [int](OSQL -S $InstanceName -E -Q \"select count(*) from master.sys.endpoints where name = '$EndPointName'\" -h-1)[0]
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
		ServerInstance = $env:COMPUTERNAME;		
		EndPointName = $EndPointName;		
		EndPointPort = $EndPointPort;
		Configured = $configured
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
        [ValidateNotNullOrEmpty()]
		[string] $EndPointName,
		
		[parameter(Mandatory)]        
		[UInt32] $EndPointPort,
		
		[parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
		[string] $SqlServerServiceAccount,
		
		[Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $LocalAdministratorCredential
  	)

	$server = $env:COMPUTERNAME
	$serverPath   = "SQLSERVER:\SQL\$server\Default"		
	$endpointPath = "$serverPath\Endpoints\$EndPointName"
		
	try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $LocalAdministratorCredential      
		
		New-SqlHadrEndpoint -Path $serverPath -Name $EndPointName -Port $EndPointPort -EA Stop | Out-Null
		Write-Verbose "Created Endpoint [$EndPointName] on port [$EndPointPort]"
		Set-SqlHadrEndpoint -Path $endpointPath -State "Started" -EA Continue | Out-Null
		Write-Verbose "Starting Endpoint [$EndPointName] (if not already started)"
		Invoke-SqlCmd -Query "GRANT CONNECT ON ENDPOINT::[$EndPointName] TO [$SqlServiceAccount]" -ServerInstance $server
		Write-Verbose "Granting endpoint connect permissions to [$SqlServiceAccount]"
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
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
		[string] $EndPointName,
		
		[parameter(Mandatory)]        
		[UInt32] $EndPointPort,
		
		[parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
		[string] $SqlServerServiceAccount,
		
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