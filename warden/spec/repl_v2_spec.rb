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
        @command = "simple_test --field field"
        Readline.should_receive(:readline).once.with('warden> ', true)
          .and_return(@command, nil)

        @client.should_receive(:connected?).once.and_return(true)
        Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
          .and_return(@client)

        @repl = described_class.new
        @repl.should_receive(:restore_history).once.and_return(nil)
      end

      it "should read commands from stdin" do
        @repl.should_receive(:process_line).once.with(@command)
          .and_return({:result => "result"})

        STDOUT.should_receive(:write).with("result").once

        @repl.should_receive(:save_history).once.and_return(nil)
        @repl.start
      end

      it "should write error messages to stderr" do
        ce = Warden::CommandsManager::CommandError.new("command error")
        ce.set_backtrace(["backtrace"])
        @repl.should_receive(:process_line).once.with(@command)
          .and_raise(ce)

        expected = "#{ce}\n"
        ce.backtrace.each { |err| expected << "#{err}\n" }

        received = ""
        STDERR.stub!(:write) { |str| received << str }

        @repl.start
        expected.should == received
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
          .and_return("simple_test --field field", nil)

        history = mock("history")
        Readline::HISTORY.should_receive(:to_a).and_return(history)
        history.should_receive(:to_json).once.and_return('"["test"]"')

        command = "simple_test --field field"
        @repl.should_receive(:process_line).once.with(command)
          .and_return({:result => "result"})
        @repl.should_receive(:restore_history).and_return(nil)

        file = mock("history file")
        file.should_receive(:write).once.with('"["test"]"')

        @repl.should_receive(:open).once.with("history_path", "w+")
          .and_yield(file)

        STDOUT.should_receive(:write).with("result").once

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

  describe "#process_line" do
    before :each do
      @client = mock("warden client")
      Warden::Client.should_receive(:new).once.with("/tmp/warden.sock")
          .and_return(@client)
    end

    context "handle run command" do
      before :each do
        Warden::Protocol::Type.should_receive(:generate_klass_map)
          .with("Request").and_return({1 => Warden::Protocol::RunRequest})
      end

      it "should convert run command to spawn and stream commands" do
        run_request = Warden::Protocol::RunRequest.new
        run_request.handle = "handle"
        run_request.script = "script"

        spawn_request = Warden::Protocol::SpawnRequest.new
        spawn_request.handle = run_request.handle
        spawn_request.script = run_request.script

        spawn_response = Warden::Protocol::SpawnResponse.new
        spawn_response.job_id = 10

        stream_request = Warden::Protocol::StreamRequest.new
        stream_request.handle = run_request.handle
        stream_request.job_id = spawn_response.job_id

        stream_data = Warden::Protocol::StreamResponse.new
        stream_data.name = "stdout"
        stream_data.data = "stdout"

        stream_exit = Warden::Protocol::StreamResponse.new
        stream_exit.exit_status = 1

        @client.should_receive(:connected?).once.and_return(true)
        @client.should_receive(:call).once.with(spawn_request)
          .and_return(spawn_response)
        @client.should_receive(:stream).once.with(stream_request)
          .and_yield(stream_data).and_return(stream_exit)

        STDOUT.should_receive(:write).once.with("stdout")

        repl = described_class.new
        command_info = repl.process_line("run --handle handle --script script")
      end

      it "should generate right description for run command in global help" do
        repl = described_class.new
        command_info = repl.process_line("--help")

        width = Warden::Protocol::RunRequest.type_underscored.size + 2
        expected = "\n"
        expected << "\trun  #{described_class.run_command_description}\n"
        expected << "\thelp Show help.\n"
        expected << "\n"
        expected << "Use --help with each command for more information."
        expected << "\n"

        command_info[:result].should == expected
      end

      it "should generate right description for run command help" do
        repl = described_class.new
        command_info = repl.process_line("run --help")
        command_info[:result]
          .index("description: #{described_class.run_command_description}").
          should be > 0
      end
    end

    context "handle other commands" do
      before :each do
        Warden::Protocol::Type.should_receive(:generate_klass_map)
          .with("Request").and_return(test_klass_map)
      end

      it "should add command trace to output" do
        request = response = SimpleTest.new
        request.field = "field"

        @client.should_receive(:connected?).once.and_return(true)
        @client.should_receive(:call).once.with(request).and_return(response)

        repl = described_class.new(:trace => true)

        command_info = repl.process_line("simple_test --field field")
        expected = "+ simple_test --field field\nfield : field\n"
        command_info.keys.should == [:result]
        command_info[:result].should =~ /^\+ simple_test --field field\n.*/
      end

      it "should serialize response from warden server" do
        request = response = SimpleTest.new
        request.field = "field"

        @client.should_receive(:connected?).once.and_return(true)
        @client.should_receive(:call).once.with(request).and_return(response)

        repl = described_class.new

        command_info = repl.process_line("simple_test --field field")
        expected = "+ simple_test --field field\nfield : field\n"
        command_info.should == {:result => "field : field\n"}
      end

      it "should generate prettified global help" do
        repl = described_class.new

        command_info = repl.process_line("--help")

        width = NestedFieldsHelpTest.type_underscored.size + 2
        expected = "\n"
        test_desc_map.each_pair do |command, description|
          expected << "\t%-#{width}s%s\n" % [command, description]
        end

        expected << "\t%-#{width}s%s\n" % ["help", "Show help."]
        expected << "\n"
        expected << "Use --help with each command for more information."
        expected << "\n"

        command_info[:result].should == expected
      end

      it "should generate prettified command help for simple command" do
        repl = described_class.new

        command_info = repl.process_line("simple_test --help")

        expected = "command: #{SimpleTest.type_underscored}\n"
        expected << "description: #{SimpleTest.description}\n"
        expected << "usage: #{SimpleTest.type_underscored} [options]\n\n"
        expected << "[options] can be one of the following:\n\n"
        expected << "\t--field <field> (string)  # required\n"

        command_info[:result].should == expected
      end

      it "should generate prettified command help for complex command" do
        repl = described_class.new

        command_info = repl.process_line("mixed_test --help")

        expected = "command: #{MixedTest.type_underscored}\n"
        expected << "description: #{MixedTest.description}\n"
        expected << "usage: #{MixedTest.type_underscored} [options]\n\n"
        expected << "[options] can be one of the following:\n\n"
        expected << "\t--bool_field  # required\n"
        expected << "\t--complex_field[index]  # array\n"
        expected << "\t\t.field <field> (string)  # required\n"

        command_info[:result].should == expected
      end
    end
  end
end
