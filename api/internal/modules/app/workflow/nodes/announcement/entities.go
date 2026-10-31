package announcement

import (
	announcementruntime "github.com/webb-chen/AgentSystem/api/internal/modules/app/workflow/announcement"
	"github.com/webb-chen/AgentSystem/api/internal/modules/app/workflow/nodes/base"
)

type NodeData struct {
	base.NodeData
	Announcement announcementruntime.NodeConfig    `json:"announcement"`
	Timeout      announcementruntime.TimeoutConfig `json:"timeout"`
}

type Node struct {
	base.NodeStruct
	NodeData NodeData
}
