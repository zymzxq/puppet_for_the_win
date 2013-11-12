$hostname = [Net.Dns]::GetHostName()

function Install-Puppet($opts)
{
  $params = @('/qn', '/i', 'pkg\puppet.msi', '/l*v', 'install.log')
  if ($opts.Account) { $params += "PUPPET_AGENT_ACCOUNT_USER=`"$($opts.Account)`"" }
  if ($opts.Domain) { $params += "PUPPET_AGENT_ACCOUNT_DOMAIN=`"$($opts.Domain)`"" }
  if ($opts.Password) { $params += "PUPPET_AGENT_ACCOUNT_PASSWORD=`"$($opts.Password)`"" }
  if ($opts.Startup) { $params += "PUPPET_AGENT_STARTUP_MODE=`"$($opts.Startup)`"" }

  Write-Host "`nInstalling Puppet Agent with $params"
  $process = Start-Process 'msiexec' -ArgumentList $params -Wait -PassThru

  if ($process.ExitCode -ne 0)
  {
    Write-Error "Puppet Agent failed to install with : $($process.ExitCode)"
    return $process.ExitCode
  }

  # Automatic is returned as Auto from WMI
  $expectedMode = $opts.Startup
  if (!$expectedMode -or $expectedMode -eq 'Automatic') { $expectedMode = 'Auto' }
  $expectedState = 'Stopped'
  if ($expectedMode -eq 'Auto') { $expectedState = 'Running' }

  $expectedUser = if ($opts.Account) { $opts.Account } else { 'LocalSystem' }
  $expectedDomain = if ($opts.Domain) { $opts.Domain } else { '.' }
  if (@('.', $hostname) -contains $expectedDomain)
  {
    if (@('LocalService', 'NetworkService') -contains $expectedUser)
      { $expectedUser = "NT AUTHORITY\$expectedUser" }
    elseif ('LocalSystem' -ne $expectedUser)
      { $expectedUser = ".\$expectedUser" }
  }
  else
  {
    $expectedUser = "$expectedDomain\$expectedUser"
  }

  Write-Host "Verifying service user $expectedUser / state $expectedState / startup $expectedMode"

  $puppet = Get-WmiObject Win32_Service -Filter 'Name = "Puppet"'
  if (!$puppet)
  {
    Write-Error 'Puppet service not installed!'
    return 1
  }

  if ($puppet.StartMode -ne $expectedMode)
  {
    Write-Error "Puppet service mode [$($puppet.StartMode)] does not match requested [$expectedMode]"
    return 1
  }

  if ($puppet.State -ne $expectedState)
  {
    Write-Error "Puppet service state [$($puppet.State)] does not match requested [$expectedState]"
    return 1
  }

  # local user accounts get prefixed with the . -- unless LocalService, LocalSystem, NetworkService
  if ($puppet.StartName -ne $expectedUser)
  {
    Write-Error "Puppet user [$($puppet.StartName)] does not match requested [$expectedUser]"
    return 1
  }
  Write-Host 'Verified successfully'

  Write-Host "Successfully installed Puppet with $params" -ForegroundColor Green
  return 0
}

function Uninstall-Puppet
{
  Write-Host 'Uninstalling Puppet'
  $uninst = @('/qn', '/x', 'pkg\puppet.msi')
  $process = Start-Process 'msiexec' -ArgumentList $uninst -Wait -PassThru

  if ($process.ExitCode -ne 0)
  {
    Write-Error "Puppet Agent failed to uninstall with : $($process.ExitCode)"
  }

  return $process.ExitCode
}

@(
  @{},
  @{ Account = 'LocalSystem' },
  @{ Domain = '.'; Account = 'LocalSystem' },
  @{ Domain = $hostname; Account = 'LocalSystem' },
  @{ Domain = $hostname; Account = 'LocalSystem'; Startup = 'Manual' },
  @{ Domain = $hostname; Account = 'LocalSystem'; Startup = 'Disabled' },
  @{ Domain = $hostname; Account = 'LocalSystem'; Startup = 'Automatic' },
  @{ Account = 'vagrant'; Password = 'vagrant' },
  @{ Domain = $hostname; Account = 'vagrant'; Password = 'vagrant' },
  @{ Account = 'LocalService' },
  @{ Domain = '.'; Account = 'LocalService' },
  @{ Account = 'NetworkService' },
  @{ Domain = '.'; Account = 'NetworkService' }
  @{ Domain = 'NT Authority'; Account = 'NetworkService' }
) |
  % {
    try
    {
      $exitCode = Install-Puppet $_
    }
    finally
    {
      $exitCode =  Uninstall-Puppet
      if ($exitCode -ne 0) { exit $exitCode }
    }
  }
