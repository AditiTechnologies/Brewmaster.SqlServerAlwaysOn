#
# xSqlHAGroup: DSC resource to add database to a Sql High Availability (HA) Group.
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
        [string] $FirstDriveLetter
  	)
    
    $retVal = @{ 
       Disks = Get-Disk; 
       Partitions = Get-Disk | Get-Partition; 
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
        [string] $FirstDriveLetter        
  	)
   
    Format-RawDisks $FirstDriveLetter[0] -ErrorAction Stop
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
        [string] $FirstDriveLetter        
  	)

    # Set-TargetResource is idempotent
    return $false    
}

function Format-RawDisks
{
    [cmdletbinding()]
    param([char]$nextDriveLetter)

	foreach ($disk in Get-Disk | Where PartitionStyle -eq 'RAW')
	{
		Write-Verbose "Formatting disk [$nextDriveLetter]"
		$disk | Initialize-Disk -PartitionStyle MBR -PassThru |
				New-Partition -DriveLetter $nextDriveLetter -UseMaximumSize |
				Format-Volume -FileSystem NTFS -Confirm:$false

		$nextDriveLetter = [char]([int]$nextDriveLetter + 1)
	}
}

Export-ModuleMember -Function *-TargetResource