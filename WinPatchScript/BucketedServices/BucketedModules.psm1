$currenttime = (Get-Date)

Function Check-OOSStatus
{ #check if spare is patching
	param (
		[string] $server
	)
		
	$HC = "http://$($server):16001/IS.html"

	try
	{
		$response = Invoke-WebRequest -Uri $HC -ErrorAction Stop -UseBasicParsing
		$StatusCode = $response.StatusCode
		"$server response $StatusCode" | out-file .\patching.log -Append
	}
	catch
	{
		$statusCode = $_.Exception.Response.StatusCode.value__
		"$server had statuscode $StatusCode" | out-file .\patching.log -Append
	}
		
	If ($statusCode -ne 200)
	{
		$found = $false
		"Found $server OOS" | out-file .\patching.log -Append
    }
	
	If ($statusCode -eq 200){
		$found = $true
	}

	return $found
}

Function Check-Healthcheck
{
	param (
	[Parameter(Mandatory = $true)]
	[string] $healthcheck
	)
	
		try
		{
			$response = Invoke-WebRequest -Uri $healthcheck -ErrorAction Stop -UseBasicParsing
			$statusCode = $response.StatusCode
			"$server response $StatusCode" | out-file .\patching.log -Append
		}
		catch
		{
			$statusCode = $_.Exception.Response.StatusCode.value__
			"$server had statuscode $StatusCode" | out-file .\patching.log -Append
		}
		
		If ($statusCode -ne 200)
		{
			"Server not ready for service" | out-file .\patching.log -Append
        }
	return $statusCode
}

Function Get-DestinationHost
{ #Get yoself a destination
	param(
		[System.Data.Datatable] $results
	)

	$spareserver = ""
	
	ForEach($spare in $results) { #foreach Datarow from Datatable
		$spare = $spare.vc_server.ToString() #converts datarow to string
		$sparefound = Check-OOSStatus $spare

		If($sparefound -eq $true){
			$spareserver = $spare
			"$spareserver will be the destination" | out-file .\patching.log -Append
			break
		}
	}

	return $spareserver
}

Function Get-SpareServers
{ #queries DB for spares 
    param(
		[string] $interface,
        [string] $dataSource = "<redacted>",
		[string] $database = "<redacted>",
        [string] $sqlCommand = $("<redacted>") #this contains a select statement for the DB to find hosts without buckets
      )

    $connectionString = "Data Source=$dataSource; " + "Integrated Security=SSPI; " + "Initial Catalog=$database"

    $connection = New-Object System.Data.SQLClient.SQLConnection($connectionString)
    $command = New-Object System.Data.SQLClient.SQLCommand($sqlCommand,$connection)
    $connection.Open()

    $adapter = New-Object System.Data.SQLClient.SQLDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()
    $spares = $dataSet.Tables
	
	"$spares" | out-file .\spares.log
	
	return $spares
}

Function Get-Buckets
{ #get list of buckets on host and drop into an array
	param(
		[string] $interface,
        [string] $dataSource = "<redacted>",
		[string] $database = "<redacted>",
        [string] $sqlCommand = $("<redacted>") #this contains a select statement to of current buckets on host
	)

	$connectionString = "Data Source=$dataSource; " + "Integrated Security=SSPI; " + "Initial Catalog=$database"

    $connection = New-Object System.Data.SQLClient.SQLConnection($connectionString)
    $command = New-Object System.Data.SQLClient.SQLCommand($sqlCommand,$connection)
    $connection.Open()

    $adapter = New-Object System.Data.SQLClient.SQLDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()
    $titles = $dataSet.Tables

	"$titles" | Out-File .\buckets.log

	return $titles
}

Function Initialize-BucketCutover
{ #this function cuts buckets from one server to another.  This does not work for stats
	param (
		[string] $interface,
		[string] $hostname,
		[string] $destination,
		[string] $dataSource = "<redacted>",
		[string] $database = "<redacted>",
		[string] $bucketCutover = $("<redacted>") #this contains an update transaction to the DB to shift buckets
	)

	$queryTimeout = 15
	$connectionString = "Data Source=$dataSource; " + "Integrated Security=SSPI; " + "Initial Catalog=$database"

    $connection = New-Object System.Data.SQLClient.SQLConnection($connectionString)
	$command = New-Object System.Data.SQLClient.SQLCommand($bucketCutover,$connection)

	$command.CommandTimeout = $queryTimeout
	$connection.Open()
	$command.ExecuteNonQuery() | Out-Null
	$connection.Close()
} 