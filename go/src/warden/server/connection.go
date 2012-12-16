package server

import (
	"fmt"
	"net"
	"warden/protocol"
)

type Conn struct {
	net.Conn
	R *protocol.Reader
	W *protocol.Writer
}

func NewConn(nc net.Conn) *Conn {
	c := &Conn{}

	c.Conn = nc
	c.R = protocol.NewReader(nc)
	c.W = protocol.NewWriter(nc)

	return c
}

func (c *Conn) ReadRequest() (*Request, error) {
	r, err := c.R.ReadRequest()
	if err != nil {
		return nil, err
	}

	return NewRequest(c, r), nil
}

func (c *Conn) WriteResponse(r protocol.Response) error {
	return c.W.WriteResponse(r)
}

func (c *Conn) Flush() error {
	return c.W.Flush()
}

func (c *Conn) WriteErrorResponse(x string) {
	y := &protocol.ErrorResponse{}
	y.Message = &x
	c.WriteResponse(y)
}

func (c *Conn) WriteInvalidState(x string) {
	c.WriteErrorResponse(fmt.Sprintf("Cannot execute request in state: %s", x))
}

type Request struct {
	*Conn
	r    protocol.Request
	done chan bool
}

func NewRequest(x *Conn, y protocol.Request) *Request {
	r := &Request{
		Conn: x,
		r:    y,
		done: make(chan bool),
	}

	return r
}
