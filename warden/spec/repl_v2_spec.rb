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

    context "connect to the server" do
      before :each do
        Readline.should_receive(:readline).once.with('warden> ', true)
          .and_return(nil)
      end

      it "through the default socket path if none is specified" do
        @client.should_receive(:connect).once
        @client.should_receive(:connected?).once.and_return(false)

        Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
          .and_return(@client)

        repl = described_class.new
        repl.should_receive(:restore_history).once
        repl.start
      end

      it "through the specified socket path" do
        socket_path = "socket_path"

        @client.should_receive(:connect).once
        @client.should_receive(:connected?).once.and_return(false)

        Warden::Client.should_receive(:new).once.with(socket_path)
          .and_return(@client)

        repl = described_class.new(:socket_path => socket_path)
        repl.should_receive(:restore_history).once
        repl.start
      end

      it "not reconnect to the server if already connected" do
        @client.should_receive(:connected?).once.and_return(true)

        Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
          .and_return(@client)

        repl= described_class.new
        repl.should_receive(:restore_history).once
        repl.start
      end
    end

    context "read input, write errors" do
      before :each do
        Readline.should_receive(:readline).once.with('warden> ', true)
          .and_return("simple_test", nil)

        @client.should_receive(:connected?).once.and_return(true)

        Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
          .and_return(@client)

        @repl = described_class.new
        @repl.should_receive(:restore_history).once.and_return(nil)
      end

      it "should read commands from stdin" do
        @repl.should_receive(:process_command).once.with("simple_test")
          .and_return({:result => "result"})

        STDOUT.should_receive(:write).with("result\n").once

        @repl.should_receive(:save_history).once.and_return(nil)
        @repl.start
      end

      it "should write error messages to stderr" do
        @repl.should_receive(:process_command).once.with("simple_test")
          .and_raise(Warden::Repl::ReplError.new("error"))

        STDERR.should_receive(:write).with("error\n").once

        @repl.start
      end
    end

    context "save, restore history" do
      before :each do
        @client.should_receive(:connected?).once.and_return(true)
        Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
          .and_return(@client)

        @repl = described_class.new(:history_path => "history_path")
      end

      it "should save the command history" do
        Readline.should_receive(:readline).once.with('warden> ', true)
          .and_return("simple_test", nil)

        history = mock("history")
        Readline::HISTORY.should_receive(:to_a).and_return(history)
        history.should_receive(:to_json).once.and_return('"["test"]"')

        @repl.should_receive(:process_command).once.with("simple_test")
          .and_return({:result => "result"})
        @repl.should_receive(:restore_history).and_return(nil)

        file = mock("history file")
        file.should_receive(:write).once.with('"["test"]"')

        @repl.should_receive(:open).once.with("history_path", "w+")
          .and_yield(file)

        STDOUT.should_receive(:write).with("result\n").once

        @repl.start
      end

      it "should not restore the command history when the file is absent" do
        Readline.should_receive(:readline).once.with('warden> ', true)
          .and_return(nil)

        File.should_receive(:exists?).once.with("history_path")
          .and_return(false)

        @repl.start
      end

      it "should restore the command history" do
        Readline.should_receive(:readline).once.with('warden> ', true)
          .and_return(nil)

        File.should_receive(:exists?).once.with("history_path")
          .and_return(true)

        JSON.should_receive(:parse).once.with('["test"]')
          .and_return(["test"])

        Readline::HISTORY.should_receive(:push).once.with("test")
          .and_return(nil)

        file = mock("history file")
        file.should_receive(:read).once.and_return('["test"]')

        @repl.should_receive(:open).once.with("history_path", "r")
          .and_yield(file)
        @repl.start
      end
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
