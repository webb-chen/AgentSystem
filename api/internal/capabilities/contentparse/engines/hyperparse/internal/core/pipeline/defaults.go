package pipeline

import (
	"github.com/webb-chen/AgentSystem/api/internal/capabilities/contentparse/engines/hyperparse/internal/adapters/docx"
	"github.com/webb-chen/AgentSystem/api/internal/capabilities/contentparse/engines/hyperparse/internal/adapters/image"
	"github.com/webb-chen/AgentSystem/api/internal/capabilities/contentparse/engines/hyperparse/internal/adapters/markdown"
	"github.com/webb-chen/AgentSystem/api/internal/capabilities/contentparse/engines/hyperparse/internal/adapters/pdf"
	"github.com/webb-chen/AgentSystem/api/internal/capabilities/contentparse/engines/hyperparse/internal/adapters/text"
)

// NewDefaultRouter registers built-in adapters and extension mappings.
func NewDefaultRouter() *Router {
	r := NewRouter()
	r.RegisterAdapter(pdf.Adapter{}, ".pdf")
	r.RegisterAdapter(docx.Adapter{}, ".docx")
	r.RegisterAdapter(markdown.Adapter{}, ".md", ".markdown")
	r.RegisterAdapter(text.Adapter{}, ".txt", ".csv", ".tsv")
	r.RegisterAdapter(image.Adapter{}, ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".webp")
	return r
}
