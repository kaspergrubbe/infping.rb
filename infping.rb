# frozen_string_literal: true

require 'pty'
require 'influxdb'

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

  influxdb_hostname = ENV['INFLUXDB_HOSTNAME']
  raise 'Environment-variable INFLUXDB_HOSTNAME not set, exiting!' if influxdb_hostname.nil?

  influxdb_database = ENV['INFLUXDB_DATABASE']
  raise 'Environment-variable INFLUXDB_DATABASE not set, exiting!' if influxdb_database.nil?

  influxdb_username = ENV['INFLUXDB_USERNAME']
  raise 'Environment-variable INFLUXDB_USERNAME not set, exiting!' if influxdb_username.nil?

  influxdb_password = ENV['INFLUXDB_PASSWORD']
  raise 'Environment-variable INFLUXDB_PASSWORD not set, exiting!' if influxdb_password.nil?

  influxdb = InfluxDB::Client.new(influxdb_database,
    host: influxdb_hostname,
    username: influxdb_username,
    password: influxdb_password,
    time_precision: 's',
  )

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
  }.flatten.join(" ")

  puts "Command: #{command}"

  PTY.spawn(command) do |stdout, stdin, pid|
    begin
      stdout.each do |line|
        case line
        when /\[[0-9+]{2}:[0-9+]{2}:[0-9+]{2}\]/
          # Ignore until this is resolved: https://github.com/schweikert/fping/issues/203
        else
          hostname, lossp, min, avg, max = parse_fping_line(line)

          data = {
            tags: {
              host: hostname,
            },
            timestamp: Time.now.utc.to_i,
          }

          data[:values] = unless [min, avg, max].any?(&:nil?)
            puts "#{hostname}: loss=#{lossp}%, min=#{min}, avg=#{avg}, max=#{max}" if debug?
            {
              loss: lossp,
              min:  min,
              avg:  avg,
              max:  max,
            }
          else
            puts "#{hostname}: loss=#{lossp}%" if debug?
            {
              loss: lossp,
            }
          end

          influxdb.write_point('pings', data)
        end
      end
    rescue Errno::EIO
    end
  end
rescue PTY::ChildExited
  puts 'The child process exited!'
end
