# coding: UTF-8

require "spec_helper"

require "warden/server"
require "warden/client"
require "warden/network"
require "warden/util"

require "warden/container/base"

class SpecNetworkPool < Array
  alias :acquire :shift
  alias :release :push
end

class SpecUidPool < Array
  alias :acquire :shift
  alias :release :push
end

describe Warden::Container::Base do

  # Shortcuts
  Container = Warden::Container::Base
  NetworkPool = SpecNetworkPool
  UidPool = SpecUidPool

  def new_connection
    connection = double("connection")
    connection.extend Warden::EventEmitter
    connection
  end

  let(:connection)   { new_connection }

  let(:network_pool) { NetworkPool.new }
  let(:network)      { Warden::Network::Address.new("127.0.0.0") }
  let(:uid_pool)     { UidPool.new }
  let(:uid)          { 1 }

  before(:each) do
    Container.reset!
    Container.network_pool = network_pool
    Container.uid_pool = uid_pool

    network_pool.push(network)
    uid_pool.push(uid)
  end

  def initialize_container
    container = Container.new
    container.stub(:do_create)
    container.stub(:do_stop)
    container.stub(:do_destroy)
    container.stub(:do_info)
    container.stub(:delete_snapshot)
    container.stub(:write_snapshot)
    container.acquire
    container
  end

  context "create" do
    let(:container) { Container.new }

    before do
      container.stub(:delete_snapshot)
      container.stub(:write_snapshot)
    end

    context "on success" do
      before do
        container.stub(:do_create)
        container.should_receive(:write_snapshot)
      end

      it "should call #do_create" do
        container.should_receive(:do_create)
        container.dispatch(Warden::Protocol::CreateRequest.new)
      end

      it "should return the container handle" do
        response = container.dispatch(Warden::Protocol::CreateRequest.new)
        response.handle.should_not be_nil
      end

      it "should acquire a network" do
        container.dispatch(Warden::Protocol::CreateRequest.new)
        container.network.should == network
        network_pool.should be_empty
      end

      it "should acquire a uid" do
        container.dispatch(Warden::Protocol::CreateRequest.new)
        container.uid.should == uid
        uid_pool.should be_empty
      end

      it "should register with the global registry" do
        container.dispatch(Warden::Protocol::CreateRequest.new)
        Container.registry.size.should == 1
      end
    end

    context "on failure" do
      before do
        container.stub(:do_stop)
        container.stub(:do_destroy)
        container.stub(:do_create).and_raise(Warden::WardenError.new("create"))
      end

      it "should destroy" do
        container.should_receive(:do_destroy)

        expect do
          container.dispatch(Warden::Protocol::CreateRequest.new)
        end.to raise_error(Warden::WardenError, "create")
      end

      it "should not register with the global registry" do
        expect do
          container.dispatch(Warden::Protocol::CreateRequest.new)
        end.to raise_error(Warden::WardenError, "create")

        Container.registry.should be_empty
      end

      it "should release the acquired network" do
        expect do
          container.dispatch(Warden::Protocol::CreateRequest.new)
        end.to raise_error(Warden::WardenError, "create")

        network_pool.size.should == 1
      end

      it "should release the acquired uid" do
        expect do
          container.dispatch(Warden::Protocol::CreateRequest.new)
        end.to raise_error(Warden::WardenError, "create")

        uid_pool.size.should == 1
      end

      context "on failure of destroy" do
        before do
          container.stub(:do_destroy).and_raise(Warden::WardenError.new("destroy"))
        end

        it "should raise original error" do
          expect do
            container.dispatch(Warden::Protocol::CreateRequest.new)
          end.to raise_error(Warden::WardenError, "create")
        end

        it "should release the acquired network" do
          expect do
            container.dispatch(Warden::Protocol::CreateRequest.new)
          end.to raise_error(Warden::WardenError, "create")

          network_pool.size.should == 1
        end

        it "should release the acquired uid" do
          expect do
            container.dispatch(Warden::Protocol::CreateRequest.new)
          end.to raise_error(Warden::WardenError, "create")

          uid_pool.size.should == 1
        end
      end
    end
  end

  context "dispatch" do
    let(:response) { double("response", filtered_hash: {}).as_null_object }
    let(:request) { double("request", filtered_hash: {fake: "request", sensitive: "information"}, create_response: response).as_null_object }
    let(:logger) { double("logger").as_null_object }

    subject(:container) { Container.new }

    before do
      container.stub(:logger).and_return(logger)
      container.stub(:hook)
    end

    it "logs to debug level to avoid logging sensitive information in production" do
      logger.should_receive(:debug).with(an_instance_of(String), request: request.filtered_hash, response: an_instance_of(Hash))

      container.dispatch(request)
    end

    it "calls filtered hash on the request to exclude sensitive information" do
      request.should_receive(:filtered_hash)
      container.dispatch(request)
    end

    it "calls filtered hash on the response to exclude sensitive information" do
      response.should_receive(:filtered_hash)
      container.dispatch(request)
    end
  end

  describe "stop" do
    before(:each) do
      @container = initialize_container
      @container.dispatch(Warden::Protocol::CreateRequest.new)
    end

    it "should call #do_stop" do
      @container.should_receive(:do_stop)
      @container.should_receive(:write_snapshot)
      @container.dispatch(Warden::Protocol::StopRequest.new)
    end
  end

  describe "destroy" do
    before(:each) do
      @container = initialize_container
      @container.dispatch(Warden::Protocol::CreateRequest.new)
    end

    it "should call #do_destroy" do
      @container.should_receive(:do_destroy)
      @container.dispatch(Warden::Protocol::DestroyRequest.new)
    end

    describe "saving the container info" do
      it "saves the container info as #obituary" do
        info_response = Warden::Protocol::InfoResponse.new

        @container.should_receive(:do_stop)
        @container.should_receive(:do_info).and_return(info_response)

        expect do
          @container.dispatch(Warden::Protocol::DestroyRequest.new)
        end.to change { @container.obituary }.from(nil).to(info_response)
      end

      context "when getting the info fails" do
        it "ignores the failure" do
          @container.should_receive(:do_info).and_raise(
            Warden::WardenError.new("failure"))

          expect do
            @container.dispatch(Warden::Protocol::DestroyRequest.new)
          end.to_not raise_error
        end
      end
    end

    context "when stopped" do
      before(:each) do
        @container.dispatch(Warden::Protocol::StopRequest.new)
      end

      it "should not call #do_stop" do
        @container.should_not_receive(:do_stop)
        @container.dispatch(Warden::Protocol::DestroyRequest.new)
      end
    end

    context "when not yet stopped" do
      it "should call #do_stop" do
        @container.should_receive(:do_stop)
        @container.dispatch(Warden::Protocol::DestroyRequest.new)
      end

      it "should not care if #do_stop succeeds" do
        @container.should_receive(:do_stop).and_raise(Warden::WardenError.new("failure"))

        expect do
          @container.dispatch(Warden::Protocol::DestroyRequest.new)
        end.to_not raise_error
      end
    end

    context "when do_destroy fails" do
      before do
        @container.should_receive(:do_destroy).and_raise(Warden::WardenError.new("failure"))
      end

      it "should not be destroyed" do
        expect do
          @container.dispatch(Warden::Protocol::DestroyRequest.new)
        end.to raise_error

        expect(@container.state).to_not eql(Warden::Container::State::Destroyed)
      end

      it "should not be removed from the registry" do
        expect do
          @container.dispatch(Warden::Protocol::DestroyRequest.new)
        end.to raise_error

        expect(Container.registry.size).to eq 1
      end

      it "should not delete the snapshot" do
        @container.should_receive(:delete_snapshot).once

        expect do
          @container.dispatch(Warden::Protocol::DestroyRequest.new)
        end.to raise_error
      end
    end
  end

  describe "connection management" do
    let(:container) { Container.new }
    let(:connection) { new_connection }

    before do
      container.register_connection(connection)
    end

    it "should not store existing connections more than once" do
      expect do
        container.register_connection(connection)
      end.to_not change(container.connections, :size)
    end

    it "should store new connections" do
      another_connection = new_connection

      expect do
        container.register_connection(another_connection)
      end.to change(container.connections, :size)
    end

    it "should setup grace timer" do
      container.should_receive(:setup_grace_timer)
      connection.emit(:close)
    end
  end

  context "grace timer" do
    context "when unspecified" do
      it "should fire after server-wide grace time" do
        Warden::Server.should_receive(:container_grace_time).and_return(0.02)

        @container = initialize_container

        em do
          @container.should_receive(:fire_grace_timer)
          @container.setup_grace_timer

          ::EM.add_timer(0.03) { done }
        end
      end
    end

    context "when nil" do
      it "should not fire" do
        @container = initialize_container
        @container.grace_time = nil

        em do
          @container.should_not_receive(:fire_grace_timer)
          @container.setup_grace_timer

          ::EM.add_timer(0.03) { done }
        end
      end
    end

    context "when not nil" do
      before(:each) do
        @container = initialize_container
        @container.grace_time = 0.02
      end

      context "when there are connections still left" do
        before do
          @container.register_connection(new_connection)
        end

        it "should not fire" do
          em do
            @container.should_not_receive(:fire_grace_timer)
            @container.setup_grace_timer

            ::EM.add_timer(0.01) { @container.cancel_grace_timer }
            ::EM.add_timer(0.03) { done }
          end
        end
      end

      context "when the last connection closed" do
        it "should fire after grace time" do
          em do
            @container.should_receive(:fire_grace_timer)
            @container.setup_grace_timer

            ::EM.add_timer(0.03) { done }
          end
        end

        it "should not fire when timer is cancelled" do
          em do
            @container.should_not_receive(:fire_grace_timer)
            @container.setup_grace_timer

            ::EM.add_timer(0.01) { @container.cancel_grace_timer }
            ::EM.add_timer(0.03) { done }
          end
        end

        context "when fired" do
          it "should destroy container" do
            em do
              @container.should_receive(:dispatch).
                with(Warden::Protocol::DestroyRequest.new)
              @container.setup_grace_timer

              ::EM.add_timer(0.03) { done }
            end
          end

          it "should ignore any WardenError raised by destroy" do
            em do
              @container.should_receive(:dispatch).
                with(Warden::Protocol::DestroyRequest.new).
                and_raise(Warden::WardenError.new("failure"))
              @container.setup_grace_timer

              ::EM.add_timer(0.03) { done }
            end
          end
        end
      end
    end
  end

  describe "state" do
    before(:each) do
      @container = initialize_container
    end

    let(:container) do
      @container
    end

    shared_examples "succeeds when born" do |blk|
      it "succeeds when container was not yet created" do
        expect do
          instance_eval(&blk)
        end.to_not raise_error
      end

      it "fails when container was already created" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)

        expect do
          instance_eval(&blk)
        end.to raise_error(Warden::WardenError, /container state/i)
      end

      it "fails when container was already stopped" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)
        @container.dispatch(Warden::Protocol::StopRequest.new)

        expect do
          instance_eval(&blk)
        end.to raise_error(Warden::WardenError, /container state/i)
      end

      it "fails when container was already destroyed" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)
        @container.dispatch(Warden::Protocol::DestroyRequest.new)

        expect do
          instance_eval(&blk)
        end.to raise_error(Warden::WardenError, /container state/i)
      end
    end

    shared_examples "succeeds when active" do |blk|
      it "succeeds when container was created" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)

        expect do
          instance_eval(&blk)
        end.to_not raise_error
      end

      it "fails when container was not yet created" do
        expect do
          instance_eval(&blk)
        end.to raise_error(Warden::WardenError, /container state/i)
      end

      it "fails when container was already stopped" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)
        @container.dispatch(Warden::Protocol::StopRequest.new)

        expect do
          instance_eval(&blk)
        end.to raise_error(Warden::WardenError, /container state/i)
      end

      it "fails when container was already destroyed" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)
        @container.dispatch(Warden::Protocol::DestroyRequest.new)

        expect do
          instance_eval(&blk)
        end.to raise_error(Warden::WardenError, /container state/i)
      end
    end

    shared_examples "succeeds when active or stopped" do |blk|
      it "succeeds when container was created" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)

        expect do
          instance_eval(&blk)
        end.to_not raise_error
      end

      it "succeeds when container was created and stopped" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)
        @container.dispatch(Warden::Protocol::StopRequest.new)

        expect do
          instance_eval(&blk)
        end.to_not raise_error
      end

      it "fails when container was not yet created" do
        expect do
          instance_eval(&blk)
        end.to raise_error(Warden::WardenError, /container state/i)
      end

      it "fails when container was already destroyed" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)
        @container.dispatch(Warden::Protocol::StopRequest.new)
        @container.dispatch(Warden::Protocol::DestroyRequest.new)

        expect do
          instance_eval(&blk)
        end.to raise_error(Warden::WardenError, /container state/i)
      end
    end

    shared_examples "succeeds when born, active, stopped or destroyed" do |blk|
      it "succeeds when container was created" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)

        expect do
          instance_eval(&blk)
        end.to_not raise_error
      end

      it "succeeds when container was created and stopped" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)
        @container.dispatch(Warden::Protocol::StopRequest.new)

        expect do
          instance_eval(&blk)
        end.to_not raise_error
      end

      it "succeeds when container was not yet created" do
        expect do
          instance_eval(&blk)
        end.to_not raise_error
      end

      it "fails when container was already destroyed" do
        @container.dispatch(Warden::Protocol::CreateRequest.new)
        @container.dispatch(Warden::Protocol::StopRequest.new)
        @container.dispatch(Warden::Protocol::DestroyRequest.new)

        expect do
          instance_eval(&blk)
        end.to_not raise_error
      end
    end

    describe "create" do
      include_examples "succeeds when born", Proc.new {
        container.dispatch(Warden::Protocol::CreateRequest.new)
      }
    end

    describe "stop" do
      include_examples "succeeds when active or stopped", Proc.new {
        container.dispatch(Warden::Protocol::StopRequest.new)
      }
    end

    describe "destroy" do
      include_examples "succeeds when born, active, stopped or destroyed", Proc.new {
        container.dispatch(Warden::Protocol::DestroyRequest.new)
      }
    end

    describe "spawn" do
      before(:each) do
        @job = double("job", :job_id => 1)
        @container.stub(:create_job).and_return(@job)
      end

      include_examples "succeeds when active", Proc.new {
        container.dispatch(Warden::Protocol::SpawnRequest.new)
      }
    end

    describe "run" do
      let(:job) { double("job", :job_id => 1, :err => nil, :yield => [0, "", ""], :cleanup => nil) }
      before(:each) do
        container.stub(:create_job).and_return(job)
      end

      include_examples "succeeds when active", Proc.new {
        container.dispatch(Warden::Protocol::RunRequest.new)
      }

      context "when job yielded with error" do
        before do
          job.stub(:err) { WardenError.new("failed to do the job") }

          it "saves the error message in response events" do
            container.dispatch(Warden::Protocol::CreateRequest.new)
            response = container.dispatch(Warden::Protocol::RunRequest.new)
            response.info.events.should include("failed to do the job")
          end
        end
      end
    end

    describe "net_in" do
      before(:each) do
        @container.stub(:do_net_in)
      end

      include_examples "succeeds when active", Proc.new {
        container.dispatch(Warden::Protocol::NetInRequest.new)
      }
    end

    describe "net_out" do
      before(:each) do
        @container.stub(:do_net_out)
      end

      include_examples "succeeds when active", Proc.new {
        container.dispatch(Warden::Protocol::NetOutRequest.new)
      }
    end

    describe "copy_in" do
      before(:each) do
        @container.stub(:do_copy_in)
      end

      include_examples "succeeds when active", Proc.new {
        container.dispatch(Warden::Protocol::CopyInRequest.new)
      }
    end

    describe "copy_out" do
      before(:each) do
        @container.stub(:do_copy_out)
      end

      include_examples "succeeds when active or stopped", Proc.new {
        container.dispatch(Warden::Protocol::CopyOutRequest.new)
      }
    end

    describe "limit_memory" do
      before(:each) do
        @container.stub(:do_limit_memory)
      end

      include_examples "succeeds when active or stopped", Proc.new {
        container.dispatch(Warden::Protocol::LimitMemoryRequest.new)
      }
    end

    describe "limit_disk" do
      before(:each) do
        @container.stub(:do_limit_disk)
      end

      include_examples "succeeds when active or stopped", Proc.new {
        container.dispatch(Warden::Protocol::LimitDiskRequest.new)
      }
    end

    describe "limit_bandwidth" do
      before(:each) do
        @container.stub(:do_limit_bandwidth)
      end

      include_examples "succeeds when active or stopped", Proc.new {
        container.dispatch(Warden::Protocol::LimitBandwidthRequest.new)
      }
    end

    describe "limit_cpu" do
      before(:each) do
        @container.stub(:do_limit_cpu)
      end

      include_examples "succeeds when active or stopped", Proc.new {
        container.dispatch(Warden::Protocol::LimitCpuRequest.new)
      }
    end
  end
end
