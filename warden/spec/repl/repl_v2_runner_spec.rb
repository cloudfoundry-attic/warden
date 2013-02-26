# coding: UTF-8

require "warden/repl/repl_v2_runner"

describe Warden::Repl::ReplRunner do
  describe "run" do
    context "parse global arguments" do
      it "should parse global arguments" do
        repl = double("repl")
        repl.should_receive(:start).once.and_return(0)

        expected_options = {
          :trace => true,
          :socket_path => "/foo/bar",
          :exit_on_error => true,
        }
        Warden::Repl::Repl.should_receive(:new).once.with(expected_options).
          and_return(repl)

        expect do
          described_class.run(["--trace", "--exit_on_error",
                               "--socket", "/foo/bar"])
        end.to raise_error(SystemExit) do |error|
          error.status.should == 0
        end
      end

      it "should raise an error when a global argument is wrong" do
        expect {
          described_class.run(["--socket"])
        }.to raise_error(OptionParser::MissingArgument, /.*--socket$/)

        expect {
          described_class.run(["--blah"])
        }.to raise_error(OptionParser::InvalidOption, /.*--blah$/)
      end

      it "should print help" do
        received_output = ""
        STDOUT.should_receive(:write).any_number_of_times do |arg|
          received_output << arg
        end

        expect {
          described_class.run(["--help"])
        }.to raise_error(SystemExit) { |error|
          error.status.should == 0
        }

        received_output.should =~ /^Usage:.*/
      end

      it "should raise error if the delimiter separating global args and command args is specified more than once" do
        expect {
          described_class.run(["--", "--"])
        }.to raise_error(RuntimeError,
                         "Delimiter: '--' specified multiple times.")
      end
    end

    context "start interactive repl" do
      it "should set trap for SIGINT signal" do
        described_class.should_receive(:trap).once.and_yield
        STDERR.should_receive(:write).once.with("\n\nExiting...\n")

        repl = double("repl")
        Warden::Repl::Repl.should_receive(:new).once.with({}).and_return(repl)

        expect {
          described_class.run
        }.to raise_error(SystemExit) { |error|
          error.status.should == 0
        }
      end

      it "should start interactive repl" do
        repl = double("repl")
        repl.should_receive(:start).once.and_return(0)

        Warden::Repl::Repl.should_receive(:new).once.with({}).and_return(repl)

        expect do
          described_class.run
        end.to raise_error(SystemExit) do |error|
          error.status.should == 0
        end
      end
    end

    context "execute commands non-interactively" do
      it "should write output of command to stdout and exit with exit status of the command" do
        repl = double("repl")
        repl.should_receive(:process_command).once.with(["command", "--arg"]).
          and_return({ :result => "result", :exit_status => 2 })

        Warden::Repl::Repl.should_receive(:new).once.with({}).and_return(repl)

        received_output = ""
        STDOUT.should_receive(:write).any_number_of_times do |arg|
          received_output << arg
        end

        expect {
          described_class.run(["--", "command", "--arg"])
        }.to raise_error(SystemExit) { |error|
          error.status.should == 2
        }

        received_output.should == "result"
      end

      it "should write stack back trace of command error to stderr and exit with status 0" do
        repl = double("repl")
        ce = Warden::Repl::CommandsManager::CommandError.new("command error")
        repl.should_receive(:process_command).once.with(["command", "--arg"]).
          and_raise(ce)

        Warden::Repl::Repl.should_receive(:new).once.with({}).and_return(repl)

        received_err = ""
        STDERR.should_receive(:write).any_number_of_times do |arg|
          received_err << arg
        end

        expect {
          described_class.run(["--", "command", "--arg"])
        }.to raise_error(SystemExit) { |error|
          error.status.should == 0
        }

        expected_err = "#{ce}\n"
        ce.backtrace.each { |err| expected_err << "#{err}\n" }

        received_err.should == expected_err
      end
    end
  end
end
