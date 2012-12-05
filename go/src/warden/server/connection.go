package server

import (
	"net"
	"warden/protocol"
)

type Conn struct {
	net.Conn
	*protocol.Reader
	*protocol.Writer
}

func NewConn(nc net.Conn) *Conn {
	c := &Conn{}

	c.Conn = nc
	c.Reader = protocol.NewReader(nc)
	c.Writer = protocol.NewWriter(nc)

	return c
}

func (c *Conn) WriteErrorResponse(x string) {
	y := &protocol.ErrorResponse{}
	y.Message = &x
	c.WriteResponse(y)
}
