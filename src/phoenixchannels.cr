require "http/web_socket"
require "uri"
require "socket"
require "json"
require "log"

module Phoenixchannels
  VERSION = "0.1.0"
  DEFAULT_VSN = "2.0.0"

  Log = ::Log.for("phoenix-channels")
  
  alias MessageJoinRef = String | Nil
  alias MessageRef = String
  alias MessageTopic = String
  alias MessageEvent = String
  alias MessagePayload = String
  alias AttachMessageCallback = Proc(String, Bool)
  
  class Message(T)
    getter :join_ref
    getter :ref
    getter :topic
    getter :event
    getter :payload

    def initialize(@join_ref : MessageJoinRef?, @ref : MessageRef, @topic : MessageTopic, @event : MessageEvent, @payload : T?)
    end

    def hash
      {join_ref: @join_ref,
       ref: @ref,
       topic: @topic,
       event: @event,
       payload: @payload}.hash
    end

    def ==(other)
      other.hash == hash
    end
  end

  class Serializer

    def self.encode(msg : Message)
      [
        msg.join_ref,
        msg.ref,
        msg.topic,
        msg.event,
        msg.payload
      ].to_json
    end

    def self.decode(data : String, totype : T.class) : Message(T) forall T

      result = JSON.parse(data)
      join_ref = nil
      if result[0].as_s?
        join_ref = result[0].as_s
      end

      payload : T? = nil

      # nil payload when fail decode
      begin
        payload_string = result[4].to_json()
        payload = T.from_json(payload_string)
      rescue e
        Log.error { e.inspect_with_backtrace }
      end

      Message(T).new(
        join_ref: join_ref,
        ref: result[1].as_s,
        topic: result[2].as_s,
        event: result[3].as_s,
        payload: payload)
    end
  end

  class Socket
    @ws : HTTP::WebSocket
    @serializer = Serializer
    @heartbeat_timeout = 1
    @on_messages = Array(AttachMessageCallback).new
    @ref = 1
    
    class Error < Exception
    end

    def initialize(address : String)
      # socket.js#144
      uri = URI.parse("#{address}/websocket?vsn=#{DEFAULT_VSN}")
      @ws = HTTP::WebSocket.new(uri)

      spawn do
        @ws.run
      end

      install_heartbeat()

      @ws.on_message do |raw|
        Log.debug { "websocket message: #{raw}" }

        cb_to_removes = [] of AttachMessageCallback
        @on_messages.each do |on_message|
          done = on_message.call(raw)
          if done
            cb_to_removes << on_message
          end
        end

        cb_to_removes.each do |cb|
          @on_messages.delete(cb)
        end
      end
    end

    def run

    end

    def abnormalClose(reason : String)
      # socket.js#486
      @ws.close(HTTP::WebSocket::CloseCode::NormalClosure, reason)
    end

    private def send_heartbeat()
      return if @ws.closed?

      ref = make_ref()

      send(Message.new(topic: "phoenix",
                       event: "heartbeat",
                       payload: {} of String => String,
                                      join_ref: nil,
                                      ref: ref))

      ref
    end

    private def send(msg : Message)
      @ws.send(@serializer.encode(msg))
    rescue ex : Socket::Error
      raise Error.new(ex.message)
    end

    private def make_ref()
      @ref += 1
      @ref.to_s
    end

    private def install_heartbeat()
      spawn do
        ch = stream_messages(Hash(String, String | Hash(String, String))) { false }
        ref = send_heartbeat()

        loop do
          select
          when msg = ch.receive
            if msg.ref == ref
              Log.debug { "sending heartbeat" }
              ref = send_heartbeat()
            end
          when timeout(@heartbeat_timeout.seconds)
            ref = send_heartbeat()
          end
        end
      end
    end

    private def attach_on_messages(&block : AttachMessageCallback)
      @on_messages << block
    end

    def stream_messages(decode_type : T.class, &filter: Message(T) -> Bool) : Channel(Message(T)) forall T
      ch = Channel(Message(T)).new(1)

      attach_on_messages do |raw|
        if @ws.closed?
          ch.close
          next true
        end

        msg = @serializer.decode(raw, decode_type)
        if !filter.call(msg)
          ch.send msg
        end

        next false
      end

      return ch
    end
  end
end
