package config

import (
	"io/ioutil"
	"launchpad.net/goyaml"

//	"warden/server/pool"
)

type quotaConfig struct {
	DiskQuotaEnabled bool "disk_quota_enabled"
}

type rlimitsConfig struct {
	As         int64 "as"
	Core       int64 "core"
	Cpu        int64 "cpu"
	Data       int64 "data"
	Fsize      int64 "fsize"
	Locks      int64 "locks"
	Memlock    int64 "memlock"
	Msgqueue   int64 "msgqueue"
	Nice       int64 "nice"
	Nofile     int64 "nofile"
	Nproc      int64 "nproc"
	Rss        int64 "rss"
	Rtprio     int64 "rtprio"
	Sigpending int64 "sigpending"
	Stack      int64 "stack"
}

type serverConfig struct {
	UnixDomainPath        string "unix_domain_path"
	UnixDomainPermissions int    "unix_domain_permissions"

	ContainerRootfsPath string "container_rootfs_path"
	ContainerDepotPath  string "container_depot_path"
	ContainerScriptPath string "container_script_path"

	ContainerGraceTime uint "container_grace_time"

	ContainerRlimits rlimitsConfig "container_rlimits"

	Quota quotaConfig "quota"
}

var defaultServerConfig = serverConfig{
	UnixDomainPath:        "/tmp/warden.sock",
	UnixDomainPermissions: 0755,

	ContainerGraceTime: 300, // 5 minutes

	ContainerRlimits: rlimitsConfig{
		As:     4294967296,
		Nofile: 8192,
		Nproc:  512,
	},

	Quota: quotaConfig{DiskQuotaEnabled: true},
}

type networkConfig struct {
	PoolStartAddress string "pool_start_address"
	PoolSize         int    "pool_size"

	DenyNetworks  []string "deny_networks"
	AllowNetworks []string "allow_networks"
}

var defaultNetworkConfig = networkConfig{
	PoolStartAddress: "10.254.0.0",
	PoolSize:         256,
}

type userConfig struct {
	PoolStartUid int "pool_start_uid"
	PoolSize     int "pool_size"
}

var defaultUserConfig = userConfig{
	PoolStartUid: 10000,
	PoolSize:     256,
}

type Config struct {
	Server  serverConfig  "server"
	Network networkConfig "network"
	User    userConfig    "user"
}

func DefaultConfig() Config {
	var c = Config{
		Server:  defaultServerConfig,
		Network: defaultNetworkConfig,
		User:    defaultUserConfig,
	}

	c.sanitize()

	return c
}

func (c *Config) sanitize() {
	if c.Network.DenyNetworks == nil {
		c.Network.DenyNetworks = make([]string, 0)
	}
	if c.Network.AllowNetworks == nil {
		c.Network.AllowNetworks = make([]string, 0)
	}
}

func InitConfigFromFile(path string) *Config {
	var c Config = DefaultConfig()
	var e error

	b, e := ioutil.ReadFile(path)
	if e != nil {
		panic(e.Error())
	}

	e = goyaml.Unmarshal(b, &c)
	if e != nil {
		panic(e.Error())
	}

	return &c
}
