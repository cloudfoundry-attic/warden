require "thread"

shared_examples "snapshotting_common" do
  it "should snapshot a container after creation" do
    handle = client.create.handle
    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = JSON.parse(File.read(snapshot_path))
    snapshot["state"].should == "active"
  end

  it "should snapshot a container after it is stopped" do
    handle = client.create.handle
    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = JSON.parse(File.read(snapshot_path))
    snapshot["state"].should == "active"

    client.stop(:handle => handle)
    File.exist?(snapshot_path).should be_true
    snapshot = JSON.parse(File.read(snapshot_path))
    snapshot["state"].should == "stopped"
  end

  it "should snapshot a container when a spawned process exits" do
    handle = client.create.handle

    client.spawn(:handle => handle, :script => "echo abc")
    sleep 0.1

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = JSON.parse(File.read(snapshot_path))
    snapshot["jobs"].keys.size.should == 1
  end

  it "should not snapshot alive processes when a spawned process exits" do
    handle = client.create.handle

    client.spawn(:handle => handle, :script => "echo abc")
    client.spawn(:handle => handle, :script => "sleep 2; echo abc")
    sleep 0.1

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = JSON.parse(File.read(snapshot_path))
    snapshot["jobs"].keys.size.should == 1
  end
end

shared_examples "snapshotting_net_in" do
  it "should snapshot a container after net_in request" do
    handle = client.create.handle
    client.net_in(:handle => handle)

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = JSON.parse(File.read(snapshot_path))
    snapshot["resources"]["ports"].size.should == 1
  end

  it "should not snapshot alive processes after net_in request" do
    handle = client.create.handle
    client.spawn(:handle => handle, :script => "sleep 2; echo abc")
    client.net_in(:handle => handle)

    snapshot_path = File.join(container_depot_path, handle, "snapshot.json")
    File.exist?(snapshot_path).should be_true
    snapshot = JSON.parse(File.read(snapshot_path))
    snapshot["jobs"].keys.size.should == 0
  end
end
