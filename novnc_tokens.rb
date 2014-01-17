#!/usr/bin/env ruby
begin
	require 'rubygems'
  require 'em-eventsource'
	require 'json'
	require 'rest_client'
	require 'nokogiri'
	require 'getoptlong'
	require 'digest/md5'
	require 'uri'
  require 'logger'
rescue LoadError
	puts "Some dependencies are missing.
	Check for availabilty of rubygems, rest-client, em-http-request, nokogiri, getoptlong, digest/md5, uri.
	Try again once dependencies are met.

"
end

host = ""
user = ""
pass = ""
outfile = ""
@flush_int = 5
@clean_int = 20
@logfile = "novnc_tokens_stream.log"

#
# Prints command parameters help
def print_help()
	print "novnc_tokens.rb [OPTION]
 
		-h, --help:
			show help
 
		-a [abiquo_api_url] -u [username] -p [password] -o [outfile] [-f [flush-interval]] [-c [clean-interval]] [-l [logfile]]

		[abiquo_api_url]  needs to be the url to the API resoure. ie. \"https://my_abiquo/api\".
    [username]        User to access Abiquo API, needs CLOUD_ADMIN role.
    [password]        Password for [username].
    [outfile]         File where the tokens will be written. This will be used by websockify.
    [flush-interval]  Interval in seconds beetwen writes to [outfile].
    [clean-interval]  Interval in seconds beetwen clean writes (removing non existing tokens) to [outfile].
    [logfile]         Changes default log file ./novnc_tokens_stream.log to [logfile].
"
end

def get_all_vms()
  tokens = Array.new

  url = "#{@host}/admin/enterprises?limit=0"
  entxml = RestClient::Request.new(:method => :get, :url => url, :user => @user, :password => @pass).execute
  Nokogiri::XML.parse(entxml).xpath('//enterprises/enterprise').each do |ent|
    ent.xpath('./link[@rel="virtualmachines"]').each do |entvm|
      url = "#{entvm.attribute("href").to_s}?limit=0"
      vmxml = RestClient::Request.new(:method => :get, :url => url, :user => @user, :password => @pass).execute
      Nokogiri::XML.parse(vmxml).xpath('//virtualMachines/virtualMachine').each do |vm|
        unless vm.at('vdrpIP').nil? or vm.at('vdrpPort').nil?
          conn = "#{vm.at('vdrpIP').to_str}:#{vm.at('vdrpPort').to_str}"
          digest = Digest::MD5.hexdigest(conn)
          line = "#{digest}: #{conn}"
          tokens << line
          #some error occur, dir not writable etc.
        end
      end
    end
  end

  return tokens
end

opts = GetoptLong.new(
	[ '--help', '-h', GetoptLong::NO_ARGUMENT ],
	[ '--api', '-a', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--user', '-u', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--pass', '-p', GetoptLong::REQUIRED_ARGUMENT ],
	[ '--output', '-o', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--flush-interval', '-f', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--clean-interval', '-c', GetoptLong::OPTIONAL_ARGUMENT ],
  [ '--logfile', '-l', GetoptLong::OPTIONAL_ARGUMENT ]
)

opts.each do |opt, arg|
	case opt
	when '--help'
		print_help()
		exit 0
	when '--api'
		@host = arg
	when '--user'
		@user = arg
	when '--pass'
		@pass = arg
	when '--output'
		@outfile = arg
  when '--flush-interval'
    @flush_int = arg.to_i
  when '--clean-interval'
    @clean_int = arg.to_i
  when '--logfile'
    @logfile = arg
	else
		print_help()
		exit 0
	end
end

begin
  f = File.open(@logfile, File::WRONLY | File::APPEND | File::CREAT)
  f.sync = true
  @log = Logger.new(f, 'daily')
  @log.level = Logger::INFO
	
  # Do a clean start
  # Now check existing VMs
  @log.info "Checking for VMs in Abiquo API..."
  tokens = Hash.new()

  get_all_vms.each do |line|
    token, data = line.split(": ")
    tokens[token] = data if not tokens.has_key?(token)
  end
  @log.info "Done."

  # Flush tokens to disk
  @log.info "Flushing data to #{@outfile}... (each #{@flush_int} s)"
  ofile = File.open(@outfile, 'w+')
  tokens.keys.each do |key|
    line = "#{key}: #{tokens[key]}"
    ofile.puts("#{line}")
  end
  ofile.close
  @log.info "Done."

  # Get m url
	api_uri = URI(@host)
	m_url = "#{api_uri.scheme}://#{api_uri.host}/m/stream"
	@log.info "Consuming from #{m_url}"
	
	# Start event machine
  auth = Base64.encode64("#{@user}:#{@pass}").to_s

  EM.run do
    EM.add_periodic_timer(@flush_int) {
      to_write = Array.new

      token_file = File.open(@outfile, 'r+')
      token_file.each do |line|
        token, data = line.split(": ")
        to_write << "#{token}: #{data}" if tokens.has_key?(token)
      end
      token_file.close

      tokens.keys.each do |key|
        line = "#{key}: #{tokens[key]}"
        to_write << line if not to_write.include?(line)
      end
      
      @log.info "Flushing data to #{@outfile}..."
      ofile = File.open(@outfile, 'w+')
      tokens.keys.each do |key|
        line = "#{key}: #{tokens[key]}"
        ofile.puts("#{line}")
      end
      ofile.close
      @log.info "Done."
    }

    EM.add_periodic_timer(@clean_int + 0.2) {
      @log.info "Doing a clean write... (each #{@clean_int} s)"
      new_tokens = Hash.new()

      all_vms = get_all_vms
      @log.info "Found #{all_vms.length} VMs."
      
      all_vms.each do |line|
        token, data = line.split(": ")
        new_tokens[token] = data if not new_tokens.has_key?(token)
      end

      @log.info "Flushing clean data to #{@outfile}..."
      ofile = File.open(@outfile, 'w+')
      new_tokens.keys.each do |key|
        line = "#{key}: #{new_tokens[key]}"
        ofile.puts("#{line}")
      end
      ofile.close
      
      tokens = new_tokens

      @log.info "Done."
    }

    source = EM::EventSource.new(m_url,
      { 'X-Atmosphere-Transport' => 'sse',
        'X-Atmosphere-Framework' => '1.0',
        'action' => 'DEPLOY_FINISH,UNDEPLOY_FINISH' },
      { 'Authorization' => "Basic #{auth.strip}" })

    source.message do |message|
      @log.debug "Received event #{message}"
      if message.start_with?("{")
        evento = JSON.parse(message)
        @log.debug JSON.pretty_generate(evento)

        #vmurl = @host + evento["entityIdentifier"]
        vmurl = "#{@host}#{evento['enterprise']}/action/virtualmachines?limit=0"
        @log.debug "vmurl : #{vmurl}"

        vmxml = RestClient::Request.new(:method => :get, :url => vmurl, :user => @user, :password => @pass, :headers => {'Accept' => 'application/vnd.abiquo.virtualmachines+xml'}).execute
        Nokogiri::XML.parse(vmxml).xpath("//virtualMachines/virtualMachine[name='#{evento['details']['VIRTUAL_MACHINE_NAME']}']").each do |vm|
           unless vm.at('vdrpIP').nil? or vm.at('vdrpPort').nil?
              conn = "#{vm.at('vdrpIP').to_str}:#{vm.at('vdrpPort').to_str}"
              digest = Digest::MD5.hexdigest(conn)
              if not evento['details'].has_key?('TASK_OWNER_ID')
                tokens[digest] = conn
                @log.info "Added token #{digest} for #{conn}"
              else 
                @log.debug "Digest: #{digest} ||"
                tokens.delete(digest)
                @log.info "Removed token #{digest}"
              end
           end
        end
      end

      #puts "TOKENS : #{tokens.inspect}"
    end

    source.error do |error|
      @log.error "error #{error}"
    end

    source.start
  end
rescue SocketError
	@log.error "Cannot connect to specified host."
	exit 1
rescue Interrupt => e
  @log.warn "Caught SIGINT. Flushing to disk..."
  ofile = File.open(@outfile, 'w+')
  tokens.keys.each do |key|
    line = "#{key}: #{tokens[key]}"
    ofile.puts("#{line}")
  end
  ofile.close
  @log.warn "Bye!"
  rescue Exception => e
    puts e.message
    @log.error e.message
end
