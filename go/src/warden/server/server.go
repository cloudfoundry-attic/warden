package server

import (
	"log"
	"net"
	"os"
	"sync"
)

type Server struct {
	sync.Mutex
	Containers map[string]*Container

	RootPath            string
	ContainerRootfsPath string
	ContainerDepotPath  string
}

func NewServer() *Server {
	s := &Server{}
	s.Containers = make(map[string]*Container)
	return s
}

func (s *Server) NewContainer() *Container {
	return NewContainer(s)
}

func (s *Server) RegisterContainer(c *Container) {
	s.Lock()
	defer s.Unlock()

	s.Containers[c.Handle] = c
}

func (s *Server) UnregisterContainer(c *Container) {
	s.Lock()
	defer s.Unlock()

	delete(s.Containers, c.Handle)
}

func (s *Server) FindContainer(h string) *Container {
	s.Lock()
	defer s.Unlock()

	c, ok := s.Containers[h]
	if !ok {
		return nil
	}

	return c
}

func Start() {
	s := NewServer()

	s.RootPath = "/home/pieter/dev/cf/warden/warden/root/linux"
	s.ContainerRootfsPath = "/tmp/warden/rootfs"
	s.ContainerDepotPath = "/home/pieter/dev/cf/warden/warden/root/linux/instances"

	os.Remove("/tmp/warden.sock")

	addr, err := net.ResolveUnixAddr("unix", "/tmp/warden.sock")
	if err != nil {
		panic(err)
	}

	l, err := net.ListenUnix("unix", addr)
	if err != nil {
		log.Panic("Can't listen on /tmp/warden.sock")
	}

	for {
		nc, err := l.Accept()
		if err != nil {
			log.Printf("Error accepting connection: %s\n", err)
			continue
		}

		c := NewConnection(s, nc)
		go c.Run()
	}
}
