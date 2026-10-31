package license

// PublicKeyPEM 是内置到程序里的统一授权平台（ULP）公钥，仅用于验签。
//
// 安全说明：
//   - 公钥是公开信息，可以进代码仓库并随程序交付；私钥只存在于 ULP 服务端，
//     永远不下发到业务项目。
//   - 本项目的 product 标识为 "agent-system"，必须与 ULP 项目管理页一致。
//   - 公钥可通过环境变量 LICENSE_PUBLIC_KEY 覆盖（多环境构建/测试用）。
//   - 公钥轮换后，旧授权会全部验签失败，需向客户重新下发授权文件。
const PublicKeyPEM = `-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnDcoeIAh+zCopqt3nkpF
iu1Alfz/CSCY2BtqEqQVYImi0zuhdpX5cAifrJz0tOgDM2vqNSEBa50KaG/FvMCx
CnxamhNFv4YIciftDGcCDvleaEzXLVBjIMelb3b5tOQIK6bVYXIellyttZxWo8F0
qyZhRYZcBmOxrP3EuLlr+jcY0n7WmzLODy/vOWkQSkDXWEWZaPNGhmfOn/xcrYAm
Iu/Jwa7W0m1Dua5vciIre74vm0QXS83Gc7JEPsQXTKPc47kSVuFSA1TQPreC0eMS
aUg6FQKw0tACP0q1czh2tgUslk9vmn8MXywSexiPLWkYEbqPTsscsjJfqVjFylPE
cQIDAQAB
-----END PUBLIC KEY-----`
