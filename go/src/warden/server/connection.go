package server

import (
	"net"
	"warden/protocol"
)

type Connection struct {
	net.Conn
	*protocol.Reader
	*protocol.Writer
}

func NewConnection(nc net.Conn) *Connection {
	c := &Connection{}

	c.Conn = nc
	c.Reader = protocol.NewReader(nc)
	c.Writer = protocol.NewWriter(nc)

	return c
}

func (c *Connection) WriteErrorResponse(x string) {
	y := &protocol.ErrorResponse{}
	y.Message = &x
	c.WriteResponse(y)
}
