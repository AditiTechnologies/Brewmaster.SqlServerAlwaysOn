###Overview
Using the latest available image for SQL Server 2014 (Enterprise) in the azure gallery, it will create a SQL Server AlwaysOn deployment and in the process setup Active Directory and Windows Failover Cluster.

###Virtual Machines (VMs)
1.Two VMs will be created for setting Active Directory and they will act as the primary and secondary DNS. 
2.The number of SQL VMs is controlled by the input parameter 'NumberOfSQLNodes, but a minimum of two is needed for creating the availability group. The minimum recommended size for SQL VM is 'Large'.
3.A single VM for having a 'Node and File Share Majority' quorum configuration in the failover cluster, with the VM acting as a 'file share witness'.

###SQL Server Availability Group Connectivity

The deployment does not create any additional SQL Server logins other than enabling 'sa' and setting its password to the deployment parameter <SqlAdminPassword>. While creating additonal SQL logins, please ensure that they are (synced)[http://support.microsoft.com/kb/918992] across all the SQL VMs. To skip the process of syncing SQL logins, databases in the availability group can be enabled for (partial containment)[http://technet.microsoft.com/en-us/library/ff929071.aspx].

####From Azure Cloud Service
Create a one or more new subnets (for creating the Azure Cloud Service(s) that need access to the availability group) in the deployed Azure Virtual Network (specified by the deployment parameter <VnetName>). Use the connection string `Data Source=tcp:<AvailabilityGroupName>Listener,1433;Initial Catalog=<DatabaseName>;Uid=sa;Pwd=<SqlAdminPassword>;MultiSubnetFailover=True`.

####From On-Premise Applications
The deployment creates endpoints (TCP:1433 with load balancing) on the SQL VMs to enable access from on-premise applications. Use the connection string `Data Source=<SSAOCloudService>.cloudapp.net;Initial Catalog=<DatabaseName>;Uid=sa;Pwd=<SqlAdminPassword>;MultiSubnetFailover=True`.

###Limitations
Following are the limitations of this template. Users can fork this repository and customize the template to fix them or wait for our periodic updates.
> - The template does not allow selection of a image for the SQL VM.
> - The template adds just a single data disk of 40 GB to the SQL VMs.
> - The template only supports adding a single database (specified by the input parameter 'DatabaseName') to the availability group.
> - The template does not support the scenario where Active Directory setup has already been performed in the specified Azure Virtual Network.

###References
Please refer to the following links for more information on SQL Server Availability Groups.
> - [SQL Server Availability Group](http://technet.microsoft.com/en-us/library/ff877884.aspx)
> - [High Availability and Disaster Recovery for SQL Server in Azure Virtual Machines](http://msdn.microsoft.com/en-us/library/jj870962.aspx)

