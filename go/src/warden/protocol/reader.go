package protocol

import (
	"bufio"
	"code.google.com/p/goprotobuf/proto"
	"io"
	"strconv"
)

var messageToRequest = map[Message_Type]func() Request{
	Message_Create:         func() Request { return &CreateRequest{} },
	Message_Stop:           func() Request { return &StopRequest{} },
	Message_Destroy:        func() Request { return &DestroyRequest{} },
	Message_Info:           func() Request { return &InfoRequest{} },
	Message_Spawn:          func() Request { return &SpawnRequest{} },
	Message_Link:           func() Request { return &LinkRequest{} },
	Message_Run:            func() Request { return &RunRequest{} },
	Message_Stream:         func() Request { return &StreamRequest{} },
	Message_NetIn:          func() Request { return &NetInRequest{} },
	Message_NetOut:         func() Request { return &NetOutRequest{} },
	Message_CopyIn:         func() Request { return &CopyInRequest{} },
	Message_CopyOut:        func() Request { return &CopyOutRequest{} },
	Message_LimitMemory:    func() Request { return &LimitMemoryRequest{} },
	Message_LimitDisk:      func() Request { return &LimitDiskRequest{} },
	Message_LimitBandwidth: func() Request { return &LimitBandwidthRequest{} },
	Message_Ping:           func() Request { return &PingRequest{} },
	Message_List:           func() Request { return &ListRequest{} },
	Message_Echo:           func() Request { return &EchoRequest{} },
}

var messageToResponse = map[Message_Type]func() Response{
	Message_Create:         func() Response { return &CreateResponse{} },
	Message_Stop:           func() Response { return &StopResponse{} },
	Message_Destroy:        func() Response { return &DestroyResponse{} },
	Message_Info:           func() Response { return &InfoResponse{} },
	Message_Spawn:          func() Response { return &SpawnResponse{} },
	Message_Link:           func() Response { return &LinkResponse{} },
	Message_Run:            func() Response { return &RunResponse{} },
	Message_Stream:         func() Response { return &StreamResponse{} },
	Message_NetIn:          func() Response { return &NetInResponse{} },
	Message_NetOut:         func() Response { return &NetOutResponse{} },
	Message_CopyIn:         func() Response { return &CopyInResponse{} },
	Message_CopyOut:        func() Response { return &CopyOutResponse{} },
	Message_LimitMemory:    func() Response { return &LimitMemoryResponse{} },
	Message_LimitDisk:      func() Response { return &LimitDiskResponse{} },
	Message_LimitBandwidth: func() Response { return &LimitBandwidthResponse{} },
	Message_Ping:           func() Response { return &PingResponse{} },
	Message_List:           func() Response { return &ListResponse{} },
	Message_Echo:           func() Response { return &EchoResponse{} },
}

type Reader struct {
	*bufio.Reader
}

func NewReader(r_ io.Reader) *Reader {
	r := &Reader{}
	r.Reader = bufio.NewReader(r_)
	return r
}

func (r *Reader) ReadMessage() (*Message, error) {
	l, more, err := r.ReadLine()
	if err != nil {
		return nil, err
	}

	if more {
		panic("Didn't expect more")
	}

	i, err := strconv.Atoi(string(l))
	if err != nil {
		return nil, err
	}

	data := make([]byte, i)
	_, err = r.Read(data)
	if err != nil {
		return nil, err
	}

	crlf := make([]byte, 2)
	_, err = r.Read(crlf)
	if err != nil {
		return nil, err
	}

	m := &Message{}
	err = proto.Unmarshal(data, m)
	if err != nil {
		return nil, err
	}

	return m, nil
}

func (r *Reader) ReadRequest() (Request, error) {
	m, err := r.ReadMessage()
	if err != nil {
		return nil, err
	}

	fn, ok := messageToRequest[m.GetType()]
	if !ok {
		panic("Unknown message type")
	}

	req := fn()

	err = proto.Unmarshal(m.GetPayload(), req)
	if err != nil {
		return nil, err
	}

	return req, nil
}

func (r *Reader) ReadResponse() (Response, error) {
	m, err := r.ReadMessage()
	if err != nil {
		return nil, err
	}

	fn, ok := messageToResponse[m.GetType()]
	if !ok {
		panic("Unknown message type")
	}

	res := fn()

	err = proto.Unmarshal(m.GetPayload(), res)
	if err != nil {
		return nil, err
	}

	return res, nil
}
