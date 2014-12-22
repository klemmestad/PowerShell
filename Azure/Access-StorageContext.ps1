param(
     # The name of the storage account to enumerate.
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName
)

$storageAccount = Get-AzureStorageAccount -StorageAccountName $StorageAccountName -ErrorAction SilentlyContinue
if ($storageAccount -eq $null)
{
    throw "The storage account specified does not exist in this subscription."
}
 
# Instantiate a storage context for the storage account.
$storagePrimaryKey = (Get-AzureStorageKey -StorageAccountName $StorageAccountName).Primary
$storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storagePrimaryKey