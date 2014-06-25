#
# xWaitForSqlHAGroup: DSC resource to wait for existency of given name of Sql HA group, it checks the state of 
# the HA group with given interval until it exists or the number of retries is reached.
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

	    [UInt64] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 10,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $PrimaryReplicaInstanceName,        
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$SqlAdministratorCredential
    )

    $sa = $SqlAdministratorCredential.UserName
    $saPassword = $SqlAdministratorCredential.GetNetworkCredential().Password

    $bFound = Check-SQLHAGroup -InstanceName $PrimaryReplicaInstanceName -Name $Name -sa $sa -saPassword $saPassword

    $returnValue = @{
        Name = $Name
        InstanceName = $PrimaryReplicaInstanceName
        RetryIntervalSec = $RetryIntervalSec
        RetryCount = $RetryCount

        HAGroupExist = $bFound
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

	    [UInt64] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 10,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $PrimaryReplicaInstanceName,        
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$SqlAdministratorCredential
    )

    $bFound = $false
    Write-Verbose -Message "Checking for SQL HA Group $Name on instance $PrimaryReplicaInstanceName ..."

    $sa = $SqlAdministratorCredential.UserName
    $saPassword = $SqlAdministratorCredential.GetNetworkCredential().Password

    for ($count = 0; $count -lt $RetryCount; $count++)
    {
        $bFound = Check-SQLHAGroup -Name $Name -InstanceName $PrimaryReplicaInstanceName -sa $sa -saPassword $saPassword
        if ($bFound)
        {
            Write-Verbose -Message "Found SQL HA Group $Name on instance $PrimaryReplicaInstanceName"
            break;
        }
        else
        {
            Write-Verbose -Message "SQL HA Group $Name on instance $PrimaryReplicaInstanceName not found. Will retry again after $RetryIntervalSec sec"
            Start-Sleep -Seconds $RetryIntervalSec
        }
    }


    if (!$bFound)
    {
        throw "SQL HA Group $Name on instance $PrimaryReplicaInstanceName not found afater $count attempt with $RetryIntervalSec sec interval"
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

	    [UInt64] $RetryIntervalSec = 10,
        [UInt32] $RetryCount = 10,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $PrimaryReplicaInstanceName,        
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$SqlAdministratorCredential
    )

    return $false;
}


function Check-SQLHAGroup($InstanceName, $Name, $sa, $saPassword)
{
    [int]$count = 0
    $query = OSQL -S $InstanceName -U $sa -P $saPassword -Q "select count(name) from master.sys.availability_groups where name = '$Name'" -h-1
    $parsed = [System.Int32]::TryParse($query[0].Trim(), [ref]$count)
    return [bool]$count
}
Export-ModuleMember -Function *-TargetResource