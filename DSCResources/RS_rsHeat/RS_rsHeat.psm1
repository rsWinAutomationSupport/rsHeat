
#region Helper Functions
Function Invoke-OpenStackRestMethod
{
    param (
        [string][ValidateNotNull()]$Uri,
        [string][ValidateSet('GET', 'PUT', 'POST', 'DELETE', ignorecase=$true)]$Method,
        [string]$Body,
        [hashtable]$Headers,
        [string][ValidateSet('application/json', 'application/xml', ignorecase=$true)]$ContentType = "application/json",
        [uint32]$Retries = 2,
        [uint32]$TimeOut = 10
    )

    $i = 0
    $ContentType = $ContentType.ToLower()
    
    do 
    {
        if($i -ge $Retries) 
        {
            Write-Verbose -Message "Failed to retrieve OpenStack Service Catalog, reached maximum retries"
            return $null
        }
        
        if($Method.ToLower() -eq "post" -or $Method.ToLower() -eq "put") 
        {
            try 
            {
                $Data =  (Invoke-RestMethod -Uri $Uri -Method $Method.ToUpper() -Body $Body -Headers $Headers -ContentType $ContentType -ErrorAction SilentlyContinue)
            }
            catch 
            {
                if( (($error[0].Exception.Response.StatusCode.value__) -ge 500) -or ($Error[0].Exception.Message -like "The remote name could not be resolved:*") ) 
                {
                    Write-Verbose -Message "An OpenStack API call Failed `n $Method`: $Uri `n $Body `n $($_.Exception.Message) `n $($_.ErrorDetails.Message)"
                }
                else 
                {
                    Write-Verbose -Message "An OpenStack API call Failed `n $Method`: $Uri `n $Body `n $($_.Exception.Message) `n $($_.ErrorDetails.Message)"
                    break
                }
            }
        }
        else 
        {
           try 
           {
               $Data =  (Invoke-RestMethod -Uri $Uri -Method $Method.ToUpper() -Headers $Headers -ContentType $ContentType -ErrorAction SilentlyContinue)
           }
           catch 
           {
               if( (($error[0].Exception.Response.StatusCode.value__) -ge 500) -or ($Error[0].Exception.Message -like "The remote name could not be resolved:*") ) 
               {
                   Write-Verbose -Message "An OpenStack API call Failed `n $Method`: $Uri `n $Body `n $($_.Exception.Message) `n $($_.ErrorDetails.Message)"
               }
               else 
               {
                   Write-Verbose -Message "An OpenStack API call Failed `n $Method`: $Uri `n $Body `n $($_.Exception.Message) `n $($_.ErrorDetails.Message)"
                   break
               }
           }
        }
        
        $i++
        if($Data -eq $null) 
        {
            Write-Verbose -Message "Failed OpenStack API call. Trying again in $TimeOut seconds`n $($_.Exception.Message)"

            if($i -ge $Retries) 
            {
                return $null
            }
            else 
            {
                Start-Sleep -Seconds $TimeOut
            }
        }
    }
    while($Data -eq $null)

    return $Data
}

Function Get-OpenStackServiceCatalog
{
    param (
        $Uri = "https://identity.api.rackspacecloud.com/v2.0/tokens",
        $Username,
        $ApiKey
    )

    $Body = $(@{"auth" = @{"RAX-KSKEY:apiKeyCredentials" = @{"username" = $Username; "apiKey" = $ApiKey}}} | convertTo-Json)

    $Result = (Invoke-OpenStackRestMethod -Retries 20 -TimeOut 15 -Uri $Uri -Method POST -Body $body -ContentType application/json)

    return $Result
}
#endregion

#region DSC Functions

function Get-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [String]$TemplateFile,
        [String]$TemplateHash,
        [String]$Region,
        [Microsoft.Management.Infrastructure.CimInstance[]]$Parameters,
        [uint32]$TimeoutMins,
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    @{
        Name = $Name
        Parameters = $Parameters
    } 
}

function Set-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [String]$TemplateFile,
        [String]$TemplateHash,
        [String]$Region,
        [Microsoft.Management.Infrastructure.CimInstance[]]$Parameters,
        [uint32]$TimeoutMins,
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [string]$Username,
        [string]$ApiKey
    )
       
    $Catalog = Get-OpenStackServiceCatalog -Username $Username -ApiKey $ApiKey
    $XAuthToken = @{"X-Auth-Token"=($Catalog.access.token.id)}

    $uri = (($catalog.access.serviceCatalog | Where-Object type -eq 'orchestration').endpoints | Where-Object region -eq $Region ).publicURL
    $stacks = (Invoke-OpenStackRestMethod -Uri "$uri/stacks" -Method GET -Headers $XAuthToken -ContentType application/json).stacks
    $stackID = ($stacks | Where-Object {$_.stack_name -eq $Name}).id

    if( $Ensure -eq "Present" )
    {
        $params = @{}
        foreach($instance in $Parameters) 
        {
            $params += @{$instance.Key=$instance.Value}
        }
        
        $file = (Get-Content $TemplateFile | Out-String) 
        $body = @{
                    "stack_name"= $Name;
                    "template"= $file;
                    "parameters"= $params;
                    "timeout_mins"= $TimeoutMins
                } | ConvertTo-Json -Depth 8
    
        if( ($stacks | Where-Object {$_.stack_name -eq $Name}).id.count -eq 0 )
        {
            Write-Verbose "OpenStack API POST Request: $uri/stacks"
            $response = Invoke-OpenStackRestMethod -Uri "$uri/stacks" -Method POST -Headers $XAuthToken -Body $body -ContentType application/json -Verbose
        }
        else
        {
            Write-Verbose "Openstack PUT Request: $uri/stacks/$Name"
            $response = Invoke-OpenStackRestMethod -Uri "$uri/stacks/$Name/$stackID" -Method PUT -Headers $XAuthToken -Body $body -ContentType application/json
        }
        if( ($response -match "Accepted") -or ($response.stack.id.count -gt 0) )
        {
            Set-Content -Path $TemplateHash -Value (Get-FileHash -Path $TemplateFile | ConvertTo-Csv)
        }
    }
    else
    {
        Write-Verbose "DELETE Request: $($uri,"stacks",$Name -join '/')"
        $response = Invoke-OpenStackRestMethod -Uri "$uri/stacks/$Name/$stackID" -Method DELETE -Headers $XAuthToken -Body $body -ContentType application/json
        if( Test-Path $TemplateHash )
        {
            Remove-Item $TemplateHash -Force
        }
    }

}

function Test-TargetResource
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [String]$TemplateFile,
        [String]$TemplateHash,
        [String]$Region,
        [Microsoft.Management.Infrastructure.CimInstance[]]$Parameters,
        [uint32]$TimeoutMins,
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [string]$Username,
        [string]$ApiKey
    )

    $testresult = $true
    
    $Catalog = Get-OpenStackServiceCatalog -Username $Username -ApiKey $ApiKey
    $XAuthToken = @{"X-Auth-Token"=($Catalog.access.token.id)}

    $uri = (($catalog.access.serviceCatalog | Where-Object type -eq 'orchestration').endpoints | Where-Object region -eq $Region ).publicURL
    $stacks = (Invoke-OpenStackRestMethod -Uri "$uri/stacks" -Method GET -Headers $XAuthToken -ContentType application/json).stacks

    if( !(Test-Path $TemplateFile))
    {
        Write-Verbose -Message "File not found: $TemplateFile"
        Throw "Template File Not Found - $($TemplateFile)"
    }
    if( $Ensure -eq "Absent" -and ( ($stacks | Where-Object {$_.stack_name -eq $Name}).id.count -eq 0) )
    {
        return $true
    }    
    if( $Ensure -eq "Present" -and ( ($stacks | Where-Object {$_.stack_name -eq $Name}).id.count -eq 0) )
    {
        return $false
    }
    if( $Ensure -eq "Absent" -and ( ($stacks | Where-Object {$_.stack_name -eq $Name}).id.count -gt 0) )
    {
        return $false
    }
    if( !(Test-Path $TemplateHash))
    {
        return $false
    }

    $checkHash = Get-FileHash $TemplateFile
    $currentHash = Import-Csv $TemplateHash
    if($checkHash.Hash -ne $currentHash.hash)
    {
        $testresult = $false
    }
    return $testresult
}#endregion

Export-ModuleMember -Function *-TargetResource
