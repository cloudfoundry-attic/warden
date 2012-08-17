# coding: UTF-8

require "warden/repl_v2"
require "spec_helper"

describe Warden::Repl do
  describe "#start" do
    it "should connect to the server through the default socket path" do
      client = mock("warden client")
      client.should_receive(:connect).once
      client.should_receive(:connected?).once.and_return(false)

      Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
        .and_return(client)

      Readline.should_receive(:completion_append_character=).once
      Readline.should_receive(:completion_proc=).once
      Readline.should_receive(:readline).once.with('warden> ', true)
        .and_return(nil)
      repl = described_class.new
      repl.start
    end

    it "should connect to the server through the specified socket path" do
      socket_path = "socket_path"

      client = mock("warden client")
      client.should_receive(:connect).once
      client.should_receive(:connected?).once.and_return(false)

      Warden::Client.should_receive(:new).once.with(socket_path)
        .and_return(client)

      Readline.should_receive(:completion_append_character=).once
      Readline.should_receive(:completion_proc=).once
      Readline.should_receive(:readline).once.with('warden> ', true)
        .and_return(nil)
      repl = described_class.new(:socket_path => socket_path)
      repl.start
    end

    it "should not reconnect to the server if already connected" do
      socket_path = "socket_path"

      client = mock("warden client")
      client.should_receive(:connected?).once.and_return(true)

      Warden::Client.should_receive(:new).once.with(socket_path)
        .and_return(client)

      Readline.should_receive(:completion_append_character=).once
      Readline.should_receive(:completion_proc=).once
      Readline.should_receive(:readline).once.with('warden> ', true)
        .and_return(nil)
      repl = described_class.new(:socket_path => socket_path)
      repl.start
    end

    it "should read commands from stdin" do
      client = mock("warden client")
      client.should_receive(:connected?).twice.and_return(true)

      Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
        .and_return(client)

      Readline.should_receive(:completion_append_character=).once
      Readline.should_receive(:completion_proc=).once
      Readline.stub(:readline).and_return("simple_test", nil)

      repl = described_class.new
      repl.should_receive(:deserialize).once
        .with(["simple_test"]).and_return(SimpleTest.new)

      repl.start
    end

    it "should write error messages to stderr" do
      client = mock("warden client")

    end

    it "should save the command history" do
    end

    it "should restore the command history" do
    end

    it "should perform keyword completion" do
    end
  end

  describe "#process_command" do
    it "should add command trace to output" do
    end

    it "should return global help" do
    end

    it "should return command help" do
    end

    it "should convert run command to spawn and stream commands" do
    end

    it "should serialize response from warden server" do
    end

    it "should wrap errors" do
    end
  end
end
