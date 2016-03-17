shared_examples "writing_pidfile" do
  context "when a pidfile is configured" do
    let!(:piddir) { Dir.mktmpdir }
    let(:server_pidfile) { File.join(piddir, "warden.pid") }

    before { stop_warden }
    after { FileUtils.rm_rf(piddir) }

    it "writes to it on startup and removes it on shutdown" do
      start_warden

      expect { File.exists?(server_pidfile) }.to eventually(be_truthy)
      expect(File.read(server_pidfile).to_i).to eq(@pid)

      stop_warden

      expect { File.exists?(server_pidfile) }.to eventually(be_falsey)
    end
  end
end
