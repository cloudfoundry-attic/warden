package server

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"os"
	"os/exec"
	"path"
	"strings"
	"sync"
	"warden/protocol"
	"warden/server/config"
)

type Server struct {
	sync.Mutex
	R *Registry

	c *config.Config
}

func NewServer(c *config.Config) *Server {
	s := &Server{c: c}
	s.R = NewRegistry()
	return s
}

func (s *Server) NewContainer() Container {
	return NewContainer(s, s.c)
}

func (s *Server) servePing(x *Request, y *protocol.PingRequest) {
	z := &protocol.PingResponse{}
	x.WriteResponse(z)
}

func (s *Server) serveEcho(x *Request, y *protocol.EchoRequest) {
	m := y.GetMessage()

	z := &protocol.EchoResponse{}
	z.Message = &m

	x.WriteResponse(z)
}

func (s *Server) serveCreate(x *Request, y *protocol.CreateRequest) {
	var c Container

	c = s.R.Find(y.GetHandle())
	if c != nil {
		x.WriteErrorResponse(fmt.Sprintf("container with handle: %s already exists.", y.GetHandle()))
		return
	}

	c = s.NewContainer()

	// Start container loop
	go c.Run()

	c.Execute(x)
}

type containerRequest interface {
	protocol.Request
	GetHandle() string
}

func (s *Server) serveContainerRequest(x *Request, y containerRequest) {
	var c Container

	c = s.R.Find(y.GetHandle())
	if c == nil {
		x.WriteErrorResponse(fmt.Sprintf("unknown handle"))
		return
	}

	c.Execute(x)
}

func (s *Server) serve(x net.Conn) {
	y := NewConn(x)

	for {
		u, e := y.ReadRequest()
		if e != nil {
			log.Printf("Error reading request: %s\n", e)
			break
		}

		log.Printf("Request: %#v\n", u)

		switch v := u.r.(type) {
		case *protocol.PingRequest:
			s.servePing(u, v)
		case *protocol.EchoRequest:
			s.serveEcho(u, v)
		case *protocol.CreateRequest:
			s.serveCreate(u, v)
		case containerRequest:
			s.serveContainerRequest(u, v)
		default:
			u.WriteErrorResponse("Unknown request")
		}

		// Wait for request to be done before continuing with the next one
		u.Wait()
	}

	y.Close()
}

func (s *Server) Listen() net.Listener {
	var err error

	p := s.c.Server.UnixDomainPath

	// Unlink before bind
	os.Remove(p)

	x, err := net.ResolveUnixAddr("unix", p)
	if err != nil {
		panic(err)
	}

	l, err := net.ListenUnix("unix", x)
	if err != nil {
		panic(fmt.Sprintf("Can't listen on %s", p))
	}

	// Fix permissions
	err = os.Chmod(p, os.FileMode(s.c.Server.UnixDomainPermissions))
	if err != nil {
		panic(err)
	}

	return l
}

func (s *Server) Setup() {
	cmd := exec.Command(path.Join(s.c.Server.ContainerScriptPath, "setup.sh"))

	// Initialize environment
	cmd.Env = os.Environ()

	// Networks
	cmd.Env = append(cmd.Env, fmt.Sprintf("ALLOW_NETWORKS=%s", strings.Join(s.c.Network.AllowNetworks, " ")))
	cmd.Env = append(cmd.Env, fmt.Sprintf("DENY_NETWORKS=%s", strings.Join(s.c.Network.DenyNetworks, " ")))

	// Paths
	cmd.Env = append(cmd.Env, fmt.Sprintf("CONTAINER_ROOTFS_PATH=%s", s.c.Server.ContainerRootfsPath))
	cmd.Env = append(cmd.Env, fmt.Sprintf("CONTAINER_DEPOT_PATH=%s", s.c.Server.ContainerDepotPath))
	cmd.Env = append(cmd.Env, fmt.Sprintf("CONTAINER_DEPOT_MOUNT_POINT_PATH=%s", FindMountPoint(s.c.Server.ContainerDepotPath)))
	cmd.Env = append(cmd.Env, fmt.Sprintf("DISK_QUOTA_ENABLED=%t", s.c.Server.Quota.DiskQuotaEnabled))

	err := runCommand(cmd)
	if err != nil {
		panic(err)
	}
}

func (s *Server) destroy(x string) {
	var err error

	y := path.Join(x, "destroy.sh")

	_, err = os.Stat(y)
	if err != nil {
		if os.IsNotExist(err) {
			return
		}

		panic(err)
	}

	log.Printf("Destroying container at: %s", x)

	// Run destroy.sh
	err = runCommand(exec.Command(y))
	if err != nil {
		panic(err)
	}

	// Remove directory
	err = os.RemoveAll(x)
	if err != nil {
		panic(err)
	}
}

func (s *Server) restore(x string) {
	var err error

	log.Printf("Restoring container at: %s", x)

	y := path.Join(x, "etc", "snapshot.json")

	// Read snapshot
	f, err := os.Open(y)
	if err != nil {
		panic(err)
	}

	c := s.NewContainer().(*LinuxContainer)

	// Unmarshal snapshot into container
	d := json.NewDecoder(f)
	err = d.Decode(c)
	if err != nil {
		panic(err)
	}

	// Acquire resources
	err = c.Acquire()
	if err != nil {
		panic(err)
	}

	// Register container
	s.R.Register(c)

	// Start container loop
	go c.Run()
}

func (s *Server) Restore() {
	fs, err := ioutil.ReadDir(s.c.Server.ContainerDepotPath)
	if err != nil {
		if os.IsNotExist(err) {
			// Don't care if it doesn't exist
			return
		}

		panic(err)
	}

	for _, f := range fs {
		// Only care about directories
		if !f.IsDir() {
			continue
		}

		x := path.Join(s.c.Server.ContainerDepotPath, f.Name())

		// Figure out if the container has a snapshot or not
		y := path.Join(x, "etc", "snapshot.json")
		_, err := os.Stat(y)
		if err != nil && !os.IsNotExist(err) {
			panic(err)
		}

		if os.IsNotExist(err) {
			s.destroy(x)
		} else {
			s.restore(x)
		}
	}
}

func (s *Server) Start() {
	s.Setup()
	s.Restore()

	l := s.Listen()

	for {
		nc, err := l.Accept()
		if err != nil {
			log.Printf("Error accepting connection: %s", err)
			continue
		}

		go s.serve(nc)
	}
}
