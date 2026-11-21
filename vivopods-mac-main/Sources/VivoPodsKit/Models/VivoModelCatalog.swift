import Foundation

/// vivo / iQOO TWS 型号识别与 profile 选择。移植自参考实现 `vivovivo_models.py`。
public enum VivoModelCatalog {

    public static let vivoPrefix = "vivotws"
    public static let iqooPrefix = "iqootws"

    /// 小写 + 仅保留字母数字。
    public static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 零售型号表（含别名）。
    static let models: [(canonical: String, aliases: [String])] = [
        ("vivo TWS Air3 Pro", []),
        ("vivo TWS 3e", []),
        ("vivo TWS Air2", ["vivo TWS Air200"]),
        ("vivo TWS 5e", []),
        ("vivo TWS 3 Pro", []),
        ("vivo TWS 3", []),
        ("vivo TWS 2e", []),
        ("vivo TWS 2", []),
        ("vivo TWS 1", []),
        ("vivo TWS A1 Pro", []),
        ("vivo TWS A1", []),
        ("vivo TWS Air Pro", []),
        ("vivo TWS Air", []),
        ("vivo TWS Neo", []),
        ("vivo TWS X1", []),
        ("vivo TWS", []),
        ("iQOO TWS Air3 Pro", []),
        ("iQOO TWS Air", []),
        ("iQOO TWS 1", []),
    ]

    /// 具体型号 → wire profile。未列出的型号回落到家族默认 v4。
    static let modelProfiles: [String: VivoProfile] = [
        "vivo TWS Air3 Pro": .air3ProCaptured,
        "iQOO TWS Air3 Pro": .air3ProCaptured,  // iQOO 与 vivo Air3 Pro 同硬件，复用已验证抓包 profile
        "vivo TWS 3e": .tws3eV3,
    ]

    /// 名称是否落入 vivo / iQOO TWS 家族。
    public static func isFamilyName(_ deviceName: String?) -> Bool {
        guard let deviceName else { return false }
        let n = normalize(deviceName)
        return n.hasPrefix(vivoPrefix) || n.hasPrefix(iqooPrefix)
    }

    /// 按归一化名精确匹配具体型号。
    public static func findModel(_ deviceName: String?) -> String? {
        guard let deviceName else { return nil }
        let n = normalize(deviceName)
        for (canonical, aliases) in models {
            if n == normalize(canonical) || aliases.contains(where: { n == normalize($0) }) {
                return canonical
            }
        }
        return nil
    }

    /// 选定 profile：先精确命中；再按语义关键字兜底命中 Air3 Pro；最后回家族默认 v4。
    public static func selectProfile(_ deviceName: String?) -> VivoProfile {
        // 1) 精确命中型号表且该型号有专属 profile
        if let name = findModel(deviceName), let p = modelProfiles[name] { return p }
        // 2) 兜底：名字含 air3 + pro 一律走 Air3 Pro 抓包 profile（兼容品牌前缀/后缀变体）
        if let n = deviceName.map(normalize), n.contains("air3"), n.contains("pro") {
            return .air3ProCaptured
        }
        // 3) 家族默认 v4
        return .familyDefaultV4
    }

    /// 展示名。
    public static func canonicalFor(_ deviceName: String?) -> String {
        if let deviceName {
            if let exact = findModel(deviceName) { return exact }
            if isFamilyName(deviceName) { return deviceName }
        }
        return "未知蓝牙设备"
    }

    /// 内部型号 id → 标签。本机 vivo TWS 5 上报 `model: 192` → `DPD2523_BASE`。
    public static let modelIdLabels: [Int: String] = [
        1: "TWS1_BASE",
        2: "TWS1_BLACK / TWS1_TOP",
        16: "TWS_NEO_BASE",
        17: "TWS_NEO_BLUE",
        19: "TWS_NEO_TOP",
        28: "TWS2_BASE",
        29: "TWS2_BLUE",
        31: "TWS2_TOP",
        32: "TWS2E_BASE",
        33: "TWS2E_BLUE",
        35: "TWS2E_TOP",
        48: "DPD2135A",
        49: "DPD2135A_BLUE",
        60: "TWS3_BASE",
        72: "DPD2220_BASE",
        156: "DPD2430_BASE",
        176: "DPD2430F_VIVO_WHITE",
        177: "DPD2430F_VIVO_BLUE",
        180: "DPD2430F_IQOO_BLACK",
        184: "DPD2430F_JOVI_WHITE",
        185: "DPD2430F_JOVI_BLUE",
        192: "DPD2523_BASE",
        203: "DPD2523_TOP",
    ]

    public static func modelIdLabel(_ modelId: Int) -> String? {
        modelIdLabels[modelId]
    }
}
