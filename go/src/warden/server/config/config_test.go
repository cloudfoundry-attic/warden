package config

import (
	. "launchpad.net/gocheck"
	"launchpad.net/goyaml"
)

type ConfigSuite struct {
	Config
}

var _ = Suite(&ConfigSuite{})

func (s *ConfigSuite) SetUpTest(c *C) {
	s.Config = DefaultConfig()
}

func (s *ConfigSuite) TestServerUnixDomain(c *C) {
	var b = []byte(`
server:
  unix_domain_path: /tmp/whatever.sock
  unix_domain_permissions: 0600
`)

	c.Check(s.Server.UnixDomainPath, Equals, "/tmp/warden.sock")
	c.Check(s.Server.UnixDomainPermissions, Equals, 0755)

	goyaml.Unmarshal(b, &s.Config)

	c.Check(s.Server.UnixDomainPath, Equals, "/tmp/whatever.sock")
	c.Check(s.Server.UnixDomainPermissions, Equals, 0600)
}

func (s *ConfigSuite) TestServerContainerPath(c *C) {
	var b = []byte(`
server:
  container_rootfs_path: /tmp/rootfs
  container_depot_path: /tmp/depot
  container_script_path: /tmp/script
`)

	c.Check(s.Server.ContainerRootfsPath, Equals, "")
	c.Check(s.Server.ContainerDepotPath, Equals, "")
	c.Check(s.Server.ContainerScriptPath, Equals, "")

	goyaml.Unmarshal(b, &s.Config)

	c.Check(s.Server.ContainerRootfsPath, Equals, "/tmp/rootfs")
	c.Check(s.Server.ContainerDepotPath, Equals, "/tmp/depot")
	c.Check(s.Server.ContainerScriptPath, Equals, "/tmp/script")
}

func (s *ConfigSuite) TestServerContainerGraceTime(c *C) {
	var b = []byte(`
server:
  container_grace_time: 10
`)

	c.Check(s.Server.ContainerGraceTime, Equals, uint(300))

	goyaml.Unmarshal(b, &s.Config)

	c.Check(s.Server.ContainerGraceTime, Equals, uint(10))
}

func (s *ConfigSuite) TestServerContainerRlimits(c *C) {
	var b = []byte(`
server:
  container_rlimits:
    as: 37
    core: 37
    cpu: 37
    data: 37
    fsize: 37
    locks: 37
    memlock: 37
    msgqueue: 37
    nice: 37
    nofile: 37
    nproc: 37
    rss: 37
    rtprio: 37
    sigpending: 37
    stack: 37
`)

	c.Check(s.Server.ContainerRlimits.As, Equals, int64(4294967296))
	c.Check(s.Server.ContainerRlimits.Core, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Cpu, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Data, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Fsize, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Locks, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Memlock, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Msgqueue, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Nice, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Nofile, Equals, int64(8192))
	c.Check(s.Server.ContainerRlimits.Nproc, Equals, int64(512))
	c.Check(s.Server.ContainerRlimits.Rss, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Rtprio, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Sigpending, Equals, int64(0))
	c.Check(s.Server.ContainerRlimits.Stack, Equals, int64(0))

	goyaml.Unmarshal(b, &s.Config)

	c.Check(s.Server.ContainerRlimits.As, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Core, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Cpu, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Data, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Fsize, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Locks, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Memlock, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Msgqueue, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Nice, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Nofile, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Nproc, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Rss, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Rtprio, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Sigpending, Equals, int64(37))
	c.Check(s.Server.ContainerRlimits.Stack, Equals, int64(37))
}

func (s *ConfigSuite) TestServerQuota(c *C) {
	var b = []byte(`
server:
  quota:
    disk_quota_enabled: false
`)

	c.Check(s.Server.Quota.DiskQuotaEnabled, Equals, true)

	goyaml.Unmarshal(b, &s.Config)

	c.Check(s.Server.Quota.DiskQuotaEnabled, Equals, false)
}

func (s *ConfigSuite) TestNetworkPool(c *C) {
	var b = []byte(`
network:
  pool_start_address: 10.0.0.0
  pool_size: 1
`)

	c.Check(s.Network.PoolStartAddress, Equals, "10.254.0.0")
	c.Check(s.Network.PoolSize, Equals, 256)

	goyaml.Unmarshal(b, &s.Config)

	c.Check(s.Network.PoolStartAddress, Equals, "10.0.0.0")
	c.Check(s.Network.PoolSize, Equals, 1)
}

func (s *ConfigSuite) TestNetworkDenyAllow(c *C) {
	var b = []byte(`
network:
  deny_networks:
    - 1.1.1.1
    - 2.2.2.2
  allow_networks:
    - 3.3.3.3
    - 4.4.4.4
`)

	c.Check(s.Network.DenyNetworks, DeepEquals, []string{})
	c.Check(s.Network.AllowNetworks, DeepEquals, []string{})

	goyaml.Unmarshal(b, &s.Config)

	c.Check(s.Network.DenyNetworks, DeepEquals, []string{"1.1.1.1", "2.2.2.2"})
	c.Check(s.Network.AllowNetworks, DeepEquals, []string{"3.3.3.3", "4.4.4.4"})
}

func (s *ConfigSuite) TestUserPool(c *C) {
	var b = []byte(`
user:
  pool_start_uid: 37
  pool_size: 1
`)

	c.Check(s.User.PoolStartUid, Equals, 10000)
	c.Check(s.User.PoolSize, Equals, 256)

	goyaml.Unmarshal(b, &s.Config)

	c.Check(s.User.PoolStartUid, Equals, 37)
	c.Check(s.User.PoolSize, Equals, 1)
}
