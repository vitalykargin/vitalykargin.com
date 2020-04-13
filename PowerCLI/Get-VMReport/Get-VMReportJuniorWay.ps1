<#
http://vitalykargin.com
https://github.com/vitalykargin/vitalykargin.com
Create VMs report in Spreadsheet
Junior Way
#>
$credentials = Get-Credential -Message "Type credentials for VCSA"
$vcsa = Read-Host "Enter your VCSA server FQDN or IP address"
$path = Read-Host "Enter report path"

Connect-VIServer $vcsa -Credential $credentials

    New-VIProperty -Name ResourcePoolFullPath -ObjectType VirtualMachine -Value {
        $path = ''
        $parentId = $args[0].ResourcePoolId
        #Write-Host "before while: $parentId"
        while($parentId){
            try{
                $parent = Get-ResourcePool -Id $parentId -ErrorAction Stop
                $parentId = $parent.parentId
                #Write-Host "try"    
            }
            catch{
                $parent = $parent.Parent
                $parentId = $null
                #Write-Host "catch"
            }
            finally{
                #Write-Host "during while: $parent"
                #Write-Host "during while: $parentId"
                $path = $parent.Name + '/' + $path
            }
        }
        $path -replace ".$"
    } -Force

    New-VIProperty -Name FolderFullPath -ObjectType VirtualMachine -Value {
        $path = ''
        $parentId = $Args[0].FolderId
        #Write-Host "before while: $parentId"
        while($parentId){
            try{
                $parent = Get-Folder -Id $parentId -ErrorAction Stop
                $parentId = $parent.parentId
                #Write-Host "try"    
            }
            catch{
                $parent = Get-Datacenter -Id $parentId -ErrorAction Stop
                $parentId = $parent.parentFolderId
                #Write-Host "catch"
            }
            finally{
                #Write-Host "during while: $parent"
                #Write-Host "during while: $parentId"
                $path = $parent.Name + '/' + $path
            }
        }
        $path -replace ".$"
    } -Force

    New-VIProperty -Name IP -ObjectType VirtualMachine -Value {
        $Args[0].Guest.IpAddress -join ', '
    } -Force -BasedOnExtensionProperty 'Guest.IpAddress'

    New-VIProperty -ObjectType VirtualMachine -Name ToolsRunningStatus -ValueFromExtensionProperty 'Guest.ToolsRunningStatus' -Force
    New-VIProperty -ObjectType VirtualMachine -Name ToolsVersionStatus -ValueFromExtensionProperty 'Guest.ToolsVersionStatus' -Force
    New-VIProperty -ObjectType VirtualMachine -Name ConfiguredOS -ValueFromExtensionProperty 'Config.GuestFullName' -Force
    New-VIProperty -ObjectType VirtualMachine -Name RunningOS -ValueFromExtensionProperty 'Guest.GuestFullName' -Force
    New-VIProperty -ObjectType VirtualMachine -Name FQDN -ValueFromExtensionProperty 'Guest.HostName' -Force

    $VMs = Get-VM -Name vAppVM1 | Select-Object Name, `
    FQDN, `
    IP, `
    ConfiguredOS, `
    RunningOS, `
    @{N="Cores";E={$_.NumCpu}}, `
    @{N="Memory, GB";E={[math]::Round($_.MemoryGB,0)}}, `
    @{N="Used Space, GB";E={[math]::Round($_.UsedSpaceGB,0)}}, `
    HardwareVersion, `
    ToolsVersionStatus, `
    ToolsRunningStatus, `
    PowerState, `
    FolderFullPath, `
    ResourcePoolFullPath, `
    Notes

    $VMs | Select-Object * | Sort-Object ResourcePoolFullPath, Name | Export-Csv -Path $path -Delimiter ';' -NoTypeInformation -Force

Disconnect-VIServer $vcsa -Confirm:$false