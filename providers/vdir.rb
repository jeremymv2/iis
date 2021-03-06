#
# Author:: Justin Schuhmann (<jmschu02@gmail.com>)
# Cookbook Name:: iis
# Provider:: site
#
# Copyright:: 2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/mixin/shell_out'
require 'rexml/document'

include Chef::Mixin::ShellOut
include Windows::Helper
include REXML

action :add do
  unless @current_resource.exists
    cmd = "#{appcmd} add vdir /app.name:\"#{@new_resource.application_name}\""
    cmd << " /path:\"#{@new_resource.path}\""
    cmd << " /physicalPath:\"#{win_friendly_path(@new_resource.physical_path)}\""
    cmd << " /userName:\"#{@new_resource.username}\"" if @new_resource.username
    cmd << " /password:\"#{@new_resource.password}\"" if @new_resource.password
    cmd << " /logonMethod:#{@new_resource.logon_method.to_s}" if @new_resource.logon_method
    cmd << " /allowSubDirConfig:#{@new_resource.allow_sub_dir_config}" if @new_resource.allow_sub_dir_config
    
    Chef::Log.info(cmd)
    shell_out!(cmd, {:returns => [0,42]})

    @new_resource.updated_by_last_action(true)
    Chef::Log.info("#{@new_resource} added new virtual directory to application: '#{@new_resource.application_name}'")
  else
    Chef::Log.debug("#{@new_resource} virtual directory already exists - nothing to do")
  end
end

action :config do
  isUpdated = false
  cmd_current_values = "#{appcmd} list vdir \"#{application_identifier}\" /config:* /xml"
  Chef::Log.debug(cmd_current_values)
  cmd_current_values = shell_out(cmd_current_values)
  if cmd_current_values.stderr.empty?
    xml = cmd_current_values.stdout
    doc = Document.new(xml)
    physical_path = XPath.first(doc.root, "VDIR/@physicalPath").to_s == @new_resource.physical_path.to_s || @new_resource.physical_path.to_s == '' ? false : true
    userName = XPath.first(doc.root, "VDIR/virtualDirectory/@userName").to_s == @new_resource.username.to_s || @new_resource.username.to_s == '' ? false : true
    password = XPath.first(doc.root, "VDIR/virtualDirectory/@password").to_s == @new_resource.password.to_s || @new_resource.password.to_s == '' ? false : true
    logonMethod = XPath.first(doc.root, "VDIR/virtualDirectory/@logonMethod").to_s == @new_resource.logon_method.to_s || @new_resource.logon_method.to_s == '' ? false : true
    allowSubDirConfig = XPath.first(doc.root, "VDIR/virtualDirectory/@allowSubDirConfig").to_s == @new_resource.allow_sub_dir_config.to_s || @new_resource.allow_sub_dir_config.to_s == '' ? false : true
  end

  if @new_resource.physical_path && physical_path
    isUpdated = true
    cmd = "#{appcmd} set vdir \"#{application_identifier}\" /physicalPath:\"#{@new_resource.physical_path}\""
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end

  if @new_resource.username && userName
    isUpdated = true
    cmd = "#{appcmd} set vdir \"#{application_identifier}\" /userName:\"#{@new_resource.username}\""
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end

  if @new_resource.password && password
    isUpdated = true
    cmd = "#{appcmd} set vdir \"#{application_identifier}\" /password:\"#{@new_resource.password}\""
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end

  if @new_resource.logon_method && logonMethod
    isUpdated = true
    cmd = "#{appcmd} set vdir \"#{application_identifier}\" /logonMethod:#{@new_resource.logon_method.to_s}"
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end

  if @new_resource.allow_sub_dir_config && allowSubDirConfig
    isUpdated = true
    cmd = "#{appcmd} set vdir \"#{application_identifier}\" /allowSubDirConfig:#{@new_resource.allow_sub_dir_config}"
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end

  if isUpdated
    @new_resource.updated_by_last_action(true)
    Chef::Log.info("#{@new_resource} configured virtual directory to application: '#{@new_resource.application_name}'")
  else
    Chef::Log.debug("#{@new_resource} virtual directory - nothing to do")
  end
end

action :delete do
  if @current_resource.exists
    shell_out!("#{appcmd} delete vdir \"#{application_identifier}\"", {:returns => [0,42]})
    @new_resource.updated_by_last_action(true)
    Chef::Log.info("#{@new_resource} deleted")
  else
    Chef::Log.debug("#{@new_resource} virtual directory does not exist - nothing to do")
  end
end

def load_current_resource
  @current_resource = Chef::Resource::IisVdir.new(@new_resource.name)
  @current_resource.application_name(@new_resource.application_name)
  @current_resource.path(@new_resource.path)
  @current_resource.physical_path(@new_resource.physical_path)

  cmd = shell_out("#{ appcmd } list vdir #{ application_identifier }")
  Chef::Log.debug("#{ @new_resource } list vdir command output: #{ cmd.stdout }")

  if cmd.stderr.empty?
    result = cmd.stdout.match(/^VDIR\s\"#{ Regexp.escape(application_identifier) }\"/)
  end

  Chef::Log.debug("#{ @new_resource } current_resource match output: #{ result }")
  if result
    @current_resource.exists = true
  else
    @current_resource.exists = false
  end
end

private
def appcmd
  @appcmd ||= begin
    "#{node['iis']['home']}\\appcmd.exe"
  end
end

def application_identifier
  @new_resource.application_name.chomp('/') + @new_resource.path
end
