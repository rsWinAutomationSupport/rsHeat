# rsHeat
The **rsHeat** module contains a DSC resource for interfacing with [Heat API](https://wiki.openstack.org/wiki/Heat) for automating builds of new cloud servers and, if required, make them managed nodes of a articular pull server via heat templates and a bootstrap scripts, which are downloaded and executed as part of the node provisioning workflow.

This module should be invoked on a central system, normally the pull or another management server, which manages the orchestration for a given environment.

**Please note:** 
* This module has only been tested with Rackspace Cloud at the time of writing.
* This module is currently only intended to be used as part of Rackspace Automation Service provisioning workflow.

## Resources
### rsHeat
* **Name:** Name of the heat Stack that is being created
* **Region:** RS Cloud region, where this stack is being deployed
* **Parameters:** A hash table that contains parameters that need to be passed as part of bootstrap process
	* **Naming_Scheme:** Name ot be given to all servers being built (You can use '%index%' to add q sequential number to each server name - server%index% would result in names being: server01, server02, etc)
	* **PullServerAddress:** IP or dns name of the pull server to which the node being built will be connecting
	* **dsc_config:** DSC configuration script file name to use for this stack (located in the configuration repository, along with PULL server script)
	* **shared_key:** Shared secret string that is used for client registration process - this must be the same  complex string that was used during the initial PULL server build
	* **rsBootURL:** Source URL of the bootstrap script, which will be downloaded and executed as part of server provisioning process 
* **TemplateFile:** Path of the HEAT template file from the configuration repository, located on PULL server.Total number of servers within a stack is defined within the template at the moment.
* **TemplateHash:** Path of the HEAT template checksum file, located on PULL server (do not store this in the cloned repository folder). Thsi is used to detect changes to the heat template and reapply it as needed.
* **Username:** Rackspace Cloud user name that will be used to initiate the build
* **ApiKey:** Rackspace Cloud API key for the above user 
* **TimeOutMins:** HEAT API timeout value, recommended to leave this at 60 unless you are experiencing issues
* **Ensure:** Control whether this stack is present. 
	* "Present" will initiate the creation of the stack, based on the template
	* "Absent" will completely delete the stack and all servers that were built as part of it.
* **DependsOn:**

## Versions
### 3.0.0
* Remove external module dependencies (rsCommon)
  - all configuration parameters now have to be specified as part of invocation 

### 2.0.0
* Initial release of the module

## Example configuration


```PoSh
        rsHeat MyHeatEnv
        {
            Name         = "WebFarm"
            Region       = "LON"
            Parameters = @{
                              "Naming_Scheme"     = "WebFarm%index%";
                              "PullServerAddress" = "<pull_server_IP_or_dns_name>";
                              "dsc_config"        = "WebFarm.ps1";
                              "shared_key"        = "<shared_registration_key>";
                              "rsBootURL"         = "https://raw.githubusercontent.com/rsWinAutomationSupport/rsboot/wmf4/boot.ps1";
                          }
            TemplateFile = [Environment]::GetEnvironmentVariable('defaultPath','Machine'), $d.mR, 'WebFarm.yml' -join '\'
            TemplateHash = [Environment]::GetEnvironmentVariable('defaultPath','Machine'), 'WebFarm.yml.hash' -join '\'
            Username     = "<rs_cloud_user>"
            ApiKey       = "<rs_cloud_api_key>"
            TimeoutMins  = 60
            Ensure       = "Present"
            DependsOn    = "[rsPlatform]Modules"
        }
```

## Example HEAT Templates

### Stand-alone server template
```
description: 'HEAT template for configuring clients in a single role'
heat_template_version: '2014-10-16'
parameters:
    flavor:
        constraints:
        -   allowed_values: [1 GB Performance, 2 GB Performance, 4 GB Performance,
                8 GB Performance, 15 GB Performance]
            description: must be a valid Rackspace Cloud Server flavor.
        default: 2 GB Performance
        description: Rackspace Cloud Server flavor
        type: string
    image: {default: Windows Server 2012 R2, description: Windows Server Image, type: string}
    Naming_Scheme: {default: Node%index%, description: base name for the web server instances,
        type: string}
    PullServerAddress: {type: string, description: IP or hostname of the Pull server}
    dsc_config: {default: Template-Client.ps1,type: string}
    shared_key: {type: string}
    rsBootURL: {type: string, default: "https://raw.githubusercontent.com/rsWinAutomationSupport/rsboot/wmf4_namefix/boot.ps1"}
resources:
  client_nodes:
    type: OS::Heat::ResourceGroup
    properties:
      count: 1
      resource_def:
        type: Rackspace::Cloud::WinServer
        properties:
          flavor: {get_param: flavor}
          image: {get_param: image}
          name: {get_param: Naming_Scheme}
          metadata: 
            build_config: core
          save_admin_pass: true
          user_data:
            str_replace: 
              template: |
                      Set-Location C:\
                      Invoke-WebRequest %%rsBootURL -OutFile 'boot.ps1'
                      Set-Content -Path "C:\DevOpsBoot.cmd" -Value "Powershell.exe -Command `".\boot.ps1 -PullServerAddress '%%PullServerAddress' -dsc_config '%%dsc_config' -shared_key '%%shared_key'`""
                      Start-Process "C:\DevOpsBoot.cmd"
              params:
                "%%PullServerAddress" : { get_param: PullServerAddress }
                "%%shared_key" : { get_param: shared_key }
                "%%dsc_config" : { get_param: dsc_config }
                "%%Naming_Scheme" : {get_param: Naming_Scheme}
                "%%rsBootURL" : {get_param: rsBootURL}
```

### Cloud servers, added to an existing F5 LB pool
```
description: 'HEAT template for configuring clients in a single role'
heat_template_version: '2014-10-16'
parameters:
    flavor:
        constraints:
        -   allowed_values: [1 GB Performance, 2 GB Performance, 4 GB Performance,
                8 GB Performance, 15 GB Performance]
            description: must be a valid Rackspace Cloud Server flavor.
        default: 2 GB Performance
        description: Rackspace Cloud Server flavor
        type: string
    image: {default: Windows Server 2012 R2, description: Windows Server Image, type: string}
    Naming_Scheme: {default: Node%index%, description: base name for the web server instances,
        type: string}
    PullServerAddress: {type: string, description: IP or hostname of the Pull server}
    dsc_config: {default: Template-Client.ps1,type: string}
    shared_key: {type: string}
    rsBootURL: {type: string, default: "https://raw.githubusercontent.com/rsWinAutomationSupport/rsboot/wmf4_namefix/boot.ps1"}
resources:
  client_nodes:
    type: OS::Heat::ResourceGroup
    properties:
      count: 1
      resource_def:
        type: Rackspace::Cloud::WinServer
        properties:
          flavor: {get_param: flavor}
          image: {get_param: image}
          name: {get_param: Naming_Scheme}
          metadata: 
            build_config: core
          save_admin_pass: true
          user_data:
            str_replace: 
              template: |
                      Set-Location C:\
                      Invoke-WebRequest %%rsBootURL -OutFile 'boot.ps1'
                      Set-Content -Path "C:\DevOpsBoot.cmd" -Value "Powershell.exe -Command `".\boot.ps1 -PullServerAddress '%%PullServerAddress' -dsc_config '%%dsc_config' -shared_key '%%shared_key'`""
                      Start-Process "C:\DevOpsBoot.cmd"
              params:
                "%%PullServerAddress" : { get_param: PullServerAddress }
                "%%shared_key" : { get_param: shared_key }
                "%%dsc_config" : { get_param: dsc_config }
                "%%Naming_Scheme" : {get_param: Naming_Scheme}
                "%%rsBootURL" : {get_param: rsBootURL}
  lb:
    type: "Rackspace::Cloud::LoadBalancer"
    properties:
      name:
        str_replace:
          template: lb-%server_name%
          params:
            "%server_name%": { get_param: pullserver_hostname }
      nodes:
      - addresses: { get_attr: [ client_nodes, privateIPv4 ] }
        port: 80
        condition: ENABLED
      protocol: HTTP
      halfClosed: False
      algorithm: LEAST_CONNECTIONS
      connectionThrottle:
        maxConnections: 50
        minConnections: 50
        maxConnectionRate: 50
        rateInterval: 50
      port: 80
      timeout: 120
      sessionPersistence: HTTP_COOKIE
      virtualIps:
      - type: PUBLIC
        ipVersion: IPV4
      healthMonitor:
        type: HTTP
        delay: 10
        timeout: 10
        attemptsBeforeDeactivation: 3
        path: "/"
        statusRegex: "."
        bodyRegex: "."
      contentCaching: ENABLED
```