@ECHO OFF
REM This is the parent directory of the directory containing this script.
SET PL_BASEDIR=%~dp0..
REM Avoid the nasty \..\ littering the paths.
SET PL_BASEDIR=%PL_BASEDIR:\bin\..=%

REM Set a fact so we can easily source the environment.bat file in the future.
SET FACTER_env_windows_installdir=%PL_BASEDIR%

REM Get the file name we were originally called as.  e.g. puppet.bat or puppet
REM or facter.bat or facter.  ~n means: will return the file name only of
SET SCRIPT_TEMP=%~n1
REM Strip off the extension of the script name.  We need to do this to know
REM what to pass to ruby -S
SET SCRIPT_NAME=%SCRIPT_TEMP:.bat=%
REM Shift off the original command name we we were called
SHIFT

SET PUPPET_DIR=%PL_BASEDIR%\puppet
REM Facter will load FACTER_ env vars as facts, so don't use FACTER_DIR
SET FACTERDIR=%PL_BASEDIR%\facter
SET HIERA_DIR=%PL_BASEDIR%\hiera
SET MCOLLECTIVE_DIR=%PL_BASEDIR%\mcollective

SET PATH=%PL_BASEDIR%\bin;%PUPPET_DIR%\bin;%FACTERDIR%\bin;%HIERA_DIR%\bin;%MCOLLECTIVE_DIR%\bin;%PL_BASEDIR%\sys\ruby\bin;%PL_BASEDIR%\sys\tools\bin;%PATH%

REM Set the RUBY LOAD_PATH using the RUBYLIB environment variable
SET RUBYLIB=%PUPPET_DIR%\lib;%FACTERDIR%\lib;%HIERA_DIR%\lib;%MCOLLECTIVE_DIR%\lib;%RUBYLIB%;

REM Translate all slashes to / style to avoid issue #11930
SET RUBYLIB=%RUBYLIB:\=/%

REM Enable rubygems support
SET RUBYOPT=rubygems
REM Now return to the caller.

REM Set SSL variables to ensure trusted locations are used
SET SSL_CERT_FILE=%SystemRoot%\system32\ssl\cert.pem
SET SSL_CERT_DIR=%SystemRoot%\system32\ssl\certs
