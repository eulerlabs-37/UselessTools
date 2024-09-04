#param (
#	[string]$filePath = "",
#	[string]$driveLetter = ""
#)
[string]$filePath = "hosts.txt"
[string]$driveLetter = "Y"
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
 
    $outputFile = Join-Path $outputDir ($hostname + "_customers_" + (Get-Date).ToString("yyyyMMdd_HHmmss") + ".txt")
 
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
 
    # Define an array with file extensions that most likely contain customer private data
    $fileExtensions = @(
        ".doc",    # Microsoft Word documents
        ".docx",   # Microsoft Word documents (modern)
        ".pdf",    # PDF documents
        ".odt",    # OpenDocument text files
        ".rtf",    # Rich Text Format files
        ".xls",    # Microsoft Excel spreadsheets
        ".xlsx",   # Microsoft Excel spreadsheets (modern)
        ".ods",    # OpenDocument spreadsheet files
        ".csv",    # Comma-separated values files
        ".db",     # General database files
        ".dbf",    # Database files
        ".mdb",    # Microsoft Access database files
        ".accdb",  # Microsoft Access database files (modern)
        ".sqlite", # SQLite database files
        ".sql",    # SQL script files
        ".json",   # JSON files
        ".yaml",   # YAML files
        ".yml",    # YAML files
        ".odp",    # OpenDocument presentation files
        ".eml",    # Email message files
        ".msg",    # Microsoft Outlook email message files
        ".pst",    # Microsoft Outlook data files
        ".ost",    # Microsoft Outlook data files (offline)
        ".mbox",   # Mailbox files
        ".html",   # HTML files
        ".htm",    # HTML files
        ".zip",    # ZIP compressed files
        ".rar",    # RAR compressed files
        ".tar",    # TAR archive files
        ".gz",     # GZIP compressed files
        ".tgz",    # TAR and GZIP compressed files
        ".bz2"    # BZIP2 compressed files
    )
 
    # Ensure the output directory exists
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory
    }
 
    # Loop through each share name
    foreach ($share in $shareNames) {
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
            #exit 0
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
                $relPath = $file.PSPath
                $relPattern = "Microsoft\.PowerShell\.Core\\FileSystem::" + $driveLetter + ":(.*)"
                if ($relPath -match $relPattern) {
                    [string]$tmp = $matches[1]
                    $result = "$smbPath$tmp"
                    Add-Content -Path $outputFile -Value $result
                } else {
                    Write-Output "Something went wrong on host $hostname"
                    Exit 0
                }
            }
             
            # Unmount the SMB share
            Remove-PSDrive -Name $driveLetter
        } else {
            Write-Output "Failed to mount $smbPath. Proceeding to the next share."
        }
    }
}
Write-Output "Script completed. Matches saved to $outputFile."
exit