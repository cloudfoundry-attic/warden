package server

import (
	"fmt"
	"log"
	"os/exec"
	"path"
	"strconv"
	"time"
	"warden/protocol"
)

type request struct {
	c    *Connection
	r    protocol.Request
	done chan bool
}

func newRequest(c_ *Connection, r_ protocol.Request) *request {
	r := &request{c: c_, r: r_}
	r.done = make(chan bool)
	return r
}

type Job struct {
}

type Container struct {
	r chan *request
	s *Server

	State string

	Id     string
	Handle string
}

// Seed Id with time since epoch in microseconds
var _Id = time.Now().UnixNano() / 1000

// Every container gets its own Id
func NextId() string {
	var s string
	var i uint

	_Id++

	// Explicit loop because we MUST have 11 characters.
	// This is required because we use the handle to name a network
	// interface for the container, this name has a 2 character prefix and
	// suffix, and has a maximum length of 15 characters (IFNAMSIZ).
	for i = 0; i < 11; i++ {
		s += strconv.FormatInt((_Id>>(55-(i+1)*5))&31, 32)
	}

	return s
}

func NewContainer(s *Server) *Container {
	c := &Container{}

	c.r = make(chan *request)
	c.s = s

	c.State = "born"

	c.Id = NextId()
	c.Handle = c.Id

	return c
}

func (c *Container) Execute(c_ *Connection, r_ protocol.Request) {
	r := newRequest(c_, r_)

	// Send request
	c.r <- r

	// Wait
	<-r.done
}

func (c *Container) ContainerPath() string {
	return path.Join(c.s.ContainerDepotPath, c.Handle)
}

func (c *Container) Run() {

	for {
		var r *request
		var ok bool

		select {
		case r, ok = <-c.r:
			if !ok {
				break
			}
		}

		t1 := time.Now()

		switch c.State {
		case "born":
			c.runBorn(r)

		case "active":
			c.runActive(r)

		case "stopped":
			c.runStopped(r)

		case "destroyed":
			c.runDestroyed(r)

		default:
			panic("Unknown state: " + c.State)
		}

		t2 := time.Now()

		log.Printf("took: %.6fs\n", t2.Sub(t1).Seconds())
	}
}

func (c *Container) invalidState(r *request) {
	m := fmt.Sprintf("Cannot execute request in state %s", c.State)
	r.c.WriteErrorResponse(m)
}

func (c *Container) runBorn(r *request) {
	switch req := r.r.(type) {
	case *protocol.CreateRequest:
		c.DoCreate(r.c, req)
		close(r.done)

	default:
		c.invalidState(r)
		close(r.done)
	}
}

func (c *Container) runActive(r *request) {
	switch req := r.r.(type) {
	case *protocol.StopRequest:
		c.DoStop(r.c, req)
		close(r.done)

	case *protocol.DestroyRequest:
		c.DoDestroy(r.c, req)
		close(r.done)

	default:
		c.invalidState(r)
		close(r.done)
	}
}

func (c *Container) runStopped(r *request) {
	switch req := r.r.(type) {
	case *protocol.DestroyRequest:
		c.DoDestroy(r.c, req)
		close(r.done)

	default:
		c.invalidState(r)
		close(r.done)
	}
}

func (c *Container) runDestroyed(r *request) {
	switch r.r.(type) {
	default:
		c.invalidState(r)
		close(r.done)
	}
}

func runCommand(cmd *exec.Cmd) error {
	log.Printf("Run: %#v\n", cmd.Args)
	out, err = cmd.CombinedOutput()
	if err != nil {
		log.Printf("Error running %s: %s\n", cmd.Args[0], err)
		log.Printf("Output: %s\n", out)
	}

	return err
}

func (c *Container) DoCreate(conn *Connection, req *protocol.CreateRequest) {
	var cmd *exec.Cmd
	var out []byte
	var err error

	// Override handle if specified
	if h := req.GetHandle(); h != "" {
		c.Handle = h
	}

	res := &protocol.CreateResponse{}
	res.Handle = &c.Handle

	// Create
	cmd = exec.Command(path.Join(c.s.RootPath, "create.sh"), c.ContainerPath())
	cmd.Env = append(cmd.Env, fmt.Sprintf("id=%s", c.Id))
	cmd.Env = append(cmd.Env, fmt.Sprintf("network_host_ip=%s", "10.0.0.1"))
	cmd.Env = append(cmd.Env, fmt.Sprintf("network_container_ip=%s", "10.0.0.2"))
	cmd.Env = append(cmd.Env, fmt.Sprintf("user_uid=%d", 10000))
	cmd.Env = append(cmd.Env, fmt.Sprintf("rootfs_path=%s", c.s.ContainerRootfsPath))

	err = runCommand(cmd)
	if err != nil {
		conn.WriteErrorResponse("error")
		return
	}

	// Start
	cmd = exec.Command(path.Join(c.ContainerPath(), "start.sh"))
	err = runCommand(cmd)
	if err != nil {
		conn.WriteErrorResponse("error")
		return
	}

	c.State = "active"
	c.s.RegisterContainer(c)

	conn.WriteResponse(res)
}

func (c *Container) DoStop(conn *Connection, req *protocol.StopRequest) {
	var cmd *exec.Cmd
	var out []byte
	var err error

	done := make(chan error, 1)

	cmd = exec.Command(path.Join(c.ContainerPath(), "stop.sh"))

	// Don't wait for graceful stop if kill=true
	if req.GetKill() {
		cmd.Args = append(cmd.Args, "-w", "0")
	}

	// Run command in background
	go func() {
		done <- runCommand(cmd)
	}()

	// Wait for completion if background=false
	if !req.GetBackground() {
		<-done
	}

	c.State = "stopped"

	res := &protocol.StopResponse{}
	conn.WriteResponse(res)
}

func (c *Container) DoDestroy(conn *Connection, req *protocol.DestroyRequest) {
	var cmd *exec.Cmd
	var out []byte
	var err error

	cmd = exec.Command(path.Join(c.ContainerPath(), "destroy.sh"))
	if err != nil {
		conn.WriteErrorResponse("error")
		return
	}

	c.State = "destroyed"
	c.s.UnregisterContainer(c)

	res := &protocol.DestroyResponse{}
	conn.WriteResponse(res)
}
