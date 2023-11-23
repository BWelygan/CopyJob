<#
.SYNOPSIS
    Copy backups/file to a separate server, archiving them
.DESCRIPTION
    Copy files creating an archive, and copy them to a separate location.
    Used to replicate backups to a new location, or copy a scheduled application backup to a new location for archive.
    Backups script is logged, the specified log fill will have the date appended to it. i.e. [logName][fileNameDelimiter][date].[extension]
    Author: Brad Welygan
    Date: Nov 7, 2023
    Updated: Nov 21, 2023
    Debug complete: Nov 10, 2023
.PARAMETER jsonSettings
    Source location of the json settings files.
.NOTES
    Settings file has two sections 'globalSettings' and 'jobs'
    Each section contains a similar set of settings. Copy Job settings take precedence
    Any setting that has a default can be left out of the JSON file and the defaults will be applied.
    
        globalSettings:
            This is any setting you want to apply to every job
            All logging settings are set here. The Jobs will be logged and added to this file.
        jobs:
            This section can be repeated for each copy job needed.
            If any global setting is placed here, it overrides global settings. EXCEPT log settings

        Global only Settings:
            'logPath' - Path for the job log to be placed.
                DEFAULT: script location
            'logFileName' - Name of the log file.
                NOTE: the date will be added to this file name: [logName][fileNameDelimiter][date].[extension]
            'logExtension' - file extension you want the log file in.
                DEFAULT: log
            'fileNameDelimiter' - Delimiter to separate file names from dates. This can be used to help process your logs, or copy archives later.
                i.e. SQLCopyJob_2023-Nov-01.log
                DEFAULT: "_"
            
        Global AND job settings: **Job overrides Global
            'sourcePath' - Path to source files
            'destinationPath' - path to destination, or location you want the file copied to.
                NOTE: If the destination folder doesn't exsist it will be created.
            'includeExtension' - Extension to include in a Get-Childitem. DEFAULT: blank
            'excludeExtension' - Extension to exclude in a Get-Childitem. DEFAULT: blank
            'compressionLevel' - None, Normal, Fast, High, Low, Ultra. DEFAULT: None
                NOTE: any compression used will eat into backup time and server resources. 
            'archiveType' - Auto, BZip2, GZip, SevenZip, Tar, XZ, Zip DEFAULT: Zip
            'copy' - folder, file
                NOTE:   Folder will copy and compress into an archive at the folder level
                        File will copy and compress at the folder level. If 'compession': None is
                            specified it will just copy the files

        Job only settings:
            'archiveName' - Name for your backup copy archive. Manual entry will not use the 'fileNameDelimieter'.
                            Only the use of the variables %DATE%, %JOBNAME%, and %DEFAULT% will use the 'fileNameDelimiter'
                %JOBNAME% Adds the copy job name to 'archiveName'. i.e. %JOBNAME%_SQL.[archiveType] = Financial_SQL.zip 
                %DATE% Adds a DATE to the 'archiveName'. Date format yyyy-MMM-dd, i.e. 2023-Nov-01.[archiveType] = 2023-Nov-01.zip
                    NOTE: %DATE% does not add "_" (Delimiter) to the file name. Use the same delimiter through out your 'archiveName'
                %DEFAULT% Provides a Default file name. DEFAULT: [jobName]_%DATE%.[archiveType] = Finacial_2023-Nov-01.zip
                    NOTE: Append to Default archive name i.e. [[jobName]_%DATE%]_[archiveName].[archiveType] = Finacial_2023-Nov-01_SQL.zip
                **Leaving 'archiveName' blank or excluding 'archiveName' from the JSON and %DEFAULT% is used.
    
    json settings file example:
        {
            "globalJobSettings": {
                    "sourcePath": "E:\\Backups\\",
                    "destinationPath": "\\\\server\\share$",
                    "logPath": "E:\\Logs\\",
                    "logFileName": "logFileName",
                    "logExtension": "log",
                    "compressionLevel": "None",
                    "archiveType": "SevenZip",
                    "fileNameDelimiter": "_",
                    "jobs": [
                                {
                                    "[jobName]": {
                                        "archiveName": "Data_%DATE%",
                                        "includeExtension": "",
                                        "excludeExtension": "*.log, *.prv"
                                    }
                                },
                                {
                                    "[jobName]": {
                                        "archiveName": "%DEFAULT%-prv"
                                        "includeExtension": "*.prv",
                                        "excludeExtension": "*.log"
                                        }
                                }
                            ]
            }
        }

    Error Codes:
        Success = 0
        UnknownError = -1
        sourcePath = -101
        sourcePath = -111
        destinationPath = -102
        destinationPathExists = -112
        logPath = -103
        logPath = -113
        logFileName = -104
        logExtension = -105
        compressionLevel = -106
        includeExtension = -107
        excludeExtension = -108
        jobSourcePath = -201
        jobSourcePathExists = -211
        jobDestinationPath = -202
        jobDestinationPathExists = -212
        jobLogPath = -203
        jobLogPathExists = -213
        jobLogFileName = -204
        jobLogExtension = -205
        jobCompressionLevel = -206
        jobIncludeExtension = -207
        jobExcludeExtension = -208

        *not used/implemented
.EXAMPLE
    PowerShell 7+
    Command line execution
    c:\>"C:\Program Files\PowerShell\7\pwsh.exe" -file e:\CAMAlot-CopyBackups-v4.1.ps1 -jsonSettings "E:\backupSettings.json"
    PS C:\>.\CAMAlot-CopyBackups-v4.1.ps1 -jsonSettings "E:\backupSettings.json"
#>
## Todo:
## Add in SWITCH for error codes
## Add in SWITCH to create a template settings file.
## Add in SWITCH for Delete Original after copy (Move option)
[CmdletBinding(DefaultParameterSetName='Default')]
Param(
    [Parameter(Mandatory=$true,
    ParameterSetName="Default",
    HelpMessage="Setting file, json")]
    [Alias("json")]
    [string]$jsonSettings
)
# ---- Create enum for Errors ---
enum errorNumber {
    Success = 0
    UnknownError = -1
    moduleLoad = -2
    settingFileExists = -3
    nuGetError = -4
    psVerionMisMatch = -5
    sourcePath = -101
    sourcePathExists = -111
    destinationPath = -102
    destinationPathExists = -112
    logPath = -103
    logPathExists = -113
    logFileName = -104
    logExtension = -105
    compressionLevel = -106
    includeExtension = -107
    excludeExtension = -108
    jobSourcePath = -201
    jobSourcePathExists = -211
    jobDestinationPath = -202
    jobDestinationPathExists = -212
    jobLogPath = -203
    jobLogPathExists = -213
    jobLogFileName = -204
    jobLogExtension = -205
    jobCompressionLevel = -206
    jobIncludeExtension = -207
    jobExcludeExtension = -208
}
#INIT logging
#Create a log file
$tmpFile = Get-Item ([System.IO.Path]::GetTempFileName())
# Send start time to Log
"Starting backups: $(Get-Date)" >> $tmpFile
"jsonSettings: $jsonSettings" >> $tmpFile 

# Dump logs to script root 
function Dump-Log {
    [CmdletBinding(DefaultParameterSetName="Default")]
    param (
        # Log file path
        [Parameter(ParameterSetName="Default")]
        [System.IO.FileSystemInfo]
        $logFile
    )
    
    begin {
        $tmpFileName = ((Get-Date -Format yyyy-MMM-dd).Replace('.','') + ".log")
        #$tmpFileLocation = $logFile.DirectoryName
        #$tmpLogfileName = $logFile.Name
    }
    
    process {
        if (!(Test-Path -PathType Leaf -Path ($PSScriptRoot + "\" + $tmpFileName))){
            $newLogFile = New-Item -Path $PSScriptRoot -Name $tmpFileName -Force -ItemType File 4>> $logFile
        }else {
            $newLogFile = Get-Item -Path ($PSScriptRoot + "\" + $tmpFileName)
        }
        Get-Content $logFile | Out-File $newLogFile
    }
    
    end {
        Remove-Item $logFile
        #Move-Item -Path $logFile -Destination $PSScriptRoot -Verbose 4>> $logFile
    }
}
# Get Json file
function Get-jsonFile {
	<#
	.SYNOPSIS
		Loads json file content in to powershell CustomObject
	.PARAMETER filePath
		File path to json file
    .PARAMETER hashTable
        Output object as a hashtable
	.OUTPUTS
	powershell object with json content
	#>
	[CmdletBinding(DefaultParameterSetName='Default')]
	param (
		[Parameter(Mandatory=$true,
		ParameterSetName='Default',
		Position=0,
		ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true,
		HelpMessage="json File path")]
		[ValidateNotNullOrEmpty()]
		[Alias("Path")]
		[String]$filePath,
        [Parameter(ParameterSetName='Default',
        Position=2,
        HelpMessage="Output a Hashtable")]
        [Alias("ht")]
        [switch]$hashTable
	)
	begin{
		if ($hashTable) {
            [System.Collections.Hashtable]$jsonContent | Out-Null
        }else{
            [System.Object[]]$jsonContent | Out-Null
        }
	}
	process{
		try{
            if($hashTable){
                if (Test-Path -PathType Leaf -Path $filePath) {
                    $jsonContent = Get-Content -Path $filePath | ConvertFrom-Json -AsHashtable -Depth 25
                }else{
                    throw "Error - file doesn't exsist at location $filePath"
                }
            }else{
                if (Test-Path -PathType Leaf -Path $filePath) {
                    $jsonContent = Get-Content -Path $filePath | ConvertFrom-Json -Depth 25
                }else{
                    throw "Error - file doesn't exsist at location $filePath"
                }
            }
		}catch{
			$_
		}
		
	}
	end{
		if ($null -eq $jsonContent){
			$null
		}else{
            if ($hashTable) {
			    [System.Collections.Hashtable]$jsonContent
            }else{
                $jsonContent
            }
            #, $jsonContent
		}
	}
}
# Confirm Paths
function Confirm-Paths {
    [CmdletBinding(DefaultParameterSetName="Default")]
    param (
        [Parameter(
            Mandatory=$true,
            ParameterSetName="Default",
            HelpMessage="Path String to verify it has a trailing slash"
        )]
        [Alias("path")]
        [ValidateNotNullOrEmpty()]
        [string]
        $pathName
    )
    
    process {
        if($false -eq $pathName.EndsWith("\")){
            $pathName += "\"
        }
    }
    
    end {
        $pathName
    }
}
# Confirm Settings
function Confirm-Settings {
    <#
    .SYNOPSIS
        Validates the settings file
    .DESCRIPTION
        Checks that the all manditory settings are available in the settings json file, either in the Global settings or the job settings.
        If any errors occure outputs a hash table with error codes.
    .NOTES
        None
    .EXAMPLE
        $results = Confirm-Settings -SettingsFile $settingsJson
    #>
    [CmdletBinding(DefaultParameterSetName="Default")]
    param (
        [Parameter(Mandatory=$true,
        ParameterSetName="Default",
        HelpMessage="A hash table from a json file.")]
        [Alias("json")]
        [hashtable][ref]$settingsFile
    )
    
    begin {
        #$propertyCountGlobal = $settingsFile.globalJobSettings.Count
        #$jobCount = $settingsFile.globalJobSettings.jobs.Count
        $currentDate = (Get-Date -Format yyyy-MMM-dd).Replace('.','')
        # Place holder for archive name
        $archiveName = $null

        $errorLog = @{
            "sourcePath" = $null
            "destinationPath" = $null
            "logPath" = $null
            "logFileName" = $null
            "logExtension" = $null
            "compressionLevel" = $null
            "archiveType" = $null
            "includeExtension" = $null
            "excludeExtension" = $null
            "fileNameDelimiter" = $null
        }
    }
    
    process {
        # log path check
        if (!($settingsFile.globalJobSettings.ContainsKey('logPath'))){
            $settingsFile.globalJobSettings.logPath = Confirm-Paths -pathName $PSScriptRoot
        }else {
            $settingsFile.globalJobSettings.logPath = Confirm-Paths -pathName $settingsFile.globalJobSettings.logPath.Trim()
            if (!(Test-Path -Path $settingsFile.globalJobSettings.logPath)) {
                $errorLog.logPath = [int][errorNumber]::logPathExists
            }
        }
        if ($null -eq $errorLog.logPath) {
            $errorLog.logPath = $true
        }
        # Log Extension check
        if (!($settingsFile.globalJobSettings.ContainsKey('logExtension'))){
            $settingsFile.globalJobSettings.logExtension = ".log"
        }else{
            $settingsFile.globalJobSettings.logExtension = "." + $settingsFile.globalJobSettings.logExtension.Trim()
        }
        $errorLog.logExtension = $true
        # compression Level check
        if (!($settingsFile.globalJobSettings.ContainsKey('compressionLevel'))){
            $settingsFile.globalJobSettings.compressionLevel = "None"
        }else{
            $settingsFile.globalJobSettings.compressionLevel = $settingsFile.globalJobSettings.compressionLevel.Trim()
        }
        $errorLog.compressionLevel = $true
        # source path check
        if ($settingsFile.globalJobSettings.ContainsKey('sourcePath')) {
            $errorLog.sourcePath = $true
            $settingsFile.globalJobSettings.sourcePath = Confirm-Paths -pathName $settingsFile.globalJobSettings.sourcePath.Trim()
        }else {
            # set error code in Job section
            #$errorLog.sourcePath = [int][errorNumber].GetEnumValues('sourcePath')
            $errorLog.sourcePath = $false
        }
        # destination Path Check
        if ($settingsFile.globalJobSettings.ContainsKey('destinationPath')) {
            $errorLog.destinationPath = $true
            $settingsFile.globalJobSettings.destinationPath = Confirm-Paths -pathName $settingsFile.globalJobSettings.destinationPath.Trim()
        }else {
            # set error code in Job section
            #$errorLog.destinationPath = [int][errorNumber].GetEnumValues('destinationPath')
            $errorLog.destinationPath = $false
        }
        # include Extension Check
        if ($settingsFile.globalJobSettings.ContainsKey('includeExtension')) {
            $errorLog.includeExtension = $true
            $settingsFile.globalJobSettings.includeExtension = $settingsFile.globalJobSettings.includeExtension.Trim()
        }else {
            $errorLog.includeExtension = $false
        }
        # exclude Extension check
        if ($settingsFile.globalJobSettings.ContainsKey('excludeExtension')) {
             $errorLog.excludeExtension = $true
             $settingsFile.globalJobSettings.excludeExtension = $settingsFile.globalJobSettings.excludeExtension.Trim()
        }else {
            $errorLog.excludeExtension = $false
        }
        # Archive Type check
        if ($settingsFile.globalJobSettings.ContainsKey('archiveType')) {
            $settingsFile.globalJobSettings.archiveType = $settingsFile.globalJobSettings.archiveType.Trim()
            $settingsFile.globalJobSettings.Add("archiveExt", ("." + $settingsFile.globalJobSettings.archiveType))
        }else {
            $settingsFile.globalJobSettings.archiveType = "Zip"
            $settingsFile.globalJobSettings.Add("archiveExt", (".zip"))
        }
        $errorLog.archiveType = $true
        # file Name Delimiter check
        if ($settingsFile.globalJobSettings.ContainsKey('fileNameDelimiter')) {
            #clean for spaces
            $settingsFile.globalJobSettings.fileNameDelimiter = $settingsFile.globalJobSettings.fileNameDelimiter.Trim()
        }else {
            $settingsFile.globalJobSettings.fileNameDelimiter = "_"
        }
        $errorLog.fileNameDelimiter = $true
        # log file name check
        if (!($settingsFile.globalJobSettings.ContainsKey('logFileName'))){
            $settingsFile.globalJobSettings.logFileName= $currentDate
        }else{
            $settingsFile.globalJobSettings.logFileName = $settingsFile.globalJobSettings.logFileName.Trim() + $settingsFile.globalJobSettings.fileNameDelimiter + $currentDate
            # Create a full path for creating the file
            $settingsFile.globalJobSettings.fullLogPath = $settingsFile.globalJobSettings.logPath + $settingsFile.globalJobSettings.logFileName + $settingsFile.globalJobSettings.logExtension
        }
        $errorLog.logFileName = $true
        #================================================================================================================================
        #=                                              process jobs                                                                    =
        #================================================================================================================================
        foreach ($job in $backupSettings.globalJobSettings.jobs.Keys) {
            # check job for source path
            if ($backupSettings.globalJobSettings.jobs.$job.ContainsKey('sourcePath')) {
                $errorLog.Add( ($job + "SourcePath"), $true )
                $settingsFile.globalJobSettings.jobs.$job.sourcePath = Confirm-Paths -pathName $settingsFile.globalJobSettings.jobs.$job.sourcePath.Trim()
            }else {
                # no job path check global
                if ($errorLog.sourcePath) {
                    #global has path, it has been checked an trimmed
                    $settingsFile.globalJobSettings.jobs.$job.sourcePath = $settingsFile.globalJobSettings.sourcePath
                    $errorLog.Add( ($job + "SourcePath"), $true )
                    # Test path to see if it Exists, if not fill in error code
                    if (!(Test-Path -Path $settingsFile.globalJobSettings.jobs.$job.sourcePath)) {
                        $errorLog.sourcePath = [int][errorNumber]::sourcePathExists
                        $errorLog.Add( ($job + "SourcePath"), [int][errorNumber]::jobSourcePathExists)
                    }
                }else{
                    # no path for global or job OR path doesn't exsist
                    $errorLog.sourcePath = [int][errorNumber]::sourcePath
                    $errorLog.Add( ($job.ToString() + "SourcePath"), [int][errorNumber]::jobSourcePath)
                }
            }
            if ($backupSettings.globalJobSettings.jobs.$job.ContainsKey('destinationPath')) {
                #destination path for Job
                $errorLog.Add( ($job.ToString() + "DestinationPath"), $true)
                $settingsFile.globalJobSettings.jobs.$job.destinationPath = Confirm-Paths -pathName $settingsFile.globalJobSettings.jobs.$job.destinationPath.Trim()
            }else {
                # no job path confirm global has it
                if ($errorLog.destinationPath) {
                    #Global has path, it has been checked and trimmed.
                    $settingsFile.globalJobSettings.jobs.$job.destinationPath = $settingsFile.globalJobSettings.destinationPath
                    $errorLog.Add( ($job + "DestinationPath"), $true)
                    # Test path to see if it Exists, if not fill in error code
                    if (!(Test-Path -Path $settingsFile.globalJobSettings.jobs.$job.destinationPath)) {
                        $errorLog.destinationPath = [int][errorNumber]::destinationPathExists
                        $errorLog.Add(($job + "DestinationPathExists"), [int][errorNumber]::jobDestinationPathExists)
                    }
                }else {
                    # No global or job path
                    $errorLog.destinationPath = [int][errorNumber]::destinationPath
                    $errorLog.Add( ($job.ToString() + "DestinationPath"), [int][errorNumber]::jobDestinationPath)
                }
            }
            if ($settingsFile.globalJobSettings.jobs.$job.ContainsKey("compressionLevel")) {
                $errorLog.Add( ($job.ToString() + "compressionLevel"), $true)
                $settingsFile.globalJobSettings.jobs.$job.compressionLevel = $settingsFile.globalJobSettings.jobs.$job.compressionLevel.Trim()
            }else {
                if ($errorLog.compressionLevel) {
                    # No Job compression Level set, copy global to job, it has already been Trimmed
                    $settingsFile.globalJobSettings.jobs.$job.Add("compressionLevel", $settingsFile.globalJobSettings.compressionLevel)
                }else {
                    #$errorLog.compressionLevel = [int][errorNumber]::compressionLevel
                    #$errorLog.Add( ($job.ToString() + "compressionLevel"), [int][errorNumber]::jobCompressionLevel)
                    # Both Global and Job are empty -- Set CompressionLevel default
                    $errorLog.Add( ($job.ToString() + "compressionLevel"), $true)
                    $settingsFile.globalJobSettings.jobs.$job.Add("compressionLevel", "None")
                }
            }
            # check Include Exclude to Global
            if ($settingsFile.globalJobSettings.jobs.$job.ContainsKey('includeExtension')){
                #job has include
                $errorLog.Add( ($job.ToString() + "IncludeExtension"), $true)
                $settingsFile.globalJobSettings.jobs.$job.includeExtension = $settingsFile.globalJobSettings.jobs.$job.includeExtension.Split(',').Trim()
            }else{
                if ($errorLog.includeExtension){
                    #global has include, Move to job
                    #$errorLog.Add( ($job.ToString() + "IncludeExtension"), $false)
                    $settingsFile.globalJobSettings.jobs.$job.Add( "includeExtension", $settingsFile.globalJobSettings.includeExtension.Split(',').Trim())
                }else{
                    #both are false, set to default
                    #$errorLog.includeExtension = [int][errorNumber]::includeExtension
                    #$errorLog.Add( ($job.ToString() + "IncludeExtension"), [int][errorNumber]::jobIncludeExtension)
                    $errorLog.Add( ($job.ToString() + "IncludeExtension"), $true)
                    $settingsFile.globalJobSettings.jobs.$job.Add("includeExtension", "")
                }
                
            }
            # Check exclude Extension, clean it up or set default
            if ($settingsFile.globalJobSettings.jobs.$job.ContainsKey('excludeExtension')) {
                # Job has exclude
                $errorLog.Add( ($job.ToString() + "ExcludeExtension"), $true)
                $settingsFile.globalJobSettings.jobs.$job.excludeExtension = $settingsFile.globalJobSettings.jobs.$job.excludeExtension.Split(',').Trim()
            }else {
                if ($errorLog.excludeExtension) {
                    #global has exclude, move to Job
                    #$errorLog.Add( ($job.ToString() + "ExcludeExtension"), $false)
                    $settingsFile.globalJobSettings.jobs.$job.Add( "excludeExtension", ($settingsFile.globalJobSettings.excludeExtension.Split(',').Trim()))
                }else {
                    # both are missing set to default
                    #$errorLog.includeExtension = [int][errorNumber]::excludeExtension
                    #$errorLog.Add( ($job.ToString() + "ExcludeExtension"), [int][errorNumber]::jobExcludeExtension)
                    $errorLog.Add( ($job.ToString() + "ExcludeExtension"), $true)
                    $settingsFile.globalJobSettings.jobs.$job.Add( "excludeExtension", "")
                }
            }
            # Check for Archive name, clean up Archive Name Or set default
            if ($settingsFile.globalJobSettings.jobs.$job.ContainsKey('archiveName')) {
                # Clean
                $settingsFile.globalJobSettings.jobs.$job.archiveName = $settingsFile.globalJobSettings.jobs.$job.archiveName.Trim()
                # Check to see if 'archiveName' is After to any variable and put a 'fileNameDelimiter' between
                if ($settingsFile.globalJobSettings.jobs.$job.archiveName.Contains(("%" + $settingsFile.globalJobSettings.jobs.$job.archiveName))){
                    $settingsFile.globalJobSettings.jobs.$job.archiveName = $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace(("%" + $settingsFile.globalJobSettings.jobs.$job.archiveName), ("%"+ $settingsFile.globalJobSettings.fileNameDelimiter + $settingsFile.globalJobSettings.jobs.$job.archiveName))
                }
                # Check to see if 'archiveName' is Before to any variable and put a 'fileNameDelimiter' between
                if ($settingsFile.globalJobSettings.jobs.$job.archiveName.Contains(($settingsFile.globalJobSettings.jobs.$job.archiveName + "%"))){
                    $settingsFile.globalJobSettings.jobs.$job.archiveName = $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace(($settingsFile.globalJobSettings.jobs.$job.archiveName + "%"), ($settingsFile.globalJobSettings.jobs.$job.archiveName + $settingsFile.globalJobSettings.fileNameDelimiter + "%"))
                }
                # Check for multiple variables, add the 'fileNameDelimiter' between the %%
                if ($settingsFile.globalJobSettings.jobs.$job.archiveName.Contains("%%")){
                    $settingsFile.globalJobSettings.jobs.$job.archiveName = $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace("%%", ("%"+ $settingsFile.globalJobSettings.fileNameDelimiter +"%"))
                }
                # Check for %DATE%
                if ($settingsFile.globalJobSettings.jobs.$job.archiveName.Contains('%DATE%')){
                    #$archiveName = $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace("%DATE%", $currentDate)
                    $settingsFile.globalJobSettings.jobs.$job.archiveName = $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace("%DATE%", $currentDate)
                }
                # Check for %JOBNAME%
                if ($settingsFile.globalJobSettings.jobs.$job.archiveName.Contains('%JOBNAME%')) {
                    #$archiveName += $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace("%JOBNAME%", $job)
                    $settingsFile.globalJobSettings.jobs.$job.archiveName = $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace("%JOBNAME%", $job)
                }
                # Check for %DEFAULT%
                if ($settingsFile.globalJobSettings.jobs.$job.archiveName.Contains('%DEFAULT%')) {
                    #Default Archive Name [JobName][fileNameDelimiter]%DATE%.[ArchiveType]
                    #$defaultArchiveName = [fileNameDelimiter] + $currentDate
                    #$archiveName += $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace("%DEFAULT%", ($job + $settingsFile.globalJobSettings.fileNameDelimiter + $currentDate))
                    $settingsFile.globalJobSettings.jobs.$job.archiveName = $settingsFile.globalJobSettings.jobs.$job.archiveName.Replace("%DEFAULT%", ($job + $settingsFile.globalJobSettings.fileNameDelimiter + $currentDate))
                }
                # Have we replaced any of the %% items, Update archiveName
                <#if ($null -ne $archiveName) {
                    $settingsFile.globalJobSettings.jobs.$job.archiveName = $archiveName
                }#>
            }else {
                $settingsFile.globalJobSettings.jobs.$job.archiveName = ($job + $settingsFile.globalJobSettings.fileNameDelimiter + $currentDate)
            }
        }
        #================================================================================================================================
        #=                                          END process jobs                                                                    =
        #================================================================================================================================
    }
    
    end {
        # Return our Error log
        , $errorLog
    }
}

# Check PS version - Minimum Version 6.0
If (6 -gt ($PSVersionTable.PSVersion.Major)) {
    "PowerShell version mismatch. Minimum version required PowerShell 6.0" >> $tmpFile
    Dump-Log -logFile $tmpFile
    return [int][errorNumber]::psVerionMisMatch
}

# Load modules
if (($null -eq (Get-Module -ListAvailable -Name 7Zip4Powershell)) -and ($null -ne (Get-PackageProvider -ListAvailable -Name NuGet))){
    Install-Module -Name 7Zip4Powershell -RequiredVersion 1.9.0 -Confirm:$false -Force 4>> $tmpFile
} elseif ($null -eq (Get-PackageProvider -ListAvailable -Name NuGet)){
    "Device does not have NuGet as a package provider. Can not install 7Zip4Powershell." >> $tmpFile
    "Manually install with Install-Module -Name 7Zip4Powershell as ADMINISTRATOR." >> $tmpFile
    return [int][errorNumber]::nuGetError
}else {
    try {
        Import-Module 7zip4powershell -Verbose 4>> $tmpFile
    }
    catch {
        "Error loading module 7Zip4Powershell. Does the computer have this module installed?" >> $tmpFile
        "Manually install with Install-Module -Name 7Zip4Powershell as ADMINISTRATOR." >> $tmpFile
        return [int][errorNumber]::moduleLoad
    }
}

# Read in json settings file
if ((Test-Path -PathType Leaf -Path $jsonSettings) -and (Get-Item $jsonSettings).Length -gt 0) {
    $backupSettings = Get-jsonFile -filePath $jsonSettings -hashTable
    $backupSettings.GetType() >> $tmpFile
    $backupSettings >> $tmpFile
}else {
    "Error settings file does not exist." >> $tmpFile
    return [int][errorNumber]::settingFileExists
}


# check for global settings and set variables to them
# if no global settings set them based on the jobs.
# Check logs first to log any issues with the settings file

#Confirm Settings file
# https://stackoverflow.com/questions/29596634/how-to-define-named-parameter-as-ref-in-powershell
"`nStarting to confirming json file settings" >> $tmpFile
$errorLog = Confirm-Settings -settingsFile ([ref]$backupSettings)
"`nCompleted confirming json file settings, dumping Confirm-Settings Error log:" >> $tmpFile
$errorLog *>> $tmpFile


# Create Log file in logPath
$logFile = [System.IO.File]
# Test-Path $backupSettings.globalJobSettings.logPath
# IF errorLog.logPath -eq $true the path is valid and filled out. If anything else...exit script returning error code.
if ($errorLog.logPath) {
    $backupSettings.globalJobSettings.logPath >> $tmpFile
    ($backupSettings.globalJobSettings.logFileName + $backupSettings.globalJobSettings.logExtension) >> $tmpFile
    #$logFilePath = $backupSettings.globalJobSettings.logPath + ($backupSettings.globalJobSettings.logFileName + $backupSettings.globalJobSettings.logExtension)
    $logFile = New-Item -ItemType File -Path $backupSettings.globalJobSettings.fullLogPath -Confirm:$false -Force -Verbose 4>>$tmpFile
    #$logFile = Get-Item -Path $logFilePath -Verbose -Debug >>$tmpFile
        
    <#create logfile Name
    $logFileName = $logPath + $backupSettings. + (Get-Date -Format yyy-MMM-dd).toString() + ".log"
    if( !(Test-Path $logFileName)) {
        New-Item -ItemType File -Path $logFileName -Force -confirm:$false -Verbose -Debug *>>$tmpFile
    }#>
}else {
    # Log Path doesn't exist - Exit and dump temp log to script location and rename with Date.
    Dump-Log -logFile $tmpFile
    return $PSScriptRoot
}
# dump Temp Log file to log file
Get-Content -path $tmpFile | out-file -FilePath $logFile.FullName -Append
# Remove temp Log file
Remove-Item $tmpFile

#===================================#
# Process Jobs in JSON file         #
#===================================#
foreach ($job in $backupSettings.globalJobSettings.jobs.Keys) {
    # job logs ---- MOVE TO JOB PROCCESSING
    "`n$job`nCreating tmp log file:" >> $logFile
    if ($errorLog.logPath) {
        # Create our new variable for this job, holding this jobs Logging
        if ($null -eq (Get-Variable -Name $job -ValueOnly -ErrorAction SilentlyContinue)) {
            New-Variable -Name $job -Value (Get-Item ([System.IO.Path]::GetTempFileName())) -Scope 0 -Verbose 4>> $logFile
            #$jobLog1 = [System.IO.Path]::GetTempFileName()
        }else {
            Remove-Variable -Name $job
            New-Variable -Name $job -Value (Get-Item ([System.IO.Path]::GetTempFileName())) -Scope 0 -Verbose 4>> $logFile
        }
        
    }
    #check that we have a source path
    if ($errorLog.($job + "sourcePath")) {
        #set-location 
        Push-Location $backupSettings.globalJobSettings.sourcePath -Verbose 4>> $logFile
        #set-location $sourcePath
    }else {
        "No source path provided in setting file" >> $logFile
        $errorLog.($job + "sourcePath") >> $logFile
        return $errorLog.($job + "sourcePath")
    }
    #Check that we have a destination and it Exists
    if ($errorLog.($job + "destinationPath")) {
       # Create full Archive Name
        $archiveFullName = $backupSettings.globalJobSettings.jobs.$job.destinationPath + $backupSettings.globalJobSettings.jobs.$job.archiveName + $backupSettings.globalJobSettings.archiveExt
        "Archive Name: $archiveFullName" >> $logFile
        #Pause 
        # Does the location exsist
        if (!(Test-Path -PathType Container -Path ($backupSettings.globalJobSettings.jobs.$job.destinationPath))){
            New-Item -ItemType Directory -Path ($backupSettings.globalJobSettings.jobs.$job.destinationPath)
        }
        # Log Archive path and name
        Add-Content -path $logFile -Value $($job + " archive location: " + $archiveFullName)
        # Start copy job
        # threadJob doesn't work in a Task Schedule
        <# Threadjob
        $jobNumber = Start-ThreadJob `
            -ScriptBlock {Get-ChildItem ($using:backupSettings.globalJobSettings.jobs.$job.sourcePath + '*') -File `
            -Exclude $using:backupSettings.globalJobSettings.jobs.$job.excludeExtension `
            -Include $using:backupSettings.globalJobSettings.jobs.$job.includeExtension |
                Compress-7Zip -ArchiveFileName $using:archiveFullName -CompressionLevel $using:backupSettings.globalJobSettings.jobs.$job.compressionLevel `
                -Format $using:backupSettings.globalJobSettings.archiveType -Verbose -Debug} -Verbose *>> (Get-Variable -Name $job)
        #>
        Get-ChildItem $($backupSettings.globalJobSettings.jobs.$job.sourcePath + '*') -File `
            -Exclude $backupSettings.globalJobSettings.jobs.$job.excludeExtension `
            -Include $backupSettings.globalJobSettings.jobs.$job.includeExtension | 
            Compress-7Zip -ArchiveFileName $archiveFullName `
                -CompressionLevel $backupSettings.globalJobSettings.jobs.$job.compressionLevel `
                -Format $backupSettings.globalJobSettings.archiveType -Verbose 4>> (Get-Variable -Name $job -ValueOnly).FullName
        # for Threaded jobs
        #$jobNumber.Command *>> (Get-Variable -Name $job)

        # Dump log file
        "`n" + $job + " log:" >> $logFile
        Get-Content -path (Get-Variable -Name $job -ValueOnly).FullName >> $logFile
        Remove-Item (Get-Variable -Name $job -ValueOnly).FullName
        Remove-Variable -Name $job -Scope global -Force -ErrorAction SilentlyContinue
    }else{
        "Destination path error, check the settings file." >> $logFile
         $errorLog.($job + "destinationPath") >> $logFile
        return $errorLog.($job + "destinationPath")
    }
}
# for Threaded jobs
#$jobList = Get-Job -Verbose *>> $logFile
# for Threaded jobs
#Get-Job | Wait-Job *>> $logFile

"`n`nEnd backup processing: $(Get-Date)" >> $logFile

# For threaded jobs
#Get-Job | Remove-Job

# return to original location
Pop-Location

# successfull run return 0
return 0
# SIG # Begin signature block
# MIIJ+QYJKoZIhvcNAQcCoIIJ6jCCCeYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAnQXec11qz7UU1
# 5Qc8603o0Cx+gMEuAL0lQHjuZhvOEaCCBzUwggcxMIIFGaADAgECAhMsAAAO1W/C
# GJKYdeKkAAEAAA7VMA0GCSqGSIb3DQEBDQUAMFExEjAQBgoJkiaJk/IsZAEZFgJD
# QTEgMB4GCgmSJomT8ixkARkWEENMRUFSV0FURVJDT1VOVFkxGTAXBgNVBAMTEENX
# LVItQ09SRUFEMDEtQ0EwHhcNMjMwMzI0MTkyODQzWhcNMjQwMzIzMTkyODQzWjCB
# izESMBAGCgmSJomT8ixkARkWAkNBMSAwHgYKCZImiZPyLGQBGRYQQ0xFQVJXQVRF
# UkNPVU5UWTEaMBgGA1UECxMRQ2xlYXJ3YXRlciBDb3VudHkxDTALBgNVBAsTBFRJ
# TVMxDjAMBgNVBAsTBVVzZXJzMRgwFgYDVQQDEw9CcmFkbGV5IFdlbHlnYW4wggEi
# MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDIVmI9LxJ/BlzFNFnYeM/hN5Z6
# iBRbf/6jiEVx4HVL5wE7CeJknzbrFEO+ebBDvzXE2JcyQcJmDOvipCeFQCW5m3Pl
# nMWSa+x1FCnxDCKswQAOg1B2B7Gste4KS4xRgvHzEfg4Tuyfef2s/sBPv3jcWvqK
# kX0B4iUux4y3jnZJ+hMYlo8lGS4vn1NT/Hygx3IL52n6sBWBNKSYrJdEGy2QW6MC
# 1PmBPf9L8O3yoIGcrEm33d5d2uWLKbsrIhIn3EFTvmq1vcfwIRJEuQYJs8Um0Ubo
# jW8kt8UavFjoC8SdW+MAnDVd5YDHyORT8+aXDebtsI7l2aCO21s9Gp0KrV2xAgMB
# AAGjggLFMIICwTAlBgkrBgEEAYI3FAIEGB4WAEMAbwBkAGUAUwBpAGcAbgBpAG4A
# ZzATBgNVHSUEDDAKBggrBgEFBQcDAzAOBgNVHQ8BAf8EBAMCB4AwHQYDVR0OBBYE
# FPiGetYysti/HmoXiHwRrKL70B91MB8GA1UdIwQYMBaAFILZocDpyynoLzRXnB0i
# V0ev944kMIHcBgNVHR8EgdQwgdEwgc6ggcuggciGgcVsZGFwOi8vL0NOPUNXLVIt
# Q09SRUFEMDEtQ0EsQ049Q1ctUi1Db3JlQUQwMSxDTj1DRFAsQ049UHVibGljJTIw
# S2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1D
# TEVBUldBVEVSQ09VTlRZLERDPUNBP2NlcnRpZmljYXRlUmV2b2NhdGlvbkxpc3Q/
# YmFzZT9vYmplY3RDbGFzcz1jUkxEaXN0cmlidXRpb25Qb2ludDCBygYIKwYBBQUH
# AQEEgb0wgbowgbcGCCsGAQUFBzAChoGqbGRhcDovLy9DTj1DVy1SLUNPUkVBRDAx
# LUNBLENOPUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNl
# cyxDTj1Db25maWd1cmF0aW9uLERDPUNMRUFSV0FURVJDT1VOVFksREM9Q0E/Y0FD
# ZXJ0aWZpY2F0ZT9iYXNlP29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3Jp
# dHkwNwYDVR0RBDAwLqAsBgorBgEEAYI3FAIDoB4MHGJ3ZWx5Z2FuQENMRUFSV0FU
# RVJDT1VOVFkuQ0EwTgYJKwYBBAGCNxkCBEEwP6A9BgorBgEEAYI3GQIBoC8ELVMt
# MS01LTIxLTM2NDMyOTU0OTgtMjk0Mzk3Mzc5MS05NjgwMDQ0OTMtMjcwMDANBgkq
# hkiG9w0BAQ0FAAOCAgEAky5x+RfjRnoQFQ25cuEilr2mkwuJo8Iefghsvmr6UNeW
# VY6UUhpZBNvDWgq25mIcm72m4HXR0daXZ60WxF9qoCFDMILRkUQOvuwumWwQEMmz
# Iv1TsxpOg6IOPgHaxWCjn0A+7gyOVtMWia7rQOxlLERnYyNgQZN3LMdrPZf1sc5D
# 7O9dXpCSM4rKOY8kEIOZstJqQgTYov3JfCNIf0dYFj2MWjBOXxdzvxGHBC8naWEW
# oXYvCH2U+g3EHgyd6mwzw4mpm64PIiGoJu0V5m/HCq4YH5tA6luiF5aB8D0J6Z+y
# eTw1IBvbKgKUPMCH3+ZkFlAoLptGd8oqYoJx5topENBXPzgMXHhfUKoQkNUYePsL
# 5NS9aCDG+W+SIvnrXxMWQQC0+ZJYhWhMe2CTbHh9L1FfxRZkNUE4Ry3JCaVRJBAr
# SQ3SQ8FTFHKya7vi4Ng8CxA9/se9zWa1FQclmqFymj0PDcOF4PTFvjke/D5MNj3e
# sHSyh+BwjTU9SKx8+nBFy5ZArm/KrVl4wH4tqNesXTi4WGuxiKJX0tihy1cvnEE1
# +0nEtmb69qn09IlId80wkgqRPw4ViTl+K4WO4KkanBrrVLUndGGLkyeeDSQV948d
# ACLPe4XAQEWni0DW9YvyIxhRPcyQY3cze6qSwTCKr9SSOqe7i8Swfhe4VPgoC0cx
# ggIaMIICFgIBATBoMFExEjAQBgoJkiaJk/IsZAEZFgJDQTEgMB4GCgmSJomT8ixk
# ARkWEENMRUFSV0FURVJDT1VOVFkxGTAXBgNVBAMTEENXLVItQ09SRUFEMDEtQ0EC
# EywAAA7Vb8IYkph14qQAAQAADtUwDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGC
# NwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgUUpTKeya
# wiuaKQ9epUs6qMCgK9gUZB5uVLhrNRM0QCUwDQYJKoZIhvcNAQEBBQAEggEAF1JN
# VJNyUUwbyN7Bghk/X2xQXk/2+3tLaqDyXsEzMCUphk7fy9jfsP3k+oiheAqmN3Ie
# 7EBpnoYBQX6tz73mu98IeBUmd5YB3GdCZXw1gdjrg8p+DWScXe/M512s0Kw7Wjqo
# RTJBypZUYZ8D9fzmdAcaCqx0xrs7AOMyZNBbNLsdhxJ9bcx0EFJ2D21lZ/fXdmvn
# JZi6eaok+t0KVG7/NxFiWkaTRnFqyGeT3QayclS+mItow4KJ22LE8KU3LfFpW6ro
# Mq98hMCAM88ldp0994GAj3ZIO09vRI5TJzgI+JmK5CE3Likt4bVd8vpjsBEIkq+N
# j9wktaPg4DU8voun/Q==
# SIG # End signature block
