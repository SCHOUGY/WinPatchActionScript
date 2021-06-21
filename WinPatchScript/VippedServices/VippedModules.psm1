$found = 0
$currenttime = (Get-Date)

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


Function Get-LastWriteTime
{ #Check if OOS.txt/Patching.html exists and then get the last write time of the file.  This cannot be called unless the file exists in the first place
	param (
	[Parameter(Mandatory = $true)]
	[string] $currentHost,
	[Parameter(Mandatory = $true)]
	[string] $oosfile
	)
	If (Test-Path \\$currentHost\$oosfile){
		$lastwrite = (Get-Item \\$currentHost\$oosfile).LastWriteTime
	}
	return $lastwrite
}


Function Confirm-DrainTimeExceeded
{ #Verify OOS.txt/patching.html exceeds minimum drain time for server
	param (
	[Parameter(Mandatory = $true)]
	[string] $currentHost,
	[Parameter(Mandatory = $true)]
	[int] $mindraintime,
	[Parameter(Mandatory = $true)]
	[string] $oosfile
	)
	
	$lastwrite = Get-LastWriteTime $currentHost $oosfile
	
	$totaltime = $currenttime - $lastwrite
    If (($totaltime.TotalMinutes) -ge $mindraintime) {
        "Server is patching.  Minimum drain time is $mindraintime minutes" | out-file .\patching.log
		$isDrained = $true
    } else {
		$oostime = $currenttime - $lastwrite
		$oostimehours = $oostime.TotalHours
		$oostimeminutes = $oostime.TotalMinutes
		"Server has been OOS since $lastwrite.  Total time OOS $oostimeminutes minutes.  Minimum drain time is $mindraintime minutes" | out-file .\patching.log -Append
        $isDrained = $false
    }
	
	return $isDrained
}

Function Check-IsHostIS
{ #check if host is IS
	param (
	[string] $server,
	[string] $oostype
	)
	
	If ($oostype -eq "html"){
		$HC = "http://$($server):16001/IS.html"
	}
	If ($oostype -eq "text"){
		$HC = "http://$($server):8080/platformhealth"
	}
	
	try
	{
		$response = Invoke-WebRequest -Uri $HC -ErrorAction Stop -UseBasicParsing
		$statusCode = $response.StatusCode
        "$server response $statusCode" | out-file .\patching.log -Append
	}
	catch
	{
		$statusCode = $_.Exception.Response.StatusCode.value__
	}
	
	If ($statusCode -ne 200)
	{
		$IS = $false
    } else {
		$IS = $true
	}
	return $IS
}

Function Check-CanHostOOS
{ #Have machine check that total count of OOS machines is under fail limit before pulling itself out of service
	param (
	[Parameter(Mandatory = $true)]
	[int] $found,
	[Parameter(Mandatory = $true)]
	[int] $count,
	[Parameter(Mandatory = $true)]
	[int] $failingMachineLimit
	)
	
	"$failingMachineLimit percent is the limit" | out-file .\patching.log -Append
	
	If ((($found / $count) * 100) -ge $failingMachineLimit) {
		return $false
	} else {
		return $true
	}
}


Function Check-OOSStatusByServer
{ #check how many of like hosts are oos
	param (
	[Parameter(Mandatory = $true)]
	[PSCustomObject] $serverConfig
	)
	
	ForEach ($server in $serverConfig.servers) {
	
		If ($serverConfig.oostype -eq "html"){
			$HC = "http://$($server):16001/IS.html"
		}
		If ($serverConfig.oostype -eq "text"){
			$HC = "http://$($server):8080/platformhealth"
		}
		try
		{
			$response = Invoke-WebRequest -Uri $HC -ErrorAction Stop -UseBasicParsing
			$StatusCode = $response.StatusCode
			"$server response $statusCode" | out-file .\patching.log -Append
		}
		catch
		{
			$statusCode = $_.Exception.Response.StatusCode.value__
			"$server had statuscode $statusCode" | out-file .\patching.log -Append
		}
		
		If ($statusCode -ne 200)
		{
			$found++
        }
    }
	"Found $found servers OOS" | out-file .\patching.log -Append

	return $found
} 