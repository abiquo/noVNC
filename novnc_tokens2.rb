#!/usr/bin/env ruby

# 82473345 - 40762279 - 45174221 - 33652054 - 12387249

require 'rubygems'
require 'trollop'
require '/home/antxon/github/abiquo/api-ruby/lib/abiquo-api.rb'
require 'pry-byebug'

# Usage:
# novnc_tokens2.rb ABQ_ENDPOINT USERNAME PASSWORD TOKENFILE
#
# Example
# novnc_tokens2.rb http://abq38.bcn.abiquo.com/api admin xabiquo /opt/websockify/config.vnc

def link(h, a)
  AbiquoAPI::Link.new(:href => h, :type => "application/vnd.abiquo.#{a}+json", :client => $client)
end

begin
  opts = Trollop::options do
    opt :endpoint, "API endpoint", :type => :string
    opt :username, "API username", :type => :string, :default => "admin"
    opt :password, "API password", :type => :string, :default => "xabiquo"
    opt :mode    , "Authmode",     :type => :string, :default => "basic"
    opt :file    , "Tokens file",  :type => :string, :default => "/opt/websockify/config.vnc"
    opt :key     , "Consumer key", :type => :string
    opt :secret  , "Consumer key", :type => :string
    opt :tkey    , "Token key"   , :type => :string
    opt :tsecret , "Token secret", :type => :string
  end
  
  $client = case opts[:mode]
    when "oauth" then
      AbiquoAPI.new(
        :abiquo_api_url      => opts[:endpoint],
        :abiquo_api_key      => opts[:key],
        :abiquo_api_secret   => opts[:secret],
        :abiquo_token_key    => opts[:tkey],
        :abiquo_token_secret => opts[:tsecret])
    else
      AbiquoAPI.new(
        :abiquo_api_url => opts[:endpoint],
        :abiquo_username => opts[:username],
        :abiquo_password => opts[:password])
    end

  # Get tokens
  tokens = []
  datacenters = link("/api/admin/datacenters", "datacenters").get
  datacenters.each do |d|
    racks = d.link(:racks).get
    racks.each do |r|
      vms = link("#{r.url}/deployedvms", "virtualmachines").get(:limit => 0)
      vms.each do |vm|
        next unless (vm.vdrpIP && vm.vdrpPort)
        conn = "#{vm.vdrpIP}:#{vm.vdrpPort}"
        hash = Digest::MD5.hexdigest(conn)
        tokens << "#{hash}: #{conn}"
      end
    end
  end

  # Update token file
  File.open(opts[:file], "w") { |f| f.puts(tokens) }
rescue => e
  STDERR.puts "Unexpected exception"
  raise
end
