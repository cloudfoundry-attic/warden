# coding: UTF-8

require "warden/repl_v2"
require "spec_helper"

describe Warden::Repl do
  describe "#start" do
    before :each do
      Readline.should_receive(:completion_append_character=).once
      Readline.should_receive(:completion_proc=).once
      @client = mock("warden client")
    end

    it "should connect to the server through the default socket path if none is specified" do
      @client.should_receive(:connect).once
      @client.should_receive(:connected?).once.and_return(false)

      Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
        .and_return(@client)

      Readline.should_receive(:readline).once.with('warden> ', true)
        .and_return(nil)

      repl = described_class.new
      repl.should_receive(:restore_history).once

      repl.start
    end

    it "should connect to the server through the specified socket path" do
      socket_path = "socket_path"

      @client.should_receive(:connect).once
      @client.should_receive(:connected?).once.and_return(false)

      Warden::Client.should_receive(:new).once.with(socket_path)
        .and_return(@client)

      Readline.should_receive(:readline).once.with('warden> ', true)
        .and_return(nil)

      repl = described_class.new(:socket_path => socket_path)
      repl.should_receive(:restore_history).once

      repl.start
    end

    it "should not reconnect to the server if already connected" do
      socket_path = "socket_path"

      @client.should_receive(:connected?).once.and_return(true)

      Warden::Client.should_receive(:new).once.with(socket_path)
        .and_return(@client)

      Readline.should_receive(:readline).once.with('warden> ', true)
        .and_return(nil)

      repl = described_class.new(:socket_path => socket_path)
      repl.should_receive(:restore_history).once

      repl.start
    end

    it "should read commands from stdin" do
      request = SimpleTest.new
      response = SimpleTest.new

      @client.should_receive(:connected?).once.and_return(true)

      Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
        .and_return(@client)

      Readline.stub(:readline).once.with('warden> ', true)
        .and_return("simple_test", nil)

      repl = described_class.new
      repl.should_receive(:restore_history).once
      repl.should_receive(:process_command).once.with("simple_test")
        .and_return({:result => "result"})

      STDOUT.should_receive(:write).with("result\n").once
      repl.start
    end

    it "should write error messages to stderr" do
      request = SimpleTest.new
      response = SimpleTest.new

      @client.should_receive(:connected?).once.and_return(true)

      Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
        .and_return(@client)

      Readline.stub(:readline).once.with('warden> ', true)
        .and_return("simple_test", nil)

      repl = described_class.new
      repl.should_receive(:restore_history).and_return(nil)
      repl.should_receive(:process_command).once.with("simple_test")
        .and_raise(Warden::Repl::ReplError.new("dummy error"))

      STDERR.should_receive(:write).with("dummy error\n").once

      repl.start
    end

    it "should save the command history" do
      request = SimpleTest.new
      response = SimpleTest.new

      @client.should_receive(:connected?).once.and_return(true)

      Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
        .and_return(@client)

      Readline.stub(:readline).once.with('warden> ', true)
        .and_return("simple_test", nil)

      history = mock("history")
      Readline::HISTORY.should_receive(:to_a).and_return(history)
      history.should_receive(:to_json).once.and_return("simple_test")

      repl = described_class.new(:history_path => "history_path")

      repl.should_receive(:restore_history).and_return(nil)
      repl.should_receive(:process_command).once.with("simple_test")
        .and_return({:result => "result"})

      file = mock("history file")
      file.should_receive(:write).once.with("simple_test")
      repl.should_receive(:open).once.with("history_path", "w+").and_yield(file)

      STDOUT.should_receive(:write).with("result\n").once

      repl.start
    end

    #it "should restore the command history" do
    #end

    #it "should perform keyword completion" do
    #end
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
