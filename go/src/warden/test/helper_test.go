package test

import (
	"bytes"
	"fmt"
	"io/ioutil"
	. "launchpad.net/gocheck"
	"launchpad.net/goyaml"
	"net"
	"os"
	"os/exec"
	"path"
	"strings"
	"testing"
	"time"
	"warden/protocol"
	"warden/server/config"
)

func run(i string) {
	c := exec.Command("bash")
	c.Stdin = strings.NewReader(i)
	b, err := c.CombinedOutput()
	if err != nil {
		fmt.Printf(string(b))
		fmt.Printf("Error running: %#v (%s)\n", i, err)
		panic("help")
	}
}

type server struct {
	WorkPath            string
	ConfigPath          string
	UnixDomainPath      string
	ContainerRootfsPath string
	ContainerDepotPath  string
	ContainerDepotFile  string

	WardenBinPath             string
	WardenContainerScriptPath string

	c config.Config

	x *exec.Cmd
	o bytes.Buffer
	w chan error
}

func (s *server) Initialize() {
	wardenBinPath := os.Getenv("WARDEN_BIN_PATH")
	if wardenBinPath == "" {
		panic("WARDEN_BIN_PATH not set")
	}

	wardenContainerScriptPath := os.Getenv("WARDEN_CONTAINER_SCRIPT_PATH")
	if wardenContainerScriptPath == "" {
		panic("WARDEN_CONTAINER_SCRIPT_PATH not set")
	}

	s.WorkPath = path.Join(os.TempDir(), "warden", "test")
	s.ConfigPath = path.Join(s.WorkPath, "warden.yml")
	s.UnixDomainPath = path.Join(s.WorkPath, "warden.sock")
	s.ContainerRootfsPath = path.Join(s.WorkPath, "..", "rootfs")
	s.ContainerDepotPath = path.Join(s.WorkPath, "containers")
	s.ContainerDepotFile = s.ContainerDepotPath + ".img"
	s.WardenBinPath = wardenBinPath
	s.WardenContainerScriptPath = wardenContainerScriptPath

	s.c = config.DefaultConfig()
	s.c.Server.UnixDomainPath = s.UnixDomainPath
	s.c.Server.ContainerRootfsPath = s.ContainerRootfsPath
	s.c.Server.ContainerDepotPath = s.ContainerDepotPath
	s.c.Server.ContainerScriptPath = wardenContainerScriptPath

	s.x = exec.Command(s.WardenBinPath, fmt.Sprintf("-config=%s", s.ConfigPath))
	s.x.Stdout = &s.o
	s.x.Stderr = &s.o
	s.w = make(chan error, 1)
}

func (s *server) Start() {
	var err error

	err = os.MkdirAll(s.WorkPath, 0700)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll(s.ContainerDepotPath, 0700)
	if err != nil {
		panic(err)
	}

	b, err := goyaml.Marshal(s.c)
	if err != nil {
		panic(err)
	}

	err = ioutil.WriteFile(s.ConfigPath, b, 0700)
	if err != nil {
		panic(err)
	}

	run(fmt.Sprintf("dd if=/dev/null of=%s bs=1M seek=100", s.ContainerDepotFile))
	run(fmt.Sprintf("mkfs.ext4 -b 4096 -q -F -O ^has_journal,uninit_bg %s", s.ContainerDepotFile))
	run(fmt.Sprintf("mount -o loop %s %s", s.ContainerDepotFile, s.ContainerDepotPath))

	err = s.x.Start()
	if err != nil {
		panic(err)
	}

	// Wait for the process to exit
	go func() {
		s.w <- s.x.Wait()
	}()

	// Wait for the process to start listening on the unix socket
	for stop := false; !stop; {
		select {
		case err := <-s.w:
			fmt.Printf(s.o.String())
			panic(err)
		default:
		}

		_, err := net.Dial("unix", s.UnixDomainPath)
		if err == nil {
			stop = true
			break
		}

		time.Sleep(10 * time.Millisecond)
	}

	// Good to go!
}

func (s *server) Stop() {
	var err error

	err = s.x.Process.Kill()
	if err != nil {
		panic(err)
	}

	// Wait for process to exit
	<-s.w

	// Destroy all artifacts
	run(fmt.Sprintf("%s/clear.sh %s", s.WardenContainerScriptPath, s.ContainerDepotPath))
	run(fmt.Sprintf("umount %s", s.ContainerDepotPath))
}

type client struct {
	net.Conn
	R *protocol.Reader
	W *protocol.Writer
}

func NewClient(p string) (*client, error) {
	x, err := net.Dial("unix", p)
	if err != nil {
		return nil, err
	}

	c := &client{
		Conn: x,
		R:    protocol.NewReader(x),
		W:    protocol.NewWriter(x),
	}

	return c, nil
}

func (c *client) WriteRequest(r protocol.Request) error {
	var err error

	err = c.W.WriteRequest(r)
	if err != nil {
		return err
	}

	err = c.W.Flush()
	if err != nil {
		return err
	}

	return nil
}

func (c *client) ReadResponse() (protocol.Response, error) {
	return c.R.ReadResponse()
}

type ServerError struct {
	Message string
	Data    string
}

func (s ServerError) Error() string {
	return s.Message
}

func (c *client) Call(p protocol.Request) (protocol.Response, error) {
	var err error

	err = c.WriteRequest(p)
	if err != nil {
		return nil, err
	}

	q, err := c.ReadResponse()
	if err != nil {
		return nil, err
	}

	r, ok := q.(*protocol.ErrorResponse)
	if ok {
		return nil, ServerError{r.GetMessage(), r.GetData()}
	}

	return q, nil
}

func (c *client) Create(p *protocol.CreateRequest) (*protocol.CreateResponse, error) {
	q, err := c.Call(p)
	if err != nil {
		return nil, err
	}

	return q.(*protocol.CreateResponse), nil
}

func (c *client) Destroy(p *protocol.DestroyRequest) (*protocol.DestroyResponse, error) {
	q, err := c.Call(p)
	if err != nil {
		return nil, err
	}

	return q.(*protocol.DestroyResponse), nil
}

func Test(t *testing.T) {
	TestingT(t)
}
