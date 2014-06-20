shared_examples "snapshotting_common" do
  it "should snapshot a container after creation" do
    handle = client.create.handle
    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = Yajl::Parser.parse(File.read(snapshot_path))
    snapshot["state"].should == "active"
  end

  it "should snapshot a container after it is stopped" do
    handle = client.create.handle
    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = Yajl::Parser.parse(File.read(snapshot_path))
    snapshot["state"].should == "active"

    client.stop(:handle => handle)
    File.exist?(snapshot_path).should be_true
    snapshot = Yajl::Parser.parse(File.read(snapshot_path))
    snapshot["state"].should == "stopped"
  end

  it "should snapshot a container when a spawned process exits" do
    handle = client.create.handle

    client.spawn(:handle => handle, :script => "echo abc")

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = Yajl::Parser.parse(File.read(snapshot_path))
    snapshot["jobs"].keys.size.should == 1
  end

  it "should create empty snapshots for alive processes" do
    handle = client.create.handle

    client.spawn(:handle => handle, :script => "sleep 2; echo abc")

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = Yajl::Parser.parse(File.read(snapshot_path))
    snapshot["jobs"].keys.size.should == 1

    job_snapshot = snapshot["jobs"].values.first
    job_snapshot.should be_an_instance_of Hash
  end
end

shared_examples "snapshotting_net_in" do
  it "should snapshot a container after net_in request" do
    handle = client.create.handle
    client.net_in(:handle => handle)

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = Yajl::Parser.parse(File.read(snapshot_path))
    snapshot["resources"]["ports"].size.should == 1
  end

  it "should create empty snapshot for alive processes after net_in request" do
    handle = client.create.handle
    client.spawn(:handle => handle, :script => "sleep 2; echo abc")
    client.net_in(:handle => handle)

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = Yajl::Parser.parse(File.read(snapshot_path))
    snapshot["jobs"].keys.size.should == 1

    job_snapshot = snapshot["jobs"].values.first
    job_snapshot.should be_an_instance_of Hash
  end
end

shared_examples "snapshotting_net_out" do
  it "should snapshot a container after a net_out request" do
    handle = client.create.handle
    client.net_out(:handle => handle, :network => "1.2.3.0/32", :port => 8765, :protocol => Warden::Protocol::NetOutRequest::Protocol::TCP)

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = Yajl::Parser.parse(File.read(snapshot_path))

    snapshot["resources"]["net_out"].size.should == 1
    snapshot["resources"]["net_out"].first.should eq ["1.2.3.0/32", "8765", "tcp", nil, nil]
  end
end