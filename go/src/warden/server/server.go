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
		x.WriteErrorResponse("Handle exists")
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
		x.WriteErrorResponse("Handle does not exist")
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
			y.WriteErrorResponse("Unknown request")
		}

		y.Flush()
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

func (s *Server) Start() {
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
