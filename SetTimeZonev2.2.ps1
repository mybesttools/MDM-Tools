# ---------------------------------------------------------------------------- #
# Author(s)    : Mike van der Sluis - mybesttools                              #
#                Peter Klapwijk - www.inthecloud247.com                        #
#                Johannes Muller - Co-author @ www.2azure.nl                   #
#                Original script from Koen Van den Broeck                      #
# Version      : 2.2                                                           #
#                                                                              #
# Description  : Automatically configure the time zone using timezonedb        #
#                Uses `timezone/enumWindows` API to dynamically map time zones #
#                                                                              #
# Notes:                                                                       #
# https://ipinfo.io/ has a limit of 50k requests per month without a license   #
#                                                                              #
# This script is provided "As-Is" without any warranties                       #
#                                                                              #
# ---------------------------------------------------------------------------- #

# Microsoft Intune Management Extension might start a 32-bit PowerShell instance. If so, restart as 64-bit PowerShell
If ($ENV:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    Try {
        &"$ENV:WINDIR\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -File $PSCOMMANDPATH
    }
    Catch {
        Throw "Failed to start $PSCOMMANDPATH"
    }
    Exit
}

#region Functions
Function CleanUpAndExit() {
    Param(
        [Parameter(Mandatory=$True)][String]$ErrorLevel
    )

    # Write results to registry for Intune Detection
    $Key = "HKEY_LOCAL_MACHINE\Software\$StoreResults"
    $NOW = Get-Date -Format "yyyyMMdd-hhmmss"

    If ($ErrorLevel -eq "0") {
        [microsoft.win32.registry]::SetValue($Key, "Success", $NOW)
    } else {
        [microsoft.win32.registry]::SetValue($Key, "Failure", $NOW)
        [microsoft.win32.registry]::SetValue($Key, "Error Code", $Errorlevel)
    }
    
    # Exit Script with the specified ErrorLevel
    EXIT $ErrorLevel
}
# Function to get geolocation data from IP address
function Get-GeoLocation {
    try {
        # Using ip-api.com (free service, no API key required)
        $geoData = Invoke-RestMethod -Uri "http://ip-api.com/json/" -Method Get
        return $geoData
    }
    catch {
        Write-Error "Failed to get geolocation data: $_"
        return $null
    }
}
# Function to get Windows time zone from coordinates
function Get-TimeZoneFromCoordinates {
    param (
        [Parameter(Mandatory=$true)]
        [double]$Latitude,
         
        [Parameter(Mandatory=$true)]
        [double]$Longitude
    )
     
    try {
        # Using TimeZoneDB API (requires free API key)
        # Replace YOUR_API_KEY with an actual key from https://timezonedb.com/
        $apiKey = "YOUR-API-KEY-HERE"
        $uri = "http://api.timezonedb.com/v2.1/get-time-zone?key=$apiKey&format=json&by=position&lat=$Latitude&lng=$Longitude"
         
        $tzData = Invoke-RestMethod -Uri $uri -Method Get
         
        # Convert IANA time zone to Windows time zone
        $ianaTimeZone = $tzData.zoneName
        $windowsTimeZone = Get-WindowsTimeZoneFromIANA -IANATimeZone $ianaTimeZone
         
        return $windowsTimeZone
    }
    catch {
        Write-Error "Failed to get time zone data: $_"
        return $null
    }
}
# Function to convert IANA time zone to Windows time zone
function Get-WindowsTimeZoneFromIANA {
    param (
        [Parameter(Mandatory=$true)]
        [string]$IANATimeZone
    )
     
    # Simplified mapping of common IANA to Windows time zones
    $tzMapping = @{
        "America/New_York" = "Eastern Standard Time"
        "America/Chicago" = "Central Standard Time"
        "America/Denver" = "Mountain Standard Time"
        "America/Los_Angeles" = "Pacific Standard Time"
        "Europe/London" = "GMT Standard Time"
        "Europe/Paris" = "Romance Standard Time"
        "Asia/Tokyo" = "Tokyo Standard Time"
        # Add more mappings as needed
    }
     
    if ($tzMapping.ContainsKey($IANATimeZone)) {
        return $tzMapping[$IANATimeZone]
    }
    else {
        # Default to UTC if mapping not found
        Write-Warning "Time zone mapping not found for $IANATimeZone. Defaulting to UTC."
        return "UTC"
    }
}
#endregion Functions

# ------------------------------------------------------------------------------------------------------- #
# Variables, change to your needs
# ------------------------------------------------------------------------------------------------------- #
$StoreResults = "COMPANY\TimeZone\v2.2"

# Start Transcript
Start-Transcript -Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\$($(Split-Path $PSCommandPath -Leaf).ToLower().Replace(".ps1",".log"))" | Out-Null

$currentTZ=$Null

# Main script execution
try {
    # Get geolocation data
    $geoLocation = Get-GeoLocation
     
    if ($geoLocation) {
        # Get time zone from coordinates
        $timeZone = Get-TimeZoneFromCoordinates -Latitude $geoLocation.lat -Longitude $geoLocation.lon
         
        if ($timeZone) {
            # Set the system time zone
            Set-TimeZone -Id $timeZone
            Write-Host "Successfully set time zone to: $timeZone"
             
            # Verify the change
            $currentTZ = Get-TimeZone
            Write-Host "Current time zone: $($currentTZ.Id)"

        }
    }
}
catch {
    Write-Error "Script execution failed: $_"
    exit 1
}

If (![string]::IsNullOrEmpty($currentTZ)) {
    Write-Output "Mapped Country ($CountryCode) to Windows Time Zone: $currentTZ"
} else {
    Write-Output "No matching Windows Time Zone found for country: $CountryCode"
    CleanUpAndExit -ErrorLevel 103
}

# Set the Windows time zone
Set-TimeZone -Id $currentTZ
Write-Output "Successfully set Windows Time Zone: $currentTZ"

CleanUpAndExit -ErrorLevel 0

Stop-Transcript
