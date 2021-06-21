########################################
#This is the PostAction script for WinPatchv2 for all XMP assets
########################################
Set-ExecutionPolicy -executionpolicy bypass
$ScriptFolder = "\\release\patching\WinPatchScript"
Import-Module $ScriptFolder\AutoPatchModules.psm1 -Force
$hostname = hostname
#gets the config for the host
$serverConfig = Get-ServerConfig $hostname
#grabs IS/OOS modules based on the server role
$workingPath = Get-PatchingModuleLocationByRole $serverConfig
#See if Server is already OOS
$serverConfig.isoos = Check-IsOOS $serverConfig.currentHost $serverConfig.oostype
#get oosfile type
$oosfile = Get-OOSFileLocation $serverConfig.oostype

#give thumbs up / down whether the box can return to service
 
###############
##Front Door IS
###############

If ($serverConfig.role -eq 'FD') {
	#grabs module needed to run the rest of the OOS/HC process
	Import-Module $workingPath\VippedModules.psm1 -Force
	If (Check-IsHostIS $serverConfig.currentHost $serverconfig.oostype) {
		$isInService = $true
	} else {
		If ([string]::IsNullOrWhitespace($serverConfig.healthcheckurl)) {
			#we are assuming any machine that does not have a HC will be fit for service when it is rebooted and postaction is ran
			$isInService = Set-HostIS $serverConfig.currentHost $oosfile
		} else {
			#inject hostname into healthcheck url then test response.  some hosts may not allow for this to be ran locally, if this is the case, we will remove HC from config and assume healthy
			$serverConfig.healthcheckurl = $serverConfig.healthcheckurl.Replace("[REPLACEME]", $hostname)
			$statusCode = Check-HealthCheck $serverConfig.healthcheckurl
			If ($statusCode -ne 200) {
				"Healthcheck did not return 200 | $hostnanme returned status code $statuscode" | out-file .\patching.log -Append
				exit 3
			} else {
				$isInService = Set-HostIS $serverConfig.currentHost $oosfile
			}
		}
	}
	If ($isInService) {
		"Host returned to service" | out-file .\patching.log
		exit 4
	} else {
		"Host not returned to service yet." | out-file .\patching.log -Append
		exit 3
	}
}


###############
##Bucketed Host IS
###############


#This process is solely for the patching script.  The bucketed services will continue to function if all machines have "patching.html"  We use patching.html to give the script a better idea of what is/is not available to patch

If ($serverConfig.role -eq 'IH') {
	#grabs module needed to run the rest of the OOS/HC process
	Import-Module $workingPath\BucketedModules.psm1 -Force
	#get list of spares
	$results = Get-SpareServers $serverConfig.ServiceName
	
	If ($results.vc_server -match $hostname) { #check that host is the spare (this means no buckets)
		"NPDB reports that this server is a spare." | out-file .\patching.log
		#check if host is listed as oos
		If ($serverConfig.isoos) {
		
			$serverConfig.healthcheckurl = $serverConfig.healthcheckurl.Replace("[REPLACEME]", $hostname)
			$statusCode = Check-HealthCheck $serverConfig.healthcheckurl
			
			If ($statusCode -ne 200) {
				"Healthcheck did not return 200" | out-file .\patching.log -Append
				exit 3
			} else {
				$isInService = Set-HostIS $serverConfig.currentHost $oosfile
			}
		}
	} else { #The host has buckets but is still showing OOS?
		If ($serverConfig.isoos) {
			#attempt to remove oos file
			$isInService = Set-HostIS $serverConfig.currentHost $oosfile
			If ($isInService -eq $false) {
				"Host already has buckets and is showing OOS.  This should not happen.  Stopping post action to generate post action alert" | out-file .\patching.log -Append
				Exit 2			
			}
		} else {
        $isInService = $true
        }
	}


	If ($isInService) {
		"Host returned to service" | out-file .\patching.log
		exit 4
	} else {
		"Host not returned to service yet." | out-file .\patching.log -Append
		exit 3
	}
}