package server

import (
	"fmt"
	"log"
	"net"
	"os"
	"sync"
	"warden/protocol"
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
			log.Printf("Error accepting xection: %s\n", err)
			continue
		}

		go s.serve(nc)
	}
}

func (s *Server) servePing(x *Conn, y *protocol.PingRequest) {
	z := &protocol.PingResponse{}
	x.WriteResponse(z)
}

func (s *Server) serveEcho(x *Conn, y *protocol.EchoRequest) {
	m := y.GetMessage()

	z := &protocol.EchoResponse{}
	z.Message = &m

	x.WriteResponse(z)
}

func (s *Server) serveCreate(x *Conn, y *protocol.CreateRequest) {
	var c *Container

	c = s.FindContainer(y.GetHandle())
	if c != nil {
		x.WriteErrorResponse("Handle exists")
		return
	}

	c = s.NewContainer()

	// Start container loop
	go c.Run()

	c.Execute(x, y)
}

type containerRequest interface {
	protocol.Request
	GetHandle() string
}

func (s *Server) serveContainerRequest(x *Conn, y containerRequest) {
	var c *Container

	c = s.FindContainer(y.GetHandle())
	if c == nil {
		x.WriteErrorResponse("Handle does not exist")
		return
	}

	c.Execute(x, y)
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

		switch v := u.(type) {
		case *protocol.PingRequest:
			s.servePing(y, v)
		case *protocol.EchoRequest:
			s.serveEcho(y, v)
		case *protocol.CreateRequest:
			s.serveCreate(y, v)
		case containerRequest:
			s.serveContainerRequest(y, v)
		default:
			y.WriteErrorResponse("Unknown request")
		}

		y.Flush()
	}

	y.Close()
}
