package server

import (
	"net"
	"sync"
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

type Request struct {
	sync.Mutex

	c        *Conn
	r        protocol.Request
	done     chan bool
	hijacked bool
}

func NewRequest(x *Conn, y protocol.Request) *Request {
	r := &Request{
		c:        x,
		r:        y,
		hijacked: false,
		done:     make(chan bool),
	}

	return r
}

// Hijack marks the request as being hijacked, which means that it is not
// automatically marked as done. After hijacking, the caller is responsible for
// marking the request as done.
func (x *Request) Hijack() {
	x.Lock()
	defer x.Unlock()

	if x.hijacked {
		panic("request was already hijacked")
	}

	x.hijacked = true
}

// Wait waits for the request to be done.
func (x *Request) Wait() {
	<-x.done
}

// Done marks the request as done.
func (x *Request) Done() {
	close(x.done)
}

func (x *Request) WriteResponse(r protocol.Response) error {
	x.Lock()
	defer x.Unlock()

	err := x.c.WriteResponse(r)
	if err != nil {
		return err
	}

	if !x.hijacked {
		x.Done()
	}

	return x.c.Flush()
}

func (x *Request) WriteErrorResponse(y string) error {
	z := &protocol.ErrorResponse{}
	z.Message = &y
	return x.WriteResponse(z)
}
