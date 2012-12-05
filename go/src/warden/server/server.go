package server

import (
	"fmt"
	"log"
	"net"
	"os"
	"sync"
	"warden/server/config"
)

type Server struct {
	sync.Mutex
	Containers map[string]*Container

	c *config.Config
}

func NewServer() *Server {
	s := &Server{}
	s.Containers = make(map[string]*Container)
	return s
}

func (s *Server) NewContainer() *Container {
	return NewContainer(s, s.c)
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

	return l
}

func Start() {
	s := NewServer()

	s.c = config.InitConfigFromFile("../warden/config/linux.yml")

	l := s.Listen()

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
