<#
.SYNOPSIS
    Compmletely uninstalls Dynatrace .NET Agent software.
.DESCRIPTION
    -- Requires Administrator rights to run --
	(OPTIONAL)Stops IIS,
	,
	Modifies Dynatrace Web Server Configuration File to point to [ $CollectorHost ]:[ $CollectorPort ] with web server name = [ $webServerName ],
	Stops Dynatrace Web Server Service,
	Removes Dynatrace Native IIS Modules,
	Removes Dynatrace Whitelisted Processes,
	Removes Dynatrace Environment Variables,
	Removes Dynatrace Agent software,
	(OPTIONAL) Restarts IIS
.USAGE
	- To run script using all default values, edit the default Param values in the "Param" section, and execute...
		.\dynaUninstall.ps1    (No command line arguments necessary)
		
	- To uninstall Dynatrace with base directory = "C:\dyna", and automatically restart IIS...
		.\dynaUninstall.ps1 -dynaBaseDir C:\dyna -dynatraceBuildVer 6.2.0.1300 -restartIIS 1
		
.PARAMETER dynaBaseDir
    ROOT directory of the Dynatrace agents. Agent DLLs are referenced relative from this directory [$dynaBaseDir]\agent\lib\dtagent.dll
.PARAMETER dynatraceBuildVer
	Set this equal to the build version of the Dynatrace Agent Installer MSI that was installed
.PARAMETER restartIIS
	Switch to enable automatic restart of IIS upon uninstallation of the Dynatrace Agent software.
	An iisreset is mandatory in order for the Dynatrace Agent to be removed from your application
	0 for FALSE (default),  1 for TRUE
#>

[CmdletBinding()]
Param(
   [string]$dynaBaseDir="C:\dyna",
   [string]$dynatraceBuildVer="6.2.0.1300",
   [Boolean]$restartIIS=1
)

Function Remove-WhitelistedProcesses
{
<#
.SYNOPSIS
    Removes all whitelisted processes from configuration for Dynatrace .NET agent
#>
  "Remove Whitelisted Processes"
  $regPath = "HKLM:\SOFTWARE\Wow6432Node\dynaTrace"
  if (Test-Path $regPath) { 
	Remove-Item $regPath -Recurse
  }
}

Function Disable-DotNETAgent
{
<#
.SYNOPSIS
    Disables Dynatrace .NET agent and removes it's configuration
#>
	"Disable .NET Agent"
	$EnvironmentVariableTarget = 'Machine'
	[System.Environment]::SetEnvironmentVariable('DT_SERVER',$null, $EnvironmentVariableTarget) 
	[System.Environment]::SetEnvironmentVariable('COR_ENABLE_PROFILING',$null, $EnvironmentVariableTarget) 
	[System.Environment]::SetEnvironmentVariable('COR_PROFILER',$null, $EnvironmentVariableTarget) 
	[System.Environment]::SetEnvironmentVariable('COR_PROFILER_PATH',$null, $EnvironmentVariableTarget) 
}

Function Test-IsAdminInternal
{
	If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
	    [Security.Principal.WindowsBuiltInRole] "Administrator")){
	    Write-Warning "You do not have Administrator rights to run this module!`nPlease re-run this script as Administrator!"
	    Break}}

  Write-Output "Checking Admin Rights..."
  Test-IsAdminInternal
  Write-Output "---OK ADMIN---"
  Write-Warning "Uninstalling Dynatrace .NET Agent"
  Write-Output "Stopping Dynatrace Web Server Service"
  stop-service -displayname "dynaTrace Web Server Agent*"
  
  Write-Output "Removing Dynatrace Native IIS Modules"
  C:\Windows\System32\inetsrv\appcmd.exe uninstall module /module.name:'Dynatrace Webserver Agent (64bit)'
  C:\Windows\System32\inetsrv\appcmd.exe uninstall module /module.name:'Dynatrace Webserver Agent (32bit)'

  Write-Output "Removing Dynatrace Whitelisted Processes"
  Remove-WhitelistedProcesses
  
  Write-Output "Removing Dynatrace Environment Variables"
  Disable-DotNETAgent

  Write-Output "UNINSTALLING Dynatrace Agent MSI"
  msiexec /passive /x $destDir\dynatrace-agent-$dynatraceBuildVer.msi APPDIR=$dynaBaseDir\ ADDLOCAL="ALL" | Wait-Job
  Write-Output "MSI UNINSTALLED"
  
  if($restartIIS -eq 1)
  {
  Write-Output "Restarting IIS"
  iisreset /restart
  }
  
  Write-Warning "Done Uninstalling Dynatrace .NET Agent"