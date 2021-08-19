# Change the execution policy to unblock importing AzFilesHybrid.psm1 module
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser

# Navigate to where AzFilesHybrid is unzipped and stored and run to copy the files into your path
.\CopyToPSPath.ps1 

# Import AzFilesHybrid module
Import-Module -Name AzFilesHybrid

# Login with an Azure AD credential that has either storage account owner or contributer Azure role assignment
# If you are logging into an Azure environment other than Public (ex. AzureUSGovernment) you will need to specify that.
# See https://docs.microsoft.com/azure/azure-government/documentation-government-get-started-connect-with-ps
# for more information.
Connect-AzAccount

# Define variables, $StorageAccountName currently has a maximum limit of 15 characters
$SubscriptionId = (Get-AzContext).Subscription.ID
$ResourceGroupName = "rg-storage-log-test"
$StorageAccountName = "logtestsa01"
$DomainAccountType = "ComputerAccount" # Default is set as ComputerAccount
# If you don't provide the OU name as an input parameter, the AD identity that represents the storage account is created under the root directory.
$OuDistinguishedName = "OU=Storage,OU=Azure,DC=pavzetti,DC=com"
# Specify the encryption agorithm used for Kerberos authentication. Default is configured as "'RC4','AES256'" which supports both 'RC4' and 'AES256' encryption.
$EncryptionType = "<AES256|RC4|AES256,RC4>"
# NTFS permission variables
$driveLetter = "x"
$userEmail = "adpavlik@pavzetti.onmicrosoft.com"
# AD DS group synced to AAD
$group = "avdUsers"
# file share name
$shareName = "filesharetest-01"

# Create storage account
New-AzStorageAccount -ResourceGroupName $resourceGroupName `
                     -Name $storageAccountName `
                     -Location eastus `
                     -SkuName Standard_LRS

# Create file share

New-AzRmStorageShare `
        -ResourceGroupName $resourceGroupName `
        -StorageAccountName $storageAccountName `
        -Name $shareName `
        -AccessTier TransactionOptimized `
        -QuotaGiB 1024 | `
    Out-Null

# Select the target subscription for the current session
Select-AzSubscription -SubscriptionId $SubscriptionId 

# Register the target storage account with your active directory environment under the target OU (for example: specify the OU with Name as "UserAccounts" or DistinguishedName as "OU=UserAccounts,DC=CONTOSO,DC=COM"). 
# You can use to this PowerShell cmdlet: Get-ADOrganizationalUnit to find the Name and DistinguishedName of your target OU. If you are using the OU Name, specify it with -OrganizationalUnitName as shown below. If you are using the OU DistinguishedName, you can set it with -OrganizationalUnitDistinguishedName. You can choose to provide one of the two names to specify the target OU.
# You can choose to create the identity that represents the storage account as either a Service Logon Account or Computer Account (default parameter value), depends on the AD permission you have and preference. 
# Run Get-Help Join-AzStorageAccountForAuth for more details on this cmdlet.

Join-AzStorageAccountForAuth `
        -ResourceGroupName $ResourceGroupName `
        -StorageAccountName $StorageAccountName `
        -DomainAccountType $DomainAccountType `
        -OrganizationalUnitDistinguishedName $OuDistinguishedName `
        -EncryptionType $EncryptionType

# Run the command below if you want to enable AES 256 authentication. If you plan to use RC4, you can skip this step.
# Uses SamAccountName, must be less then 15 characters
Update-AzStorageAccountAuthForAES256 -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName

# You can run the Debug-AzStorageAccountAuth cmdlet to conduct a set of basic checks on your AD configuration with the logged on AD user. This cmdlet is supported on AzFilesHybrid v0.1.2+ version. For more details on the checks performed in this cmdlet, see Azure Files Windows troubleshooting guide.
Debug-AzStorageAccountAuth -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName -Verbose

# Get/format the UNC path
$uncPath = (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName `
                            -StorageAccountName $StorageAccountName).PrimaryEndpoints.File
$uncPath = $uncPath.Replace('https://','\\')
$uncPath = $uncPath.Replace('/','\')
$uncPath = $uncPath + $shareName

# Get the storage account key
$saKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName `
                                  -Name $StorageAccountName)[0].Value

# Configure NTFS permissions
net use z: $uncPath $saKey /user:Azure\$StorageAccountName

# Review access
icacls ${driveLetter}:

Start-Process icacls -ArgumentList "X: /grant $($Group):(M)" -Wait -NoNewWindow -PassThru -ErrorAction 'Stop'
Start-Process icacls -ArgumentList 'X: /grant "Creator Owner":(OI)(CI)(IO)(M)' -Wait -NoNewWindow -PassThru -ErrorAction 'Stop'
Start-Process icacls -ArgumentList 'X: /remove "Authenticated Users"' -Wait -NoNewWindow -PassThru -ErrorAction 'Stop'
Start-Process icacls -ArgumentList 'X: /remove "Builtin\Users"' -Wait -NoNewWindow -PassThru -ErrorAction 'Stop'
