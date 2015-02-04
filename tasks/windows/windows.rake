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
require 'erb'
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
  flags['HieraDescTag']  = describe 'downloads/hiera'

  # The regular expression with back reference groups for version string
  # parsing.  We re-use this against either git-describe on Puppet or on
  # ENV['PE_VERSION_STRING'] which should match the same pattern.  NOTE that we
  # can only use numbers in the product version and that product version
  # impacts major upgrades: ProductVersion Property is defined as
  # [0-255].[0-255].[0-65535] See:
  # http://stackoverflow.com/questions/9312221/msi-version-numbers
  # This regular expression focuses on the major numbers and discards things like "rc1" in the string
  @version_regexps = [
    /(\d+)[^.]*?\.(\d+)[^.]*?\.(\d+)[^.]*?-(\d+)-(.*)/,
    /(\d+)[^.]*?\.(\d+)[^.]*?\.(\d+)[^.]*?\.(\d+)/,
    /(\d+)[^.]*?\.(\d+)[^.]*?\.(\d+)[^.]*?/,
  ]

  case ENV['BRANDING']
  when /enterprise/i
    flags['PackageBrand'] = "enterprise"
    msg = "Could not parse PE_VERSION_STRING env variable.  Set it with something like PE_VERSION_STRING=2.5.0"
    flags['MCODescTag']  = describe 'downloads/mcollective'
    # The Package Version components for PE
    match_data = nil
    @version_regexps.find(lambda { raise ArgumentError, msg }) do |re|
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
    @version_regexps.find(lambda { raise ArgumentError, msg }) do |re|
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

def erb(erbfile, outfile)
  template         = File.read(erbfile)
  message          = ERB.new(template, nil, "-")
  message.filename = erbfile
  output           = message.result(binding)
  File.open(outfile, 'wb') { |f| f.write output }
  puts "Generated: #{outfile}"
end

def cp_p(src, dest, options={})
  cp(src, dest, options.merge({:preserve => true}))
end

# Produce a wixobj from a wxs file.
def candle(wxs_file, flags=[])
  flags_string = flags.join(' ')
  if ENV['BUILD_UI_ONLY'] then
    flags_string << " -dBUILD_UI_ONLY"
  end
  flags_string << " -dlicenseRtf=conf/windows/stage/misc/LICENSE.rtf"
  flags_string << " -dPlatform=#{ENV['ARCH']}"
  flags_string << " " << variable_define_flags
  Dir.chdir File.join(TOPDIR, File.dirname(wxs_file)) do
    sh "candle -ext WiXUtilExtension -ext WixUIExtension -arch #{ENV['ARCH']} #{flags_string} \"#{File.basename(wxs_file)}\""
  end
end

# Produce a wxs file from a directory in the stagedir
# e.g. heat('wxs/fragments/foo.wxs', 'stagedir/sys/foo')
# note that heat doesn't have a switch for architecture and hence we don't get
# <Component win64="yes" />, however candle.exe provides this capability as long
# as the Platform variable is set for the Product in the .wxs file
def heat(wxs_file, stage_dir)
  Dir.chdir TOPDIR do
    cg_name = File.basename(wxs_file.ext(''))
    dir_ref = File.basename(File.dirname(stage_dir))
    filters_xslt = File.join(TOPDIR, 'wix/filters/filters.xslt').gsub('/','\\')
    # NOTE:  The reference specified using the -dr flag MUST exist in the
    # parent puppet.wxs file.  Otherwise, WiX won't be able to graft the
    # fragment into the right place in the package.
    dir_ref = 'INSTALLDIR' if dir_ref == 'stagedir'
    sh "heat dir #{stage_dir} -v -ke -indent 2 -cg #{cg_name} -gg -dr #{dir_ref} -t \"#{filters_xslt}\" -var var.StageDir -out #{wxs_file}"
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
  directory 'stagedir/bin'
  directory 'wix/fragments'

  CONFIG = YAML.load_file(ENV["config"] || "config.yaml")
  APPS = CONFIG[:repos]
  ENV['ARCH'] = ENV['ARCH'] || 'x86'

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
        puts "Fetching #{name} from #{config[:ref]}"
        sh 'git fetch origin'
        sh 'git fetch origin --tags'
        sh 'git clean -xfd'
        sh "git checkout -f #{config[:ref]}"
      end
    end
  end

  task :bin => 'stagedir' do
    FileList["conf/windows/stage/bin/*.erb"].each do |template|
      target = template.gsub(/\.erb$/,"")
      erb(template, target)
    end

    mkdir_p("stagedir/bin")

    # Only copy the .bat files into place
    cp_p(FileList["conf/windows/stage/bin/*.bat"], "stagedir/bin/")
  end

  task :misc => 'stagedir' do
    FileUtils.cp_r("conf/windows/stage/misc", "stagedir/misc")
    FileUtils.cp_r(FileList['downloads/puppet/ext/windows/eventlog/*.dll'], 'stagedir/misc')
  end

  task :service => 'stagedir' do
    mkdir_p("stagedir/service")
    FileUtils.cp_r(FileList['downloads/puppet/ext/windows/service/*'], 'stagedir/service')
    FileUtils.cp('downloads/mcollective/ext/windows/daemon.bat', 'stagedir/service/mco_daemon.bat') if File.exists?('downloads/mcollective/ext/windows/daemon.bat')
  end

  task :stage => [:checkout, 'stagedir', :bin, :misc, :service] do
    FileList["downloads/*"].each do |app|
      dst = "stagedir/#{File.basename(app)}"
      puts "Copying #{app} to #{dst} ..."
      FileUtils.mkdir(dst)
      excludes = [ %r{/acceptance/*},
                   %r{/benchmarks/*},
                   %r{/autotest/*},
                   %r{/docs/*},
                   %r{/ext/*},
                   %r{/examples/*},
                   %r{/man/*},
                   %r{/spec/*},
                   %r{/tasks/*},
                   %r{/util/*},
                   %r{/yardoc/*},
                   %r{/COMMITTERS.md},
                   %r{/CONTRIBUTING.md},
                   %r{/Gemfile},
                   %r{/Rakefile},
                   %r{/README.md},
                   %r{/*.patch}
                 ]
      # This avoids copying hidden files like .gitignore and .git
      FileUtils.cp_r(FileList["#{app}/*"].exclude(*excludes), dst, :verbose => true)
    end
    mkdir_p('stagedir/hiera/ext')
    FileUtils.cp('downloads/hiera/ext/hiera.yaml', 'stagedir/hiera/ext/hiera.yaml')
  end

  task :remove_vendor => [ :stage ] do
    puts "Removing vendored JSON from mcollective..."
    FileUtils.rm_rf(["stagedir/mcollective/lib/mcollective/vendor/json", "stagedir/mcollective/lib/mcollective/vendor/load_json.rb"])
  end

  task :wxs => [ :stage, 'wix/fragments' ] do
    if ENV["BRANDING"] == "enterprise"
      Rake::Task["windows:remove_vendor"].invoke
    end
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
      ["puppet", "mcollective"].each do | product |
        if File.exists?("stagedir/#{product}/lib/#{product}/version.rb")
          version_file = "stagedir/#{product}/lib/#{product}/version.rb"
        elsif File.exists?("stagedir/#{product}/lib/#{product}.rb")
          version_file = "stagedir/#{product}/lib/#{product}.rb"
        else
          raise ArgumentError, "Could not patch #{product} version, no version file found"
        end

        content = File.open(version_file, 'rb') { |f| f.read }

        if product == "puppet"
          modified = content.gsub(/(PUPPETVERSION\s*=\s*)(['"])([\.\d]*)\s*(.*?)(['"])/) do |match|
            pre         = $1
            start_quote = $2
            version     = $3
            pe_version  = $4
            end_quote   = $5

            modified =
              if pe_version =~ /\(Puppet Enterprise.*\)/
                # rewrite as one line:
                #   PUPPETVERSION = "3.6.2 (Puppet Enterprise 3.3.0)"
                "#{pre}#{start_quote}#{version} (Puppet Enterprise #{ENV['PE_VERSION_STRING']})#{end_quote}"
              else
                # rewrite as two lines:
                #   PEVERSION = '3.3.0'
                #   PUPPETVERSION = "3.6.2 (Puppet Enterprise 3.3.0)"
                "PEVERSION = #{start_quote}#{ENV['PE_VERSION_STRING']}#{end_quote}\n    #{pre}#{start_quote}#{version} (Puppet Enterprise #{ENV['PE_VERSION_STRING']})#{end_quote}"
              end
          end
        elsif product == "mcollective"
          msg = 'Could not parse git-describe annotated tag for MCollective'
          match_data=[]
          @version_regexps.find(lambda { raise ArgumentError, msg }) do |re|
            match_data = (describe 'downloads/mcollective').match re
          end
          mco_version="#{match_data[1]}.#{match_data[2]}.#{match_data[3]}." << (match_data[4] || 0).to_s
          modified = content.gsub("@DEVELOPMENT_VERSION@", "#{mco_version}")
        end

        if content == modified
          raise ArgumentError, "(#12975) Could not patch #{product}.rb.  Check the regular expression around this line in the backtrace against #{version_file}"
        end

        File.open(version_file, "wb") { |f| f.write(modified) }
      end
    end
  end

  task :msi => [:wixobj, :wixobj_ui, :version] do
    OBJS = FileList['wix/**/*.wixobj']

    out = ENV['BRANDING'] =~ /enterprise/i ? 'puppetenterprise' : 'puppet'
    out = "#{out}-#{ENV['ARCH']}" if ENV['ARCH'] == 'x64'
    msi_file_name =  ENV['PKG_FILE_NAME'] || "#{out}.msi"

    Dir.chdir TOPDIR do
      sh "light -ext WiXUtilExtension -ext WixUIExtension -cultures:en-us -loc wix/localization/puppet_en-us.wxl -out pkg/#{msi_file_name} #{OBJS}"
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
    msi_file_name =  ENV['PKG_FILE_NAME'] || 'puppetenterprise.msi'
    Dir.chdir TOPDIR do
      Dir.chdir "pkg" do
        sh "signtool sign /d \"Puppet Enterprise\" /du \"http://www.puppetlabs.com\" /n \"Puppet Labs\" /t \"http://timestamp.verisign.com/scripts/timstamp.dll\" #{msi_file_name}"
      end
    end
  end

  desc "Sign the FOSS msi package"
  # signtool.exe must be in your path for this task to work.  You'll need to
  # install the Windows SDK to get signtool.exe.  puppetwinbuilder.zip's
  # setup_env.bat should have added it to the PATH already.
  task :sign_foss => 'pkg' do |t|
    msi_file_name =  ENV['PKG_FILE_NAME'] || 'puppet.msi'
    Dir.chdir TOPDIR do
      Dir.chdir "pkg" do
        sh "signtool sign /d \"Puppet\" /du \"http://www.puppetlabs.com\" /n \"Puppet Labs\" /t \"http://timestamp.verisign.com/scripts/timstamp.dll\" #{msi_file_name}"
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
  task :install => 'pkg' do |t|
    msi_file_name =  ENV['PKG_FILE_NAME'] || 'puppet.msi'
    Dir.chdir "pkg" do
      sh "msiexec /q /l*v install.txt /i #{msi_file_name} INSTALLDIR=\"C:\\puppet\" PUPPET_MASTER_SERVER=\"puppetmaster\" PUPPET_AGENT_CERTNAME=\"windows.vm\""
    end
  end

  desc 'Uninstall the MSI using msiexec'
  task :uninstall => 'pkg' do |t|
    msi_file_name =  ENV['PKG_FILE_NAME'] || 'puppet.msi'
    Dir.chdir "pkg" do
      sh "msiexec /qn /l*v uninstall.txt /x #{msi_file_name}"
    end
  end
end
