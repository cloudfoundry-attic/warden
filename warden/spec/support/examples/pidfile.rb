shared_examples "writing_pidfile" do
  context "when a pidfile is configured" do
    let!(:piddir) { Dir.mktmpdir }
    let(:server_pidfile) { File.join(piddir, "warden.pid") }

    before { stop_warden }
    after { FileUtils.rm_rf(piddir) }

    it "writes to it on startup and removes it on shutdown" do
      expect {
        start_warden

        # give warden EM thread time to write out the pidfile
        sleep(0.1)
      }.to change { File.exists?(server_pidfile) }.from(false).to(true)

      expect(File.read(server_pidfile).to_i).to eq(@pid)

      expect {
        stop_warden
      }.to change { File.exists?(server_pidfile) }.from(true).to(false)
    end
  end
end
