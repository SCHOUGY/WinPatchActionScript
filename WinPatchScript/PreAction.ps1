########################################
#This is the PreAction script for WinPatchv2 for all XMP assets
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

#random wait just incase another box is trying to patch | this is the best protection we have for WinPatch firing off multiple machines at once
$randomNo = new-object system.random
$number = $randomNo.Next(1, 60)
Start-Sleep -Seconds $number


###############
##Front Door OOS
############### 

If ($serverConfig.role -eq 'FD') {
	#grabs module needed to run the rest of the OOS/HC process (we could do all of this at once but I want FD/IH modules separate)
	Import-Module $workingPath\VippedModules.psm1 -Force
	If ($serverConfig.isoos) {
		$isDrained = Confirm-DrainTimeExceeded $serverConfig.currentHost $serverConfig.drainTimeInMinutes $oosfile
	} else {
		$totalServerCount = $serverConfig.servers.count #current count of machines from json
		$totalServersFound = Check-OOSStatusByServer $serverConfig # how many machines found oos
		$canOOS = Check-CanHostOOS $totalServersFound $totalServerCount $serverConfig.failingMachineLimit #can the host oos based on machines found
		If ($canOOS) { #if ok to oos, oos the box and tell winpatch to come back
			$serverConfig.isoos = Set-HostOOS $serverConfig.currentHost $oosfile
			
			If ($serverConfig.oostype -eq "text") { #anything that we have that uses oos.txt to OOS uses APClient which will need the below to keep chkdsk from not occurring
				Disable-ChkDskOnNextReboot | out-null
			}
			exit 3
		} else {
			"Found $totalServersFound servers OOS | too many machines OOS" | out-file .\patching.log -Append
			exit 2
		}
	}
	
	If ($isDrained) {
		"Host is ready to patch" | out-file .\patching.log -Append
		exit 4
	} else {
		"Host is not ready to patch" | out-file .\patching.log -Append
		exit 3
	}
}


###############
##Bucketed Host OOS
###############

#This process is solely for the patching script.  The bucketed services will continue to function if all machines have "patching.html"  We use patching.html to give the script a better idea of what is/is not available to patch

If ($serverConfig.role -eq 'IH') {
	#grabs module needed to run the rest of the OOS/HC process (we could do all of this at once but I want FD/IH modules separate)
	Import-Module $workingPath\BucketedModules.psm1 -Force
	#check for spares
	$spareServers = Get-SpareServers $serverConfig.ServiceName
	
	If ($spareServers.vc_server -match $hostname) { #check that host is the spare (this means no buckets)
		"NPDB reports that this server has no titles" | out-file .\patching.log
        If ($serverConfig.isoos) {
            Exit 4
        }
        If ($serverConfig.isoos -eq $false) {
            #place oos file to keep other machines from attempting to use this machine as a spare
		    $serverConfig.isoos = Set-HostOOS $serverConfig.currentHost $oosfile
		    Exit 4
		}
	} else { #host still has buckets
		"NPDB reports that this server has titles and will need migration" | out-file .\patching.log -Append
		
		#picks a spare that is not showing oos
		$destination = Get-DestinationHost $spareServers
		If ([string]::IsNullOrWhitespace($destination)){
			"No available host to migrate to (Either all spares have patching.html because it was never cleaned up or they are actually patching).  Will WinPatchv2 inform to try again." | out-file .\patching.log -Append
			Exit 3
		}
		
		If ($serverConfig.ServiceName -eq 'lbsvr') {
            #has this box already attempted to move buckets in the last 8 hours if so, try to go back to the same host
            $migrationlogfolder = "\\release\patching\winpatchscript\stats\"
            $hours_to_check = $(Get-Date).AddHours(-8)
            $gcifolder = gci $migrationlogfolder -directory -recurse
            $recentMigration = $gcifolder -match $hostname | Where-Object {$_.LastWriteTime -gt $hours_to_check}
            If ($recentMigration) {
                $recentMigration_string = $recentMigration.Name.ToString()
                $recentMigration_string = $recentMigration_string.Substring(31,12)

                $destination = $recentMigration_string
            }

			#Stat migration check / start
			$statMigrationExeFilepath = 'C:\WinPatchv2\StatMigration\StatMigration.exe'
			IF (Get-Process | Where-Object {$_.name -eq "StatMigration"}) {
				Write-host "Migration process is Active" | Out-File .\patching.log -Append
				Exit 3
			} else {
				$args = ($hostname, $destination)
				Start-process -WindowStyle Hidden $statMigrationExeFilepath $args
				"Starting StatMigration.exe, migrating buckets from $hostname to $destination" | Out-File .\patching.log -Append
            	#place oos file to keep other machines from attempting to use this machine as a spare
		        $serverConfig.isoos = Set-HostOOS $serverConfig.currentHost $oosfile
				Exit 3
			}
		} else {
			#This is for all the "cutover" IH boxes, basically everything but stats
			#update npdb with a script which is scary but this gets us away from using a tool which doesn't work remotely and that we have no code for'
			"Migrating $($serverConfig.ServiceName) buckets from $hostname to $destination" | out-file .\patching.log -Append
			Initialize-BucketCutover $serverConfig.ServiceName $hostname $destination
		    #place oos file to keep other machines from attempting to use this machine as a spare
		    $serverConfig.isoos = Set-HostOOS $serverConfig.currentHost $oosfile
			Exit 3
		}
	}
}