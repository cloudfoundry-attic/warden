package protocol

import proto "code.google.com/p/goprotobuf/proto"

type Request interface {
	proto.Message

	WardenRequest()
	Type() Message_Type
}

type Response interface {
	proto.Message

	WardenResponse()
	Type() Message_Type
}

func (*ErrorResponse) WardenResponse()    {}
func (*ErrorResponse) Type() Message_Type { return Message_Error }

func (*CopyInRequest) WardenRequest()      {}
func (*CopyInResponse) WardenResponse()    {}
func (*CopyInRequest) Type() Message_Type  { return Message_CopyIn }
func (*CopyInResponse) Type() Message_Type { return Message_CopyIn }

func (*CopyOutRequest) WardenRequest()      {}
func (*CopyOutResponse) WardenResponse()    {}
func (*CopyOutRequest) Type() Message_Type  { return Message_CopyOut }
func (*CopyOutResponse) Type() Message_Type { return Message_CopyOut }

func (*CreateRequest) WardenRequest()      {}
func (*CreateResponse) WardenResponse()    {}
func (*CreateRequest) Type() Message_Type  { return Message_Create }
func (*CreateResponse) Type() Message_Type { return Message_Create }

func (*DestroyRequest) WardenRequest()      {}
func (*DestroyResponse) WardenResponse()    {}
func (*DestroyRequest) Type() Message_Type  { return Message_Destroy }
func (*DestroyResponse) Type() Message_Type { return Message_Destroy }

func (*EchoRequest) WardenRequest()      {}
func (*EchoResponse) WardenResponse()    {}
func (*EchoRequest) Type() Message_Type  { return Message_Echo }
func (*EchoResponse) Type() Message_Type { return Message_Echo }

func (*InfoRequest) WardenRequest()      {}
func (*InfoResponse) WardenResponse()    {}
func (*InfoRequest) Type() Message_Type  { return Message_Info }
func (*InfoResponse) Type() Message_Type { return Message_Info }

func (*LimitBandwidthRequest) WardenRequest()      {}
func (*LimitBandwidthResponse) WardenResponse()    {}
func (*LimitBandwidthRequest) Type() Message_Type  { return Message_LimitBandwidth }
func (*LimitBandwidthResponse) Type() Message_Type { return Message_LimitBandwidth }

func (*LimitDiskRequest) WardenRequest()      {}
func (*LimitDiskResponse) WardenResponse()    {}
func (*LimitDiskRequest) Type() Message_Type  { return Message_LimitDisk }
func (*LimitDiskResponse) Type() Message_Type { return Message_LimitDisk }

func (*LimitMemoryRequest) WardenRequest()      {}
func (*LimitMemoryResponse) WardenResponse()    {}
func (*LimitMemoryRequest) Type() Message_Type  { return Message_LimitMemory }
func (*LimitMemoryResponse) Type() Message_Type { return Message_LimitMemory }

func (*LinkRequest) WardenRequest()      {}
func (*LinkResponse) WardenResponse()    {}
func (*LinkRequest) Type() Message_Type  { return Message_Link }
func (*LinkResponse) Type() Message_Type { return Message_Link }

func (*ListRequest) WardenRequest()      {}
func (*ListResponse) WardenResponse()    {}
func (*ListRequest) Type() Message_Type  { return Message_List }
func (*ListResponse) Type() Message_Type { return Message_List }

func (*NetInRequest) WardenRequest()      {}
func (*NetInResponse) WardenResponse()    {}
func (*NetInRequest) Type() Message_Type  { return Message_NetIn }
func (*NetInResponse) Type() Message_Type { return Message_NetIn }

func (*NetOutRequest) WardenRequest()      {}
func (*NetOutResponse) WardenResponse()    {}
func (*NetOutRequest) Type() Message_Type  { return Message_NetOut }
func (*NetOutResponse) Type() Message_Type { return Message_NetOut }

func (*PingRequest) WardenRequest()      {}
func (*PingResponse) WardenResponse()    {}
func (*PingRequest) Type() Message_Type  { return Message_Ping }
func (*PingResponse) Type() Message_Type { return Message_Ping }

func (*RunRequest) WardenRequest()      {}
func (*RunResponse) WardenResponse()    {}
func (*RunRequest) Type() Message_Type  { return Message_Run }
func (*RunResponse) Type() Message_Type { return Message_Run }

func (*SpawnRequest) WardenRequest()      {}
func (*SpawnResponse) WardenResponse()    {}
func (*SpawnRequest) Type() Message_Type  { return Message_Spawn }
func (*SpawnResponse) Type() Message_Type { return Message_Spawn }

func (*StopRequest) WardenRequest()      {}
func (*StopResponse) WardenResponse()    {}
func (*StopRequest) Type() Message_Type  { return Message_Stop }
func (*StopResponse) Type() Message_Type { return Message_Stop }

func (*StreamRequest) WardenRequest()      {}
func (*StreamResponse) WardenResponse()    {}
func (*StreamRequest) Type() Message_Type  { return Message_Stream }
func (*StreamResponse) Type() Message_Type { return Message_Stream }
