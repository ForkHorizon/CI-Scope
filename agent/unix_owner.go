package agent

import (
	"errors"
	"os"
)

func socketOwnerUID(info os.FileInfo) (uint32, error) {
	if info == nil {
		return 0, errors.New("socket information is missing")
	}
	return socketOwnerUIDFromInfo(info)
}
