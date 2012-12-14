package server

import (
	"fmt"
	"log"
	"os/exec"
	"path"
	"time"
	"warden/protocol"
	"warden/server/config"
)

type Container interface {
	Handle() string
	Run()
	Execute(*Conn, protocol.Request)
}

type request struct {
	c    *Conn
	r    protocol.Request
	done chan bool
}

func newRequest(c_ *Conn, r_ protocol.Request) *request {
	r := &request{c: c_, r: r_}
	r.done = make(chan bool)
	return r
}

type Job struct {
}

type LinuxContainer struct {
	Config *config.Config

	r chan *request
	s *Server

	State string

	id     string
	handle string
}

func (c *LinuxContainer) Id() string {
	return c.id
}

func (c *LinuxContainer) Handle() string {
	return c.handle
}

func NewContainer(s *Server, cfg *config.Config) *LinuxContainer {
	c := &LinuxContainer{}

	c.Config = cfg

	c.r = make(chan *request)
	c.s = s

	c.State = "born"

	c.id = NextId()
	c.handle = c.id

	return c
}

func (c *LinuxContainer) Execute(c_ *Conn, r_ protocol.Request) {
	r := newRequest(c_, r_)

	// Send request
	c.r <- r

	// Wait
	<-r.done
}

func (c *LinuxContainer) ContainerPath() string {
	return path.Join(c.Config.Server.ContainerDepotPath, c.handle)
}

func (c *LinuxContainer) Run() {
	for r := range c.r {
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

func (c *LinuxContainer) invalidState(r *request) {
	m := fmt.Sprintf("Cannot execute request in state %s", c.State)
	r.c.WriteErrorResponse(m)
}

func (c *LinuxContainer) runBorn(r *request) {
	switch req := r.r.(type) {
	case *protocol.CreateRequest:
		c.DoCreate(r.c, req)
		close(r.done)

	default:
		c.invalidState(r)
		close(r.done)
	}
}

func (c *LinuxContainer) runActive(r *request) {
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

func (c *LinuxContainer) runStopped(r *request) {
	switch req := r.r.(type) {
	case *protocol.DestroyRequest:
		c.DoDestroy(r.c, req)
		close(r.done)

	default:
		c.invalidState(r)
		close(r.done)
	}
}

func (c *LinuxContainer) runDestroyed(r *request) {
	switch r.r.(type) {
	default:
		c.invalidState(r)
		close(r.done)
	}
}

func runCommand(cmd *exec.Cmd) error {
	log.Printf("Run: %#v\n", cmd.Args)
	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("Error running %s: %s\n", cmd.Args[0], err)
		log.Printf("Output: %s\n", out)
	}

	return err
}

func (c *LinuxContainer) DoCreate(x *Conn, req *protocol.CreateRequest) {
	var cmd *exec.Cmd
	var err error

	// Override handle if specified
	if h := req.GetHandle(); h != "" {
		c.handle = h
	}

	res := &protocol.CreateResponse{}
	res.Handle = &c.handle

	// Create
	cmd = exec.Command(path.Join(c.Config.Server.ContainerScriptPath, "create.sh"), c.ContainerPath())
	cmd.Env = append(cmd.Env, fmt.Sprintf("id=%s", c.id))
	cmd.Env = append(cmd.Env, fmt.Sprintf("network_host_ip=%s", "10.0.0.1"))
	cmd.Env = append(cmd.Env, fmt.Sprintf("network_container_ip=%s", "10.0.0.2"))
	cmd.Env = append(cmd.Env, fmt.Sprintf("user_uid=%d", 10000))
	cmd.Env = append(cmd.Env, fmt.Sprintf("rootfs_path=%s", c.Config.Server.ContainerRootfsPath))

	err = runCommand(cmd)
	if err != nil {
		x.WriteErrorResponse("error")
		return
	}

	// Start
	cmd = exec.Command(path.Join(c.ContainerPath(), "start.sh"))
	err = runCommand(cmd)
	if err != nil {
		x.WriteErrorResponse("error")
		return
	}

	c.State = "active"
	c.s.RegisterContainer(c)

	x.WriteResponse(res)
}

func (c *LinuxContainer) DoStop(x *Conn, req *protocol.StopRequest) {
	var cmd *exec.Cmd

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
	x.WriteResponse(res)
}

func (c *LinuxContainer) DoDestroy(x *Conn, req *protocol.DestroyRequest) {
	var cmd *exec.Cmd
	var err error

	cmd = exec.Command(path.Join(c.ContainerPath(), "destroy.sh"))

	err = runCommand(cmd)
	if err != nil {
		x.WriteErrorResponse("error")
		return
	}

	c.State = "destroyed"
	c.s.UnregisterContainer(c)

	res := &protocol.DestroyResponse{}
	x.WriteResponse(res)
}
