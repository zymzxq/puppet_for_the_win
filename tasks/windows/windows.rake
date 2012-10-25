#! /usr/bin/env ruby

# This rakefile is meant to be run from within the [Puppet Win
# Builder](http://links.puppetlabs.com/puppetwinbuilder) tree.

# Load Rake
begin
  require 'rake'
rescue LoadError
  require 'rubygems'
  require 'rake'
end

require 'pathname'
require 'yaml'
require 'rake/clean'

# Where we're situated in the filesystem relative to the Rakefile
TOPDIR=File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))

# This method should be called by candle to figure out the list of variables
# we're defining "outside" the build system.  Git describe and what have you.
# This is ultimately set by the environment variable BRANDING which could be
# foss|enterprise
def variable_define_flags
  flags = Hash.new
  flags['PuppetDescTag'] = describe 'downloads/puppet'
  flags['FacterDescTag'] = describe 'downloads/facter'

  # The regular expression with back reference groups for version string
  # parsing.  We re-use this against either git-describe on Puppet or on
  # ENV['PE_VERSION_STRING'] which should match the same pattern.  NOTE that we
  # can only use numbers in the product version and that product version
  # impacts major upgrades: ProductVersion Property is defined as
  # [0-255].[0-255].[0-65535] See:
  # http://stackoverflow.com/questions/9312221/msi-version-numbers
  # This regular expression focuses on the major numbers and discards things like "rc1" in the string
  version_regexps = [
    /(\d+)[^.]*?\.(\d+)[^.]*?\.(\d+)[^.]*?-(\d+)-(.*)/,
    /(\d+)[^.]*?\.(\d+)[^.]*?\.(\d+)[^.]*?\.(\d+)/,
    /(\d+)[^.]*?\.(\d+)[^.]*?\.(\d+)[^.]*?/,
  ]

  case ENV['BRANDING']
  when /enterprise/i
    flags['PackageBrand'] = "enterprise"
    msg = "Could not parse PE_VERSION_STRING env variable.  Set it with something like PE_VERSION_STRING=2.5.0"
    # The Package Version components for FOSS
    match_data = nil
    version_regexps.find(lambda { raise ArgumentError, msg }) do |re|
      match_data = ENV['PE_VERSION_STRING'].match re
    end
    flags['MajorVersion'] = match_data[1]
    flags['MinorVersion'] = match_data[2]
    flags['BuildVersion'] = match_data[3]
    flags['Revision'] = match_data[4] || 0
  else
    flags['PackageBrand'] = "foss"
    msg = "Could not parse git-describe annotated tag for Puppet"
    # The Package Version components for FOSS
    match_data = nil
    version_regexps.find(lambda { raise ArgumentError, msg }) do |re|
      match_data = flags['PuppetDescTag'].match re
    end
    flags['MajorVersion'] = match_data[1]
    flags['MinorVersion'] = match_data[2]
    flags['BuildVersion'] = match_data[3]
    flags['Revision'] = match_data[4] || 0
  end

  # Return the string of flags suitable for candle
  flags.inject([]) { |a, (k,v)| a << "-d#{k}=\"#{v}\"" }.join " "
end

def describe(dir)
  @git_tags ||= Hash.new
  @git_tags[dir] ||= Dir.chdir(dir) { %x{git describe}.chomp }
end

# Produce a wixobj from a wxs file.
def candle(wxs_file, flags=[])
  flags_string = flags.join(' ')
  if ENV['BUILD_UI_ONLY'] then
    flags_string << " -dBUILD_UI_ONLY"
  end
  flags_string << " -dlicenseRtf=conf/windows/stage/misc/LICENSE.rtf"
  flags_string << " " << variable_define_flags
  Dir.chdir File.join(TOPDIR, File.dirname(wxs_file)) do
    sh "candle -ext WiXUtilExtension -ext WixUIExtension -arch x86 #{flags_string} \"#{File.basename(wxs_file)}\""
  end
end

# Produce a wxs file from a directory in the stagedir
# e.g. heat('wxs/fragments/foo.wxs', 'stagedir/sys/foo')
def heat(wxs_file, stage_dir)
  Dir.chdir TOPDIR do
    cg_name = File.basename(wxs_file.ext(''))
    dir_ref = File.basename(File.dirname(stage_dir))
    # NOTE:  The reference specified using the -dr flag MUST exist in the
    # parent puppet.wxs file.  Otherwise, WiX won't be able to graft the
    # fragment into the right place in the package.
    dir_ref = 'INSTALLDIR' if dir_ref == 'stagedir'
    sh "heat dir #{stage_dir} -v -ke -indent 2 -cg #{cg_name} -gg -dr #{dir_ref} -var var.StageDir -out #{wxs_file}"
  end
end

CLOBBER.include('downloads/*')
CLEAN.include('stagedir/*')
CLEAN.include('wix/fragments/*.wxs')
CLEAN.include('wix/**/*.wixobj')
CLEAN.include('pkg/*')

namespace :windows do
  # These are file tasks that behave like mkdir -p
  directory 'pkg'
  directory 'downloads'
  directory 'stagedir'
  directory 'wix/fragments'

  CONFIG = YAML.load_file(ENV["config"] || "config.yaml")
  APPS = CONFIG[:repos]

  task :clean_downloads => 'downloads' do
    FileList["downloads/*"].each do |repo|
      if not APPS[File.basename(repo)]
        puts "Deleting #{repo}"
        FileUtils.rm_rf(repo)
      end
    end
  end

  task :clone => :clean_downloads do
    APPS.each do |name, config|
      if not File.exists?("downloads/#{name}")
        Dir.chdir "#{TOPDIR}/downloads" do
          sh "git clone #{config[:repo]} #{name}"
        end
      end
    end
  end

  task :checkout => :clone do
    APPS.each do |name, config|
      Dir.chdir "#{TOPDIR}/downloads/#{name}" do
        sh 'git fetch origin'
        sh 'git fetch origin --tags'
        sh 'git clean -xfd'
        sh "git checkout -f #{config[:ref]}"
      end
    end
  end

  task :bin => 'stagedir' do
    FileUtils.cp_r("conf/windows/stage/bin", "stagedir/bin")
  end

  task :misc => 'stagedir' do
    FileUtils.cp_r("conf/windows/stage/misc", "stagedir/misc")
  end

  task :stage => [:checkout, 'stagedir', :bin, :misc] do
    FileList["downloads/*"].each do |app|
      dst = "stagedir/#{File.basename(app)}"
      puts "Copying #{app} to #{dst} ..."
      FileUtils.mkdir(dst)
      # This avoids copying hidden files like .gitignore and .git
      FileUtils.cp_r FileList["#{app}/*"], dst
    end
  end

  task :wxs => [:stage, 'wix/fragments'] do
    FileList["stagedir/*"].each do |staging|
      name = File.basename(staging)
      heat("wix/fragments/#{name}.wxs", staging)
    end
  end

  task :wixobj => :wxs do
    FileList['wix/*.wxs'].each do |wxs|
      candle(wxs)
    end
    FileList['wix/fragments/*.wxs'].each do |wxs|
      source_dir = "stagedir/#{File.basename(wxs, '.wxs')}"
      candle(wxs, [ "-dStageDir=#{source_dir}" ])
    end
  end

  task :wixobj_ui do
    FileList['wix/ui/*.wxs'].each do |wxs|
      candle(wxs)
    end
  end

  task :version do
    if ENV['PE_VERSION_STRING']
      if File.exists?('stagedir/puppet/lib/puppet/version.rb')
        version_file = 'stagedir/puppet/lib/puppet/version.rb'
      else
        version_file = 'stagedir/puppet/lib/puppet.rb'
      end

      content = File.open(version_file, 'rb') { |f| f.read }

      modified = content.gsub(/(PUPPETVERSION\s*=\s*)(['"])(.*?)(['"])/) do |match|
        "#{$1}#{$2}#{$3} (Puppet Enterprise #{ENV['PE_VERSION_STRING']})#{$2}"
      end

      if content == modified
        raise ArgumentError, "(#12975) Could not patch puppet.rb.  Check the regular expression around this line in the backtrace against stagedir/puppet/lib/puppet.rb"
      end

      File.open(version_file, "wb") { |f| f.write(modified) }
    end
  end

  task :msi => [:wixobj, :wixobj_ui, :version] do
    OBJS = FileList['wix/**/*.wixobj']

    out = ENV['BRANDING'] =~ /enterprise/i ? 'puppetenterprise' : 'puppet'

    Dir.chdir TOPDIR do
      sh "light -ext WiXUtilExtension -ext WixUIExtension -cultures:en-us -loc wix/localization/puppet_en-us.wxl -out pkg/#{out}.msi #{OBJS}"
    end
  end

  # Sign all packages
  desc "Sign all MSI packages"
  task :sign => [ :sign_pe, :sign_foss ]

  # Digitally sign the MSI package
  desc "Sign the PE msi package"
  # signtool.exe must be in your path for this task to work.  You'll need to
  # install the Windows SDK to get signtool.exe.  puppetwinbuilder.zip's
  # setup_env.bat should have added it to the PATH already.
  task :sign_pe => 'pkg' do |t|
    Dir.chdir TOPDIR do
      Dir.chdir "pkg" do
        sh 'signtool sign /d "Puppet Enterprise" /du "http://www.puppetlabs.com" /n "Puppet Labs" /t "http://timestamp.verisign.com/scripts/timstamp.dll" puppetenterprise.msi'
      end
    end
  end

  desc "Sign the FOSS msi package"
  # signtool.exe must be in your path for this task to work.  You'll need to
  # install the Windows SDK to get signtool.exe.  puppetwinbuilder.zip's
  # setup_env.bat should have added it to the PATH already.
  task :sign_foss => 'pkg' do |t|
    Dir.chdir TOPDIR do
      Dir.chdir "pkg" do
        sh 'signtool sign /d "Puppet" /du "http://www.puppetlabs.com" /n "Puppet Labs" /t "http://timestamp.verisign.com/scripts/timstamp.dll" puppet.msi'
      end
    end
  end

  task :default => :build
  # High Level Tasks.  Other tasks will add themselves to these tasks
  # dependencies.

  # This is also called from the build script in the Puppet Win Builder archive.
  # This will be called AFTER the update task in a new process.
  desc "Build puppet.msi"
  task :build => :clean do |t|
    ENV['BRANDING'] = 'foss'
    ENV['PE_VERSION_STRING'] = nil
    Rake::Task["windows:msi"].invoke
  end

  desc "Build puppetenterprise.msi"
  task :buildenterprise => :clean do |t|
    ENV['BRANDING'] = "enterprise"
    if not ENV['PE_VERSION_STRING']
      puts "Warning: PE_VERSION_STRING is not set in the environment.  Defaulting to 2.5.0"
      ENV['PE_VERSION_STRING'] = '2.5.0'
    end
    Rake::Task["windows:msi"].invoke
  end

  desc "List available rake tasks"
  task :help do
    sh 'rake -T'
  end

  # The update task is always called from the build script
  # This gives the repository an opportunity to update itself
  # and manage how it updates itself.
  desc "Update the build scripts"
  task :update do
    sh 'git pull'
  end

  desc 'Install the MSI using msiexec'
  task :install => 'pkg/puppet.msi' do |t|
    Dir.chdir "pkg" do
      sh 'msiexec /q /l*v install.txt /i puppet.msi INSTALLDIR="C:\puppet" PUPPET_MASTER_SERVER="puppetmaster" PUPPET_AGENT_CERTNAME="windows.vm"'
    end
  end

  desc 'Uninstall the MSI using msiexec'
  task :uninstall => 'pkg/puppet.msi' do |t|
    Dir.chdir "pkg" do
      sh 'msiexec /qn /l*v uninstall.txt /x puppet.msi'
    end
  end
end
