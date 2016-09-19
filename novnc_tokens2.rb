#!/usr/bin/env ruby

require 'rubygems'
require 'trollop'
require 'abiquo-api'

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
      vms = link("#{r.url}/deployedvms", "virtualmachines").get
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
