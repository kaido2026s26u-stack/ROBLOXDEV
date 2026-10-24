-- RXDEV release configuration and explicit module interfaces.
return {
    version = "1.0.0",
    guiName = "RXDEV_Utilities",
    legacyGuiNames = {"ROBLOXDEV_Utilities", "ROBLOXDEV_AntiAFK",
        "ROBLOXDEV_NativeInputTest", "ROBLOXDEV_ConsoleButton"},
    modules = {
        App={"start"}, UI={"create"}, AntiAFK={"start"},
        Graphics={"new"}, PerformanceMeter={"start"},
        FastMode={"start", "stop", "active", "status", "advance", "level", "super", "ultra", "busy"},
        ExtremelyFastMode={"start", "stop", "active", "status", "busy"},
    },
}
