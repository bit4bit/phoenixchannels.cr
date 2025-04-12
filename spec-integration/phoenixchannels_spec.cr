require "./spec_helper"
require "log"

Log.setup_from_env(default_level: :debug)

describe Phoenixchannels do
  it "connect" do
    socket = Phoenixchannels::Socket.new("ws://elixir-spec.dev:4000/socket")
    stream = socket.stream_messages(Hash(String, JSON::Any))

    select
    when msg = stream.receive
      msg.topic.should eq("phoenix")
    when timeout(3.seconds)
      fail "expected messaget with topic phoenix"
    end
    socket.abnormal_close("test")
  end

  it "connect channel not raises exception" do
    socket = Phoenixchannels::Socket.new("ws://elixir-spec.dev:4000/socket")
    channel = socket.channel("echo:lobby", "super payload")

    stream = channel.stream_messages(Hash(String, JSON::Any?))
    select
    when msg = stream.receive
      msg.event.should eq("heartbeat")
    when timeout(3.seconds)
      fail "expected message heartbeat"
    end

    socket.abnormal_close("test")
  end

  it "connect channel and push async message" do
    socket = Phoenixchannels::Socket.new("ws://elixir-spec.dev:4000/socket")
    channel = socket.channel("echo:lobby", "super payload")
    stream = channel.stream_messages(Hash(String, JSON::Any?))
    push_echo_ref = channel.push("echo", "echoing")

    select
    when msg = stream.receive
      msg.ref.should eq(push_echo_ref)
      msg.event.should eq("phx_reply")
      msg.payload["response"].to_s.should eq("echoing")
    when timeout(3.seconds)
      fail "expected message echoing"
    end

    socket.abnormal_close("test")
  end

  it "connect channel and push sync message" do
    socket = Phoenixchannels::Socket.new("ws://elixir-spec.dev:4000/socket")
    channel = socket.channel("echo:lobby", "super payload")

    resp = channel.push_and_receive("echo", "echoing2")

    resp.payload["response"].to_s.should eq("echoing2")

    socket.abnormal_close("test")
  end
end
