require "./spec_helper"

describe Phoenixchannels do
  it "connect" do
    socket = Phoenixchannels::Socket.new("ws://elixir-spec.dev:4000/socket")
    socket.connect()
    socket.abnormalClose("test")
  end
end
