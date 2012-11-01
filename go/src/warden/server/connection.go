package server

import (
	"log"
	"net"
	"warden/protocol"
)

type Connection struct {
	net.Conn
	*protocol.Reader
	*protocol.Writer

	s *Server
}

func NewConnection(s *Server, nc net.Conn) *Connection {
	c := &Connection{}

	c.Conn = nc
	c.Reader = protocol.NewReader(nc)
	c.Writer = protocol.NewWriter(nc)

	c.s = s

	return c
}

func (c *Connection) WriteErrorResponse(s string) {
	res := &protocol.ErrorResponse{}
	res.Message = &s
	c.WriteResponse(res)
}

func (c *Connection) Run() {
	// Many requests that specify a handle are specific to a container
	type ContainerRequest interface {
		GetHandle() string
	}

	for {
		reqi, err := c.ReadRequest()
		if err != nil {
			log.Printf("Error reading request: %s\n", err)
			break
		}

		log.Printf("Request: %#v\n", reqi)

		switch req := reqi.(type) {
		case *protocol.PingRequest:
			resp := &protocol.PingResponse{}

			c.WriteResponse(resp)

		case *protocol.EchoRequest:
			m := req.GetMessage()

			resp := &protocol.EchoResponse{}
			resp.Message = &m

			c.WriteResponse(resp)

		case *protocol.CreateRequest:
			ct := c.s.NewContainer()

			// Start container loop
			go ct.Run()

			ct.Execute(c, reqi)

		case ContainerRequest:
			ct := c.s.FindContainer(req.GetHandle())
			if ct == nil {
				c.WriteErrorResponse("Unknown handle")
				break
			}

			ct.Execute(c, reqi)

		default:
			m := string("Unknown request")

			resp := &protocol.ErrorResponse{}
			resp.Message = &m

			c.WriteResponse(resp)
		}

		c.Flush()
	}

	c.Close()
}
