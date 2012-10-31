package protocol

import proto "code.google.com/p/goprotobuf/proto"

type Request interface {
	proto.Message

	WardenRequest()
}

type Response interface {
	proto.Message

	WardenResponse()
}

func (*ErrorResponse) WardenResponse() {}

func (*CopyInRequest) WardenRequest()   {}
func (*CopyInResponse) WardenResponse() {}

func (*CopyOutRequest) WardenRequest()   {}
func (*CopyOutResponse) WardenResponse() {}

func (*CreateRequest) WardenRequest()   {}
func (*CreateResponse) WardenResponse() {}

func (*DestroyRequest) WardenRequest()   {}
func (*DestroyResponse) WardenResponse() {}

func (*EchoRequest) WardenRequest()   {}
func (*EchoResponse) WardenResponse() {}

func (*InfoRequest) WardenRequest()   {}
func (*InfoResponse) WardenResponse() {}

func (*LimitBandwidthRequest) WardenRequest()   {}
func (*LimitBandwidthResponse) WardenResponse() {}

func (*LimitDiskRequest) WardenRequest()   {}
func (*LimitDiskResponse) WardenResponse() {}

func (*LimitMemoryRequest) WardenRequest()   {}
func (*LimitMemoryResponse) WardenResponse() {}

func (*LinkRequest) WardenRequest()   {}
func (*LinkResponse) WardenResponse() {}

func (*ListRequest) WardenRequest()   {}
func (*ListResponse) WardenResponse() {}

func (*NetInRequest) WardenRequest()   {}
func (*NetInResponse) WardenResponse() {}

func (*NetOutRequest) WardenRequest()   {}
func (*NetOutResponse) WardenResponse() {}

func (*PingRequest) WardenRequest()   {}
func (*PingResponse) WardenResponse() {}

func (*RunRequest) WardenRequest()   {}
func (*RunResponse) WardenResponse() {}

func (*SpawnRequest) WardenRequest()   {}
func (*SpawnResponse) WardenResponse() {}

func (*StopRequest) WardenRequest()   {}
func (*StopResponse) WardenResponse() {}

func (*StreamRequest) WardenRequest()   {}
func (*StreamResponse) WardenResponse() {}
