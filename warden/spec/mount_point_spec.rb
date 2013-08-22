require "warden/mount_point"

describe Warden::MountPoint do
  let(:mount_point) { Warden::MountPoint.new }

  describe "#for_path" do
    let(:root_pathname) { double("Pathname", mountpoint?: true, to_s: "/") }

    before do
      root_pathname.stub(realpath: root_pathname)
      Pathname.stub(:new).with("/").and_return(root_pathname)
    end

    context "when we ask about the root of the filesystem" do
      it "returns root for root" do
        mount_point.for_path("/").should == "/"
      end
    end

    context "for simple tree traversals" do
      let(:hello_pathname) do
        double("Pathname - /hello",
               mountpoint?: true,
               parent: root_pathname,
               to_s: "/hello")
      end

      let(:world_pathname) do
        double("Pathname - /world",
               mountpoint?: false,
               parent: hello_pathname,
               to_s: "/hello/world")
      end

      let(:path_pathname) do
        double("Pathname - /path",
               mountpoint?: false,
               parent: world_pathname,
               to_s: "/hello/world/path")
      end

      before do
        Pathname.stub(:new).with("/hello/world/path").and_return(path_pathname)

        hello_pathname.stub(realpath: hello_pathname)
        world_pathname.stub(realpath: world_pathname)
        path_pathname.stub(realpath: path_pathname)
      end

      it "returns the different mount point" do
        mount_point.for_path("/hello/world/path").should == "/hello"
      end
    end

    context "for traversals that include awkward symlinks" do
      let(:hello_pathname) do
        double("Pathname - /hello",
               mountpoint?: true,
               parent: root_pathname,
               to_s: "/hello")
      end

      let(:mnt_pathname) do
        double("Pathname - /mnt",
               mountpoint?: true,
               parent: nil,
               to_s: "/mnt")
      end

      let(:mnt_symlink_pathname) do
        double("Pathname - /mnt/symlink",
               mountpoint?: false,
               parent: mnt_pathname,
               to_s: "/mnt/symlink")
      end

      let(:symlink_pathname) do
        double("Pathname - /hello/symlink",
               mountpoint?: false,
               parent: hello_pathname,
               to_s: "/hello/symlink",
               realpath: mnt_symlink_pathname)
      end

      let(:path_pathname) do
        double("Pathname - /hello/symlink/path",
               mountpoint?: false,
               parent: symlink_pathname,
               to_s: "/hello/symlink/path")
      end

      before do
        mnt_pathname.stub(realpath: mnt_pathname)
        mnt_symlink_pathname.stub(realpath: mnt_symlink_pathname)
        path_pathname.stub(realpath: path_pathname)
        Pathname.stub(:new).with("/hello/symlink/path").and_return(path_pathname)
      end

      it "returns the different mount point" do
        mount_point.for_path("/hello/symlink/path").should == "/mnt"
      end
    end
  end
end