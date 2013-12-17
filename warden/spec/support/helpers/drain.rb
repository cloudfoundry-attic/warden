module Helpers
  module Drain
    def drain
      Process.kill("USR2", @pid)
      Process.waitpid(@pid)
    end

    def drain_and_restart
      drain
      start_warden
    end

    def read_streams(cli, handle, job_id)
      streams = Hash.new { |k, v| "" }

      cli.write(Warden::Protocol::StreamRequest.new(:handle => handle,
                                                    :job_id => job_id))

      loop do
        resp = cli.read
        break if resp.name.nil?

        streams[resp.name] += resp.data
      end

      streams
    end

    def get_uid(client, handle)
      run_resp = client.run(:handle => handle, :script => "id -u")
      run_resp.exit_status.should == 0
      Integer(run_resp.stdout.chomp)
    end

    def check_request_broken(&blk)
      handle = client.create.handle

      t = Thread.new do
        expect do
          blk.call
        end.to raise_error
      end

      # Force the request before the drain
      t.run if t.alive?

      drain

      t.join
    end
  end
end