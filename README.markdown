# For the Win #

This project is a small set of Rake tasks to automate the process of building MSI packages for Puppet on Windows systems.

# Overview #

This is a separate repository because it is meant to build MSI packages for arbitrary versions of Puppet, Facter and other related tools.

This project requires these tools from the `puppetwinbuilder` Dev Kit for Windows systems.

 * Ruby
 * Rake
 * Git
 * WiX

# Getting Started #

Download the [Puppet Win
Builder](http://links.puppetlabs.com/puppetwinbuilder) archive, and unzip into `C:/puppetwinbuilder/`. Once extracted, execute the
`setup_env.bat` script which will update your PATH to include the
necessary tools, e.g. git, wix (heat, candle, and light), etc.

    C:\>cd puppetwinbuilder
    C:\puppetwinbuilder>setup_env.bat
    C:\puppetwinbuilder>cd \work
    C:\work>git clone git://github.com/puppetlabs/puppet_for_the_win
    C:\work>cd puppet_for_the_win
    C:\work\puppet_for_the_win>rake -T

# Building

Puppet For The Win composes an MSI from several different repositories. You will need to specify a configuration file to build it.

## Open Source

To build Puppet open source:

    C:\work\puppet_for_the_win>rake windows:build CONFIG=foss-stable.yaml

## Puppet Enterprise

To build Puppet Enterprise:

    C:\work\puppet_for_the_win>rake windows:buildenterprise PE_VERSION_STRING=2.7.0 CONFIG=pe2.7.yaml

Note that the `PE_VERSION_STRING` is needed to patch the puppet version source file.

## Order Dependent Builds #

The builds are order dependent. Build Puppet Enterprise after building Puppet FOSS, but not the other way around:

# User Facing Customizations #

The following MSI public properties are supported:

 * `INSTALLDIR` `"%ProgramFiles(x86)%\Puppet Labs\Puppet"`
 * `PUPPET_MASTER_SERVER` "puppet"
 * `PUPPET_CA_SERVER` Unset, Puppet will default to using `PUPPET_MASTER_SERVER`
 * `PUPPET_AGENT_CERTNAME` Unset, Puppet will default to using `facter fqdn`
 * `PUPPET_AGENT_ENVIRONMENT` "production"
 * `PUPPET_AGENT_STARTUP_MODE` "Automatic"
 * `PUPPET_AGENT_ACCOUNT_DOMAIN` Unset
 * `PUPPET_AGENT_ACCOUNT_USER` "LocalSystem"
 * `PUPPET_AGENT_ACCOUNT_PASSWORD` Unset

To install silently on the command line:

    msiexec /qn /l*v install.txt /i puppet-agent.msi INSTALLDIR="C:\puppet" PUPPET_MASTER_SERVER="puppetmaster.lan"

Note that msiexec will execute asynchronously. If you want the install to execute synchronously on the command line, prepend `start /w` as follows:

    start /w msiexec /qn ...

# Upgrading

The installer preserves configuration settings during an upgrade. If you override a value on the command line, it will overwrite the previous value in puppet.conf, if any.

The `PUPPET_AGENT_ACCOUNT_*` settings are exceptions, as they must be specified each time you install or upgrade (since we do not want to save the credentials in the registry).

# WiX

Every Puppet MSI contains:

1. unique PackageCode
1. unique ProductCode, so that we always perform Major upgrades.
1. the same UpgradeCode

A major upgrade means that an upgrade will remove the old product and install the new one. However, we want to preserve settings, such as the Service startup type (Automatic, Manual, etc).

As a result, we use the "RememberMe" pattern to preserve settings. The flow works like this for an arbitrary MSI public property `PUPPET_FOO`:

1. `PUPPET_FOO` is defined.
1. Windows installer sets `PUPPET_FOO` to the command line value, if one was specified.
1. Before AppSearch, the `SaveCmdLinePuppetFoo` custom action sets `CMDLINE_PUPPET_FOO` to the current value of `PUPPET_FOO`.
1. In AppSearch, `PUPPET_FOO` is set to the value of the RememberMe property in the registry, if any.
1. After AppSearch, the `SetFromCmdLinePuppetFoo` custom action sets `PUPPET_FOO` to the value of `CMDLINE_PUPPET_FOO`.
1. In RegistryEntries, the value of `PUPPET_FOO` is written to the registry.

Note that if a value is specified on the command line, it takes precedence over the previously remembered value.

Note the property as defined in step 1 should not have a defaut value, otherwise, it will **always** take precedence over the remembered value, which would break upgrades.

## Remembered Properties ##

The remembered properties are written to the registry in two locations:

    HKLM\Software\Puppet Labs\Puppet
    HKLM\Software\Puppet Labs\PuppetInstaller

On x64 systems, this is a redirected registry path:

    HKLM\SOFTWARE\Wow6432Node\Puppet Labs\Puppet
    HKLM\SOFTWARE\Wow6432Node\Puppet Labs\PuppetInstaller

## Conditional Custom Actions ##

Information specific to working with with Properties and conditionals is available at [Using Properties in Conditional
Statements](http://msdn.microsoft.com/en-us/library/aa372435.aspx)

The CustomAction can be conditional using the syntax defined at [Conditional
Statement Syntax](http://msdn.microsoft.com/en-us/library/aa368012.aspx)
Here's an example used in the [Remember Property
Pattern](http://robmensching.com/blog/posts/2010/5/2/The-WiX-toolsets-Remember-Property-pattern)

    <Custom Action='SaveCmdLineInstallDir' Before='AppSearch' />
    <Custom Action='SetFromCmdLineInstallDir' After='AppSearch'>
      CMDLINE_INSTALLDIR
    </Custom>

In this example the `SaveCmdLineInstallDir` will act unconditionally while the `SetFromCmdLineInstallDir` action will act only when the `CMDLINE_INSTALLDIR` property is set.

This technique can be used to conditionally set properties that aren't
explicitly set by the user.

## Localization Strings ##

The strings used throughout the installer are defined in the file
`wix/Localization/puppet_en-us.wxl`. In the future if we support other
languages than English we will need to create additional localization files. A convenient place to get started is the WiX source code in the `src/ext/UIExtension/wixlib/*.wxl` directory.

For the time being, any customization of strings shown to the user needs to happen inside of `puppet_en-us.wxl`.

In addition, customization of text styles (color, size, font) needs to have a new TextStyle defined in `wix/include/textstyles.wxi`

## Documentation Links ##

Start Menu Shortcuts are provided to online documentation.  The method we're employing to create these links is a little strange.  We are not using the [InternetShortcut
Element](http://wix.sourceforge.net/manual-wix3/util_xsd_internetshortcut.htm)
because this element does not allow us to add a description or an Icon.

Instead, we use the IniFile Element to write out a file with a `.url` extension into the documentation folder of the installation directory. We then create traditional shortcuts to these special `.url` files. This allows us to add a description and an Icon to the shortcut entry.

![Doc Shortcuts](http://dl.dropbox.com/u/17169007/img/screenshot_1330369100_0_documentation.png)

# Authenticode Signatures

## Signing the Packages ##

Digitally signing the MSI is important for release.  Windows will automatically verify the authenticity of our packages if they're signed and will present a warning to the user if they're not.

Here's the less scary notification when installing a signed package:

![User Account Control](http://dl.dropbox.com/u/17169007/img/Screen%20Shot%202012-03-14%20at%203.40.15%20PM.png)

To digitally sign the packages, the [Puppet Labs Code Signing
Certificate](https://groups.google.com/a/puppetlabs.com/group/tech/browse_thread/thread/3d85b1da489af092#)
should be installed into the user store on the windows build host.  If Jenkins is being used to automate the package builds, then this certificate and private key should be installed using the same account the Jenkins agent is running as.

There should only be one code signing certificate installed.  The `signtool` will automatically select the right certificate if there is only one of them installed.

Double clicking on the PFX file will install the certificate properly. I also recommend the certificate NOT be marked as exportable when installing it.

Once the MSI packages have been built, they can be signed with the following task:

    Z:\vagrant\win\puppetwinbuilder\src\puppet_for_the_win>rake windows:sign
    signtool sign /d "Puppet Enterprise" /du "http://www.puppetlabs.com" /n "Puppet Labs" \
      /t "http://timestamp.verisign.com/scripts/timstamp.dll" puppet-agent.msi
    Done Adding Additional Store
    Successfully signed and timestamped: puppet-agent.msi
    signtool sign /d "Puppet" /du "http://www.puppetlabs.com" /n "Puppet Labs" \
      /t "http://timestamp.verisign.com/scripts/timstamp.dll" puppet-agent.msi
    Done Adding Additional Store
    Successfully signed and timestamped: puppet-agent.msi

The command the Rake task is executing will require HTTP Internet access to timestamp.verisign.com in order to get a digitally signed timestamp.

SignTool
========

The [Sign Tool](http://msdn.microsoft.com/en-us/library/windows/desktop/aa387764.aspx) is distributed as part of the [Windows
SDK](http://msdn.microsoft.com/en-us/windowsserver/bb980924.aspx) You don't need to install the full SDK to get `signtool.exe`, only the "tools" component. The SDK requires the Microsoft .NET Framework 4 to be installed as well.

The puppetwinbuilder.zip `setup_env.bat` should automatically add the SDK to the PATH.  If the SDK changes versions in the future (e.g. 7.2 is released), then the PATH environment variable may not be correct and you'll need to get signtool.exe in the path yourself or update the puppetwinbuilder.zip file.

# Troubleshooting #

## Missing .NET Framework ##

If you receive exit code 128 when running rake build tasks and it looks like `candle` and `light` don't actually do anything, it's likely because the Microsoft .NET Framework is not installed.

If you try to run `candle.exe` or `light.exe` from Explorer, you might receive "Application Error" - The application failed to initialize properly (0xC0000135). Click on OK to terminate the application.  This is the same symptom and .NET should be installed.

In order to resolve this, please use Windows Update to install the .NET Framework 3.5 (Service Pack 1).

# Setup Tips #

To get a shared filesystem:

    net use Z: "\\vmware-host\Shared Folders" /persistent:yes

EOF


