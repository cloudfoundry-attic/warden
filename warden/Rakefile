# coding: UTF-8

require "rspec/core/rake_task"
require "rspec/core/version"
require "yaml"

desc "Run all examples"
RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = %w[--color --format documentation]
end

desc "Run (or re-run) steps to setup warden"
task :setup, :config_path do |t, args|
  Rake::Task["setup:bin"].invoke
  Rake::Task["setup:rootfs"].invoke(args[:config_path])
end

namespace :setup do
  desc "Compile and install binaries"
  task :bin do
    Dir.chdir("src") do
      sh "make clean all"
    end

    sh "cp src/wsh/wshd root/linux/skeleton/bin"
    sh "cp src/wsh/wsh root/linux/skeleton/bin"

    ["linux", "insecure"].each do |ct|
      sh "cp src/iomux/iomux-spawn root/#{ct}/skeleton/bin"
      sh "cp src/iomux/iomux-link root/#{ct}/skeleton/bin"
    end
  end

  desc "Setup root filesystem for Ubuntu containers"
  task :rootfs, :config_path do |t, args|
    rootfs_path = ENV["CONTAINER_ROOTFS_PATH"]

    if args[:config_path]
      config = YAML.load_file(args[:config_path])

      if config["server"] && config["server"]["container_rootfs_path"]
        rootfs_path = config["server"]["container_rootfs_path"]
      end
    end

    unless rootfs_path
      STDERR.puts "Please specify path to config file, or CONTAINER_ROOTFS_PATH"
      Process.exit(1)
    end

    sh "mkdir -p #{File.dirname(rootfs_path)}"
    sh "sudo -E unshare -m root/linux/rootfs/setup.sh #{rootfs_path}"
  end
end

namespace :warden do
  desc "Run Warden server"
  task :start, :config_path do |t, args|
    require "warden/server"

    if args[:config_path]
      config = YAML.load_file(args[:config_path])
    end

    Warden::Server.setup(config || {})
    Warden::Server.run!
  end
end

task :ensure_coding do
  patterns = [
    /Rakefile$/,
    /\.rb$/,
  ]

  files = `git ls-files`.split.select do |file|
    patterns.any? { |e| e.match(file) }
  end

  header = "# coding: UTF-8\n\n"

  files.each do |file|
    content = File.read(file)

    unless content.start_with?(header)
      File.open(file, "w") do |f|
        f.write(header)
        f.write(content)
      end
    end
  end
end
