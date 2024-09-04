#param (
#	[string]$filePath = "",
#	[string]$driveLetter = ""
#)
[string]$filePath = "hosts.txt"
[string]$driveLetter = "X"
[string]$outputDir = "C:\ProgramData\RenameMe"
 
# Check if the file exists
if (-Not (Test-Path $filePath)) {
    Write-Output "File not found: $filePath"
    exit 1
}
 
# Read the hostnames from the file
$hosts = Get-Content -Path $filePath
 
foreach ($hostname in $hosts) {
    $netViewOutput = net view \\$hostname /all
 
    # Constructing the drive letter with a colon
    $driveLetterSemicolon = $driveLetter + ":"
     
    $outputFile = Join-Path $outputDir ($hostname + "_passwords_" + (Get-Date).ToString("yyyyMMdd_HHmmss") + ".txt")
     
    # Initialize an empty array for share names
    $shareNames = @()
     
    # Loop through each line of the output and use regex to match share names
    foreach ($line in $netViewOutput) {
        # Use regex to match share names which are at the beginning of the line
        if ($line -match "^\s*([^\s]+)\s+Platte") {
            # Add the matched share name to the array
            $shareNames += $matches[1]
        }
    }
     
    # Define the list of filename extensions
    $fileExtensions = @(
        ".bat",
        ".ps1",
        ".config",
        ".xml",
        ".cfg",
        ".txt",
        ".properties",
        ".rtsz",
        ".sql",
        ".ini",
        ".bak",
        ".conf"
    )
     
    # Define the keywords to search for
    $keywords = @(
        "password",
        "passwort",
        "pwd" # kind of noisy but actually good
    )
     
    # Ensure the output directory exists
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory
    }
     
    # Loop through each share name
    foreach ($share in $shareNames) {
        # Unmount the SMB share
        Remove-PSDrive -Name $driveLetter
 
        # Create the full SMB path
        $smbPath = "\\$hostname\$share"
         
        # Mount the SMB share
        Write-Output "Mounting $smbPath"
        try {
            New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root $smbPath -Persist -ErrorAction Stop
        } catch {
            Write-Output "Failed to mount $smbPath. Proceeding to the next share."
            continue
            # exit 0
        }
         
        # Check if the share was mounted successfully
        if (Test-Path $driveLetterSemicolon) {
            # Get the number of files in the share
            $fileCount = (Get-ChildItem -Path $driveLetterSemicolon -Recurse -File | Measure-Object).Count
            Write-Output "Number of files found: $fileCount"
     
            # If the number of files is zero, proceed with the next share
            if ($fileCount -eq 0) {
                Write-Output "No files in $smbPath. Proceeding to the next share."
                continue
            }
             
            # Search for files with specified extensions
            $files = Get-ChildItem -Path $driveLetterSemicolon -Recurse -File | Where-Object { $fileExtensions -contains $_.Extension }
     
            foreach ($file in $files) {
                # Loop through each keyword
                foreach ($keyword in $keywords) {
                    # Search for the keyword in the file
                    $findings = Select-String -Path $file.FullName -Pattern $keyword -Context 3,3
                    if ($findings) {
                        $relPath = $file.PSPath
                        if ($relPath -match "Microsoft\.PowerShell\.Core\\FileSystem::" + $driveLetter + ":(.*)") {
                            [string]$tmp = $matches[1]
             
                            # Extract the context (3 lines before and 3 lines after the match)
                            foreach ($match in $findings) {
                                $context = $match.Context.PreContext + @($match.Line) + $match.Context.PostContext
                                $contextString = $context -join "`n" # Join the lines into a single string
                                $result = "$smbPath$tmp,$keyword`n$contextString"
             
                                # Append the result to the output file
                                Add-Content -Path $outputFile -Value $result
                                Add-Content -Path $outputFile -Value "`n--------------------------------------`n`n`n"
                            }
                        } else {
                            Write-Output "Something went wrong on host $hostname"
                            Exit 0
                        }
                    }
                }
            }
        } else {
            Write-Output "Failed to mount $smbPath. Proceeding to the next share."
        }
    }
}
 
Write-Output "Script completed. Matches saved to $outputFile."
exit 0