#
# xSqlHAGroup: DSC resource to configure a Sql High Availability (HA) Group.
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
        [string] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SQLNodeNamePrefix,

        [parameter(Mandatory)]
        [ValidateRange(2,5)]
        [Uint32] $NumberOfSQLNodes,        

		[parameter(Mandatory)]        
        [UInt32] $EndpointPort,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
  	)

    $bConfigured = Test-TargetResource -Name $Name -NumberOfSQLNodes $NumberOfSQLNodes -EndpointPort $EndpointPort -SqlAdministratorCredential $SqlAdministratorCredential

    $returnValue = @{
 
        Database = $Database
        Name = $Name        
        EndpointPort = $EndpointPort
        SqlAdministratorCredential = $SqlAdministratorCredential.UserName
        Configured = $bConfigured
	}

	$returnValue
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
        [string] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SQLNodeNamePrefix,

        [parameter(Mandatory)]
        [ValidateRange(2,5)]
        [Uint32] $NumberOfSQLNodes,        

		[parameter(Mandatory)]        
        [UInt32] $EndpointPort,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
  	)

    #$Endpoint = "TCP://${EndpointName}:${EndpointPort}"
    $ComputerInfo = Get-WmiObject Win32_ComputerSystem
    if (($ComputerInfo -eq $null) -or ($ComputerInfo.Domain -eq $null))
    {
        throw "Can't find machine's domain name"
    }
    $domain = $ComputerInfo.Domain
    $sa = $SqlAdministratorCredential.UserName
    $saPassword = $SqlAdministratorCredential.GetNetworkCredential().Password     
    $agExist = Check-SQLHAGroup -InstanceName $InstanceName -Name $Name -sa $sa -saPassword $saPassword    

    if (!$agExist)
    {
        $AutomaticFailoverMode = 'AUTOMATIC'
        $ManualFailoverMode = 'MANUAL'
        $SynchronousCommitAvailabilityMode = 'SYNCHRONOUS_COMMIT'
        $AsynchronousCommitAvailabilityMode = 'ASYNCHRONOUS_COMMIT'
        $failoverMode = $AutomaticFailoverMode
        $availabilityMode = $SynchronousCommitAvailabilityMode

        Write-Verbose -Message "Creating SQL HAG $Name"        
        
        $queryAdd = ""
        $query = @"
                    CREATE AVAILABILITY GROUP $Name
                        WITH (AUTOMATED_BACKUP_PREFERENCE = SECONDARY)
                        FOR
                        REPLICA ON 
"@
        for($index = 1; $index -le $NumberOfSQLNodes; $index++)
        {
            If($index -gt 2)
	        {
		        # Only the FIRST secondary replica can be set to 'Automatic' failover mode
		        $failoverMode = $ManualFailoverMode
	        }
	        If($index -gt 3)
	        {
		        # 'SynchronousCommit' only upto the SECOND secondary replica. Other replicas are typically for
		        # disaster recovery and hence set to 'AsynchronousCommit'
		        $availabilityMode = $AsynchronousCommitAvailabilityMode
	        }

            $queryAdd = @"
                        $queryAdd
                        '$SQLNodeNamePrefix$index' WITH
                        (
                            ENDPOINT_URL = 'TCP://${SQLNodeNamePrefix}${index}.${domain}:${EndpointPort}',
                            FAILOVER_MODE = $failoverMode,
                            AVAILABILITY_MODE = $availabilityMode
                        ),
"@
        }

        $query = $query.Trim() + $queryAdd.TrimEnd(',').Trim()
        Write-Verbose -Message "Query: $query"
        
        # Create AG
        osql -S "." -U $sa -P $saPassword -Q $query        
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
        [string] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SQLNodeNamePrefix,

        [parameter(Mandatory)]
        [ValidateRange(2,5)]
        [Uint32] $NumberOfSQLNodes,        

		[parameter(Mandatory)]        
        [UInt32] $EndpointPort,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
  	)    

    Write-Verbose -Message "Checking if SQL HA Group $Name present ..."

    $sa = $SqlAdministratorCredential.UserName
    $saPassword = $SqlAdministratorCredential.GetNetworkCredential().Password

    $bFound = Check-SQLHAGroup -InstanceName $env:COMPUTERNAME -Name $Name -sa $sa -saPassword $saPassword
    if ($bFound)
    {
        Write-Verbose -Message "SQL HA Group $Name is present"
        $true
    }
    else
    {
        Write-Verbose -Message "SQL HA Group $Name not found"
        $false
    }
}


function Check-SQLHAGroup($InstanceName, $Name, $sa, $saPassword)
{
    Write-Verbose -Message "Check HAG $Name including instance $InstanceName ..."
    $query = OSQL -S $InstanceName -U $sa -P $saPassword -Q "select count(name) from master.sys.availability_groups where name = '$Name'" -h-1
    
    Write-Verbose -Message "SQL: $query"
    
    [bool] [int] ([String] $query[0]).Trim()
}

Export-ModuleMember -Function *-TargetResource