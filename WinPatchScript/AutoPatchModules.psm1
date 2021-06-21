function Get-ServerConfig
{
    param (
        [Parameter(Mandatory = $true)]
		[string] $hostname,
        [string] $configFilepath = '\\release\patching\WinPatchScript\AutoPatchConfiguration.json'
    )

    #load json config
    $jsonconfig = Get-Content -Raw -Path $configFilepath
    
    #is the json valid?
    try {
        $jsonObj = ConvertFrom-Json $jsonconfig -ErrorVariable $validJson
		$validJson = $true
    } catch {
        $validJson = $false
    }
    
    if ($validJson) {
        $serverConfig = $jsonObj.machineFunction | where {$_.servers -contains $hostname}
		$serverConfig | Add-Member -NotePropertyName currentHost -NotePropertyValue $hostname
    } else {
        "JSON configuration is invalid/improperly formatted" | Out-File .\patching.log -Append
    }
    
    return $serverConfig
}

function Get-PatchingModuleLocationByRole
{	#determine if server is FD/IH and provide module file that describes what to do next
	param (
		[Parameter(Mandatory = $true)]
		[PSCustomObject] $serverConfig
	)
	
	If ($serverConfig.role -eq 'FD') {
		$workingPath = '\\release\Patching\WinPatchScript\VippedServices'
		"{0} is where we are working out of" -f $workingpath | out-file .\patching.log -Append
	} elseif ($serverConfig.role -eq 'IH') {
		$workingPath = '\\release\Patching\WinPatchScript\BucketedServices'
		"{0} is where we are working out of" -f $workingpath | out-file .\patching.log -Append
	} else {
		"No config for this host" | out-file .\patching.log -Append
	}
	
	return $workingPath
}

Function Check-IsOOS
{	#Check if currentHost is oos
	param (
		[string] $currentHost,
		[Parameter(Mandatory = $true)]
		[string] $oostype
	)

	If ($oostype -eq 'html') {
		If (Test-Path "\\$currentHost\healthprobe\IS.html"){
			return $false
		}
		$ooslocation = "\\$currentHost\healthprobe\patching.html"
	}
	
	If ($oostype -eq 'text') {
		$ooslocation = "\\$currentHost\data\oos.txt"
	}
	
	If (Test-Path $ooslocation) {
		return $true
	}
}

Function Get-OOSFileLocation
{	#Get the oosfile location
	param (
		[Parameter(Mandatory = $true)]
		[string] $oostype
	)

	If ($oostype -eq 'html') {
		$oosfile = "x360healthprobe\patching.html"
	}
	
	If ($oostype -eq 'text') {
		$oosfile = "data\oos.txt"
	}
	
	return $oosfile
}

Function Set-HostOOS
{ #Pull host from service
	param (
	[Parameter(Mandatory = $true)]
	[string] $currentHost,
	[Parameter(Mandatory = $true)]
	[string] $oosfile
	)
	
	If (Test-Path \\$currentHost\HealthProbe\IS.html) {
		Remove-Item \\$currentHost\HealthProbe\IS.html -force
	} 
	
	New-Item -Path \\$currentHost\$oosfile -ItemType File -force | out-null
	
	return $true
}

Function Set-HostIS
{ #Return host to service
	param (
	[Parameter(Mandatory = $true)]
	[string] $currentHost,
	[Parameter(Mandatory = $true)]
	[string] $oosfile
	)
	
    If ($oosfile -eq 'data\oos.txt') {
        Remove-Item -Path \\$currentHost\$oosfile -force
        return $true
    }
	If (Test-Path \\$currentHost\HealthProbe\patching.html) {
	    try
	    {
		    Remove-Item -Path \\$currentHost\$oosfile -force -ErrorAction Stop | out-null
	    }
	    catch
	    {
		    return $false
	    }
    If (-Not (Test-Path \\$currentHost\healthprobe\patching.html)) {
        New-Item \\$currentHost\HealthProbe\IS.html -force | out-null
	    return $true
    }
}
} 