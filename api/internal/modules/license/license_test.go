package license

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

func newTestKey(t *testing.T) (*rsa.PrivateKey, string) {
	t.Helper()
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("生成测试密钥失败: %v", err)
	}
	der, err := x509.MarshalPKIXPublicKey(&priv.PublicKey)
	if err != nil {
		t.Fatalf("导出公钥失败: %v", err)
	}
	return priv, string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}))
}

func signEnvelope(t *testing.T, priv *rsa.PrivateKey, payload map[string]any) []byte {
	t.Helper()
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("序列化载荷失败: %v", err)
	}
	sum := sha256.Sum256(payloadBytes)
	sig, err := rsa.SignPKCS1v15(rand.Reader, priv, crypto.SHA256, sum[:])
	if err != nil {
		t.Fatalf("签名失败: %v", err)
	}
	raw, err := json.Marshal(Envelope{
		Data: base64.StdEncoding.EncodeToString(payloadBytes),
		Sign: base64.StdEncoding.EncodeToString(sig),
	})
	if err != nil {
		t.Fatalf("序列化信封失败: %v", err)
	}
	return raw
}

func v1Payload(expire *time.Time, grace int, machine string) map[string]any {
	issued := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	p := map[string]any{
		"schema_version":  1,
		"license_id":      "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
		"platform":        PlatformID,
		"product":         Product,
		"product_display": "Agent System",
		"customer":        "测试客户",
		"issued_at":       issued.Format(time.RFC3339),
		"expire_time":     nil,
		"grace_days":      grace,
		"machine_code":    machine,
	}
	if expire != nil {
		p["expire_time"] = expire.UTC().Format(time.RFC3339)
	}
	return p
}

func newTestManager(t *testing.T, pubPEM string) (*Manager, string) {
	t.Helper()
	pub, err := parseRSAPublicKey(pubPEM)
	if err != nil {
		t.Fatalf("解析公钥失败: %v", err)
	}
	dir := t.TempDir()
	return &Manager{
		enabled:   true,
		pub:       pub,
		licPath:   filepath.Join(dir, "license.lic"),
		clockPath: filepath.Join(dir, clockFileName),
	}, dir
}

func fixedNow() time.Time { return time.Date(2026, 6, 1, 12, 0, 0, 0, time.UTC) }

// ---------------------------------------------------------------------------
// 校验流程
// ---------------------------------------------------------------------------

func TestEvaluate_ValidLicense(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	expire := fixedNow().Add(30 * 24 * time.Hour)
	st := m.evaluateBytes(signEnvelope(t, priv, v1Payload(&expire, 7, "*")), fixedNow(), false)
	if !st.Valid || st.Code != CodeOK || st.License.Customer != "测试客户" {
		t.Fatalf("期望 ok/valid，实际 code=%s valid=%v", st.Code, st.Valid)
	}
}

func TestEvaluate_PermanentLicense(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	st := m.evaluateBytes(signEnvelope(t, priv, v1Payload(nil, 0, "*")), fixedNow(), false)
	if !st.Valid || st.Code != CodeOK || st.RemainingDays != -1 {
		t.Fatalf("永久授权应 valid/ok/-1，实际 code=%s days=%d", st.Code, st.RemainingDays)
	}
}

func TestEvaluate_GracePeriod(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	expire := fixedNow().Add(-2 * 24 * time.Hour)
	st := m.evaluateBytes(signEnvelope(t, priv, v1Payload(&expire, 7, "*")), fixedNow(), false)
	if !st.Valid || st.Code != CodeGrace || !st.InGrace {
		t.Fatalf("宽限期应 license_grace，实际 code=%s valid=%v", st.Code, st.Valid)
	}
}

func TestEvaluate_Expired(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	expire := fixedNow().Add(-10 * 24 * time.Hour)
	st := m.evaluateBytes(signEnvelope(t, priv, v1Payload(&expire, 7, "*")), fixedNow(), false)
	if st.Valid || st.Code != CodeExpired {
		t.Fatalf("过期应 license_expired，实际 code=%s", st.Code)
	}
}

func TestEvaluate_TamperedRejected(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	raw := signEnvelope(t, priv, v1Payload(nil, 0, "*"))
	var env Envelope
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatal(err)
	}
	payloadBytes, _ := base64.StdEncoding.DecodeString(env.Data)
	tampered := strings.Replace(string(payloadBytes), `"customer":"测试客户"`, `"customer":"别人"`, 1)
	env.Data = base64.StdEncoding.EncodeToString([]byte(tampered))
	raw, _ = json.Marshal(env)

	st := m.evaluateBytes(raw, fixedNow(), false)
	if st.Valid || st.Code != CodeBadSignature {
		t.Fatalf("篡改应 license_bad_signature，实际 code=%s", st.Code)
	}
}

func TestEvaluate_WrongProductRejected(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	payload := v1Payload(nil, 0, "*")
	payload["product"] = "teable"
	st := m.evaluateBytes(signEnvelope(t, priv, payload), fixedNow(), false)
	if st.Valid || st.Code != CodeProductMismatch {
		t.Fatalf("产品不符应 license_product_mismatch，实际 code=%s", st.Code)
	}
}

func TestEvaluate_MachineMismatch(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	st := m.evaluateBytes(signEnvelope(t, priv, v1Payload(nil, 0, "ffffffffffffffffffffffffffffffff")), fixedNow(), false)
	if st.Valid || st.Code != CodeMachineMismatch {
		t.Fatalf("机器码不符应 license_machine_mismatch，实际 code=%s", st.Code)
	}
}

func TestEvaluate_EmptyOrMissingMachineCodeIsMalformed(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	st := m.evaluateBytes(signEnvelope(t, priv, v1Payload(nil, 0, "")), fixedNow(), false)
	if st.Valid || st.Code != CodeMalformed {
		t.Fatalf("空 machine_code 应 license_malformed，实际 code=%s", st.Code)
	}

	payload := v1Payload(nil, 0, "*")
	delete(payload, "machine_code")
	st = m.evaluateBytes(signEnvelope(t, priv, payload), fixedNow(), false)
	if st.Valid || st.Code != CodeMalformed {
		t.Fatalf("缺失 machine_code 应 license_malformed，实际 code=%s", st.Code)
	}
}

func TestEvaluate_UnsupportedSchemaRejected(t *testing.T) {
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	payload := v1Payload(nil, 0, "*")
	payload["schema_version"] = 2
	st := m.evaluateBytes(signEnvelope(t, priv, payload), fixedNow(), false)
	if st.Valid || st.Code != CodeMalformed {
		t.Fatalf("未知 schema_version 应拒绝，实际 code=%s", st.Code)
	}
}

func TestEvaluate_LegacyEmptyMachineCodeTreatedAsUniversal(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	legacy := map[string]any{
		"product":      Product,
		"customer":     "旧客户",
		"expire_time":  fixedNow().Add(48 * time.Hour).Format(time.RFC3339),
		"issued_at":    fixedNow().Format(time.RFC3339),
		"machine_code": "",
	}
	st := m.evaluateBytes(signEnvelope(t, priv, legacy), fixedNow(), false)
	if !st.Valid || st.Code != CodeOK || !st.License.Legacy || st.License.MachineCode != "*" {
		t.Fatalf("旧版通用授权应兼容放行，实际 code=%s machine=%q", st.Code, st.License.MachineCode)
	}
}

func TestEvaluate_MalformedEnvelope(t *testing.T) {
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)
	_ = priv

	for name, raw := range map[string][]byte{
		"非法 JSON":       []byte("not-json"),
		"缺少 data":       []byte(`{"sign":"abc"}`),
		"缺少 sign":       []byte(`{"data":"abc"}`),
		"data 非 base64": []byte(`{"data":"!!!!","sign":"abc"}`),
		"sign 非 base64": []byte(`{"data":"e30=","sign":"!!!!"}`),
	} {
		st := m.evaluateBytes(raw, fixedNow(), false)
		if st.Valid || st.Code != CodeMalformed {
			t.Fatalf("%s 应 license_malformed，实际 code=%s", name, st.Code)
		}
	}
}

// ---------------------------------------------------------------------------
// 时间回拨
// ---------------------------------------------------------------------------

func TestClock_Rollback(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)
	raw := signEnvelope(t, priv, v1Payload(nil, 0, "*"))
	base := fixedNow()

	if st := m.evaluateBytes(raw, base, true); !st.Valid {
		t.Fatalf("首次校验应通过: %s", st.Code)
	}
	if st := m.evaluateBytes(raw, base.Add(-2*time.Hour), true); st.Valid || st.Code != CodeClockRollback {
		t.Fatalf("回拨应 license_clock_rollback，实际 code=%s", st.Code)
	}
	if st := m.evaluateBytes(raw, base.Add(-time.Minute), true); !st.Valid {
		t.Fatalf("容差内不应误判，实际 code=%s", st.Code)
	}
}

func TestClock_TamperedCheckpointIgnored(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)
	raw := signEnvelope(t, priv, v1Payload(nil, 0, "*"))

	if st := m.evaluateBytes(raw, fixedNow(), true); !st.Valid {
		t.Fatalf("首次校验应通过: %s", st.Code)
	}
	future := fixedNow().Add(365 * 24 * time.Hour).Unix()
	_ = os.WriteFile(m.clockPath, []byte(strconv.FormatInt(future, 10)+"|deadbeef"), 0o600)
	if st := m.evaluateBytes(raw, fixedNow(), true); !st.Valid {
		t.Fatalf("检查点被篡改应按无基准处理，实际 code=%s", st.Code)
	}
}

// ---------------------------------------------------------------------------
// 安装
// ---------------------------------------------------------------------------

func TestInstall_InvalidDoesNotOverwrite(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	good := signEnvelope(t, priv, v1Payload(nil, 0, "*"))
	if err := os.WriteFile(m.licPath, good, 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Install([]byte(`{"data":"bad","sign":"bad"}`)); err == nil {
		t.Fatal("坏文件应安装失败")
	}
	onDisk, _ := os.ReadFile(m.licPath)
	if string(onDisk) != string(good) {
		t.Fatal("坏文件不得覆盖有效授权")
	}
}

func TestInstall_BacksUpAndReplaces(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	priv, pubPEM := newTestKey(t)
	m, _ := newTestManager(t, pubPEM)

	old := signEnvelope(t, priv, v1Payload(nil, 0, "*"))
	_ = os.WriteFile(m.licPath, old, 0o600)
	newLic := signEnvelope(t, priv, v1Payload(nil, 0, "*"))
	if _, err := m.Install(newLic); err != nil {
		t.Fatalf("安装失败: %v", err)
	}
	if _, err := os.Stat(m.licPath + ".bak"); err != nil {
		t.Fatalf("应生成 .bak: %v", err)
	}
	onDisk, _ := os.ReadFile(m.licPath)
	if string(onDisk) != string(newLic) {
		t.Fatal("新授权未替换")
	}
	if _, err := os.Stat(m.licPath + ".tmp"); !os.IsNotExist(err) {
		t.Fatal("临时文件应已重命名")
	}
}

// ---------------------------------------------------------------------------
// 机器码与公钥
// ---------------------------------------------------------------------------

func TestMachineCode_FormatAndOverride(t *testing.T) {
	t.Setenv("LICENSE_MACHINE_CODE", "00112233445566778899aabbccddeeff")
	if got := GetMachineCode(); got != "00112233445566778899aabbccddeeff" {
		t.Fatalf("环境变量覆盖失败: %s", got)
	}
	t.Setenv("LICENSE_MACHINE_CODE", "")
	code := GetMachineCode()
	if len(code) != 32 || strings.ToLower(code) != code {
		t.Fatalf("机器码应为 32 位小写 hex，实际 %q", code)
	}
}

func TestParsePublicKey_PlaceholderAndPKCS1(t *testing.T) {
	if _, err := parseRSAPublicKey("REPLACE_WITH_YOUR_PUBLIC_KEY"); err == nil {
		t.Fatal("占位符应解析失败")
	}
	priv, _ := newTestKey(t)
	der := x509.MarshalPKCS1PublicKey(&priv.PublicKey)
	pemStr := string(pem.EncodeToMemory(&pem.Block{Type: "RSA PUBLIC KEY", Bytes: der}))
	if _, err := parseRSAPublicKey(pemStr); err != nil {
		t.Fatalf("PKCS#1 公钥应被接受: %v", err)
	}
}

func TestGlobal_UninitializedReturnsNotInit(t *testing.T) {
	old := globalManager
	globalManager = nil
	defer func() { globalManager = old }()

	if Global() != nil {
		t.Fatal("未初始化时 Global 应为 nil")
	}
}
