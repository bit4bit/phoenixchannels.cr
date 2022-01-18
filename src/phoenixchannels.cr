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
  alias MessagePayload = Hash(String, String | Int32 ) | Hash(String, Int32) | Hash(String, String)

  class Message(T)
    getter :join_ref
    getter :ref
    getter :topic
    getter :event
    getter :payload

    def initialize(@join_ref : MessageJoinRef?, @ref : MessageRef, @topic : MessageTopic, @event : MessageEvent, @payload : T)
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

    def self.decode(data : String, &decoder_payload : String -> Payload) : Message(Payload) forall Payload

      result = JSON.parse(data)
      join_ref = nil
      if result[0].as_s?
        join_ref = result[0].as_s
      end

      Message(Payload).new(
        join_ref: join_ref,
        ref: result[1].as_s,
        topic: result[2].as_s,
        event: result[3].as_s,
        payload: decoder_payload.call(result[4].to_json))
    end
  end

  class Socket
    @ws : HTTP::WebSocket
    @serializer = Serializer
    @heartbeat_timeout = 1
    @on_messages = Array(Proc(String, Nil)).new
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

        @on_messages.each do |on_message|
          on_message.call(raw)
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
        ch = stream_messages do |payload|
          payload
        end

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

    private def attach_on_messages(&block : String ->)
      @on_messages << block
    end

    def stream_messages(&decoder_payload : String -> Payload) : Channel(Message(Payload)) forall Payload
      ch = Channel(Message(Payload)).new(1)

      attach_on_messages do |raw|
        if @ws.closed?
          next
        end

        msg = @serializer.decode(raw, &decoder_payload)
        ch.send msg
      end

      return ch
    end
  end
end
