#
# Author:: Justin Schuhmann (<jmschu02@gmail.com>)
# Cookbook Name:: iis
# Resource:: site
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

actions :add, :delete, :config
default_action :add

attribute :application_name, :kind_of => String, :name_attribute => true
attribute :path, :kind_of => String
attribute :physical_path, :kind_of => String
attribute :username, :kind_of => String, :default => nil
attribute :password, :kind_of => String, :default => nil
attribute :logon_method, :kind_of => Symbol, :default => :ClearText, :equal_to => [:Interactive, :Batch, :Network, :ClearText]
attribute :allow_sub_dir_config, :kind_of => [TrueClass, FalseClass], :default => true

attr_accessor :exists

def initialize(*args)
  super
  @action = :add
end
