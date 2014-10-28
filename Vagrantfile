Vagrant.configure("2") do |config|

  config.vm.box = "warden-compatible"
  config.vm.box_url = "https://s3.amazonaws.com/cf-runtime-artifacts/warden-compatible.box"

  # Requires vagrant-aws and unf plugins
  config.vm.provider :aws do |aws, override|
    override.vm.box = "dummy"
    override.vm.box_url = "https://github.com/mitchellh/vagrant-aws/raw/master/dummy.box"

    override.ssh.private_key_path = ENV["WARDEN_AWS_PRIVATE_KEY_PATH"]

    aws.ami = ENV["WARDEN_COMPATIBLE_AMI"] || "ami-e0b64188"
    aws.access_key_id = ENV["AWS_ACCESS_KEY_ID"]
    aws.secret_access_key = ENV["AWS_SECRET_ACCESS_KEY"]
    aws.instance_type = "m3.medium"
    aws.tags = { "Name" => "warden-test" }
    aws.block_device_mapping = [{
      :DeviceName => "/dev/sda1", 'Ebs.VolumeSize' => 40
    }]
  end
end
