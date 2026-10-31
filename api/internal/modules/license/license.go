package license

import (
	"crypto"
	"crypto/hmac"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ============================================================================
// 统一状态码词表（《统一授权文件格式规范》§7），必须原样返回给前端。
// ============================================================================

const (
	CodeOK              = "ok"
	CodeGrace           = "license_grace"
	CodeDisabled        = "license_disabled"
	CodeNotInit         = "license_not_init"
	CodeMissing         = "license_missing"
	CodeMalformed       = "license_malformed"
	CodeBadSignature    = "license_bad_signature"
	CodeExpired         = "license_expired"
	CodeClockRollback   = "license_clock_rollback"
	CodeMachineMismatch = "license_machine_mismatch"
	CodeProductMismatch = "license_product_mismatch"
	CodeNoPublicKey     = "license_no_public_key"
)

// Product 是本项目在统一授权平台中的 product 标识。
// 必须与 ULP「项目管理」中的 product 完全一致。
const Product = "agent-system"

// SchemaVersion 是本实现支持的授权文件版本。
const SchemaVersion = 1

const (
	PlatformID           = "unified-license-platform"
	UniversalMachineCode = "*"
	clockTolerance       = 10 * time.Minute
	clockFileName        = "license-clock.dat"
	clockSecret          = "agent-system-license-clock-v1"
	// statusTTL 是授权状态缓存时长。验签在请求路径上高频调用，
	// 缓存几秒可以避免每个请求都读盘 + RSA 验签，又能快速感知文件替换。
	statusTTL = 5 * time.Second
)

// Envelope 是 .lic 文件的外层结构。
type Envelope struct {
	Data string `json:"data"`
	Sign string `json:"sign"`
}

// Payload 是 v1 授权载荷（与规范 §3.1 字段一一对应）。
type Payload struct {
	SchemaVersion   int                    `json:"schema_version"`
	LicenseID       string                 `json:"license_id"`
	Platform        string                 `json:"platform"`
	Product         string                 `json:"product"`
	ProductDisplay  string                 `json:"product_display,omitempty"`
	Customer        string                 `json:"customer,omitempty"`
	CustomerContact string                 `json:"customer_contact,omitempty"`
	IssuedAt        *time.Time             `json:"issued_at,omitempty"`
	ExpireTime      *time.Time             `json:"expire_time"`
	GraceDays       int                    `json:"grace_days"`
	MachineCode     string                 `json:"machine_code"`
	InstanceID      string                 `json:"instance_id,omitempty"`
	Features        map[string]interface{} `json:"features,omitempty"`
	IssuedBy        string                 `json:"issued_by,omitempty"`
	Note            string                 `json:"note,omitempty"`

	// Legacy 标记旧版格式（缺少 schema_version），仅过渡期兼容。
	Legacy bool `json:"-"`
}

// Permanent 表示永久授权（expire_time == null）。
func (p *Payload) Permanent() bool { return p != nil && p.ExpireTime == nil }

// Status 是一次授权检查的结论。
type Status struct {
	Code          string    `json:"code"`
	Valid         bool      `json:"valid"`
	Message       string    `json:"message"`
	InGrace       bool      `json:"in_grace"`
	RemainingDays int       `json:"remaining_days"`
	CheckedAt     time.Time `json:"checked_at"`
	License       *Payload  `json:"license,omitempty"`
}

// LicenseError 携带统一状态码的错误。
type LicenseError struct {
	Code string
	Msg  string
}

func (e *LicenseError) Error() string { return e.Msg }

// Config 是创建 Manager 所需的配置项。
type Config struct {
	Enabled       bool   // 是否启用授权校验
	LicPath       string // license.lic 文件路径
	PublicKeyPEM  string // 内置 RSA 公钥（PEM）
	LastCheckFile string // 防时间回拨检查点文件路径（可留空自动推导）
}

// Manager 封装授权校验，持有内置公钥与配置。
type Manager struct {
	mu        sync.Mutex
	enabled   bool
	initErr   error
	pub       *rsa.PublicKey
	licPath   string
	clockPath string

	cached   *Status
	cachedAt time.Time
}

// NewManager 创建一个授权管理器。
//
// 公钥解析失败不会返回 error，而是把错误记录在 Manager.initErr 中：
// 服务可以继续启动，但所有受保护请求都会返回 503 license_no_public_key，
// 绝不静默放行（不变量 4）。
func NewManager(cfg Config) (*Manager, error) {
	clockPath := cfg.LastCheckFile
	if clockPath == "" {
		clockPath = filepath.Join(filepath.Dir(cfg.LicPath), clockFileName)
	}
	m := &Manager{
		enabled:   cfg.Enabled,
		licPath:   cfg.LicPath,
		clockPath: clockPath,
	}
	if !m.enabled {
		return m, nil
	}
	pub, err := parseRSAPublicKey(cfg.PublicKeyPEM)
	if err != nil {
		m.initErr = fmt.Errorf("解析内置公钥失败（状态码 %s）: %w", CodeNoPublicKey, err)
		return m, nil
	}
	m.pub = pub
	// 确保授权文件所在目录存在，否则客户上传授权时会失败。
	if err := os.MkdirAll(filepath.Dir(cfg.LicPath), 0o755); err != nil {
		return nil, fmt.Errorf("创建授权目录失败: %w", err)
	}
	return m, nil
}

// Enabled 返回授权校验是否启用。
func (m *Manager) Enabled() bool {
	return m != nil && m.enabled
}

// Status 返回当前授权状态（带短 TTL 缓存）。
func (m *Manager) Status() Status {
	if m == nil {
		return Status{Code: CodeNotInit, Message: "授权模块未初始化", Valid: false, CheckedAt: time.Now().UTC()}
	}
	if !m.enabled {
		return Status{Code: CodeDisabled, Message: "授权校验未启用（开发态）", Valid: true, CheckedAt: time.Now().UTC()}
	}
	if m.initErr != nil {
		return Status{Code: CodeNoPublicKey, Message: m.initErr.Error(), Valid: false, CheckedAt: time.Now().UTC()}
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cached != nil && time.Since(m.cachedAt) < statusTTL {
		return *m.cached
	}
	st := m.evaluateFile()
	m.cached = &st
	m.cachedAt = time.Now()
	return st
}

// Reload 强制重新读取并校验授权文件。
func (m *Manager) Reload() Status {
	if m == nil {
		return Status{Code: CodeNotInit, Message: "授权模块未初始化", Valid: false, CheckedAt: time.Now().UTC()}
	}
	if !m.enabled {
		return Status{Code: CodeDisabled, Message: "授权校验未启用（开发态）", Valid: true, CheckedAt: time.Now().UTC()}
	}
	if m.initErr != nil {
		return Status{Code: CodeNoPublicKey, Message: m.initErr.Error(), Valid: false, CheckedAt: time.Now().UTC()}
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	st := m.evaluateFile()
	m.cached = &st
	m.cachedAt = time.Now()
	return st
}

// ValidateContent 只校验内容，不读写授权文件、不更新时间回拨检查点。
func (m *Manager) ValidateContent(content []byte) (*Payload, error) {
	if m == nil || !m.enabled {
		return nil, &LicenseError{CodeDisabled, "授权校验未启用"}
	}
	st := m.evaluateBytes(content, time.Now().UTC(), false)
	if !st.Valid {
		return st.License, &LicenseError{Code: st.Code, Msg: st.Message}
	}
	return st.License, nil
}

// Install 校验通过后原子写入新授权（不变量 6）：
// 校验 → 备份 .bak → 写 .tmp → rename 替换。
func (m *Manager) Install(content []byte) (Status, error) {
	if m == nil || !m.enabled {
		return Status{Code: CodeDisabled, Valid: false, Message: "授权校验未启用", CheckedAt: time.Now().UTC()},
			&LicenseError{CodeDisabled, "授权校验未启用"}
	}
	st := m.evaluateBytes(content, time.Now().UTC(), false)
	if !st.Valid {
		return st, &LicenseError{Code: st.Code, Msg: st.Message}
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	if old, err := os.ReadFile(m.licPath); err == nil && len(old) > 0 {
		_ = os.WriteFile(m.licPath+".bak", old, 0o600)
	}
	if err := os.MkdirAll(filepath.Dir(m.licPath), 0o755); err != nil {
		return st, fmt.Errorf("创建授权目录失败: %w", err)
	}
	tmp := m.licPath + ".tmp"
	if err := os.WriteFile(tmp, content, 0o600); err != nil {
		return st, fmt.Errorf("写入授权文件失败: %w", err)
	}
	if err := os.Rename(tmp, m.licPath); err != nil {
		_ = os.Remove(tmp)
		return st, fmt.Errorf("替换授权文件失败: %w", err)
	}

	latest := m.evaluateFile()
	m.cached = &latest
	m.cachedAt = time.Now()
	return latest, nil
}

// evaluateFile 读取授权文件并评估。
func (m *Manager) evaluateFile() Status {
	content, err := os.ReadFile(m.licPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return Status{Code: CodeMissing, Message: "未找到授权文件，请上传授权文件", Valid: false, CheckedAt: time.Now().UTC()}
		}
		return Status{Code: CodeMalformed, Message: fmt.Sprintf("读取授权文件失败: %v", err), Valid: false, CheckedAt: time.Now().UTC()}
	}
	return m.evaluateBytes(content, time.Now().UTC(), true)
}

// evaluateBytes 是完整校验流程（规范 §6）。
func (m *Manager) evaluateBytes(content []byte, now time.Time, checkClock bool) Status {
	payload, err := m.verifyContent(content)
	if err != nil {
		var le *LicenseError
		if errors.As(err, &le) {
			return Status{Code: le.Code, Message: le.Msg, Valid: false, CheckedAt: now}
		}
		return Status{Code: CodeMalformed, Message: err.Error(), Valid: false, CheckedAt: now}
	}

	if checkClock {
		if err := m.checkClock(now); err != nil {
			return Status{Code: CodeClockRollback, Message: err.Error(), Valid: false, CheckedAt: now, License: payload}
		}
	}

	if payload.Permanent() {
		return Status{Code: CodeOK, Message: "授权有效（永久授权）", Valid: true, RemainingDays: -1, CheckedAt: now, License: payload}
	}

	remaining := payload.ExpireTime.Sub(now)
	if remaining > 0 {
		return Status{
			Code:          CodeOK,
			Message:       fmt.Sprintf("授权有效，到期时间 %s", formatLocal(*payload.ExpireTime)),
			Valid:         true,
			RemainingDays: int(remaining.Hours() / 24),
			CheckedAt:     now,
			License:       payload,
		}
	}

	grace := time.Duration(payload.GraceDays) * 24 * time.Hour
	if payload.GraceDays > 0 && -remaining <= grace {
		return Status{
			Code:          CodeGrace,
			Message:       fmt.Sprintf("授权已于 %s 到期，当前处于 %d 天宽限期，请尽快续期", formatLocal(*payload.ExpireTime), payload.GraceDays),
			Valid:         true,
			InGrace:       true,
			RemainingDays: int(remaining.Hours() / 24),
			CheckedAt:     now,
			License:       payload,
		}
	}

	return Status{
		Code:          CodeExpired,
		Message:       fmt.Sprintf("授权已于 %s 到期，系统功能已停用，请上传新的授权文件", formatLocal(*payload.ExpireTime)),
		Valid:         false,
		RemainingDays: int(remaining.Hours() / 24),
		CheckedAt:     now,
		License:       payload,
	}
}

// verifyContent 解信封 → 对原始字节验签 → 解载荷 → 业务字段校验。
func (m *Manager) verifyContent(content []byte) (*Payload, error) {
	if m.pub == nil {
		return nil, &LicenseError{CodeNoPublicKey, "内置公钥未配置，无法校验授权"}
	}

	var env Envelope
	if err := json.Unmarshal(content, &env); err != nil {
		return nil, &LicenseError{CodeMalformed, "授权文件格式错误，请确认上传的是 .lic 授权文件"}
	}
	if strings.TrimSpace(env.Data) == "" || strings.TrimSpace(env.Sign) == "" {
		return nil, &LicenseError{CodeMalformed, "授权文件内容不完整（缺少 data 或 sign）"}
	}

	payloadBytes, err := base64.StdEncoding.DecodeString(env.Data)
	if err != nil {
		return nil, &LicenseError{CodeMalformed, "授权内容 base64 解码失败"}
	}
	signature, err := base64.StdEncoding.DecodeString(env.Sign)
	if err != nil {
		return nil, &LicenseError{CodeMalformed, "授权签名 base64 解码失败"}
	}

	// 不变量 1：对 data 原始字节验签，绝不重新序列化。
	sum := sha256.Sum256(payloadBytes)
	if err := rsa.VerifyPKCS1v15(m.pub, crypto.SHA256, sum[:], signature); err != nil {
		return nil, &LicenseError{CodeBadSignature, "授权文件签名校验失败，文件可能已被篡改或非统一授权平台签发"}
	}

	var payload Payload
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		return nil, &LicenseError{CodeMalformed, "授权载荷 JSON 解析失败"}
	}

	// 过渡期兼容：旧版载荷没有 schema_version。
	if payload.SchemaVersion == 0 {
		payload.Legacy = true
		if payload.GraceDays < 0 {
			payload.GraceDays = 0
		}
		// 旧版用零值时间表示永久授权；统一格式用 null 表示。
		if payload.ExpireTime != nil && payload.ExpireTime.IsZero() {
			payload.ExpireTime = nil
		}
		if strings.TrimSpace(payload.MachineCode) == "" {
			// 旧版空串=通用授权；新规范要求显式 "*"。
			payload.MachineCode = UniversalMachineCode
		}
		return &payload, nil
	}
	if payload.SchemaVersion != SchemaVersion {
		return nil, &LicenseError{CodeMalformed,
			fmt.Sprintf("不支持的授权文件版本 schema_version=%d（本程序支持 %d）", payload.SchemaVersion, SchemaVersion)}
	}

	if payload.Platform != PlatformID {
		return nil, &LicenseError{CodeProductMismatch, "授权签发方标识不匹配，非统一授权平台签发的文件"}
	}
	if payload.Product != Product {
		return nil, &LicenseError{CodeProductMismatch,
			fmt.Sprintf("授权文件属于产品 %q，与当前程序产品 %q 不符", payload.Product, Product)}
	}
	if strings.TrimSpace(payload.MachineCode) == "" {
		return nil, &LicenseError{CodeMalformed, "授权文件缺少 machine_code 字段（通用授权必须显式写 \"*\"）"}
	}
	if payload.MachineCode != UniversalMachineCode {
		if payload.MachineCode != GetMachineCode() && payload.MachineCode != legacyMachineCode() {
			return nil, &LicenseError{CodeMachineMismatch, "授权文件绑定了其他机器，与本机机器码不匹配"}
		}
	}
	if payload.GraceDays < 0 {
		payload.GraceDays = 0
	}
	return &payload, nil
}

// ============================================================================
// 时间回拨检测
// ============================================================================

func (m *Manager) checkClock(now time.Time) error {
	last, ok := readClock(m.clockPath)
	if ok && now.Add(clockTolerance).Before(last) {
		return fmt.Errorf("检测到系统时间被回拨（上次校验时间 %s，当前 %s），授权校验失败", formatLocal(last), formatLocal(now))
	}
	if !ok || now.After(last) {
		writeClock(m.clockPath, now)
	}
	return nil
}

func readClock(path string) (time.Time, bool) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return time.Time{}, false
	}
	parts := strings.SplitN(strings.TrimSpace(string(raw)), "|", 2)
	if len(parts) != 2 {
		return time.Time{}, false
	}
	sec, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return time.Time{}, false
	}
	mac, err := hex.DecodeString(parts[1])
	if err != nil {
		return time.Time{}, false
	}
	if !hmac.Equal(mac, clockMAC(sec)) {
		return time.Time{}, false
	}
	return time.Unix(sec, 0).UTC(), true
}

func writeClock(path string, t time.Time) {
	sec := t.Unix()
	body := strconv.FormatInt(sec, 10) + "|" + hex.EncodeToString(clockMAC(sec))
	_ = os.WriteFile(path, []byte(body), 0o600)
}

func clockMAC(sec int64) []byte {
	h := hmac.New(sha256.New, []byte(clockSecret))
	h.Write([]byte(strconv.FormatInt(sec, 10)))
	return h.Sum(nil)
}

// ============================================================================
// 公钥解析
// ============================================================================

func parseRSAPublicKey(pemStr string) (*rsa.PublicKey, error) {
	trimmed := strings.TrimSpace(pemStr)
	if trimmed == "" || strings.Contains(trimmed, "REPLACE_WITH_YOUR_PUBLIC_KEY") {
		return nil, errors.New("公钥未配置或仍是占位符")
	}
	block, _ := pem.Decode([]byte(trimmed))
	if block == nil {
		return nil, errors.New("公钥 PEM 解析失败")
	}
	if pub, err := x509.ParsePKIXPublicKey(block.Bytes); err == nil {
		rsaPub, ok := pub.(*rsa.PublicKey)
		if !ok {
			return nil, errors.New("公钥类型不是 RSA")
		}
		return rsaPub, nil
	}
	if pub, err := x509.ParsePKCS1PublicKey(block.Bytes); err == nil {
		return pub, nil
	}
	return nil, errors.New("公钥既不是 PKIX 也不是 PKCS#1 格式")
}

// ============================================================================
// 机器码（规范 §5）
// ============================================================================

var (
	machineOnce  sync.Once
	machineValue string
	legacyOnce   sync.Once
	legacyValue  string
)

// GetMachineCode 返回统一机器码：SHA-256("ULP-LICENSE-V1:"+raw) 前 16 字节。
// 支持 LICENSE_MACHINE_CODE 覆盖（容器场景）。
func GetMachineCode() string {
	if v := strings.TrimSpace(os.Getenv("LICENSE_MACHINE_CODE")); v != "" {
		return v
	}
	machineOnce.Do(func() {
		sum := sha256.Sum256([]byte("ULP-LICENSE-V1:" + rawMachineIdentity()))
		machineValue = hex.EncodeToString(sum[:16])
	})
	return machineValue
}

func rawMachineIdentity() string {
	for _, path := range []string{"/etc/machine-id", "/var/lib/dbus/machine-id"} {
		if b, err := os.ReadFile(path); err == nil {
			if id := strings.TrimSpace(string(b)); id != "" {
				return id
			}
		}
	}
	if host, err := os.Hostname(); err == nil && strings.TrimSpace(host) != "" {
		return strings.TrimSpace(host)
	}
	ifaces, err := net.Interfaces()
	if err == nil {
		for _, iface := range ifaces {
			if iface.Flags&net.FlagLoopback != 0 {
				continue
			}
			if addr := iface.HardwareAddr.String(); addr != "" {
				return addr
			}
		}
	}
	return "unknown"
}

// legacyMachineCode 返回旧版 AgentSystem 机器码（64 位 hex：
// SHA-256("board:<serial>|cpu:<model>")），仅用于过渡期兼容。
func legacyMachineCode() string {
	legacyOnce.Do(func() {
		board := readBoardSerial()
		cpu := readCPUInfo()
		raw := "board:" + board + "|cpu:" + cpu
		if board == "" && cpu == "" {
			if host, err := os.Hostname(); err == nil && host != "" {
				raw = "hostname:" + host
			} else {
				raw = "unknown"
			}
		}
		sum := sha256.Sum256([]byte(raw))
		legacyValue = hex.EncodeToString(sum[:])
	})
	return legacyValue
}

func readBoardSerial() string {
	for _, p := range []string{
		"/sys/class/dmi/id/board_serial",
		"/sys/class/dmi/id/product_serial",
		"/sys/class/dmi/id/product_uuid",
	} {
		if b, err := os.ReadFile(p); err == nil {
			v := strings.TrimSpace(string(b))
			if v != "" && v != "None" {
				return v
			}
		}
	}
	return ""
}

func readCPUInfo() string {
	b, err := os.ReadFile("/proc/cpuinfo")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "model name") || strings.HasPrefix(line, "Hardware") {
			return strings.TrimSpace(line)
		}
	}
	return ""
}

// ============================================================================
// 全局单例（服务启动时通过 SetGlobal 初始化一次）
// ============================================================================

var globalManager *Manager

// SetGlobal 设置全局授权管理器。
func SetGlobal(mgr *Manager) { globalManager = mgr }

// Global 返回全局授权管理器，未初始化时返回 nil。
func Global() *Manager { return globalManager }

// formatLocal 把 UTC 时刻转成本地时区展示。
func formatLocal(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.Local().Format("2006-01-02 15:04")
}
