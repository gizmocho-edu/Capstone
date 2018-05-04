

[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0)]
    [string]$target = '127.0.0.1',
    
    [Parameter(Mandatory=$false,Position=1)]
    [switch]$remote = $false,
    
    [Parameter(Mandatory=$false,Position=2)]
    [string]$username,
    
    [Parameter(Mandatory=$false,Position=3)] 
     [string]$password
)

foreach($c in $target){
    Function knockOffline{
        $wirelessNic = Get-WmiObject -Class Win32_NetworkAdapter -filter "Name LIKE '%Wireless%'"
        $wirelessNic.disable() #enable
        $localNic = Get-WmiObject -Class Win32_NetworkAdapter -filter "Name LIKE '%Intel%'"
        $localNic.disable() #enable

        $WmiHash = @{}
        if($Private:Credential){
            $WmiHash.Add('Credential',$credential)
        }
        Try{
            $Validate = (Get-WmiObject -Class Win32_OperatingSystem -ComputerName $C -ErrorAction Stop @WmiHash).Win32Shutdown('0x0')
        } Catch [System.Management.Automation.MethodInvocationException] {
            Write-Error 'No user session found to log off.'
            Exit 1
        } Catch {
            Throw
        }
        if($Validate.ReturnValue -ne 0){
            Write-Error "Can't log off target, Here's why: $($Validate.ReturnValue)"
            Exit 1
        }
    rundll32.exe user32.dll,LockWorkStation > $null 2>&1
	shutdown.exe -l
    }
}
if (-Not ($remote)) {
Invoke-Lockdown
} Else {
    if ($remote -eq $true) {
        $scriptName = $MyInvocation.MyCommand.Name
        $securePass = ConvertTo-SecureString -string $password -AsPlainText -Force
        $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $securePass
        Invoke-Command -FilePath "$scriptName" -ComputerName $target -Credential $cred
    }
}
Exit 0