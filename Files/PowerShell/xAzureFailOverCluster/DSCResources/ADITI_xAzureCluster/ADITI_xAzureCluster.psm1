#
# xAzureCluster: DSC resource to configure a Failover Cluster consisting of Windows Azure VMs.
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
		
		[parameter(Mandatory)]
        [ValidateRange(2,5)]
        [Uint32] $NumberOfSQLNodes,
        
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    $ComputerInfo = Get-WmiObject Win32_ComputerSystem
    if (($ComputerInfo -eq $null) -or ($ComputerInfo.Domain -eq $null))
    {
        throw "Can't find machine's domain name"
    }
    
    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
        
        $cluster = Get-Cluster -ErrorAction Ignore

        if ($cluster -ne $null -and $cluster.Name -eq $Name)
        {
            $address = Get-ClusterGroup -Cluster $Name -Name "Cluster IP Address" | Get-ClusterParameter "Address"
        }
        else
        {
            throw "Can't find the cluster $Name"
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

    $retvalue = @{
        Name = $Name
        IPAddress = $address.Value
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

		[parameter(Mandatory)]
        [ValidateRange(2,5)]
        [Uint32] $NumberOfSQLNodes,
        
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    $bCreate = $true

    Write-Verbose -Message "Checking if Cluster $Name is present ..."
    try
    {
        $ComputerInfo = Get-WmiObject Win32_ComputerSystem
        if (($ComputerInfo -eq $null) -or ($ComputerInfo.Domain -eq $null))
        {
            throw "Can't find machine's domain name"
        }
        $cluster = Get-Cluster -ErrorAction Ignore
        if ($cluster -ne $null -and $cluster.Name -eq $Name)
        {
            $bCreate = $false     
        }
    }
    catch
    {
        $bCreate = $true
    }

    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential  

        if ($bCreate)
        {            
			$LocalMachineName = $env:COMPUTERNAME
			$CurrentCluster = New-Cluster -Name $Name -NoStorage -Node $LocalMachineName -ErrorAction Stop
			$clusterGroup = $CurrentCluster | Get-ClusterGroup
			$clusterNameRes = $clusterGroup | Get-ClusterResource "Cluster Name" -ErrorAction Ignore
			if (!$clusterNameRes -OR $clusterNameRes.State -ne "Online")
			{
				Write-Verbose "Bringing Cluster Name resource offline"
				$clusterNameRes | Stop-ClusterResource -ErrorAction Ignore | Out-Null

				Write-Verbose "Bringing all cluster IP Addresses offline"
				$AllClusterGroupIPs = $clusterGroup | Get-ClusterResource | Where {$_.ResourceType.Name -in "IP Address","IPv6 Tunnel Address","IPv6 Address"}
				$AllClusterGroupIPs | Stop-ClusterResource -ErrorAction Ignore | Out-Null

				Write-Verbose "Removing all IP addresses except first IP Address"
				$IPv4ResourceName = ($AllClusterGroupIPs | Where {$_.ResourceType.Name -eq "IP Address"} | Select -First 1).Name
				$AllClusterGroupIPs | Where Name -ne $IPv4ResourceName | Remove-ClusterResource -Force -ErrorAction Continue | Out-Null

				Write-Verbose "Setting the cluster IP address to a link local address"
				# Compute a possibly unallocated IP address by adding (No of Cluster Nodes + 1) to the least significant octet of current IPv4 address
				$ipinfo = Get-NetIPConfiguration | Get-NetIPAddress -AddressFamily IPv4 -SkipAsSource $false | Select -First 1
				$ipAddress = [System.Net.IPAddress]::Parse($ipinfo.IPv4Address)
				[byte[]]$ipAddressBytes = $ipAddress.GetAddressBytes();
				# Increment so as to take into account the quorum node
				$clusterSize = $NumberOfSQLNodes + 1
				$ipAddressBytes[3] = $ipAddressBytes[3] + ($clusterSize * 4) + 1
				$ipAddress = [System.Net.IPAddress]$ipAddressBytes
				$subnetMask = [System.Net.IPAddress]((1 -shl $ipinfo.PrefixLength)-1)

				Write-Verbose "Using [$ipAddress] for the $IPv4ResourceName resource..."
				$res = Get-ClusterResource $IPv4ResourceName 
				$params = @(
					(New-Object Microsoft.FailoverClusters.PowerShell.ClusterParameter $res, EnableDhcp, ([Uint32]0)),
					(New-Object Microsoft.FailoverClusters.PowerShell.ClusterParameter $res, OverrideAddressMatch, ([Uint32]1)),
					(New-Object Microsoft.FailoverClusters.PowerShell.ClusterParameter $res, Address, $ipAddress.ToString()),
					(New-Object Microsoft.FailoverClusters.PowerShell.ClusterParameter $res, SubnetMask, $subnetMask.ToString()))
				$params | Set-ClusterParameter -ErrorAction Stop
			}

			#
			# Start the cluster
			#
			if ($clusterNameRes.State -ne "Online")
			{
				Write-Verbose "Starting cluster..." 
				$clusterNameRes | Start-ClusterResource -ErrorAction Stop
			}

			Write-Verbose "Starting cluster (if not already started)."
			Start-Cluster -Name $Name -ErrorAction Continue | Out-Null
			
			#
			# Now, add the secondary SQL nodes
			#
			$allNodes = Get-WmiObject -namespace "root\mscluster" -class MSCluster_Node
			for($i = 0; $i -lt ($NumberOfSQLNodes - 1); $i++)
			{
				$nodeName = "sql" + ($i + 2)
				$nodeExists = $allNodes | where { [System.String]::Compare($_.Name, $nodeName, $true) -eq 0 }
				if (!$nodeExists)
				{
					Write-Verbose "Adding node [$nodeName] to cluster..."
					$CurrentCluster | Add-ClusterNode $nodeName -ErrorAction Stop | Out-Null
				}
			}
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
}

# 
# Test-TargetResource
#
# The code will check the following in order: 
# 1. Is machine in domain?
# 2. Does the cluster exist in the domain?
# 3. Are all the cluster nodes configured and UP?
#  
# Function will return FALSE if any above is not true. Which causes cluster to be configured.
# 
function Test-TargetResource  
{
    param
    (	
        [parameter(Mandatory)]
        [string] $Name,

		[parameter(Mandatory)]
        [ValidateRange(2,5)]
        [Uint32] $NumberOfSQLNodes,
        
        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    $bRet = $false

    Write-Verbose -Message "Checking if Cluster $Name is present ..."
    try
    {

        $ComputerInfo = Get-WmiObject Win32_ComputerSystem
        if (($ComputerInfo -eq $null) -or ($ComputerInfo.Domain -eq $null))
        {
            Write-Verbose -Message "Can't find machine's domain name"
            $bRet = $false
        }
        else
        {
            try
            {
                ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
         
                $cluster = Get-Cluster -ErrorAction Ignore

                if ($cluster -ne $null -and $cluster.Name -eq $Name)
                {
					Write-Verbose -Message "Cluster $Name is present"					                
					
                    $allNodes = Get-WmiObject -namespace "root\mscluster" -class MSCluster_Node
					$nodeCount = $allNodes.Length                    
					$bRet = $nodeCount -eq $NumberOfSQLNodes
                    if ($bRet)
                    {
                        Write-Verbose -Message "Cluster $Name has been configured"
                    }
                    else
                    {
                        Write-Verbose -Message "Cluster $Name configuration incomplete"
                    }
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
        }
    }
    catch
    {
        Write-Verbose -Message "Cluster $Name is NOT present with Error $_.Message"
    }

    $bRet
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