# coding: UTF-8

shared_examples "file transfer" do
  attr_reader :handle

  def path_in_container(path)
    if container_klass =~ /::Insecure$/
      File.join(container_depot_path, handle, "root", path[1..-1])
    else
      path
    end
  end

  def run(script)
    response = client.run(:handle => handle, :script => script)
    response.should be_ok
    response
  end

  def copy_in(options)
    response = client.copy_in(options.merge(:handle => handle))
    response.should be_ok
    response
  end

  def copy_out(options)
    response = client.copy_out(options.merge(:handle => handle))
    response.should be_ok
    response
  end

  def create_file_in_container(path, contents, mode=nil)
    # Create the directory that will house the file
    response = run "mkdir -p #{path_in_container(File.dirname(path))}"
    response.exit_status.should == 0

    # Create the file
    response = run "echo -n #{contents} > #{path_in_container(path)}"
    response.exit_status.should == 0

    # Set permissions
    if mode
      response = run "chmod #{mode} #{path_in_container(path)}"
      response.exit_status.should == 0
    end
  end

  before do
    @handle = client.create.handle
    @tmpdir = Dir.mktmpdir

    @outdir = File.join(@tmpdir, 'out')
    Dir.mkdir(@outdir)

    @sentinel_dir = File.join(@tmpdir, 'sentinel_root')
    Dir.mkdir(@sentinel_dir)

    @sentinel_path = File.join(@sentinel_dir, 'sentinel')
    @sentinel_contents = 'testing123'
    File.open(@sentinel_path, 'w+') {|f| f.write(@sentinel_contents) }

    @sentinel_sym_link_path = File.join(@sentinel_dir, 'sentinel_sym_link')
    system("ln -s #{@sentinel_path} #{@sentinel_sym_link_path}").should be_true

    @sentinel_hard_link_path = File.join(@sentinel_dir, 'sentinel_hard_link')
    system("ln #{@sentinel_path} #{@sentinel_hard_link_path}").should be_true

    @relative_sentinel_path = "sentinel_root/sentinel"
  end

  after(:each) do
    FileUtils.rm_rf(@tmpdir)
  end

  it "should allow files to be copied in" do
    copy_in \
      :src_path => @sentinel_dir,
      :dst_path => "/tmp"

    c_path = path_in_container(File.join("/tmp", @relative_sentinel_path))
    response = run "cat #{c_path}"
    response.exit_status.should == 0
    response.stdout.should == @sentinel_contents
  end

  it "should allow files to be copied out" do
    create_file_in_container("/tmp/sentinel_root/sentinel", @sentinel_contents)

    copy_out \
      :src_path => "/tmp/sentinel_root",
      :dst_path => @outdir

    File.read(File.join(@outdir, @relative_sentinel_path)).should == @sentinel_contents
  end

  it "should preserve file permissions" do
    File.chmod(0755, @sentinel_path)

    copy_in \
      :src_path => @sentinel_dir,
      :dst_path => "/tmp"

    c_path = path_in_container(File.join("/tmp", @relative_sentinel_path))
    response = run "stat -c %a #{c_path}"
    response.exit_status.should == 0
    response.stdout.chomp.should == "755"

    create_file_in_container("/tmp/sentinel_root/sentinel", @sentinel_contents)

    copy_out \
      :src_path => "/tmp/sentinel_root",
      :dst_path => @outdir

    stats = File.stat(File.join(@outdir, @relative_sentinel_path))
    stats.mode.should == 33261
  end

  it "should preserve symlinks" do
    # Set up identical dir in container to house the copy
    c_sentinel_dir = path_in_container(@tmpdir)
    response = run "mkdir -p #{c_sentinel_dir}"
    response.exit_status.should == 0

    copy_in \
      :src_path => @sentinel_dir,
      :dst_path => @tmpdir

    c_link_path = path_in_container(@sentinel_sym_link_path)
    response = run "stat -c %F #{c_link_path}"
    response.exit_status.should == 0
    response.stdout.chomp.should == "symbolic link"
  end

  it "should materialize hardlinks" do
    # Set up identical dir in container to house the copy
    c_sentinel_dir = path_in_container(@tmpdir)
    response = run "mkdir -p #{c_sentinel_dir}"
    response.exit_status.should == 0

    copy_in \
      :src_path => @sentinel_dir,
      :dst_path => @tmpdir

    # No hardlinks in container
    c_sentinel_dir = path_in_container(@sentinel_dir)
    response = run "find #{c_sentinel_dir} -xdev -samefile sentinel"
    response.exit_status.should == 1

    # File should be materialized
    c_hardlink_path = path_in_container(@sentinel_hard_link_path)
    response = run "cat #{c_hardlink_path}"
    response.exit_status.should == 0
    response.stdout.chomp.should == @sentinel_contents
  end
end
