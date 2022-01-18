require "./spec_helper"

describe Phoenixchannels do

  describe Phoenixchannels::Serializer do
    example_msg = Phoenixchannels::Message(Hash(String,Int32)).new(
      join_ref: "0",
      ref: "1",
      topic: "t",
      event: "e",
      payload: {"foo" => 1}
    )
    
    it "encodes" do
      Phoenixchannels::Serializer.encode(example_msg).should eq("[\"0\",\"1\",\"t\",\"e\",{\"foo\":1}]")
    end

    it "decodes"do
      msg = Phoenixchannels::Serializer.decode("[\"0\",\"1\",\"t\",\"e\",{\"foo\":1}]") do |payload_as_json|
        Hash(String,Int32).from_json(payload_as_json)
      end
        
      msg.should eq(example_msg)
    end
  end
end
