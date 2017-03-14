require 'sidekiq'
require 'socket'
require 'timeout'
DEFAULT_SOCKET_PATH="/var/run/dokku-daemon/dokku-daemon.sock"
DEFAULT_TIMEOUT=60
Sidekiq.configure_server do |config|
  config.redis = { url: ENV["REDIS_URL"] }
end

class CommandRunner
  include Sidekiq::Worker
  def perform(command_id, command)
    logger.info "[CommandRunner] #{command_id} | #{command}"

    $redis = Redis.new( url: ENV["REDIS_URL"] )

    begin
      Timeout.timeout(DEFAULT_TIMEOUT) do
        socket = UNIXSocket.new(DEFAULT_SOCKET_PATH)
        logger.info "[CommandRunner] Sending the command"
        socket.puts(command)
        logger.info "[CommandRunner] Waiting for the result"
        result = socket.gets("\n")
        logger.info "[CommandRunner] Result: #{result}"
        $redis.set("dda:#{command_id}", result)
        socket.close
      end
    rescue Timeout::Error
      logger.info "[CommandRunner] Command Timed Out"
      $redis.set("dda:#{command_id}", {status: "error", message: "command_timed_out"}.to_json)
      socket.close if defined? socket
    rescue Exception => e
      logger.info "[CommandRunner] Exception"
      logger.info e
      $redis.set("dda:#{command_id}", {status: "error", message: e.message}.to_json)
      socket.close if defined? socket
    end
  end
end
