# CopyJob
PowerShell Copy job script

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
                        File will copy and compress at the file level, recursively.
                         If 'compession': None is specified it will just copy the files

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
        moduleLoad = -2
        settingFileExists = -3
        nuGetError = -4
        psVerionMisMatch = -5
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
    PowerShell 6.0+
    Command line execution
    c:\>"C:\Program Files\PowerShell\7\pwsh.exe" -file e:\CAMAlot-CopyBackups-v4.1.ps1 -jsonSettings "E:\backupSettings.json"
    PS C:\>.\CAMAlot-CopyBackups-v4.1.ps1 -jsonSettings "E:\backupSettings.json"

