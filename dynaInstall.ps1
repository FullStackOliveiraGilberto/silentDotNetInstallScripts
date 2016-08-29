<#
.SYNOPSIS
    Installs and enables Dynatrace IIS Native Modules and Dynatrace .NET agents.
.DESCRIPTION
    -- Requires Administrator rights to run --
    (OPTIONAL)Copies Dynatrace Agent MSI Installer from [ $originHost ] to [ $destDir ],
	(OPTIONAL)Stops IIS,
	Installs Dynatrace Agent MSI,
	Modifies Dynatrace Web Server Configuration File to point to [ $CollectorHost ]:[ $CollectorPort ] with web server name = [ $webServerName ],
	Stops Dynatrace Web Server Service,
	Registers Dynatrace IIS WebServer Agent Modules in IIS,
	Starts Dynatrace Web Server Service,
    Configures Dynatrace Environment Variables,
	Registers AppPools based on [ $csvFile ], mapping.csv,
	(OPTIONAL)Starts IIS
.NOTE 
       The mapping.csv file must be placed in the same folder as the dynaInstall.ps1 script, and must contain 
	       all .NET Processes that need to be instrumented, in the following CSV format...
	   EXAMPLE:
	   agentName,collectorHost,collectorPort,executable,path,cmdLine
	   DefaultAppPool_TestDotNet,192.168.186.226,9998,w3wp.exe,*,"-ap ""DefaultAppPool"""
	   TestAppPool_TestDotNet,192.168.186.226,9998,w3wp.exe,"C:\windows\system32\inetsrv\","-ap ""TestAppPool"""
#############################################################################
.USAGE (TYPICAL .NET-ONLY INSTALL)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	- To install only the Dynatrace .NET Agent (i.e. NO IIS Native Module Agent installation), 
	  using auto stop/start of IIS during the installation,
      using base install directory = "C:\dynatrace", 
	  using Dynatrace Collector address = 192.168.186.226:9998, 
	  using 64 Bit .NET agent for 64 bit app pools, 
	  and where app pools to be instrumented are defined within "mapping.csv" file, run the following command:
	  
	.\dynaInstall.ps1 -installNETAgent 1 -installIISAgent 0 -autoRestartIIS 1 -dynaBaseDir C:\dynatrace -CollectorHost 192.168.186.226 -CollectorPort 9998 -Use64Bit 1 -csvFile mapping.csv -dynatraceVer 6.2 -dynatraceMSIPackageVer 6.2.0.1300 

.USAGE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	- To run script using all default values, edit the default Param values in the "Param" section, and execute...
		.\dynaInstall.ps1    (No command line arguments necessary)
		
	- To install Dynatrace using base directory = "C:\dynatrace", Dynatrace Server address = 192.168.186.226:9998, 
	  and 64 Bit .NET processes defined in "mapping.csv" file...
		.\dynaInstall.ps1 -dynaBaseDir C:\dynatrace -CollectorHost 192.168.186.226 -CollectorPort 9998 -Use64Bit 1 -csvFile mapping.csv
	
	- To first copy Dynatrace MSI from one location to localhost, use all other defaults, and have the 
	  dynaInstall script perform an IISRESET automatically...
	    .\dynaInstall.ps1 -copyMSI 1 -originHost \\tsclient\C\Temp -destDir C:\Temp -autoRestartIIS 1
#############################################################################
.PARAMETER copyMSI
	Switch to tell script to copy Dynatrace Agent MSI from $originHost to $destDir
	0 for FALSE (default),  1 for TRUE
.PARAMETER installMSI
	Switch to tell script to install Dynatrace Agent using the MSI installer
	0 for FALSE (default),  1 for TRUE
.PARAMETER installIISAgent
	Switch to tell script to install the IIS Native Module Web Server Agent
	0 for FALSE (default),  1 for TRUE
	(REQUIRED:  must either pass the webServerName parameter as an argument via the script command line webServerName parameter, 
	 or hard code the webServerName parameter using the cmdlet binding section below)
.PARAMETER installNETAgent
	Switch to tell script to instrument app pools or other .NET processes/services with the Dynatrace .NET Agent
	0 for FALSE (default),  1 for TRUE
    (REQUIRED:  must either pass the csvFile parameter as an argument via the script command line csvFile parameter, 
	 or hard code the csvFile parameter in the cmdlet binding section below to point to the CSV File which defines all 
	 app pools or processes/services which Dynatrace needs to whitelist/instrument)
.PARAMETER Use64Bit
    Boolean value to force usage of 64-bit agent
.PARAMETER autoRestartIIS
	Switch to tell Dynatrace to stop and start IIS automatically (using iisreset)
	An iisreset is mandatory in order for the Dynatrace Agent to be properly injected
	0 for FALSE (default),  1 for TRUE
.PARAMETER originHost
    Origin location of the Dynatrace Agent Installer MSI
.PARAMETER destDir
    Destination location of the Dynatrace Agent Installer MSI
.PARAMETER dynaBaseDir
    ROOT directory of the Dynatrace agents. Agent DLLs are referenced relative from this directory [$dynaBaseDir]\agent\lib\dtagent.dll
.PARAMETER webServerName
    Web Server Agents name as shown in Dynatrace
.PARAMETER CollectorHost
    Server address of the Dynatrace Collector
.PARAMETER CollectorPort
    Server port of the Dynatrace Collector
.PARAMETER dynatraceMSIPackageVer
	Set this equal to the build version of the Dynatrace Agent Installer MSI filename you want to use
.PARAMETER dynatraceVer
    Simply set this to the major/minor version of Dynatrace you want to install
.PARAMETER csvFile
    Filename containing a Comma Separated Value (CSV) list of processes to whitelist.
#>

[CmdletBinding()]
Param(
   [Boolean]$copyMSI=0,
   [Boolean]$installMSI=1,
   [Boolean]$installIISAgent=1,
   [Boolean]$installNETAgent=1,
   [Boolean]$Use64Bit = 1,
   [Boolean]$autoRestartIIS=1,
   [string]$originHost="\\tsclient\C\Temp",
   [string]$destDir = "C:\Temp",
   [string]$dynaBaseDir="C:\dyna",
   [string]$webServerName = "WebServer_TestDotNet",
   [string]$CollectorHost = "192.168.186.172",
   [string]$CollectorPort = "9998",
   [string]$dynatraceMSIPackageVer="6.2.0.1300",
   [string]$dynatraceVer="6.2",
   [string]$csvFile = "mapping.csv"
)

$csv = Import-Csv $csvFile

Function Enable-DotNETAgent-Install([string] $InstallPath, [string]$AgentName, [string]$CollectorHost, [string]$CollectorPort, [Boolean]$Use64Bit, [string]$executable, [string]$path, [string]$cmdLine)
{
	$index = 1
	$regPath = "HKLM:\SOFTWARE\Wow6432Node\dynaTrace\Agent\Whitelist"
	while (Test-Path ($regPath+"\"+($index -as [string])))
	{
		$index++
		if ($index -gt 15) 
		{
			"Too many processes to instrument (15 processes already exceeded)."
			return
		}
	}
	
	$regPath = "HKLM:\SOFTWARE\Wow6432Node\dynaTrace"
	if (!(Test-Path $regPath)) { md $regPath }
	$regPath = $regPath + "\Agent"
	if (!(Test-Path $regPath)) { md $regPath }
	$regPath = $regPath + "\Whitelist"
	if (!(Test-Path $regPath)) { md $regPath }
	$regPath = $regPath + "\" + ($Index -as [string])
	if (!(Test-Path $regPath)) { md $regPath }

  "Setting up .NET Agent for '" + $AgentName + "'..."
	Set-ItemProperty -Path $regPath -Name "active" -Value "TRUE"
	Set-ItemProperty -Path $regPath -Name "path" -Value $path
	Set-ItemProperty -Path $regPath -Name "server" -Value $CollectorHost
	Set-ItemProperty -Path $regPath -Name "port" -Value $CollectorPort
	Set-ItemProperty -Path $regPath -Name "name" -Value $AgentName
	Set-ItemProperty -Path $regPath -Name "exec" -Value $executable
	Set-ItemProperty -Path $regPath -Name "cmdline" -Value "$cmdLine"

	$index++

	"Complete."
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
  Write-Warning "Starting Dynatrace .NET Agent Install"

  if($copyMSI -eq 1)
  {
	  Write-Output "Copying Dynatrace Agent MSI Installer from [ $originHost ] to [ $destDir ]"
	  New-Item -ItemType Directory -Path $destDir -Force | Out-Null
	  Copy-Item -Path $originHost\dynatrace-agent-$dynatraceMSIPackageVer.msi -Destination $destDir
  }
  if($installMSI -eq 1)
  {
	  Write-Output "Installing Dynatrace Agent MSI"
	  msiexec /passive /i $destDir\dynatrace-agent-$dynatraceMSIPackageVer.msi APPDIR=$dynaBaseDir\ ADDLOCAL="ALL" | Wait-Job
  }
  
  if($autoRestartIIS -eq 1)
  {
	  Write-Output "Stopping IIS"
	  iisreset /stop
  }

  if($installIISAgent -eq 1)
  {
  Write-Output "Modifying Dynatrace Web Server Config"
  (gc "$dynaBaseDir\agent\conf\dtwsagent.ini") | % {$_ -replace "localhost", ($CollectorHost+":"+$CollectorPort)} | sc "$dynaBaseDir\agent\conf\dtwsagent.ini"
  (gc "$dynaBaseDir\agent\conf\dtwsagent.ini") | % {$_ -replace "dtwsagent", ($webServerName)} | sc "$dynaBaseDir\agent\conf\dtwsagent.ini"

  Write-Output "Stopping Dynatrace Web Server Service"
  stop-service -displayname "dynaTrace Web Server Agent $dynatraceVer"
  sleep 3
  
  Write-Output "Registering Dynatrace IIS WebServer Agent Modules"
  C:\Windows\System32\inetsrv\appcmd.exe install module /name:'Dynatrace Webserver Agent (64bit)' /image:$dynaBaseDir'\agent\lib64\dtagent.dll' /add:true /lock:true /preCondition:bitness64
  C:\Windows\System32\inetsrv\appcmd.exe install module /name:'Dynatrace Webserver Agent (32bit)' /image:$dynaBaseDir'\agent\lib\dtagent.dll' /add:true /lock:true /preCondition:bitness32
  
  Write-Output "Starting Dynatrace Web Server Service"
  start-service -displayname "dynaTrace Web Server Agent $dynatraceVer"
  }
  
  if($installNETAgent -eq 1)
  {
  Write-Output "Configuring Environment Variables"
    $dtServer = ($CollectorHost+":"+$CollectorPort)
	$EnvironmentVariableTarget = 'Machine'
	[System.Environment]::SetEnvironmentVariable('DT_SERVER',$dtServer, $EnvironmentVariableTarget) 
	[System.Environment]::SetEnvironmentVariable('COR_ENABLE_PROFILING','1', $EnvironmentVariableTarget) 
	[System.Environment]::SetEnvironmentVariable('COR_PROFILER','{DA7CFC47-3E35-4C4E-B495-534F93B28683}', $EnvironmentVariableTarget) 
	if ($Use64Bit)
	{ [System.Environment]::SetEnvironmentVariable('COR_PROFILER_PATH',"$dynaBaseDir\agent\lib64\dtagent.dll", $EnvironmentVariableTarget) }
	else
	{ [System.Environment]::SetEnvironmentVariable('COR_PROFILER_PATH',"$dynaBaseDir\agent\lib\dtagent.dll", $EnvironmentVariableTarget) }

  Write-Output "Registering AppPools "
  foreach ($line in $csv) 
    { Enable-DotNETAgent-Install ($dynaBaseDir) ($line.agentName) ($line.collectorHost) ($line.collectorPort) (0) ($line.executable)($line.path) ($line.cmdLine) }
  }
  
  if($autoRestartIIS -eq 1)
  {
	  Write-Output "Starting IIS"
	  iisreset /start
  }
Write-Warning "Done Installing Dynatrace .NET Agent"


