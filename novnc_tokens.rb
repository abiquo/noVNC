#!/usr/bin/ruby
begin
	require 'rubygems'
	require 'rest_client'
	require 'nokogiri'
	require 'getoptlong'
	require 'digest/md5'
rescue LoadError
	puts "Some dependencies are missing.
	Check for availabilty of rubygems, rest-client, nokogiri, getoptlong, digest/md5.
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
	entxml = RestClient::Request.new(:method => :get, :url => url, :user => user, :password => pass, :headers => { 'Accept' => 'application/vnd.abiquo.enterprises+xml' }).execute
	Nokogiri::XML.parse(entxml).xpath('//enterprises/enterprise').each do |ent|
		ent.xpath('./link[@rel="virtualmachines"]').each do |entvm|
			url = entvm.attribute("href").to_s
			vmxml = RestClient::Request.new(:method => :get, :url => "#{url}?limit=0", :user => user, :password => pass, :headers => {'Accept' => 'application/vnd.abiquo.virtualmachines+xml'}).execute
			Nokogiri::XML.parse(vmxml).xpath('//virtualMachines/virtualMachine').each do |vm|
				unless vm.at('vdrpIP').nil? or vm.at('vdrpPort').nil?
					conn = "#{vm.at('vdrpIP').to_str}:#{vm.at('vdrpPort').to_str}"
					digest = Digest::MD5.hexdigest(conn)
					line = "#{digest}: #{conn}"
					puts "#{line}"
				end
			end
		end
	end
rescue SocketError
	puts "Cannot connect to specified host."
	exit 1
end
