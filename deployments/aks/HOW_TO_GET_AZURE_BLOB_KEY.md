# How to Get Azure Blob Storage Account Key

The `azure_blob_account_key` is the access key for your Azure Storage Account. Here are several ways to get it:

## Option 1: Azure Portal (Web UI)

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Storage accounts**
3. Click on your storage account name
4. In the left menu, under **Security + networking**, click **Access keys**
5. You'll see two keys: `key1` and `key2` (either one works)
6. Click the **Show** button next to the key you want to use
7. Click the **Copy** button to copy the key

## Option 2: Azure CLI

```bash
# List storage accounts
az storage account list --output table

# Get the keys for a specific storage account
az storage account keys list \
  --resource-group <your-resource-group-name> \
  --account-name <your-storage-account-name>

# Or get just the first key directly
az storage account keys list \
  --resource-group <your-resource-group-name> \
  --account-name <your-storage-account-name> \
  --query "[0].value" \
  --output tsv
```

## Option 3: PowerShell (Azure PowerShell)

```powershell
# Get storage account keys
$storageAccount = Get-AzStorageAccount `
  -ResourceGroupName "<your-resource-group-name>" `
  -Name "<your-storage-account-name>"

# Get key1
$storageAccount | Get-AzStorageAccountKey | Where-Object {$_.KeyName -eq "key1"} | Select-Object -ExpandProperty Value

# Or get key2
$storageAccount | Get-AzStorageAccountKey | Where-Object {$_.KeyName -eq "key2"} | Select-Object -ExpandProperty Value
```

## Create Storage Account (if you don't have one)

If you need to create a new storage account:

```bash
# Create resource group (if needed)
az group create --name <resource-group-name> --location eastus

# Create storage account
az storage account create \
  --name <storage-account-name> \
  --resource-group <resource-group-name> \
  --location eastus \
  --sku Standard_LRS \
  --kind StorageV2

# Create container
az storage container create \
  --name <container-name> \
  --account-name <storage-account-name> \
  --account-key <key-from-above>
```

## Security Best Practices

⚠️ **Important Security Notes:**

1. **Never commit keys to Git** - The `.gitignore` file already excludes `*.tfvars` files
2. **Use Key Vault** - For production, consider using Azure Key Vault to store secrets
3. **Rotate keys regularly** - Azure Storage accounts have 2 keys - you can rotate them
4. **Use managed identity** - Instead of keys, consider using managed identity for AKS access

## Using the Key in Terraform

Add it to your `terraform.tfvars` file (which is git-ignored):

```hcl
azure_blob_account_name   = "mystorageaccount"
azure_blob_account_key    = "your-key-here-from-above"
azure_blob_container_name = "mycontainer"
azure_blob_account_url    = "https://mystorageaccount.blob.core.windows.net"
```

## Note: Do You Need This?

With the new `dify-helm` chart setup, you might not need Azure Blob Storage keys in Terraform anymore. The Helm chart can use:
- Local persistence (PVCs) - current default
- External S3/Azure Blob configured in `values.yaml` under `externalAzureBlobStorage`

Check your `values.yaml` to see if you're using Azure Blob Storage or local persistence.
