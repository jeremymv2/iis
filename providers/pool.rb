#
# Author:: Kendrick Martin (kendrick.martin@webtrends.com)
# Contributor:: David Dvorak (david.dvorak@webtrends.com)
# Cookbook Name:: iis
# Provider:: pool
#
# Copyright:: 2011, Webtrends Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
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
  cmd = "#{appcmd} add apppool /name:\"#{@new_resource.pool_name}\""
  cmd << " /managedRuntimeVersion:" if @new_resource.runtime_version || @new_resource.no_managed_code
  cmd << "v#{@new_resource.runtime_version}" if @new_resource.runtime_version && !@new_resource.no_managed_code
  cmd << " /managedPipelineMode:#{@new_resource.pipeline_mode}" if @new_resource.pipeline_mode
  Chef::Log.debug(cmd)
  shell_out!(cmd)
  configure
  @new_resource.updated_by_last_action(true)
  Chef::Log.info("App pool created")
  else
    Chef::Log.debug("#{@new_resource} pool already exists - nothing to do")
  end
end

action :config do
  configure
end

action :delete do
  if @current_resource.exists
    shell_out!("#{appcmd} delete apppool \"#{site_identifier}\"")
    @new_resource.updated_by_last_action(true)
    Chef::Log.info("#{@new_resource} deleted")
  else
    Chef::Log.debug("#{@new_resource} pool does not exist - nothing to do")
  end
end

action :start do
  unless @current_resource.running
    shell_out!("#{appcmd} start apppool \"#{site_identifier}\"")
    @new_resource.updated_by_last_action(true)
    Chef::Log.info("#{@new_resource} started")
  else
    Chef::Log.debug("#{@new_resource} already running - nothing to do")
  end
end

action :stop do
  if @current_resource.running
    shell_out!("#{appcmd} stop apppool \"#{site_identifier}\"")
    @new_resource.updated_by_last_action(true)
    Chef::Log.info("#{@new_resource} stopped")
  else
    Chef::Log.debug("#{@new_resource} already stopped - nothing to do")
  end
end

action :restart do
  shell_out!("#{appcmd} stop APPPOOL \"#{site_identifier}\"")
  sleep 2
  shell_out!("#{appcmd} start APPPOOL \"#{site_identifier}\"")
  @new_resource.updated_by_last_action(true)
  Chef::Log.info("#{@new_resource} restarted")
end

action :recycle do
  shell_out!("#{appcmd} recycle APPPOOL \"#{site_identifier}\"")
  @new_resource.updated_by_last_action(true)
  Chef::Log.info("#{@new_resource} recycled")
end

def load_current_resource
  @current_resource = Chef::Resource::IisPool.new(@new_resource.name)
  @current_resource.pool_name(@new_resource.pool_name)
  cmd = shell_out("#{appcmd} list apppool")
  # APPPOOL "DefaultAppPool" (MgdVersion:v2.0,MgdMode:Integrated,state:Started)
  Chef::Log.debug("#{@new_resource} list apppool command output: #{cmd.stdout}")
  if cmd.stderr.empty?
    result = cmd.stdout.gsub(/\r\n?/, "\n") # ensure we have no carriage returns
    result = result.match(/^APPPOOL\s\"(#{new_resource.pool_name})\"\s\(MgdVersion:(.*),MgdMode:(.*),state:(.*)\)$/)
  end
  Chef::Log.debug("#{@new_resource} current_resource match output: #{result}")
  if result
    @current_resource.exists = true
    @current_resource.running = (result[4] =~ /Started/) ? true : false
  else
    @current_resource.exists = false
    @current_resource.running = false
  end
end

private
def appcmd
  @appcmd ||= begin
    "#{node['iis']['home']}\\appcmd.exe"
  end
end

def site_identifier
  @new_resource.pool_name
end

def configure
  isUpdated = false
  cmd_current_values = "#{appcmd} list apppool \"#{@new_resource.pool_name}\" /config:* /xml"
  Chef::Log.debug(cmd_current_values)
  cmd_current_values = shell_out(cmd_current_values)
  if cmd_current_values.stderr.empty?
    xml = cmd_current_values.stdout
    doc = Document.new(xml)
    logEventOnRecycle = XPath.first(doc.root, "APPPOOL/add/recycling/@logEventOnRecycle").to_s.gsub(" ","") == "Time,Requests,Schedule,Memory,IsapiUnhealthy,OnDemand,ConfigChange,PrivateMemory" ? false : true
    privateMemory = XPath.first(doc.root, "APPPOOL/add/recycling/periodicRestart/@privateMemory").to_s == @new_resource.private_mem.to_s || @new_resource.private_mem.to_s == '' ? false : true
    maxProcesses = XPath.first(doc.root, "APPPOOL/add/processModel/@maxProcesses").to_s == @new_resource.max_proc.to_s || @new_resource.max_proc.to_s == '' ? false : true
    enable32BitAppOnWin64 = XPath.first(doc.root, "APPPOOL/add/@enable32BitAppOnWin64").to_s == @new_resource.thirty_two_bit.to_s || @new_resource.thirty_two_bit.to_s == '' ? false : true
    recycleAfterTime = XPath.first(doc.root, "APPPOOL/add/recycling/periodicRestart/@time").to_s == @new_resource.recycle_after_time.to_s || @new_resource.recycle_after_time.to_s == '' ? false : true
    recycleAtTime = XPath.first(doc.root, "APPPOOL/add/recycling/periodicRestart/schedule/add/@value").to_s == @new_resource.recycle_at_time.to_s || @new_resource.recycle_at_time.to_s == '' ? false : true
    managedRuntimeVersion = XPath.first(doc.root, "APPPOOL/@RuntimeVersion").to_s == "v#{@new_resource.runtime_version}" ? false : true
    idleTimeout = XPath.first(doc.root, "APPPOOL/add/recycling/periodicRestart/schedule/add/@value").to_s == @new_resource.recycle_at_time.to_s || @new_resource.recycle_at_time.to_s == '' ? false : true
    identityType = XPath.first(doc.root, "APPPOOL/add/processModel/@identityType").to_s == "SpecificUser" ? false : true
    userName = XPath.first(doc.root, "APPPOOL/add/processModel/@userName").to_s == @new_resource.pool_username.to_s || @new_resource.pool_username.to_s == '' ? false : true
    password = XPath.first(doc.root, "APPPOOL/add/processModel/@password").to_s == @new_resource.pool_password.to_s || @new_resource.pool_password.to_s == '' ? false : true
  end

  if logEventOnRecycle
    isUpdated = true
    cmd = "#{appcmd} set config /section:applicationPools "
    cmd << "\"/[name='#{@new_resource.pool_name}'].recycling.logEventOnRecycle:PrivateMemory,Memory,Schedule,Requests,Time,ConfigChange,OnDemand,IsapiUnhealthy\""
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end
  if !@new_resource.private_mem.nil? && privateMemory 
    isUpdated = true
    cmd = "#{appcmd} set config /section:applicationPools \"/[name='#{@new_resource.pool_name}'].recycling.periodicRestart.privateMemory:#{@new_resource.private_mem}\""
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end
  if !@new_resource.max_proc.nil? && maxProcesses
    isUpdated = true
    cmd = "#{appcmd} set apppool \"#{@new_resource.pool_name}\" -processModel.maxProcesses:#{@new_resource.max_proc}"
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end
  if !@new_resource.thirty_two_bit.nil? && enable32BitAppOnWin64
    isUpdated = true
    cmd = "#{appcmd} set apppool \"/apppool.name:#{@new_resource.pool_name}\" /enable32BitAppOnWin64:#{@new_resource.thirty_two_bit}"
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end
  if !@new_resource.recycle_after_time.nil? && recycleAfterTime
    isUpdated = true
    cmd = "#{appcmd} set apppool \"/apppool.name:#{@new_resource.pool_name}\" /recycling.periodicRestart.time:#{@new_resource.recycle_after_time}"
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end
  if !@new_resource.recycle_at_time.nil? && recycleAtTime
    isUpdated = true
    cmd = "#{appcmd} set apppool \"/apppool.name:#{@new_resource.pool_name}\" /-recycling.periodicRestart.schedule"
    Chef::Log.debug(cmd)
    shell_out!(cmd)
    cmd = "#{appcmd} set apppool \"/apppool.name:#{@new_resource.pool_name}\" /+recycling.periodicRestart.schedule.[value='#{@new_resource.recycle_at_time}']"
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end
  if !@new_resource.runtime_version.nil? && managedRuntimeVersion
    isUpdated = true
    cmd = "#{appcmd} set apppool \"/apppool.name:#{@new_resource.pool_name}\" /managedRuntimeVersion:v#{@new_resource.runtime_version}"
    Chef::Log.debug(cmd) if @new_resource.runtime_version
    shell_out!(cmd)
  end
  if !@new_resource.worker_idle_timeout.nil? && idleTimeout
    isUpdated = true
    cmd = "#{appcmd} set config /section:applicationPools \"/[name='#{@new_resource.pool_name}'].processModel.idleTimeout:#{@new_resource.worker_idle_timeout}\""
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end
  if !@new_resource.pool_username.nil? || @new_resource.pool_username != '' and !@new_resource.pool_password.nil? || !@new_resource.pool_username == '' and userName and password
    isUpdated = true
    cmd = "#{appcmd} set config /section:applicationPools"
    cmd << " \"/[name='#{@new_resource.pool_name}'].processModel.identityType:SpecificUser\""
    cmd << " \"/[name='#{@new_resource.pool_name}'].processModel.userName:#{@new_resource.pool_username}\""
    cmd << " \"/[name='#{@new_resource.pool_name}'].processModel.password:#{@new_resource.pool_password}\""
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  elsif @new_resource.pool_username.nil? || @new_resource.pool_username == '' and @new_resource.pool_password.nil? || @new_resource.pool_username == '' and !identityType
    isUpdated = true
    cmd = "#{appcmd} set config /section:applicationPools"
    cmd << " \"/[name='#{@new_resource.pool_name}'].processModel.identityType:ApplicationPoolIdentity\""
    Chef::Log.debug(cmd)
    shell_out!(cmd)
  end

  if isUpdated
    @new_resource.updated_by_last_action(true)
    Chef::Log.info("#{@new_resource} configured application pool")
  else
    Chef::Log.debug("#{@new_resource} application pool - nothing to do")
  end
end
