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
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    $logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
    New-rsEventLogSource -logSource $logSource
    . (Get-rsSecrets)
    $catalog = Get-rsServiceCatalog
    $uri = (($catalog.access.serviceCatalog | ? type -eq 'orchestration').endpoints | ? region -eq $Region ).publicURL
    $stacks = (Invoke-rsRestMethod -Uri ($uri,"stacks" -join '/') -Method GET -Headers (Get-rsAuthToken) -ContentType application/json).stacks

    if( $Ensure -eq "Present" )
    {
        $params = @{}
        foreach($instance in $Parameters) {
            $params += @{$instance.Key=$instance.Value}
        }
        $file = (Get-Content $TemplateFile | Out-String) 
        $body = @{
            "stack_name"= $Name;
            "template"= $file;
            "parameters"= $params;
            "timeout_mins"= $TimeoutMins
        } | ConvertTo-Json -Depth 8
    
        if( ($stacks | ? {$_.stack_name -eq $Name}).id.count -eq 0 )
        {
            Write-EventLog -LogName DevOps -Source $logSource -EntryType Information -EventId 1000 -Message "POST Request: $($uri,"stacks" -join '/')"
            Write-Verbose "POST"
            $response = Invoke-rsRestMethod -Uri $($uri,"stacks" -join '/') -Method POST -Headers $(Get-rsAuthToken) -Body $body -ContentType application/json -Verbose
        }
        else
        {
            Write-EventLog -LogName DevOps -Source $logSource -EntryType Information -EventId 1000 -Message "PUT Request: $($uri,"stacks",$Name -join '/')"
            Write-Verbose "PUT"
            $response = Invoke-rsRestMethod -Uri $($uri,"stacks",$Name,$(($stacks | ? {$_.stack_name -eq $Name}).id) -join '/') -Method PUT -Headers $(Get-rsAuthToken) -Body $body -ContentType application/json
        }
        if( ($response -match "Accepted") -or ($response.stack.id.count -gt 0) )
        {
            Set-Content -Path $TemplateHash -Value (Get-FileHash -Path $TemplateFile | ConvertTo-Csv)
        }
    }
    else
    {
        Write-EventLog -LogName DevOps -Source $logSource -EntryType Information -EventId 1000 -Message "DELETE Request: $($uri,"stacks",$Name -join '/')"
        Write-Verbose "DELETE"
        $response = Invoke-rsRestMethod -Uri $($uri,"stacks",$Name,$(($stacks | ? {$_.stack_name -eq $Name}).id) -join '/') -Method DELETE -Headers $(Get-rsAuthToken) -Body $body -ContentType application/json
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
        [ValidateSet("Present", "Absent")][string]$Ensure = "Present"
    )
    $testresult = $true
    $logSource = $($PSCmdlet.MyInvocation.MyCommand.ModuleName)
    $exists = Import-Module rsCommon -ErrorAction SilentlyContinue -PassThru
    if( [string]::IsNullOrEmpty($exists) )
    {
        Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1003 -Message "rsCommon is not located on this machine"
        Throw "rsCommon is not located on this machine"
    }
    New-rsEventLogSource -logSource $logSource
    . (Get-rsSecrets)
    $catalog = Get-rsServiceCatalog
    $uri = (($catalog.access.serviceCatalog | ? type -eq 'orchestration').endpoints | ? region -eq $Region ).publicURL
    $stacks = (Invoke-rsRestMethod -Uri ($uri,"stacks" -join '/') -Method GET -Headers $(Get-rsAuthToken) -ContentType application/json).stacks

    if( !(Test-Path $TemplateFile))
    {
        Write-EventLog -LogName DevOps -Source $logSource -EntryType Error -EventId 1003 -Message "File not found: $TemplateFile"
        Throw "Template File Not Found"
    }
    if( $Ensure -eq "Absent" -and ( ($stacks | ? {$_.stack_name -eq $Name}).id.count -eq 0) )
    {
        return $true
    }    
    if( $Ensure -eq "Present" -and ( ($stacks | ? {$_.stack_name -eq $Name}).id.count -eq 0) )
    {
        return $false
    }
    if( $Ensure -eq "Absent" -and ( ($stacks | ? {$_.stack_name -eq $Name}).id.count -gt 0) )
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
}
Export-ModuleMember -Function *-TargetResource
