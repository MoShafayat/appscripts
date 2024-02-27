<#
    .SYNOPSIS
        Retrieves blobs from an Azure Storage account and downloads them to a specified directory.

    .DESCRIPTION
        The `Get-AzureBlobs.ps1` script uses the Azure Storage REST API to list the blobs in a container and filter them by a specified folder name. It then downloads each blob to the specified download directory. The script handles illegal characters in the file names by creating temporary files.

    .PARAMETER storageAccountName
        The name of the Azure Storage account.

    .PARAMETER containerName
        The name of the container to retrieve blobs from.

    .PARAMETER appFolder
        The name of the application folder on the storage account to filter blobs by.

    .PARAMETER sasToken
        The Shared Access Signature (SAS) token for the Azure Storage account.

    .PARAMETER downloadDirectory
        The directory to download the blobs to. Defaults to the current directory.

    .EXAMPLE
        .\Get-AzureBlobs.ps1 -storageAccountName "mystorageaccount" -containerName "mycontainer" -appFolder "myfolder" -sasToken "sp=rl&st=2023-09-25T23:27:07Z&se=2023-09-26T07:27:07Z&spr=https&sv=2022-11-02&sr=c&sig=OguP6tiEV0ULbXRki0PRm3sRragmmBWU8iskj0ddMb0%3D" -downloadDirectory "C:\Downloads"

    .INPUTS
		None

    .NOTES
		Version:				0.01
		Author:					Thor Schutze (thor.schutze@arinco.com.au)
		Creation Date:			26/09/2023
		Purpose/Change:			Initial script development

        Required Modules:
                                None

		Dependencies:
                                None

        Limitations:            This script requires the following permissions in Azure (At minimum):
                                - A valid sas token for the storage account
                                - Must have Read and List permissions on the storage account
                                - The script is executed by intune as system

        Supported Platforms*:   Windows 10
                                *Currently not tested against other platforms

		Version History:
                                [26/09/2023 - 0.01 - Thor Schutze]: Initial release

#>
param (
    [Parameter(Mandatory=$false)]
    [string]$storageAccountName = "fkaeprodavdappst",

    [Parameter(Mandatory=$false)]
    [string]$containerName = "applications",

    [Parameter(Mandatory=$false)]
    [string]$appFolder = "CreativeCloud2024",

    [Parameter(Mandatory=$false)]
    [string]$appCache = ".",

    [Parameter(Mandatory=$false)]
    [string]$sasToken = "?sp=rl&st=2023-10-02T05:11:20Z&se=2030-03-06T13:11:20Z&spr=https&sv=2022-11-02&sr=c&sig=ceDK74js4%2BM8soBmeZ%2FdwqT8aV4WMZiItoj4VT4bqBQ%3D"
)

function Get-FromBlob {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$downloadDirectory = ".",

        [Parameter(Mandatory=$true)]
        [string]$storageAccount,

        [Parameter(Mandatory=$true)]
        [string]$container,

        [Parameter(Mandatory=$true)]
        [string]$token,

        [Parameter(Mandatory=$true)]
        [string]$folder
    )

    begin {
        $global:ProgressPreference = 'SilentlyContinue'
        $illegalChar = '['
        $continuationToken = $null
        $url = "https://$storageAccount.blob.core.windows.net/$container"
        $operation = "&restype=container&comp=list"
    }

    process {
        try {
            do {
                $uri = "$url/$token$operation"
                if ($continuationToken) {
                    $uri += "&marker=$continuationToken"
                }
                $response = Invoke-WebRequest -Uri $uri -Method GET -ErrorAction Stop
                $xml = [xml]$response.Content.Substring(3)
                $blobs = $xml.EnumerationResults.Blobs.Blob | Where-Object {$_.Name -like "*$folder*"}
                foreach ($blob in $blobs) {
                    $escapeUriString = [uri]::EscapeDataString($blob.Name)
                    $uri = ("$url/$escapeUriString$token")
                    $fileName = ("$downloadDirectory\$($blob.Name)")
                    write-host "$uri"
                    try {
                        New-Item $fileName -Force -Verbose
                        if ($fileName.Contains($illegalChar)){
                            $newFile = New-TemporaryFile
                            $tmpFileCreated = $true
                        }
                        else {
                            $newFile = $fileName
                            $tmpFileCreated = $false
                        }
                        Invoke-WebRequest -Uri $uri -OutFile "$newFile" -Method GET -ErrorAction Stop
                        if($tmpFileCreated){
                            Move-Item -Force -LiteralPath $newFile -Destination $fileName
                        }

                    }
                    catch {
                        Write-Host "Failed to download '$uri'"
                        Write-Host "$($error[0])" -ForegroundColor Red
                        break
                    }
                }
                $continuationToken = $xml.EnumerationResults.NextMarker
            } while ($continuationToken)
        }
        catch {
            Write-Host "Error calling uri: '$uri'"
            Write-Host "$($error[0])" -ForegroundColor Red
            break
        }
    }

    end {
        $global:ProgressPreference = 'Continue'
    }
}

Get-FromBlob -storageAccount $storageAccountName -container $containerName -token $sasToken -folder $appFolder -downloadDirectory $appCache

$ExePath = "$appCache\$appFolder\source\Deploy-Application.ps1"
# Execute the Deploy-Application.ps1 script in NonInteractive mode
Invoke-Expression "& '$ExePath' -DeployMode 'NonInteractive'"
