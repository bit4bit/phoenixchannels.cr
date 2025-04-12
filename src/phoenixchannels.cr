require "http/web_socket"
require "uri"
require "uri/params"
require "socket"
require "json"
require "log"

module Phoenixchannels
  VERSION     = "0.1.0"
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

    def initialize(@join_ref : MessageJoinRef?, @ref : MessageRef?, @topic : MessageTopic, @event : MessageEvent, @payload : T)
    end

    def hash
      {join_ref: @join_ref,
       ref:      @ref,
       topic:    @topic,
       event:    @event,
       payload:  @payload}.hash
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
        msg.payload,
      ].to_json
    end

    def self.decode(data : String, totype : T.class) : Message(T) forall T
      result = JSON.parse(data)
      join_ref = nil
      if result[0].as_s?
        join_ref = result[0].as_s
      end
      ref = nil
      if result[1].as_s?
        ref = result[1].as_s
      end

      payload : T = T.new

      # nil payload when fail decode
      begin
        payload_string = result[4].to_json
        payload = T.from_json(payload_string)
      rescue e
        Log.error { e.inspect_with_backtrace }
      end

      Message(T).new(
        join_ref: join_ref,
        ref: ref,
        topic: result[2].as_s,
        event: result[3].as_s,
        payload: payload)
    end
  end

  class PhoenixChannelError < Exception
  end

  class PhoenixChannel(T)
    @join_ref : String

    def initialize(@socket : Socket, @topic : String, @payload : T)
      @join_ref = @socket.make_ref
      join()
    end

    def push(event_name, payload)
      ref = @socket.make_ref
      msg = Message(T).new(
        join_ref: @join_ref,
        ref: ref,
        topic: @topic,
        event: event_name,
        payload: payload)
      @socket.send(msg)
      ref
    end

    def push_and_receive(event_name, payload)
      ref = @socket.make_ref
      push = Message(T).new(
        join_ref: @join_ref,
        ref: ref,
        topic: @topic,
        event: event_name,
        payload: payload)
      send_and_receive(push)
    end

    private def join
      push = Message(T).new(
        join_ref: @join_ref,
        ref: @socket.make_ref,
        topic: @topic,
        event: "phx_join",
        payload: @payload)

      msg = send_and_receive(push)
      status = msg.payload.try &.fetch("status", JSON::Any.new("")).try &.as_s
      if status != "ok"
        raise PhoenixChannelError.new("fail to join status: #{msg.payload.try &.fetch("response", "unknown")}")
      end
    end

    private def send_and_receive(push : Message(T)) : Message(Hash(String, JSON::Any?))
      # install stream listener
      stream = @socket.stream_messages_with_filter(true, Hash(String, JSON::Any?)) do |recv|
        if push.ref == recv.ref && push.topic == recv.topic && recv.event == "phx_reply"
          next true
        end

        false
      end

      # push message
      @socket.send(push)

      # get response
      select
      when msg = stream.receive
        return msg
      when timeout 5.seconds
        raise PhoenixChannelError.new("timeout channel join")
      end
    end

    def stream_messages(decode_type : T.class) : Channel(Message(T)) forall T
      @socket.stream_messages_with_filter(false, decode_type) do |recv|
        if recv.join_ref == @join_ref
          next true
        end

        false
      end
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

    def initialize(address : String, params = Hash(String, Array(String)).new)
      # socket.js#144
      params["vsn"] = [DEFAULT_VSN]
      uri = URI.parse("#{address}/websocket")
      uri.query_params = URI::Params.new(params)
      @ws = HTTP::WebSocket.new(uri)

      spawn do
        @ws.run
      end

      @ws.on_message do |raw|
        Log.debug { "websocket message: #{raw}" }

        cb_to_removes = [] of AttachMessageCallback
        @on_messages.each do |on_message|
          done = on_message.call(raw)
          if done
            cb_to_removes << on_message
          end
        end

        cb_to_removes.each do |callback|
          @on_messages.delete(callback)
        end
      end
    end

    def run
    end

    def channel(topic : String, payload : T) forall T
      PhoenixChannel(T).new(self, topic, payload)
    end

    def abnormal_close(reason : String)
      # socket.js#486
      @ws.close(HTTP::WebSocket::CloseCode::NormalClosure, reason)
    end

    private def send_heartbeat
      return if @ws.closed?

      ref = make_ref()

      send(Message.new(topic: "phoenix",
        event: "heartbeat",
        payload: {} of String => String,
        join_ref: nil,
        ref: ref))

      ref
    end

    def send(msg : Message)
      Log.debug { "socket sending #{@serializer.encode(msg)}" }
      @ws.send(@serializer.encode(msg))
    rescue ex : Socket::Error
      raise Error.new(ex.message)
    end

    def make_ref
      @ref += 1
      @ref.to_s
    end

    def install_heartbeat
      spawn do
        ch = stream_messages(Hash(String, String | Hash(String, String)))
        ref = send_heartbeat()

        loop do
          select
          when msg = ch.receive
            if msg.ref == ref
              sleep @heartbeat_timeout.seconds

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

    def stream_messages_with_filter(once, decode_type : T.class, &filter : Message(T) -> Bool) : Channel(Message(T)) forall T
      ch = Channel(Message(T)).new

      stream = stream_messages(decode_type)
      spawn do
        loop do
          select
          when msg = stream.receive?
            break if msg.nil?

            if filter.call(msg)
              ch.send msg
              break if once
            end
          end
        end
        ch.close
      ensure
        ch.close
      end

      ch
    end

    def stream_messages(decode_type : T.class) : Channel(Message(T)) forall T
      ch = Channel(Message(T)).new(1)

      attach_on_messages do |raw|
        if @ws.closed?
          ch.close
          next true
        end

        msg = @serializer.decode(raw, decode_type)
        if !msg.payload.nil?
          ch.send msg
        end

        false
      end

      ch
    end
  end
end
