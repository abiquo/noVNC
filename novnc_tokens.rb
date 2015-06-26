#!/usr/bin/ruby
begin
	require 'rubygems'
	require 'rest_client'
	require 'json'
	require 'getoptlong'
	require 'digest/md5'
rescue LoadError
	puts "Some dependencies are missing.
	Check for availabilty of rubygems, rest-client, json, getoptlong, digest/md5.
	Try again once dependencies are met.

"
end

host = ""
user = ""
pass = ""

#
# Prints command parameters help
def print_help()
	print "novnc_tokens.rb [OPTION]
 
		-h, --help:
			show help
 
		-a [abiquo_api_url] -u [username] -p [password]

		[abiquo_api_url] needs to be the url to the API resoure. ie. \"https://my_abiquo/api\"
"
end

opts = GetoptLong.new(
	[ '--help', '-h', GetoptLong::NO_ARGUMENT ],
	[ '--api', '-a', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--user', '-u', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--pass', '-p', GetoptLong::REQUIRED_ARGUMENT ]
)

opts.each do |opt, arg|
	case opt
	when '--help'
		print_help()
		exit 0
	when '--api'
		host = arg
	when '--user'
		user = arg
	when '--pass'
		pass = arg
	else
		print_help()
		exit 0
	end
end

begin
	url = "#{host}/admin/enterprises?limit=0"
	entjson = RestClient::Request.new(:method => :get, :url => url, :user => user, :password => pass).execute
	enterprises = JSON.parse(entjson)['collection']
	enterprises.each do |ent|
		vm_url = ent['links'].select {|l| l['rel'].eql? "virtualmachines" }.first['href']
		vmjson = RestClient::Request.new(:method => :get, :url => "#{vm_url}?limit=0", :user => user, :password => pass, :headers => {'Accept' => 'application/vnd.abiquo.virtualmachines+json'}).execute
		vms = JSON.parse(vmjson)['collection']

		vms.each do |vm|
			conn = "#{vm['vdrpIP']}:#{vm['vdrpPort']}"
			digest = Digest::MD5.hexdigest(conn)
			line = "#{digest}: #{conn}"
			puts "#{line}"
		end
	end
rescue SocketError
	puts "Cannot connect to specified host."
	exit 1
end
