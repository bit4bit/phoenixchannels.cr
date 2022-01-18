require "./spec_helper"
require "log"

Log.setup_from_env(default_level: :debug)

describe Phoenixchannels do
  it "connect" do
    socket = Phoenixchannels::Socket.new("ws://elixir-spec.dev:4000/socket")
    stream = socket.stream_messages do |payload_as_json|
      Hash(String, Hash(String, String) | String).from_json(payload_as_json)
    end

    select
    when msg = stream.receive
      msg.topic.should eq("phoenix")
    when timeout(3.seconds)
      fail "expected messaget with topic phoenix"
    end
    socket.abnormalClose("test")
  end
end
