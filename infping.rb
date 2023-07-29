# frozen_string_literal: true

require 'pty'
require 'influxdb-client'

def program_exists?(program)
  `type "#{program}" > /dev/null 2>&1;`
  $?.success?
end

unless program_exists?('fping')
  raise 'fping is not installed'
end

def debug?
  !ENV["DEBUG"].nil?
end

def extract_slash_data(slash_data)
  headers, data = slash_data.split(' = ')
  data.split('/')
end

def parse_fping_line(line)
  hostname, data = line.split(':')
  connection_data, latency_data = data.split(',')

  sent, recv, lossp = extract_slash_data(connection_data).map(&:to_i)
  min, avg, max = if latency_data
    extract_slash_data(latency_data).map(&:to_f)
  else
    [nil, nil, nil]
  end

  [hostname.strip, lossp, min, avg, max]
end

begin
  hosts = ENV['HOSTS']
  raise 'Environment-variable HOSTS not set, exiting!' if hosts.nil?

  influxdb_endpoint = ENV['INFLUXDB_ENDPOINT']
  raise 'Environment-variable INFLUXDB_ENDPOINT not set, exiting!' if influxdb_endpoint.nil?
  # TODO parse endpoint data, verify if it's http or https
  use_ssl = false

  influxdb_bucket = ENV['INFLUXDB_BUCKET']
  raise 'Environment-variable INFLUXDB_BUCKET not set, exiting!' if influxdb_bucket.nil?

  influxdb_org = ENV['INFLUXDB_ORG']
  raise 'Environment-variable INFLUXDB_ORG not set, exiting!' if influxdb_org.nil?

  influxdb_token = ENV['INFLUXDB_TOKEN']
  raise 'Environment-variable INFLUXDB_TOKEN not set, exiting!' if influxdb_token.nil?

  influxdb = InfluxDB2::Client.new(
    influxdb_endpoint,
    influxdb_token,
    bucket: influxdb_bucket,
    org: influxdb_org,
    precision: InfluxDB2::WritePrecision::SECOND,
    use_ssl: use_ssl,
    debugging: debug?
  )
  client = influxdb.create_write_api

  command = [].tap { |it|
    it << 'fping'
    it << ['-B', '1']    # Backoff factor
    it << '-D'           # Add Unix timestamps in front of output lines generated with in looping or counting modes (-l, -c, or -C)
    it << ['-r', '0']    # Retry limit (default 3)
    it << ['-O', '0']    # Set the typ of service flag (TOS)
    it << ['-p', '1000'] # The time in milliseconds that fping waits between successive packets to an individual target.
    it << ['-Q', '5']    # Quiet. Don't show per-probe results, but show summary results every n seconds
    it << '-l'           # Loop sending packets to each target indefinitely

    hosts.split(',').each do |host|
      it << host.strip
    end
  }.flatten.join(' ')

  puts "Command: #{command}"

  PTY.spawn(command) do |stdout, stdin, pid|
    begin
      stdout.each do |line|
        puts line if debug?

        case line
        when /\[[0-9+]{2}:[0-9+]{2}:[0-9+]{2}\]/
          # Ignore until this is resolved: https://github.com/schweikert/fping/issues/203
        else
          hostname, lossp, min, avg, max = parse_fping_line(line)

          point = InfluxDB2::Point.new(name: 'pings')
          point.add_tag('host', hostname)

          unless [min, avg, max].any?(&:nil?)
            puts "#{hostname}: loss=#{lossp}%, min=#{min}, avg=#{avg}, max=#{max}" if debug?

            point.add_field('loss', lossp)
            point.add_field('min', min)
            point.add_field('avg', avg)
            point.add_field('max', max)
          else
            puts "#{hostname}: loss=#{lossp}%" if debug?
            point.add_field('loss', lossp)
          end

          client.write(data: point)
        end
      end
    rescue Errno::EIO
    end
  end
rescue PTY::ChildExited
  puts 'The child process exited!'
end
