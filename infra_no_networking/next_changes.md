# Disabling SSO for AzureML Compute Instances via Terraform (POBO Pattern)

## Overview
AzureML compute instances enable SSO (Single Sign-On) by default. To disable SSO by default, you must use the "create on behalf of" (POBO) pattern, which assigns the compute instance to a user other than the creator at creation time. This is the only supported way to disable SSO by default via infrastructure-as-code.

## Implementation Steps

1. **Add a Variable for the Assigned User**
   - In your module's `variables.tf`, add:
     ```hcl
     variable "assigned_user_object_id" {
       description = "Object ID of the user to assign the compute instance to (for POBO/SSO disablement)"
       type        = string
     }
     ```

2. **Update the Compute Instance Resource**
   - In your `main.tf`, update the `azapi_resource` for the compute instance:
     ```hcl
     resource "azapi_resource" "compute_instance_uami" {
       # ...existing code...
       body = {
         # ...existing code...
         properties = {
           computeType = "ComputeInstance"
           properties = {
             # ...existing code...
             personalComputeInstanceSettings = {
               assignedUser = {
                 objectId = var.assigned_user_object_id # Assign to a different user for SSO disabled
                 tenantId = data.azurerm_client_config.current.tenant_id
               }
             }
             # ...existing code...
           }
           # ...existing code...
         }
       }
       # ...existing code...
     }
     ```

3. **Pass the Assigned User Object ID**
   - When calling the module from your root or environment-specific configuration, pass the object ID of the user you want to assign the compute instance to (not your own):
     ```hcl
     module "aml_managed_umi" {
       # ...existing code...
       assigned_user_object_id = "<OBJECT_ID_OF_TARGET_USER>"
       # ...existing code...
     }
     ```

## Notes
- SSO will be disabled by default for the assigned user. The assigned user can later enable SSO in the AzureML Studio UI if needed.
- This approach is required because there is no direct property to disable SSO in the ARM/azapi schema.
- If you want to use a setup script or custom application to disable SSO, see AzureML documentation for details.


---

# Assigning a Public IP to the Jump Box VM NIC

## Overview
To allow direct access to your jump box VM (e.g., for RDP/SSH or as a Bastion host), you can assign a static public IP to its network interface (NIC). This section shows how to do this using your codebase's naming and variable conventions.

## Implementation Steps

1. **Create a Public IP Resource**
   ```hcl
   resource "azurerm_public_ip" "prod_vm" {
     name                = "pip-${var.prefix}-vm-prod-${var.location_code}${var.naming_suffix}"
     location            = var.location
     resource_group_name = azurerm_resource_group.prod_vnet_rg.name
     allocation_method   = "Static"
     sku                 = "Standard"
     tags                = merge(var.tags, { environment = "production", purpose = "prod", component = "vm" })
   }
   ```

2. **Update the NIC to Use the Public IP**
   ```hcl
   resource "azurerm_network_interface" "prod_vm_nic" {
     name                = "nic-${var.prefix}-vm-prod-${var.location_code}${var.naming_suffix}"
     location            = var.location
     resource_group_name = azurerm_resource_group.prod_vnet_rg.name

     ip_configuration {
       name                          = "ipconfig1"
       subnet_id                     = azurerm_subnet.prod_vm.id
       private_ip_address_allocation = "Dynamic"
       public_ip_address_id          = azurerm_public_ip.prod_vm.id
     }

     tags = merge(var.tags, { environment = "production", purpose = "prod", component = "vm" })
   }
   ```

3. **No Change Needed for the VM Resource**
   Your VM already references the NIC:
   ```hcl
   resource "azurerm_windows_virtual_machine" "jumpbox" {
     # ...existing code...
     network_interface_ids = [
       azurerm_network_interface.prod_vm_nic.id
     ]
     # ...existing code...
   }
   ```

## Notes
- This will assign a static public IP to your jump box VM's NIC.
- Make sure your NSG allows the required inbound traffic (e.g., RDP/SSH) from trusted sources.

---

## References
- [AzureML Docs: Create on behalf of disables SSO](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-create-compute-instance?view=azureml-api-2&tabs=python#create-on-behalf-of)

---

**Summary Table:**

| Method                | SSO Disabled by Default? | Supported in Terraform? |
|-----------------------|-------------------------|------------------------|
| Standard creation     | No                      | Yes                    |
| Create on behalf of   | Yes                     | Yes (with assignedUser) |
| Setup script/custom app | Yes                   | Not directly           |

---

This file documents the recommended and supported way to disable SSO for compute instances in AzureML using Terraform. Follow the steps above to implement this in your environment.
