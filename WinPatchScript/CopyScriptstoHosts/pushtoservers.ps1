#Point the script to the text file
$Servers = "\\release\patching\WinPatchScript\CopyScriptstoHosts\servers.txt"
$serverlist = @()
$serverlist = get-content $servers

# sets the varible for the file location
$PreAction = "\\release\Patching\WinPatchScript\PreAction.ps1"
$PostAction = "\\release\Patching\WinPatchScript\PostAction.ps1"
$StatMigrationEXE = "\\release\Patching\WinPatchScript\StatMigration.exe"
$StatMigrationXML = "\\release\Patching\WinPatchScript\StatMigration.exe.config"

# sets the varible for the file destination
$Destination = "WinPatchv2"

foreach ($server in $serverlist) {
	New-Item -ItemType Directory -Path "\\$server\c$\$Destination\" -force
	Copy-Item $PreAction -Destination "\\$server\c$\$Destination\" -force
	Copy-Item $PostAction -Destination "\\$server\c$\$Destination\" -force
	If ($server -like '*stat*') {
		New-Item -ItemType Directory -Path "\\$server\c$\$Destination\StatMigration\" -force
		Copy-Item -path $StatMigrationEXE -Destination "\\$server\c$\$Destination\StatMigration\" -force
		Copy-Item -path $StatMigrationXML -Destination "\\$server\c$\$Destination\StatMigration\" -force
	}
}