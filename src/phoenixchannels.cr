require "http/web_socket"
require "uri"
require "socket"

module Phoenixchannels
  VERSION = "0.1.0"
  DEFAULT_VSN = "2.0.0"

  class Socket
    @ws : HTTP::WebSocket?

    class Error < Exception
    end

    def initialize(address : String)
      # socket.js#144
      @uri = URI.parse("#{address}/websocket?vsn=#{DEFAULT_VSN}")
    end

    def connect
      ws = HTTP::WebSocket.new(@uri)

      spawn do
        ws.run
      end

      @ws = ws
    rescue ex : ::Socket::Error
      raise Error.new(ex.message)
    end

    def abnormalClose(reason : String)
      # socket.js#486
      conn.close(HTTP::WebSocket::CloseCode::NormalClosure, reason)
    end

    private def conn : HTTP::WebSocket
      ws = @ws
      if !ws.nil?
        ws
      else
        raise Error.new("invalid connection")
      end
    end
  end
end
