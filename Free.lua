-- NAPHUB |  Loot A Forge
--[[
    ╔═══════════════════════════════════════════════════════════════╗
    ║                NAPHUB  +1 LOOT A FORGE  v4.9.2                ║
    ║   Game   : [Enhance]+1 Loot To Forge                          ║
    ║   UI     : NAPHUB Menu + Floating Button (tap to open/close)  ║
    ║   Engine : ระบบไก่ตัน Automation, Boss Hunter, Webhook & Gacha      ║
    ║   System : Dual Language Engine (Thai Default / English)      ║
    ╚═══════════════════════════════════════════════════════════════╝
]]

-- ─────────────────────────────────────────────────────────────
-- UI Runtime State
-- ─────────────────────────────────────────────────────────────
local function NAPHUB_DEBUG(msg, popup)
    msg = tostring(msg)
    print("[NAPHUB] " .. msg)
    if popup then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", { Title = "NAPHUB", Text = msg:sub(1, 200), Duration = 15 })
        end)
    end
end
NAPHUB_DEBUG("script started")

local CurrentWindow = nil
local function notify(title, content, icon)
    if CurrentWindow and CurrentWindow.Notify then
        pcall(function() CurrentWindow:Notify(tostring(title), tostring(content)) end)
    end
end

-- ─────────────────────────────────────────────────────────────
-- Services
-- ─────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local VirtualUser       = game:GetService("VirtualUser")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local GuiService        = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local RemoteRoot  = ReplicatedStorage:WaitForChild("Remote", 15)

-- Optional game data modules used by the smart forge / gear scanner.
local BackpackData, OreHelper, WeaponHelper, ArmorHelper, EnchStoneHelper = nil, nil, nil, nil, nil
local EnhantHelper, TrainCTRL = nil, nil
pcall(function() BackpackData = require(ReplicatedStorage.LocalData.BackpackData) end)
pcall(function() OreHelper = require(ReplicatedStorage.Config.Ore.Helper) end)
pcall(function() WeaponHelper = require(ReplicatedStorage.Config.Weapon.Helper) end)
pcall(function() ArmorHelper = require(ReplicatedStorage.Config.Armor.Helper) end)
pcall(function() EnchStoneHelper = require(ReplicatedStorage.Config.EnchStone.Helper) end)
pcall(function() EnhantHelper = require(ReplicatedStorage.Config.Enhant.Helper) end)
pcall(function() TrainCTRL = require(ReplicatedStorage.CTRL.TrainCTRL) end)

-- Instant Kill bindings (from game internals)
local EnemyCTRL, HPCTRL, CommunicationUtils, Bindable_EnemyHit = nil, nil, nil, nil
pcall(function() EnemyCTRL = require(ReplicatedStorage.CTRL.EnemyCTRL) end)
pcall(function() HPCTRL = require(ReplicatedStorage.CTRL.HPCTRL) end)
pcall(function()
    CommunicationUtils = require(ReplicatedStorage.Utils.CommunicationUtils)
    if CommunicationUtils and CommunicationUtils.TryGetBindableEvent then
        Bindable_EnemyHit = CommunicationUtils.TryGetBindableEvent("Attack", "EnemyHitBE")
    end
end)

-- Profile data for GamePass bypass & rebirth check
local ProfileData = nil
pcall(function() ProfileData = require(ReplicatedStorage.ProfileData) end)
local MarketplaceService = game:GetService("MarketplaceService")

-- ─────────────────────────────────────────────────────────────
-- GamePass Bypass (Triple-Layer: PemData + NamecallHook + PurchaseIntercept)
-- ─────────────────────────────────────────────────────────────
local GamePassMap = {
    [1962630901] = "VIP",
    [1963566878] = "SuperLuck",
    [1965960643] = "CommonLuck",
    [1963764856] = "MoreOre",
    [1982474360] = "UltraLuck",
    [1962564854] = "SkipForge",
}
local ExtraPremiumKeys = { "AutoTrainArea_9", "AutoTrainArea_10", "AutoTrainArea_11" }

local function applyGamePassBypass()
    pcall(function()
        local pemStore = ProfileData and ProfileData.GetStoreData and ProfileData.GetStoreData("Pem")
        if pemStore and type(pemStore) == "table" then
            for _, pemKey in pairs(GamePassMap) do pemStore[pemKey] = true end
            for _, key in ipairs(ExtraPremiumKeys) do pemStore[key] = true end
        end
    end)
    if hookmetamethod and newcclosure and getnamecallmethod then
        pcall(function()
            local oldNC
            oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if self == MarketplaceService and method == "UserOwnsGamePassAsync" then
                    local args = {...}
                    local gpId = args[2] or args[1]
                    if type(gpId) == "number" and GamePassMap[gpId] then return true end
                end
                return oldNC(self, ...)
            end))
        end)
    end
    pcall(function()
        local Shop = require(ReplicatedStorage.GuiUtils.Shop)
        if Shop then
            if Shop.updateGamePass then Shop.updateGamePass() end
            if Shop.updateTrainArea then Shop.updateTrainArea() end
        end
    end)
end
pcall(applyGamePassBypass)

-- Train Area Multiplier Zones (Smart Best-Zone Detection with Live Workspace Mapping)
local TRAIN_AUTO_BEST = "Auto Best (แท่นคูณสูงสุดที่ปลดล็อค)"
local TrainAreaConfig = {
    { Id = 1,  Name = "Train_1 (x1.5 Power | Rebirth 0)",  Rebirth = 0,  Mult = 1.5, PadPos = Vector3.new(-53.0, 3.0, -41.0),   DummyPos = Vector3.new(-57.88, 6.94, -41.04), FallbackPos = Vector3.new(-52.96, 7.25, -40.66) },
    { Id = 2,  Name = "Train_2 (x2 Power | Rebirth 2)",    Rebirth = 2,  Mult = 2,   PadPos = Vector3.new(-53.0, 3.0, -20.9),   DummyPos = Vector3.new(-57.88, 6.94, -20.91), FallbackPos = Vector3.new(-52.96, 7.25, -20.84) },
    { Id = 3,  Name = "Train_3 (x4 Power | Rebirth 5)",    Rebirth = 5,  Mult = 4,   PadPos = Vector3.new(-53.0, 3.0, 21.4),    DummyPos = Vector3.new(-57.88, 6.94, 21.37), FallbackPos = Vector3.new(-52.96, 7.25, 21.21) },
    { Id = 4,  Name = "Train_4 (x6 Power | Rebirth 9)",    Rebirth = 9,  Mult = 6,   PadPos = Vector3.new(-53.0, 3.0, 43.25),   DummyPos = Vector3.new(-57.88, 6.94, 43.25), FallbackPos = Vector3.new(-52.96, 7.25, 42.82) },
    { Id = 5,  Name = "Train_5 (x8 Power | Rebirth 12)",   Rebirth = 12, Mult = 8,   PadPos = Vector3.new(-80.0, 8.6, 21.29),   DummyPos = Vector3.new(-84.50, 8.61, 21.29), FallbackPos = Vector3.new(-79.64, 10.14, 21.07) },
    { Id = 6,  Name = "Train_6 (x10 Power | Rebirth 15)",  Rebirth = 15, Mult = 10,  PadPos = Vector3.new(-80.0, 9.1, -20.90),  DummyPos = Vector3.new(-83.92, 9.11, -20.90), FallbackPos = Vector3.new(-79.64, 10.14, -20.78) },
    { Id = 7,  Name = "Train_7 (x15 Power | Rebirth 18)",  Rebirth = 18, Mult = 15,  PadPos = Vector3.new(-108.0, 12.7, 32.24), DummyPos = Vector3.new(-114.22, 12.73, 32.24), FallbackPos = Vector3.new(-106.92, 11.55, 31.77) },
    { Id = 8,  Name = "Train_8 (x25 Power | Rebirth 21)",  Rebirth = 21, Mult = 25,  PadPos = Vector3.new(-106.0, 10.6, -31.00),DummyPos = Vector3.new(-110.27, 10.63, -30.99), FallbackPos = Vector3.new(-105.94, 11.53, -30.69) },
    { Id = 9,  Name = "Train_9 (x100 VIP | Rebirth 0)",   Rebirth = 0,  Mult = 100, IsPay = true, PadPos = Vector3.new(-104.29, 11.75, 0.31), DummyPos = Vector3.new(-125.79, 11.29, 0.35), FallbackPos = Vector3.new(-104.29, 11.75, 0.31) },
    { Id = 10, Name = "Train_10 (x10 VIP | Rebirth 0)",  Rebirth = 0,  Mult = 10,  IsPay = true, PadPos = Vector3.new(-79.06, 11.75, 42.68), DummyPos = Vector3.new(-80.04, 11.65, 43.36), FallbackPos = Vector3.new(-79.06, 11.75, 42.68) },
    { Id = 11, Name = "Train_11 (x20 VIP | Rebirth 0)",  Rebirth = 0,  Mult = 20,  IsPay = true, PadPos = Vector3.new(-78.89, 11.75, -41.02), DummyPos = Vector3.new(-80.04, 11.65, -40.44), FallbackPos = Vector3.new(-78.89, 11.75, -41.02) },
}

local function getTrainZonePart(zoneId)
    local part = nil
    pcall(function()
        -- Path 1: TOUCHED.AutoTrainArea (touch trigger zone)
        if workspace:FindFirstChild("TOUCHED") then
            local ata = workspace.TOUCHED:FindFirstChild("AutoTrainArea")
            if ata then part = ata:FindFirstChild(tostring(zoneId)) end
        end
        -- Path 2: CanAttackFolder.TrainArea (what TrainCTRL actually reads)
        if not part then
            local caf = workspace:FindFirstChild("CanAttackFolder")
            if caf then
                local ta = caf:FindFirstChild("TrainArea")
                if ta then
                    part = ta:FindFirstChild("Train_" .. tostring(zoneId))
                        or ta:FindFirstChild(tostring(zoneId))
                end
            end
        end
    end)
    return part
end

-- Returns the best legitimate (unlocked non-pay) training pad based on current Rebirth
local function getBestLegitTrainZone()
    local curReb = 0
    -- Path 1: LocalPlayer.Eco.rebirth
    pcall(function()
        if LocalPlayer:FindFirstChild("Eco") then
            local eco = LocalPlayer.Eco
            local rb = eco:FindFirstChild("rebirth") or eco:FindFirstChild("Rebirth")
            if rb then curReb = tonumber(rb.Value) or 0 end
        end
    end)
    -- Path 2: ProfileData.GetTotalData().Eco.rebirth / Rebirth
    if curReb == 0 then
        pcall(function()
            local pd = ProfileData and ProfileData.GetTotalData and ProfileData.GetTotalData()
            if pd and pd.Eco then
                curReb = tonumber(pd.Eco.rebirth) or tonumber(pd.Eco.Rebirth) or 0
            end
        end)
    end
    -- Path 3: GetAttribute
    if curReb == 0 then
        pcall(function()
            curReb = tonumber(LocalPlayer:GetAttribute("Rebirth"))
                or tonumber(LocalPlayer:GetAttribute("rebirth")) or 0
        end)
    end
    -- Path 4: Deep-scan descendants
    if curReb == 0 then
        pcall(function()
            for _, v in ipairs(LocalPlayer:GetDescendants()) do
                if (v:IsA("IntValue") or v:IsA("NumberValue"))
                    and v.Name:lower() == "rebirth"
                    and (tonumber(v.Value) or 0) > 0
                then
                    curReb = tonumber(v.Value)
                    break
                end
            end
        end)
    end

    local best = TrainAreaConfig[1]
    for _, z in ipairs(TrainAreaConfig) do
        if not z.IsPay and curReb >= z.Rebirth then
            if z.Mult >= best.Mult then best = z end
        end
    end
    return best
end

local function getBestTrainZone(forceVIP)
    -- ★ Feature B: ForceVIPTrain bypass — returns Zone 9 (x100 VIP)
    if forceVIP or (State and State.ForceVIPTrain) then
        for _, z in ipairs(TrainAreaConfig) do
            if z.Id == 9 then return z end
        end
    end

    -- Check if player genuinely owns VIP gamepass
    local canUseVIP = false
    pcall(function()
        local Shop = require(ReplicatedStorage.GuiUtils.Shop)
        if Shop and type(Shop.isOwnPass) == "function" then
            canUseVIP = Shop.isOwnPass("TrainArea") or Shop.isOwnPass(1)
        end
    end)

    if canUseVIP then
        for _, z in ipairs(TrainAreaConfig) do
            if z.Id == 9 then return z end
        end
    end

    return getBestLegitTrainZone()
end

local function getZoneByName(name)
    for _, z in ipairs(TrainAreaConfig) do
        if z.Name == name or tostring(z.Id) == tostring(name) then return z end
    end
    return nil
end

local function getTrainZoneNames()
    local list = { TRAIN_AUTO_BEST }
    for _, z in ipairs(TrainAreaConfig) do table.insert(list, z.Name) end
    return list
end

-- ─────────────────────────────────────────────────────────────
-- Dynamic Game Asset Discovery (Auto-updates with game patches)
-- ─────────────────────────────────────────────────────────────
local Dynamic = {
    Stages          = {},
    TrainAreas      = {},
    Classes         = {},
    Potions         = {},
    SuperLootTiers  = { "All", "Legendary", "Eternal", "Secret" },
}

pcall(function()
    local sh = require(ReplicatedStorage.Config.Stage.Helper)
    for k in pairs(sh.GetStageEnemyConfig()) do
        table.insert(Dynamic.Stages, k)
    end
    table.sort(Dynamic.Stages, function(a, b)
        local n1 = tonumber(a:match("%d+")) or 0
        local n2 = tonumber(b:match("%d+")) or 0
        return n1 < n2
    end)
end)
if #Dynamic.Stages == 0 then
    for i = 1, 30 do table.insert(Dynamic.Stages, "Stage_" .. i) end
end
table.insert(Dynamic.Stages, 1, "Auto Max (ด่านสูงสุดที่ผ่านได้)")

local State -- forward declaration (assigned below)
local function getTargetStageId()
    local selected = State.SelectedStage or "Auto Max"
    if selected:find("Auto Max") then
        local maxPass = 0
        pcall(function()
            local pd = ProfileData and ProfileData.GetTotalData and ProfileData.GetTotalData()
            maxPass = pd and pd.Stats and tonumber(pd.Stats.StagePass) or 0
        end)
        local targetNum = math.clamp(maxPass + 1, 1, math.max(#Dynamic.Stages - 1, 30))
        return "Stage_" .. tostring(targetNum), targetNum
    else
        local clean = selected:match("Stage_%d+") or selected
        local num = tonumber(clean:match("%d+")) or 1
        return clean, num
    end
end

pcall(function()
    local tah = require(ReplicatedStorage.Config.TrainArea.Helper)
    local count = 0
    for _ in pairs(tah.GetConfig()) do count = count + 1 end
    for i = 1, count do table.insert(Dynamic.TrainAreas, tostring(i)) end
end)
if #Dynamic.TrainAreas == 0 then
    for i = 1, 15 do table.insert(Dynamic.TrainAreas, tostring(i)) end
end

pcall(function()
    local ch = require(ReplicatedStorage.Config.Class.Helper)
    for k in pairs(ch.GetConfig()) do
        table.insert(Dynamic.Classes, k)
    end
    table.sort(Dynamic.Classes, function(a, b)
        local n1 = tonumber(a:match("%d+")) or 0
        local n2 = tonumber(b:match("%d+")) or 0
        return n1 < n2
    end)
end)
if #Dynamic.Classes == 0 then
    for i = 1, 9 do table.insert(Dynamic.Classes, "Class_" .. i) end
end

pcall(function()
    local ph = require(ReplicatedStorage.Config.Potion.Helper)
    for k in pairs(ph.GetConfig()) do
        table.insert(Dynamic.Potions, k)
    end
end)
if #Dynamic.Potions == 0 then
    Dynamic.Potions = { "DamagePotion", "TrainPotion", "CoinPotion", "LuckPotion", "HPPotion" }
end

pcall(function()
    local slh = require(ReplicatedStorage.Config.SuperLoot.Helper)
    for k in pairs(slh.GetConfig()) do
        if not table.find(Dynamic.SuperLootTiers, k) then
            table.insert(Dynamic.SuperLootTiers, k)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- Localization Engine (Thai Default / English Secondary)
-- ─────────────────────────────────────────────────────────────
local Locales = {
    TH = {
        -- Window & Meta
        WindowTitle = "NAPHUB",
        WindowSub   = "NAPHUB +1 LOOT A FORGE  /  PLAY MORE • WORK LESS",
        VersionTag  = "v4.9.2",
        LangName    = "ไทย (Thai)",

        -- Tab Titles
        Tab1  = "หน้าหลัก ระบบไก่ตัน",
        Tab2  = "ฟาร์มแร่ & ดูดของ",
        Tab3  = "ดันเจี้ยน & ไต่ด่าน",
        Tab4  = "สไนป์บอสแร่ยักษ์",
        Tab5  = "ฝึกพลัง & อัปเกรด",
        Tab6  = "หลอม & อุปกรณ์",
        Tab7  = "คลาส สกิล & สัตว์เลี้ยง",
        Tab8  = "รับรางวัล & โค้ดฟรี",
        Tab9  = "จุดวาร์ป & เซิร์ฟเวอร์",
        Tab10 = "แจ้งเตือน & ตั้งค่า",

        -- Status Texts
        StatusReady         = "ระบบพร้อมทำงาน",
        StatusPaused        = "หยุดการทำงานชั่วคราว",
        StatusSafeEvacuate  = "กำลังอพยพไปจุดปลอดภัย (%s)",
        StatusDungeonEnter  = "กำลังเข้าดันเจี้ยน รอบที่ %s",
        StatusDungeonWave   = "กำลังกำจัดมอนสเตอร์ในดันเจี้ยน",
        StatusStageEnter    = "กำลังเข้าสู่ด่านต่อสู้: %s",
        StatusStageFight    = "กำลังต่อสู้ในด่าน: %s",
        StatusSuperLootHunt = "กำลังล่าบอสแร่ยักษ์: %s",
        StatusTrain         = "กำลังฝึกพลัง (โซน %s)",
        StatusRollClass     = "กำลังสุ่มคลาส (ปัจจุบัน: %s)",

        -- Tab 1: Dashboard
        Sec_Master               = "ระบบไก่ตัน (Master AI)",
        Tgl_Master247            = "เปิดระบบไก่ตัน (ออโต้ฟาร์ม)",
        Desc_Master247           = "ลงดันเจี้ยนและด่าน เก็บของ แล้วค่อยอัปเกรดกับหลอม",
        Tgl_MasterDungeonTicket  = "เน้นลงดันเจี้ยนเมื่อมีตั๋ว",
        Desc_MasterDungeonTicket = "เข้าดันเจี้ยนเพื่อฟาร์มของรางวัลระดับสูงโดยอัตโนมัติเมื่อตรวจพบตั๋ว",
        Tgl_MasterTrainWhenIdle  = "สลับไปฝึกพลังเมื่อตั๋วหมด",
        Desc_MasterTrainWhenIdle = "หากตั๋วดันเจี้ยนหมด จะสลับไปยืนฝึกพลังอัตโนมัติเพื่อเพิ่มสเตตัส",
        Sec_Telemetry            = "ข้อมูลสถิติและการทำงานแบบเรียลไทม์",
        Card_SystemStatus        = "สถานะการทำงานปัจจุบัน",
        Card_SessionStats        = "สถิติการฟาร์มรอบนี้",
        Card_BagStats            = "ช่องเก็บของและพลังชีวิต",
        Sec_QuickActions         = "คำสั่งด่วน",
        Btn_EmergencyEvac        = "อพยพฉุกเฉินไปจุดปลอดภัย (Safe Zone)",
        Desc_EmergencyEvac       = "กดรับแร่ทั้งหมด วาร์ปกลับจุดเกิด และเทขายของทันทีเพื่อป้องกันของตกหาย",
        Btn_SellAllNow           = "ขายไอเทมในกระเป๋าทั้งหมดทันที",
        Btn_InstantMagnet        = "ดูดแร่และกดรับไอเทมรอบตัวทันที",

        -- Tab 2: Safe Loot & Magnet
        Sec_Magnet         = "ระบบดูดแร่อัจฉริยะ (Drop Magnet)",
        Tgl_DropMagnet     = "เปิดระบบดูดแร่และไอเทมดรอปอัตโนมัติ",
        Desc_DropMagnet    = "ย้ายของดรอปไปยังตำแหน่งที่เลือก",
        Drop_MagnetTarget  = "ตำแหน่งปลายทางที่ต้องการให้แร่วาร์ปไป",
        Desc_MagnetTarget  = "เลือกให้แร่วาร์ปไปที่โซนปลอดภัย (Safe Zone) หรือดูดเข้าตัวผู้เล่น",
        Opt_SafeZone       = "โซนปลอดภัย (Safe Zone)",
        Opt_ToPlayer       = "ดูดเข้าหาตัวผู้เล่น (To Player)",
        Sld_MagnetInterval = "ความถี่ในการดูดแร่ (วินาที)",
        Tgl_UltraPrompt    = "เปิดระบบกดรับไอเทมอัตโนมัติระยะไกล (Ultra Prompt)",
        Desc_UltraPrompt   = "กดรับ Prompt อัตโนมัติในระยะไกล",
        Sec_SafeEvac       = "ระบบความปลอดภัยและการป้องกันของหาย",
        Tgl_AutoSafeEvac   = "อพยพไปโซนปลอดภัยเมื่อกระเป๋าใกล้เต็ม",
        Desc_AutoSafeEvac  = "กลับจุดปลอดภัยและขายของเมื่อกระเป๋าใกล้เต็ม",
        Sld_EvacThreshold  = "ความจุสัมภาระขั้นต่ำสำหรับเริ่มอพยพ (%)",
        Tgl_LowHPEvac      = "หนีฉุกเฉินเมื่อเลือดเหลือน้อยวิกฤต",
        Desc_LowHPEvac     = "วาร์ปหนีกลับโซนปลอดภัยทันทีหากเลือดลดลงต่ำกว่ากำหนด",
        Sld_LowHPThreshold = "ระดับพลังชีวิตขั้นวิกฤตสำหรับหนี (%)",
        Sec_AutoSell       = "ระบบพ่อค้าขายของอัตโนมัติ",
        Tgl_AutoSell       = "เปิดระบบขายไอเทมในกระเป๋าอัตโนมัติ",
        Desc_AutoSell      = "ขายไอเทมเป็นเงินอย่างต่อเนื่องตามรอบเวลาที่กำหนด",
        Sld_SellDelay      = "ระยะเวลารอบการขาย (วินาที)",

        -- Tab 3: Dungeon & Stages
        Sec_Dungeon       = "ระบบฟาร์มดันเจี้ยนอัตโนมัติ",
        Tgl_AutoDungeon   = "เปิดระบบฟาร์มดันเจี้ยน",
        Desc_AutoDungeon  = "ลงรอบที่เลือกและเคลียร์เวฟอัตโนมัติ",
        Sld_DungeonRound  = "เลือกรอบดันเจี้ยนที่ต้องการลง",
        Tgl_ClaimTicket   = "กดรับตั๋วดันเจี้ยนฟรีรายวันอัตโนมัติ",
        Sec_Stage         = "ระบบตะลุยด่านและไต่ระดับต่อเนื่อง",
        Drop_Stage        = "เลือกด่านต่อสู้เป้าหมาย (ดึงค่าอัตโนมัติ)",
        Desc_Stage        = "รายชื่อด่านจากข้อมูลเกม",
        Tgl_AutoStage     = "เปิดฟาร์มด่านที่เลือกอัตโนมัติ",
        Desc_AutoStage    = "ลงด่านที่เลือกและเก็บของ",
        Tgl_ClimbStages   = "เปิดระบบไต่ด่านอัตโนมัติแบบต่อเนื่อง (Auto Climb)",
        Desc_ClimbStages  = "ผ่านแล้วขยับขึ้น; ใช้เวลาเกินกำหนดให้ถอย",
        Sld_ClimbTimeout  = "ระยะเวลาจำกัดการเคลียร์ด่าน (วินาที)",
        Desc_ClimbTimeout = "หากตีมอนสเตอร์ในด่านไม่หมดภายในเวลานี้ ระบบจะถอยกลับไปด่านก่อนหน้าทันที",
        Sec_Combat        = "ระบบโจมตีและการป้องกันตัว",
        Tgl_KillAura      = "เปิดระบบคิลออร่า (Kill Aura โจมตีรอบตัวอัตโนมัติ)",
        Desc_KillAura     = "ส่งคำสั่งโจมตีมอนสเตอร์ทุกตัวในแมพพร้อมกันทันทีผ่านระบบภายในเกม",
        Sld_KillAuraDelay = "ความเร็วในการโจมตี (วินาที)",
        Tgl_SafeFlight    = "เปิดโหมดบินลอยฟ้าหลบการโจมตี (Safe Flight)",
        Desc_SafeFlight   = "ลอยตัวเหนือระยะโจมตีประชิดของมอนสเตอร์ เพื่อหลบความเสียหาย",
        Sld_FlightHeight  = "ระดับความสูงในการลอยตัว (Studs)",
        Tgl_GodMode       = "เปิดโหมดอมตะ (God Mode ป้องกันเลือดลด)",
        Desc_GodMode      = "ตั้งค่าสถานะอมตะและฟื้นฟูเลือดให้เต็มตลอดเวลาอย่างต่อเนื่อง",

        -- Tab 4: Boss Hunter
        Sec_BossHunter = "ระบบสไนป์บอสแร่ยักษ์ข้ามแมพ (Super Loot Hunter)",
        Tgl_BossHunter = "เปิดระบบตรวจจับและสไนป์บอสแร่ยักษ์อัตโนมัติ",
        Desc_BossHunter = "ค้นหาและเข้าต่อสู้กับบอสแร่ยักษ์",
        Drop_BossTier  = "เลือกระดับความหายากของบอสที่ต้องการล่า (ดึงอัตโนมัติ)",
        Desc_BossTier  = "เลือกเจาะจงระดับบอสแร่ยักษ์ที่ต้องการ หรือล่าทุกระดับ",
        Tgl_BossNotify = "แจ้งเตือนผ่าน Discord เมื่อเจอบอสแร่ยักษ์",
        Btn_ScanBoss   = "สแกนหาและวาร์ปไปจัดการบอสทันที",

        -- Tab 5: Train & Upgrades
        Sec_Train           = "ระบบฝึกซ้อมพลัง (Power Training)",
        Drop_TrainArea      = "เลือกโซนฝึกพลัง (ดึงค่าอัตโนมัติ)",
        Desc_TrainArea      = "รายชื่อโซนฝึกจากข้อมูลเกม",
        Tgl_AutoTrain       = "เปิดฝึกพลังอัตโนมัติตามรอบเวลา",
        Desc_AutoTrain      = "ส่งคำสั่งฝึกพลังอย่างรวดเร็วตามความเร็วที่ตั้งไว้",
        Sld_TrainDelay      = "ระยะเวลาฝึกพลังต่อครั้ง (วินาที)",
        Tgl_NativeAutoTrain = "เปิดโหมดฝึกพลังอัตโนมัติของตัวเกม (Native Mode)",
        Desc_NativeAutoTrain= "เปิด/ปิดฟังชั่น Auto Train ในระบบของตัวเกมเอง",
        Sec_Upgrade         = "ระบบอัปเกรดค่าสถานะอัตโนมัติ",
        Drop_UpgradeType    = "เลือกหมวดหมู่อัปเกรด",
        Desc_UpgradeType    = "เลือกอัปเกรดสถานะเจาะจง หรือเลือก All in One เพื่ออัปเกรดทั้งหมด",
        Opt_UpgradeAll      = "อัปเกรดทั้งหมด (All in One)",
        Tgl_AutoUpgrade     = "เปิดอัปเกรดสถานะอัตโนมัติเมื่อเงินพอ",
        Desc_AutoUpgrade    = "ซื้ออัปเกรดเมื่อเงินถึง",
        Sld_UpgradeDelay    = "รอบเวลาตรวจสอบการอัปเกรด (วินาที)",
        Sec_Rebirth         = "ระบบเกิดใหม่ (Rebirth Progression)",
        Tgl_AutoRebirth     = "เปิดระบบเกิดใหม่อัตโนมัติ (Auto Rebirth)",
        Desc_AutoRebirth    = "ส่งคำสั่งเกิดใหม่ทันทีเมื่อสเตตัสถึงเกณฑ์ที่เกมกำหนด",
        Sld_RebirthDelay    = "รอบเวลาตรวจสอบการเกิดใหม่ (วินาที)",
        Tgl_NativeRebirth   = "เปิดโหมด Auto Rebirth ภายในตัวเกม",

        -- Tab 6: Forge & Equipment
        Sec_Forge      = "ระบบหลอมอุปกรณ์ (Equipment Forge)",
        Tgl_AutoForge  = "เปิดหลอมอุปกรณ์อัตโนมัติ",
        Desc_AutoForge = "สร้างอุปกรณ์ใหม่จากแร่และวัตถุดิบที่ฟาร์มได้ทันทีอย่างต่อเนื่อง",
        Drop_ForgeType = "ชนิดอุปกรณ์ที่จะหลอม",
        Drop_OreQuality = "ลำดับการใช้แร่",
        Sld_MinOres = "จำนวนแร่ขั้นต่ำ / เป้าหมาย",
        Btn_EquipBest = "สวมใส่อุปกรณ์ที่ดีที่สุด",
        ForgeTypeAll = "หมุนเวียนครบชุด",
        ForgeTypeWeapon = "อาวุธ / ดาบ",
        ForgeTypeArmor = "เกราะ",
        ForgeTypeHat = "หมวก",
        OreQualityAny = "ไม่เรียงลำดับ",
        OreQualityHigh = "ใช้แร่เกรดสูงก่อน",
        OreQualityLow = "ใช้แร่เกรดต่ำก่อน",
        Sld_ForgeDelay = "ความเร็วในการหลอม (วินาที)",
        Btn_ForgeOnce  = "กดหลอมอุปกรณ์ 1 ครั้งทันที",
        Sec_AstralSpawner = "เสกไอเทมเทพ (Astral Server Spawner)",
        Btn_SpawnApocalypse = "เสกเซ็ต Apocalypse (Chaoseater + War's Horn)",
        Desc_SpawnApocalypse = "เสกดาบ Chaoseater (K_1101), หมวก War's Horn (HHat_1101), เกราะ Apocalypse (HArmor_1101) ผ่าน Dev Remote",
        Btn_SpawnTriWyrm = "เสกเซ็ต The Tri-Wyrm (มังกร 3 หัว)",
        Desc_SpawnTriWyrm = "เสกดาบ Tri-Wyrm (K_1001), หมวก (HHat_1001), เกราะ (HArmor_1001) ผ่าน Dev Remote",
        Btn_SpawnCataclysm = "เสกเซ็ต Cataclysm (หายนะ ครา)",
        Desc_SpawnCataclysm = "เสกดาบ Cataclysm (K_1002), หมวก (HHat_1002), เกราะ (HArmor_1002) ผ่าน Dev Remote",
        Btn_SpawnVoidOverlord = "เสกเซ็ต Void Overlord (เซ็ตวอยด์สูงสุด)",
        Desc_SpawnVoidOverlord = "เสกดาบ Infinite (K_26), หมวก Eternal (LHat_16), เกราะ Eternal (LArmor_16) ผ่าน Dev Remote",
        Btn_SpawnApexOres = "เสกแร่เอเพ็กซ์ The Apex x10 (Server Inject)",
        Desc_SpawnApexOres = "เสกแร่ The Apex (Ore_48) 10 ก้อนเข้ากระเป๋าตรงจากเซิร์ฟเวอร์",
        Btn_SpawnRunes = "เสกหินรูนระดับ 3 ทั้งหมด (Runes III)",
        Desc_SpawnRunes = "เสก Poison III, Frost III, Fire III, Thunder III ผ่าน Dev Remote",
        Sec_EmberStone = "เสก Ember Stone (เซฟลง Server DataStore 100%)",
        Desc_EmberSection = "ปั้มหินอัปเกรดอาวุธระดับสูง เพิ่มเข้ากระเป๋าจริง ออกเข้าใหม่ไม่หาย",
        Btn_EmberStone = "เสก Ember Stone (+5,000 ก้อน / คลิกเดียว)",
        Desc_EmberStone = "ปั้ม Ember Stone จำนวน 5,000 ก้อน เซฟถาวร 100%",
        Tgl_SpoofMaterials = "บัคเสกวัสดุ 150Dd (Visual Flex Spoofer)",
        Desc_SpoofMaterials = "ปรับจำนวนม้วนป้องกัน, หินปริซึม, ตั๋วทาวเวอร์, หินเอมเบอร์ เป็น 150Dd ตามภาพ",
        Sec_Enhance    = "ระบบสวมใส่ ตีบวก และลงอักขระ",
        Tgl_EquipBest  = "เปิดสวมใส่อุปกรณ์ที่ดีที่สุดอัตโนมัติ",
        Desc_EquipBest = "สวมใส่อุปกรณ์ที่ค่าสูงสุด",
        Tgl_AutoEnhance= "เปิดตีบวกอุปกรณ์ที่สวมใส่อัตโนมัติ",
        Desc_AutoEnhance= "อัปเกรดเลเวลของอุปกรณ์ที่สวมใส่อยู่อย่างต่อเนื่อง",
        Tgl_AutoEnchant= "เปิดลงอักขระ (Enchant) อุปกรณ์อัตโนมัติ",
        Btn_UnequipAll = "ถอดอุปกรณ์ทั้งหมดและล้างอักขระ",

        -- Tab 7: Class, Skills & Pets
        Sec_Class          = "ระบบสุ่มคลาสและล็อคเป้าหมายอัตโนมัติ",
        Drop_TargetClass   = "เลือกคลาสเป้าหมายที่ต้องการล็อค (ดึงอัตโนมัติ)",
        Desc_TargetClass   = "สุ่มคลาสไปเรื่อยๆ จนกว่าจะได้คลาสนี้ จากนั้นจะล็อคและสวมใส่ให้อัตโนมัติ",
        Tgl_RollClass      = "เปิดระบบสุ่มคลาสอัตโนมัติ (จนกว่าจะได้เป้าหมาย)",
        Desc_RollClass     = "สุ่มคลาสต่อเนื่องและหยุดทันทีเมื่อได้คลาสที่ตั้งค่าไว้",
        Sld_RollClassDelay = "ความเร็วในการสุ่มคลาส (วินาที)",
        Tgl_RollSkills     = "เปิดระบบสุ่มสกิลและพาสซีฟติดตัวอัตโนมัติ",
        Desc_RollSkills    = "สุ่มช่องสกิลเพื่อเพิ่มโบนัสพลังโจมตีและความสามารถพิเศษ",
        Sec_Pets           = "ระบบสัตว์เลี้ยงและน้ำยาบัฟ",
        Tgl_AutoPotions    = "เปิดดื่มน้ำยาบัฟอัตโนมัติเมื่อบัฟหมด",
        Desc_AutoPotions   = "ตรวจจับและดื่มน้ำยาบัฟพลัง, ฝึก, เงิน และโชคดีอัตโนมัติ",
        Tgl_AutoHatch      = "เปิดระบบฟักไข่สัตว์เลี้ยงอัตโนมัติ (Auto Hatch Eggs)",
        Desc_AutoHatch     = "ส่งคำสั่งเปิดฟักไข่สัตว์เลี้ยงเพื่อรับสัตว์เลี้ยงใหม่ต่อเนื่อง",

        -- Tab 8: Rewards & Codes
        Sec_Rewards    = "ระบบกดรับของรางวัลฟรีอัตโนมัติ",
        Tgl_AutoClaim  = "เปิดกดรับของรางวัลฟรีทั้งหมดตลอด 24 ชม.",
        Desc_AutoClaim = "รับรางวัลออฟไลน์ ออนไลน์ ดันเจี้ยน และเควส",
        Sld_ClaimDelay = "รอบเวลากดรับรางวัล (วินาที)",
        Btn_ClaimAllNow= "กดรับของรางวัลทุกหมวดหมู่ทันที",
        Sec_Codes      = "ระบบกรอกโค้ดรับไอเทม",
        Input_Code     = "กรอกโค้ดไอเทมที่นี่...",
        Btn_SubmitCode = "ยืนยันการใช้โค้ด",
        Btn_BatchCodes = "กดรับโค้ดแจกฟรียอดนิยมทั้งหมดในคลิกเดียว",

        -- Tab 9: Teleports & Server
        Sec_Locations = "จุดวาร์ปสำคัญ",
        Btn_TpSafeZone= "วาร์ปไปโซนปลอดภัย (จุดเกิด Spawn)",
        Btn_TpTrainMap= "วาร์ปไปพื้นที่ฝึกพลัง (Train Map)",
        Btn_TpDungeon = "วาร์ปไปทางเข้าดันเจี้ยน (Dungeon)",
        Btn_SavePos   = "บันทึกพิกัดตำแหน่งปัจจุบัน",
        Btn_LoadPos   = "วาร์ปกลับไปยังพิกัดที่บันทึกไว้",
        Sec_Server    = "จัดการเซิร์ฟเวอร์",
        Btn_Rejoin    = "เชื่อมต่อเข้าเซิร์ฟเวอร์เดิมใหม่อีกครั้ง (Rejoin)",
        Btn_ServerHop = "ย้ายไปเซิร์ฟเวอร์ใหม่ (คนน้อยที่สุด)",
        Btn_CopyJobId = "คัดลอกรหัสเซิร์ฟเวอร์ (JobId) ลงคลิปบอร์ด",

        -- Tab 10: Webhook & Settings
        Sec_Webhook      = "ระบบแจ้งเตือนผ่าน Discord Webhook",
        Tgl_Webhook      = "เปิดการแจ้งเตือนผ่าน Discord Webhook",
        Input_Webhook    = "วางลิงก์ Discord Webhook URL ที่นี่...",
        Tgl_NotifyRare   = "แจ้งเตือนเมื่อดรอปได้ไอเทมหายากระดับสูง (Mythic+)",
        Tgl_NotifyHourly = "ส่งรายงานสถิติการฟาร์มสรุปผลทุก 1 ชั่วโมง",
        Tgl_NotifyRebirth= "แจ้งเตือนเมื่อเกิดใหม่สำเร็จ (Rebirth Milestone)",
        Btn_TestWebhook  = "ส่งข้อความทดสอบไปยัง Discord Webhook",
        Sec_Player       = "ปรับแต่งความสามารถตัวละคร",
        Sld_WalkSpeed    = "ปรับความเร็วการเดิน (WalkSpeed)",
        Sld_JumpPower    = "ปรับระยะกระโดดสูง (JumpPower)",
        Tgl_InfJump      = "กระโดดได้ไม่จำกัด (Infinite Jump)",
        Tgl_Noclip       = "เดินทะลุกำแพงและสิ่งกีดขวาง (Noclip)",
        Tgl_AntiAFK      = "ระบบป้องกันการหลุดจากการอยู่เฉยๆ (Anti-AFK ระบบไก่ตัน)",
        Sec_Optimize     = "ลดการใช้ทรัพยากรเครื่อง",
        Tgl_CpuSaver     = "โหมดประหยัด CPU/GPU (ปิดภาพ 3D และจำกัด 15 FPS สำหรับเปิดบอทข้ามคืน)",
        Sec_Config       = "จัดการบันทึกการตั้งค่า",
        Btn_SaveConfig   = "บันทึกการตั้งค่าปัจจุบันลงเครื่อง",
        Btn_LoadConfig   = "โหลดการตั้งค่าที่บันทึกไว้",
        Tgl_AutoSave     = "บันทึกการตั้งค่าลงเครื่องอัตโนมัติเมื่อมีการเปลี่ยนแปลง",
        Sec_Interface    = "ตั้งค่าหน้าต่างโปรแกรมและภาษา",
        Drop_Language    = "เลือกภาษา / Language",
        Desc_Language    = "เปลี่ยนภาษาระหว่าง ภาษาไทย และ English (สลับทันที)",
        Drop_Theme       = "เลือกธีมสีหน้าต่าง UI",
        Tgl_Transparency = "ความโปร่งใสแบบกระจก (Glass Transparency)",
        Btn_DestroyUI    = "ปิดสคริปต์ หยุดการทำงานทั้งหมด และลบหน้าต่าง UI",

        -- Notifications & Alerts
        Notif_MasterEngaged   = "เปิดระบบไก่ตันเรียบร้อยแล้ว",
        Notif_SafeZoneSecured = "จัดเก็บไอเทมเข้าโซนปลอดภัยเรียบร้อยแล้ว",
        Notif_SellExecuted    = "ส่งคำสั่งขายไอเทมในกระเป๋าเรียบร้อยแล้ว",
        Notif_MagnetCollected = "ดูดและจัดเก็บแร่รอบตัวเรียบร้อยแล้ว",
        Notif_BossAcquired    = "ตรวจพบบอสแร่ยักษ์ระดับ: %s",
        Notif_StageAdvance    = "ไต่ระดับขึ้นสู่ %s เรียบร้อยแล้ว",
        Notif_StageRetreat    = "ดาเมจไม่พอถอยกลับไป %s เพื่อความปลอดภัย",
        Notif_ClassLocked     = "สุ่มได้คลาสเป้าหมายและล็อคสำเร็จ: %s",
        Notif_LangSwitched    = "เปลี่ยนภาษาเป็น ภาษาไทย เรียบร้อยแล้ว",
        Notif_ConfigSaved     = "บันทึกการตั้งค่าลงเครื่องเรียบร้อยแล้ว",
        Notif_ConfigLoaded    = "โหลดการตั้งค่าจากเครื่องเรียบร้อยแล้ว",
    },
    EN = {
        -- Window & Meta
        WindowTitle = "NAPHUB +1 LOOT A FORGE",
        WindowSub   = "FORGE YOUR LOOT  /  PLAY MORE • WORK LESS",
        VersionTag  = "v4.9.2",
        LangName    = "English (EN)",

        -- Tab Titles
        Tab1  = "Dashboard ระบบไก่ตัน",
        Tab2  = "Safe Loot & Magnet",
        Tab3  = "Dungeon & Stages",
        Tab4  = "Boss Hunter",
        Tab5  = "Train & Upgrades",
        Tab6  = "Forge & Equipment",
        Tab7  = "Class, Skills & Pets",
        Tab8  = "Rewards & Codes",
        Tab9  = "Teleports & Server",
        Tab10 = "Webhook & Settings",

        -- Status Texts
        StatusReady         = "System Ready",
        StatusPaused        = "Automation Paused",
        StatusSafeEvacuate  = "Evacuating to Safe Zone (%s)",
        StatusDungeonEnter  = "Entering Dungeon Round %s",
        StatusDungeonWave   = "Clearing Dungeon Wave",
        StatusStageEnter    = "Entering Battle Stage: %s",
        StatusStageFight    = "Engaging %s",
        StatusSuperLootHunt = "Hunting Super Loot: %s",
        StatusTrain         = "Power Training (Zone %s)",
        StatusRollClass     = "Rolling Class (Current: %s)",

        -- Tab 1: Dashboard
        Sec_Master               = "ระบบไก่ตัน (Master AI)",
        Tgl_Master247            = "ระบบไก่ตัน (Master Automation)",
        Desc_Master247           = "Farm dungeons and stages first; upgrade and forge as resources allow",
        Tgl_MasterDungeonTicket  = "Prioritize Dungeon on Available Tickets",
        Desc_MasterDungeonTicket = "Automatically enter high-reward Dungeon rounds when tickets are present",
        Tgl_MasterTrainWhenIdle  = "Train Power when Out of Tickets",
        Desc_MasterTrainWhenIdle = "Fallback to train zone for stat boosts when dungeon tickets are exhausted",
        Sec_Telemetry            = "Live Telemetry & Statistics",
        Card_SystemStatus        = "System Status",
        Card_SessionStats        = "Session Telemetry",
        Card_BagStats            = "Inventory & Vitality",
        Sec_QuickActions         = "Quick Execution",
        Btn_EmergencyEvac        = "Emergency Evacuate to Safe Zone",
        Desc_EmergencyEvac       = "Secure all pending ores, teleport to Spawn, and liquidate inventory",
        Btn_SellAllNow           = "Sell All Inventory Now",
        Btn_InstantMagnet        = "Instant Drop Magnet & Sweep",

        -- Tab 2: Safe Loot & Magnet
        Sec_Magnet         = "Drop Magnet System",
        Tgl_DropMagnet     = "Auto Drop Magnet",
        Desc_DropMagnet    = "Move drops to the selected destination",
        Drop_MagnetTarget  = "Magnet Destination Target",
        Desc_MagnetTarget  = "Select destination coordinates for dropped items",
        Opt_SafeZone       = "Safe Zone",
        Opt_ToPlayer       = "To Player",
        Sld_MagnetInterval = "Magnet Sweep Interval (Seconds)",
        Tgl_UltraPrompt    = "Ultra Proximity Prompt Trigger",
        Desc_UltraPrompt   = "Trigger nearby item prompts automatically",
        Sec_SafeEvac       = "Safe Zone Evacuation & Protection",
        Tgl_AutoSafeEvac   = "Auto Evacuate on Full Backpack",
        Desc_AutoSafeEvac  = "Return to safety and sell when the bag is nearly full",
        Sld_EvacThreshold  = "Backpack Full Evacuation Threshold (%)",
        Tgl_LowHPEvac      = "Emergency Evacuate on Low Health",
        Desc_LowHPEvac     = "Escape to Safe Zone immediately if health drops below critical threshold",
        Sld_LowHPThreshold = "Critical Health Threshold (%)",
        Sec_AutoSell       = "Automated Merchant (Auto Sell)",
        Tgl_AutoSell       = "Auto Sell All Inventory",
        Desc_AutoSell      = "Periodically liquidate inventory for maximum currency generation",
        Sld_SellDelay      = "Auto Sell Interval (Seconds)",

        -- Tab 3: Dungeon & Stages
        Sec_Dungeon       = "Dungeon Automation",
        Tgl_AutoDungeon   = "Auto Farm Dungeon",
        Desc_AutoDungeon  = "Enter the selected round and clear its waves",
        Sld_DungeonRound  = "Target Dungeon Round",
        Tgl_ClaimTicket   = "Auto Claim Daily Dungeon Ticket",
        Sec_Stage         = "Stage Progression & Climbing",
        Drop_Stage        = "Target Combat Stage (Auto-Discovered)",
        Desc_Stage        = "Stages discovered from game data",
        Tgl_AutoStage     = "Auto Farm Selected Stage",
        Desc_AutoStage    = "Farm the selected stage and collect loot",
        Tgl_ClimbStages   = "Auto Stage Climbing (Progressive)",
        Desc_ClimbStages  = "Advance on clear; retreat when the time limit is reached",
        Sld_ClimbTimeout  = "Stage Clearance Timeout (Seconds)",
        Desc_ClimbTimeout = "Retreat to previous stage if current wave takes longer than this duration",
        Sec_Combat        = "Combat Engine & Protection",
        Tgl_KillAura      = "Kill Aura (Automated Combat)",
        Desc_KillAura     = "Eliminate all active monsters instantly through internal BindableEvents",
        Sld_KillAuraDelay = "Kill Aura Rate (Seconds)",
        Tgl_SafeFlight    = "Safe Combat Flight",
        Desc_SafeFlight   = "Hover above monster melee strike range to avoid taking ground damage",
        Sld_FlightHeight  = "Flight Hover Altitude (Studs)",
        Tgl_GodMode       = "God Mode (Invincibility & Full HP)",
        Desc_GodMode      = "Enforce Invincible attribute and restore maximum HP continuously",

        -- Tab 4: Boss Hunter
        Sec_BossHunter = "Super Loot Autonomous Sniper",
        Tgl_BossHunter = "Enable Super Loot Boss Hunter",
        Desc_BossHunter = "Search for and engage Super Loot bosses",
        Drop_BossTier  = "Target Super Loot Tier (Auto-Discovered)",
        Desc_BossTier  = "Filter which tier of Super Loot boss to intercept",
        Tgl_BossNotify = "Discord Alert on Super Loot Intercept",
        Btn_ScanBoss   = "Manual Scan & Intercept Boss Now",

        -- Tab 5: Train & Upgrades
        Sec_Train           = "Power Training",
        Drop_TrainArea      = "Target Train Area (Auto-Discovered)",
        Desc_TrainArea      = "Training zones discovered from game data",
        Tgl_AutoTrain       = "Auto Train Power",
        Desc_AutoTrain      = "Execute TrainOnceRE rapidly based on configured interval",
        Sld_TrainDelay      = "Training Delay (Seconds)",
        Tgl_NativeAutoTrain = "Native Game Auto Train Mode",
        Desc_NativeAutoTrain= "Toggle internal game Auto Train mode",
        Sec_Upgrade         = "Attribute Upgrades",
        Drop_UpgradeType    = "Upgrade Category",
        Desc_UpgradeType    = "Select specific stat to upgrade or All in One for full progression",
        Opt_UpgradeAll      = "All in One",
        Tgl_AutoUpgrade     = "Auto Upgrade Attributes",
        Desc_AutoUpgrade    = "Buy upgrades when funds are available",
        Sld_UpgradeDelay    = "Upgrade Cycle Delay (Seconds)",
        Sec_Rebirth         = "Rebirth Progression",
        Tgl_AutoRebirth     = "Auto Rebirth (Autonomous)",
        Desc_AutoRebirth    = "Execute Rebirth automatically upon reaching requirements",
        Sld_RebirthDelay    = "Rebirth Check Interval (Seconds)",
        Tgl_NativeRebirth   = "Native Game Auto Rebirth",

        -- Tab 6: Forge & Equipment
        Sec_Forge      = "Equipment Forging",
        Tgl_AutoForge  = "Auto Forge Equipment",
        Desc_AutoForge = "Craft new equipment automatically from gathered materials",
        Drop_ForgeType = "Equipment to forge",
        Drop_OreQuality = "Ore selection order",
        Sld_MinOres = "Minimum / target ore count",
        Btn_EquipBest = "Equip best available gear",
        ForgeTypeAll = "Rotate full set",
        ForgeTypeWeapon = "Weapon",
        ForgeTypeArmor = "Armor",
        ForgeTypeHat = "Hat",
        OreQualityAny = "No sorting",
        OreQualityHigh = "Highest grade first",
        OreQualityLow = "Lowest grade first",
        Sld_ForgeDelay = "Forging Delay (Seconds)",
        Btn_ForgeOnce  = "Forge Once Immediately",
        Sec_AstralSpawner = "Astral Server Spawner & Injection",
        Btn_SpawnApocalypse = "Spawn Apocalypse Set (Chaoseater + War's Horn)",
        Desc_SpawnApocalypse = "Inject Chaoseater (K_1101), War's Horn (HHat_1101), Apocalypse (HArmor_1101) via Dev Remote",
        Btn_SpawnTriWyrm = "Spawn The Tri-Wyrm Set",
        Desc_SpawnTriWyrm = "Inject Tri-Wyrm Katana (K_1001), Hat (HHat_1001), Armor (HArmor_1001) via Dev Remote",
        Btn_SpawnCataclysm = "Spawn Cataclysm Set",
        Desc_SpawnCataclysm = "Inject Cataclysm Blade (K_1002), Hat (HHat_1002), Armor (HArmor_1002) via Dev Remote",
        Btn_SpawnVoidOverlord = "Spawn Void Overlord Set",
        Desc_SpawnVoidOverlord = "Inject Infinite Blade (K_26), Hat (LHat_16), Armor (LArmor_16) via Dev Remote",
        Btn_SpawnApexOres = "Spawn Apex Ore x10 (Server Inject)",
        Desc_SpawnApexOres = "Directly inject 10 Apex Ores (Ore_48) into inventory via Dev Remote",
        Btn_SpawnRunes = "Spawn All Tier 3 Runes",
        Desc_SpawnRunes = "Inject Poison III, Frost III, Fire III, Thunder III via Dev Remote",
        Sec_EmberStone = "Spawn Ember Stone (Server DataStore saved)",
        Desc_EmberSection = "Pump high-tier weapon upgrade stones into the real backpack, persists after rejoin",
        Btn_EmberStone = "Spawn Ember Stone (+5,000 / one click)",
        Desc_EmberStone = "Pump 5,000 Ember Stone, saved permanently",
        Tgl_SpoofMaterials = "150Dd Material Spoofer (Flex Mode)",
        Desc_SpoofMaterials = "Spoof Protection Scrolls, Prismatic Stones, Tower Tickets to 150Dd as shown in screenshots",
        Sec_Enhance    = "Enhancement & Enchantment",
        Tgl_EquipBest  = "Auto Equip Best Equipment",
        Desc_EquipBest = "Equip the highest-scoring gear",
        Tgl_AutoEnhance= "Auto Enhance Equipment",
        Desc_AutoEnhance= "Upgrade equipped gear level automatically",
        Tgl_AutoEnchant= "Auto Enchant Equipment",
        Btn_UnequipAll = "Unequip All & Remove Enchants",

        -- Tab 7: Class, Skills & Pets
        Sec_Class          = "Class Gacha & Auto-Lock",
        Drop_TargetClass   = "Target Class to Obtain (Auto-Discovered)",
        Desc_TargetClass   = "Rolls class until this target class is acquired, then locks and equips it",
        Tgl_RollClass      = "Auto Roll Class (Target Lock)",
        Desc_RollClass     = "Rolls for class continuously until target class is obtained",
        Sld_RollClassDelay = "Class Roll Delay (Seconds)",
        Tgl_RollSkills     = "Auto Roll Skill Cells",
        Desc_RollSkills    = "Execute skill cell gacha for bonus damage and passives",
        Sec_Pets           = "Potions & Egg Hatching",
        Tgl_AutoPotions    = "Auto Consume Buff Potions",
        Desc_AutoPotions   = "Monitors active buffs and drinks Damage, Train, Coin, and Luck potions when expired",
        Tgl_AutoHatch      = "Auto Open / Hatch Eggs",
        Desc_AutoHatch     = "Automatically submits PutEgg requests to hatch pets",

        -- Tab 8: Rewards & Codes
        Sec_Rewards    = "Automated Reward Claims",
        Tgl_AutoClaim  = "Auto Claim All Free Rewards ระบบไก่ตัน",
        Desc_AutoClaim = "Claim offline, online, dungeon, and quest rewards",
        Sld_ClaimDelay = "Reward Claim Interval (Seconds)",
        Btn_ClaimAllNow= "Claim All Available Rewards Now",
        Sec_Codes      = "Promotional Redemption",
        Input_Code     = "Enter code here...",
        Btn_SubmitCode = "Submit Code",
        Btn_BatchCodes = "Batch Redeem Known Promo Codes",

        -- Tab 9: Teleports & Server
        Sec_Locations = "Key Locations",
        Btn_TpSafeZone= "Teleport to Safe Zone (Spawn)",
        Btn_TpTrainMap= "Teleport to Train Map",
        Btn_TpDungeon = "Teleport to Dungeon Entrance",
        Btn_SavePos   = "Save Current Position",
        Btn_LoadPos   = "Return to Saved Position",
        Sec_Server    = "Server Operations",
        Btn_Rejoin    = "Rejoin Current Server",
        Btn_ServerHop = "Server Hop (Low Player Count)",
        Btn_CopyJobId = "Copy Server JobId",

        -- Tab 10: Webhook & Settings
        Sec_Webhook      = "Discord Webhook Integration",
        Tgl_Webhook      = "Enable Discord Webhook Notifications",
        Input_Webhook    = "Enter Discord Webhook URL...",
        Tgl_NotifyRare   = "Notify Rare Item Drops (Mythic+)",
        Tgl_NotifyHourly = "Hourly Session Telemetry Report",
        Tgl_NotifyRebirth= "Notify Rebirth Milestones",
        Btn_TestWebhook  = "Send Webhook Test Payload",
        Sec_Player       = "Player Modifications",
        Sld_WalkSpeed    = "WalkSpeed Modifier",
        Sld_JumpPower    = "JumpPower Modifier",
        Tgl_InfJump      = "Infinite Jump",
        Tgl_Noclip       = "Noclip Collision Bypass",
        Tgl_AntiAFK      = "Anti-AFK Protection (ระบบไก่ตัน Disconnect Bypass)",
        Sec_Optimize     = "Resource Optimization",
        Tgl_CpuSaver     = "Low CPU / GPU Saver Mode (3D disabled, 15 FPS)",
        Sec_Config       = "Configuration Management",
        Btn_SaveConfig   = "Save Configuration",
        Btn_LoadConfig   = "Load Configuration",
        Tgl_AutoSave     = "Auto-Save State upon Change",
        Sec_Interface    = "Interface & Language",
        Drop_Language    = "Language / ภาษา",
        Desc_Language    = "Switch language between ภาษาไทย and English",
        Drop_Theme       = "Theme Palette",
        Tgl_Transparency = "Glass Transparency",
        Btn_DestroyUI    = "Terminate Engine & Destroy UI",

        -- Notifications & Alerts
        Notif_MasterEngaged   = "Master autonomous automation engaged",
        Notif_SafeZoneSecured = "Secured inventory at Safe Zone successfully",
        Notif_SellExecuted    = "Executed Sell All command",
        Notif_MagnetCollected = "Collected surrounding drops",
        Notif_BossAcquired    = "Target acquired: %s Super Loot",
        Notif_StageAdvance    = "Progressed to %s",
        Notif_StageRetreat    = "Damage ceiling reached. Dropping back to %s",
        Notif_ClassLocked     = "Target class obtained and locked: %s",
        Notif_LangSwitched    = "Language switched to English",
        Notif_ConfigSaved     = "Configuration persisted to disk",
        Notif_ConfigLoaded    = "Configuration restored successfully",
    }
}

-- ─────────────────────────────────────────────────────────────
-- Global State (Fully Persistent ระบบไก่ตัน Engine)
-- ─────────────────────────────────────────────────────────────
State = {
    -- Language (Thai Default)
    Language            = "TH",

    -- Master ระบบไก่ตัน AI Engine
    Master247           = false,
    MasterDungeonTicket = true,
    MasterTrainWhenIdle = true,
    MasterAutoForgeWhenReady = true,  -- forge only when ore threshold met
    MasterAutoUpgrade   = true,       -- upgrade automatically in background
    MasterStageBlitz    = true,       -- use Fast Pipeline (GOD-Farm) in Master Loop
    MasterAutoClickSword = true,      -- continuously accumulate sword power in background
    AlgorithmicDPSSolver = true,      -- solve theoretical DPS matrix & auto-equip best synergy

    -- Safe Loot & Magnet
    DropMagnet          = false,
    MagnetTarget        = "Safe Zone", -- "Safe Zone" or "To Player"
    MagnetInterval      = 0.15,
    UltraPrompt         = false,
    AutoSafeEvacuate    = false,
    EvacuateThreshold   = 90,
    LowHPEvacuate       = false,
    LowHPThreshold      = 25,

    -- Combat & Dungeon
    AutoDungeon         = false,
    DungeonRound        = 1,
    AutoClaimTicket     = true,
    DungeonInstaKill    = true,   -- ← INSTANT KILL dungeon mobs (from reference pattern)
    AutoStage           = false,
    SelectedStage       = Dynamic.Stages[1] or "Stage_1",
    AutoClimbStages     = false,  -- Progressive stage climbing
    StageClimbTimeout   = 25,     -- Retreat if stage not cleared within seconds
    StageInstaKill      = true,   -- ← INSTANT KILL stage mobs
    AutoTrainBestZone   = false,  -- ← Teleport to highest unlocked multiplier zone
    GodFarmStageBlitz   = false,  -- ★ GOD-Farm: Fast Pipeline 0.08–0.1s
    StageBlitzInterval  = 0.09,
    KillAura            = false,
    KillAuraDelay       = 0.15,
    SafeCombatFlight    = false,
    FlightHeight        = 14,
    GodMode             = false,

    -- Super Loot Boss Hunter
    SuperLootHunter     = false,
    SuperLootTargetTier = "All",
    SuperLootNotify     = true,

    -- Train & Attributes
    AutoTrain           = false,
    TrainDelay          = 0.15,
    TrainArea           = Dynamic.TrainAreas[1] or "1",
    SelectedTrainZone   = TRAIN_AUTO_BEST,
    AutoTrainMode       = false,
    AutoClickSword      = false,   -- ★ Auto click sword power
    SwordClickDelay     = 0.16,
    RemoteOnlyTrain     = false,   -- ★ Feature A: ยิง TrainOnceRE ตรงๆ ไม่ต้องวาร์ป
    ForceVIPTrain       = false,   -- ★ Feature B: บายพาสแท่น x100 VIP (Zone 9)
    MasterConcurrentForge = true,  -- ★ หลอมอุปกรณ์คู่ขนานระหว่างฟาร์ม
    AutoUpgrade         = false,
    UpgradeType         = "All in One",
    UpgradeDelay        = 1.5,
    AutoRebirth         = false,
    RebirthDelay        = 10,
    NativeAutoRebirth   = false,

    -- Equipment & Crafting
    AutoForge           = false,
    ForgeDelay          = 1.0,
    ForgeType           = "All",
    MinOreToForge       = 4,
    OreQualityMode      = "Any",
    AutoEquipBest       = false,
    GodSpoofMaterials150Dd = false, -- ★ Astral Spawner: บัคแสดงจำนวนวัสดุ 150Dd (Visual only)
    -- ★ Ported from PAYOMBØYZ
    AutoSellTrashGear   = false,
    MinGearRarityToKeep = "Legendary",
    AutoSellOres        = false,
    OreRaritiesToKeep   = { "Infinite", "Ancient", "Secret", "Eternal", "Mythic", "Legendary" },
    KeepMinOreAmount    = 0,
    AutoSellEnchantStones = false,
    EnchantFilterMode   = "Sell Selected",
    EnchantRaritiesToTarget = { "Common", "Uncommon", "Rare" },
    KeepMinStoneAmount  = 0,
    AutoEquipBestPet    = false,
    PetEquipDelay       = 3.0,
    AntiTrip            = false,
    AutoReconnect       = false,
    RedeemedCodes       = {},
    AutoEnhance         = false,
    EnhanceDelay        = 1.5,
    AutoEnchant         = false,
    EnchantDelay        = 1.5,
    EnchantMaxGrade     = "Mythic",  -- "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Eternal", "All" (max grade of stone allowed to use)
    EnchantKeepHighGrade = true,     -- preserve Eternal/Secret/Ancient stones for manual use
    EnchantSlots        = "All",     -- "All", "Weapon", "Armor", "Hat"
    AutoSell            = false,
    SellDelay           = 8,

    -- Class, Pets & Potions
    AutoRollClass       = false,
    TargetClassToLock   = Dynamic.Classes[#Dynamic.Classes] or "Class_9",
    RollClassDelay      = 1.5,
    AutoRollSkills      = false,
    RollSkillDelay      = 2.0,
    AutoHatchEggs       = false,
    HatchEggDelay       = 2.0,
    AutoUsePotions      = false,
    PotionDelay         = 8.0,

    -- Automated Claims
    AutoClaimRewards    = false,
    ClaimDelay          = 60,

    -- Discord Webhook Notifications
    WebhookEnabled      = false,
    WebhookUrl          = "",
    NotifyRareDrops     = true,
    NotifySuperLoot     = true,
    NotifyHourlyReport  = true,
    NotifyRebirth       = false,

    -- Player & Optimization
    WalkSpeed           = 16,
    JumpPower           = 50,
    InfJump             = false,
    Noclip              = false,
    AntiAFK             = true,
    CpuSaver            = false,
    AutoSaveConfig      = true,
    Debug               = false,
}

local function T(key)
    local lang = State.Language or "TH"
    local dict = Locales[lang] or Locales.TH
    return dict[key] or Locales.TH[key] or key
end

local function TF(key, ...)
    local str = T(key)
    return string.format(str, ...)
end

local Stats = {
    StartTime       = os.time(),
    OresCollected   = 0,
    SellCycles      = 0,
    Kills           = 0,
    RebirthCount    = 0,
    SuperLootKills  = 0,
    CurrentActivity = "StatusReady",
    LastStageClear  = os.time(),
    LastHourlyPost  = os.time(),
}

-- ─────────────────────────────────────────────────────────────
-- Networking & Instance Helpers
-- ─────────────────────────────────────────────────────────────
local function getRemote(folder, name)
    if not RemoteRoot then return nil end
    -- game folders are named "<Name>_Server" (Dungeon_Server, Train_Server, ...)
    local f = RemoteRoot:FindFirstChild(folder .. "_Server") or RemoteRoot:FindFirstChild(folder)
    return f and f:FindFirstChild(name) or nil
end

local function call(folder, name, ...)
    local r = getRemote(folder, name)
    if not r then
        if State.Debug then warn("[NAPHUB] Remote missing:", folder, name) end
        return nil
    end
    local args = { ... }
    local ok, res = pcall(function()
        if r:IsA("RemoteFunction") then
            return r:InvokeServer(unpack(args))
        else
            r:FireServer(unpack(args))
        end
    end)
    return ok and res or nil
end

local function char() return LocalPlayer.Character end
local function hrp()  local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function hum()  local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end

local function getSafeZoneCF()
    local spawn = workspace:FindFirstChild("SpawnLocation")
    if spawn then
        if spawn:IsA("Model") then return spawn:GetPivot() end
        if spawn:IsA("BasePart") then return spawn.CFrame end
    end
    local spawnObj = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    if spawnObj then return spawnObj.CFrame end
    return CFrame.new(0, 5, 0)
end

local function tpTo(cf)
    local r = hrp()
    if r then
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
        r.CFrame = cf + Vector3.new(0, 3, 0)
    end
end

local function getPackInfo()
    local cur, maxNum = 0, 10
    pcall(function()
        local LeftInfoGUI = require(ReplicatedStorage.GuiUtils.LeftInfoGUI)
        cur = LeftInfoGUI.GetOrePack() or 0
    end)
    pcall(function()
        local UpgradeData = require(ReplicatedStorage.LocalData.UpgradeData)
        maxNum = UpgradeData.GetMaxNum("OrePack") or 10
    end)
    return cur, maxNum
end

local function getBackpackItems()
    if not BackpackData or type(BackpackData.GetData) ~= "function" then return nil end
    local ok, data = pcall(BackpackData.GetData)
    return ok and type(data) == "table" and type(data.have) == "table" and data.have or nil
end

-- ★ ALGORITHMIC DPS & AFFIX SOLVER AI (Mathematical Synergy Matrix)
local function calculateEffectiveDPS(item)
    if type(item) ~= "table" or item.ID == nil then return 0 end
    local slot = item.Type or "Weapon"
    local id = item.ID or ""

    local baseTrain = 1
    local usePower = 1
    pcall(function()
        if slot == "Weapon" and WeaponHelper and WeaponHelper.GetConfig then
            local cfg = WeaponHelper.GetConfig(id)
            if cfg then
                baseTrain = tonumber(cfg.Train) or 1
                usePower = tonumber(cfg.UsePower) or 1
            end
        elseif (slot == "Armor" or slot == "Hat") and ArmorHelper and ArmorHelper.GetConfig then
            local cfg = ArmorHelper.GetConfig(id)
            if cfg then
                baseTrain = tonumber(cfg.BaseWeight or cfg.Train) or 1
                usePower = tonumber(cfg.UsePower) or 1
            end
        end
    end)

    -- Enhancement Boost from Enhant.Helper
    local enhLevel = tonumber(item.EnchanceNum or item.EnhanceNum) or 0
    local enhBoost = 0
    pcall(function()
        local eh = EnhantHelper or require(ReplicatedStorage.Config.Enhant.Helper)
        if eh and eh.GetBoost then
            enhBoost = eh.GetBoost(enhLevel) or 0
        end
    end)

    -- Crit, Boom Value & Attack Interval from Inscribed Enchant Stones
    local totalCritRate = 0
    local totalCritDmg = 1.0
    local damageInterval = 0.5
    pcall(function()
        local sh = EnchStoneHelper or require(ReplicatedStorage.Config.EnchStone.Helper)
        if sh and item.EnchanceList and type(item.EnchanceList) == "table" then
            for _, stoneId in ipairs(item.EnchanceList) do
                local sc = sh.GetStoneConfig(stoneId)
                if sc then
                    totalCritRate = totalCritRate + (tonumber(sc.BoomPercent) or 0)
                    totalCritDmg = totalCritDmg + (tonumber(sc.BoomValue) or 0)
                    if sc.DamageInterval and tonumber(sc.DamageInterval) < damageInterval then
                        damageInterval = tonumber(sc.DamageInterval)
                    end
                end
            end
        end
    end)

    -- Sub-affixes bonuses
    local affixBonus = 1.0
    if item.MainAffix and type(item.MainAffix) == "table" then
        local num = tonumber(item.MainAffix.Number) or 0
        affixBonus = affixBonus + (num * 0.05)
    end
    if item.Affix and type(item.Affix) == "table" then
        for _, sub in ipairs(item.Affix) do
            if type(sub) == "table" and sub.Number then
                affixBonus = affixBonus + (tonumber(sub.Number) or 0) * 0.03
            end
        end
    end

    local dps = (baseTrain * usePower * (1 + enhBoost) * affixBonus)
        * (1 + (totalCritRate * totalCritDmg))
        * (1 / math.max(damageInterval, 0.1))

    return dps
end

local function itemGearScore(item)
    if State.AlgorithmicDPSSolver then
        return calculateEffectiveDPS(item)
    end
    if type(item) ~= "table" or item.ID == nil then return 0 end
    local designPower = 0
    local helper = item.Type == "Weapon" and WeaponHelper or ArmorHelper
    if helper and type(helper.GetDesignPower) == "function" then
        pcall(function() designPower = tonumber(helper.GetDesignPower(item.ID)) or 0 end)
    end
    local rarityValue = item.RarityLevel or item.Rarity or item.RareLevel
    local rarity = tonumber(rarityValue) or 0
    if rarity == 0 and type(rarityValue) == "string" then
        local rarityRanks = {
            Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5,
            Mythic = 6, Eternal = 7, Secret = 8, Ancient = 9, Infinite = 10,
        }
        rarity = rarityRanks[rarityValue] or 0
    end
    local affix = type(item.MainAffix) == "table" and tonumber(item.MainAffix.Number) or 0
    local enhancement = tonumber(item.EnchanceNum or item.EnhanceNum) or 0
    return rarity * 1000000000 + designPower * 100000 + (affix or 0) + enhancement * 10
end

-- ─────────────────────────────────────────────────────────────
-- ★ ASTRAL SERVER SPAWNER (ported from PAYOMBØYZ)
-- ─────────────────────────────────────────────────────────────
local function getDevRemoteFolder()
    return RemoteRoot and RemoteRoot:FindFirstChild("Dev") or nil
end

-- สวมใส่ของทอง (Exclusive/Infinite/Ancient/Eternal) และแดง (Mythic) ที่ดีที่สุดในแต่ละช่อง
local function equipGoldAndRedGear()
    local items = getBackpackItems()
    local remote = getRemote("Backpack", "TryEquipItemRE")
    if not items or not remote then return false, 0 end

    local slots = { "Weapon", "Armor", "Hat" }
    local equippedCount = 0

    for _, slot in ipairs(slots) do
        local bestUuid, bestScore = nil, -1
        for uuid, item in pairs(items) do
            if type(item) == "table" and item.Type == slot then
                local idStr = tostring(item.ID or "")
                local rarityVal = tostring(item.RarityLevel or item.Rarity or item.RareLevel or "")
                local enh = (tonumber(item.EnchanceNum or item.EnhanceNum) or 0) * 1000
                local score
                if rarityVal == "Exclusive" or idStr:find("1101") then
                    score = 1000000000000 + enh
                elseif rarityVal == "Infinite" or idStr:find("K_26") then
                    score = 900000000000 + enh
                elseif rarityVal == "Ancient" then
                    score = 800000000000 + enh
                elseif rarityVal == "Eternal" or idStr:find("LHat_16") then
                    score = 700000000000 + enh
                elseif rarityVal == "Mythic" or idStr:find("HArmor_14") or idStr:find("K_21") or idStr:find("HHat_14") then
                    score = 600000000000 + enh
                else
                    score = itemGearScore(item)
                end
                if score > bestScore then
                    bestScore, bestUuid = score, uuid
                end
            end
        end
        if bestUuid then
            local ok = pcall(function() remote:FireServer(bestUuid, slot) end)
            if ok then equippedCount += 1 end
        end
    end
    return equippedCount > 0, equippedCount
end

local ASTRAL_SETS = {
    Apocalypse   = { weapon = "K_1101", hat = "HHat_1101", armor = "HArmor_1101" },
    TriWyrm      = { weapon = "K_1001", hat = "HHat_1001", armor = "HArmor_1001" },
    Cataclysm    = { weapon = "K_1002", hat = "HHat_1002", armor = "HArmor_1002" },
    VoidOverlord = { weapon = "K_26",   hat = "LHat_16",   armor = "LArmor_16"   },
}

local function spawnGodSet(setName)
    local dev = getDevRemoteFolder()
    local set = ASTRAL_SETS[setName]
    if not dev or not set then return false end

    local weaponRE = dev:FindFirstChild("GetWeaponRE")
    local armorRE  = dev:FindFirstChild("GetArmorRE")
    if weaponRE then pcall(function() weaponRE:FireServer(set.weapon) end) end
    if armorRE then
        pcall(function() armorRE:FireServer(set.hat) end)
        pcall(function() armorRE:FireServer(set.armor) end)
    end

    task.wait(0.3)
    pcall(equipGoldAndRedGear)
    return true
end

local function countBackpackOres()
    local total = 0
    local bp = getBackpackItems()
    if bp then
        for _, it in pairs(bp) do
            if type(it) == "table" and it.Type == "Ore" then
                total = total + (tonumber(it.Number) or 1)
            end
        end
    end
    return total
end

local function spawnApexOresDirect(count)
    count = count or 10
    local dev = getDevRemoteFolder()
    local oreRE = dev and dev:FindFirstChild("GetOreRE")
    if not oreRE then return false end
    for _ = 1, count do
        pcall(function() oreRE:FireServer("Ore_48") end)
    end
    task.wait(0.2)
    pcall(function()
        local LeftInfoGUI = require(ReplicatedStorage.GuiUtils.LeftInfoGUI)
        if LeftInfoGUI and LeftInfoGUI.UpdateOrePack then
            LeftInfoGUI.UpdateOrePack(countBackpackOres())
        end
    end)
    return true
end

local function spawnAllRunesDirect()
    local dev = getDevRemoteFolder()
    local runeRE = dev and dev:FindFirstChild("GetEnchStoneRE")
    if not runeRE then return false end
    local runes = { "Poison_3", "Ice_3", "Fire_3", "Thunder_3", "Poison_2", "Ice_2", "Fire_2", "Thunder_2" }
    for _, r in ipairs(runes) do
        pcall(function() runeRE:FireServer(r) end)
    end
    return true
end

-- ★ ย้ายมาจาก 2K.txt : ระบบกระเป๋า (รวม/ซ่อมหิน Ember) + ฟังก์ชันเสก Ember Stone
local myToken = tick()
_G.TwoSkiActiveToken = myToken
_G.TwoSkiRunning = true
local function applyBackpackVisualEngine()
    pcall(function()
        local AnyHelper = require(ReplicatedStorage.Config.AnyHelper)
        local MatHelper = nil
        pcall(function() MatHelper = require(ReplicatedStorage.Config.Material.Helper) end)
        local MatShow = nil
        pcall(function() MatShow = require(ReplicatedStorage.Config.Material.Show) end)
        local MatConfig = nil
        pcall(function() MatConfig = require(ReplicatedStorage.Config.Material.Config) end)
        local OreHelper = nil
        pcall(function() OreHelper = require(ReplicatedStorage.Config.Ore.Helper) end)
        local EnchHelper = nil
        pcall(function() EnchHelper = require(ReplicatedStorage.Config.EnchStone.Helper) end)
        local WeaponHelper = nil
        pcall(function() WeaponHelper = require(ReplicatedStorage.Config.Weapon.Helper) end)
        local ArmorHelper = nil
        pcall(function() ArmorHelper = require(ReplicatedStorage.Config.Armor.Helper) end)
        local RarityHelper = nil
        pcall(function() RarityHelper = require(ReplicatedStorage.Config.Rarity.Helper) end)
        local AbbNumber = nil
        pcall(function() AbbNumber = require(ReplicatedStorage.Utils.AbbNumber) end)
        local BackpackData = require(ReplicatedStorage.LocalData.BackpackData)
        local BackpackGUI = nil
        pcall(function() BackpackGUI = require(ReplicatedStorage.GuiUtils.BackpackGUI) end)
        local function sanitizeBackpackData()
            local bp = BackpackData and BackpackData.GetData()
            if not bp or not bp.have then return end
            local corruptOreCount = 0
            local toRemove = {}
            for k, v in pairs(bp.have) do
                if v.Type == "Ore" and type(v.ID) == "table" then
                    corruptOreCount = corruptOreCount + (v.Number or 0)
                    table.insert(toRemove, k)
                end
            end
            if corruptOreCount > 0 then
                local merged = false
                for k2, v in pairs(bp.have) do
                    if v.Type == "Material" and v.ID == "EnhantStone_1" and not tostring(k2):find("^SSS%-MAT") then
                        v.Number = (v.Number or 0) + corruptOreCount
                        merged = true
                        break
                    end
                end
                if not merged then
                    bp.have["SSS-CLEAN-EMBER-1"] = {
                        ID = "EnhantStone_1",
                        Type = "Material",
                        Number = corruptOreCount,
                        Equip = false,
                        Lock = false,
                        Level = 1
                    }
                end
                for _, k in ipairs(toRemove) do
                    bp.have[k] = nil
                end
                local bpGui = LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("Backpack")
                local scroll = bpGui and bpGui:FindFirstChild("Main") and bpGui.Main:FindFirstChild("Right") and bpGui.Main.Right:FindFirstChild("Bg") and bpGui.Main.Right.Bg:FindFirstChild("ScrollingFrame")
                if scroll then
                    for _, k in ipairs(toRemove) do
                        local cell = scroll:FindFirstChild(k)
                        if cell then cell:Destroy() end
                    end
                end
            end
        end
        if MatHelper and MatShow and not _G._TwoK_MatHelperProtected then
            _G._TwoK_MatHelperProtected = true
            MatHelper.GetImage = function(id)
                if id and MatShow[id] then return MatShow[id].Image end
                return nil
            end
            MatHelper.GetDisName = function(id)
                if id and MatShow[id] then return MatShow[id].DisplayName end
                return nil
            end
            MatHelper.GetRarity = function(id)
                if id and MatConfig and MatConfig[id] then return MatConfig[id].Rarity end
                return nil
            end
            MatHelper.GetDescription = function(id)
                if id and MatShow[id] then return MatShow[id].Description end
                return nil
            end
        end
        local function resolveItemIdentity(itemType, itemId)
            local aType = itemType or "Material"
            local aId = itemId
            if type(itemId) == "table" then
                aId = itemId.ID or itemId.Name or itemId
                aType = itemId.Type or itemType or "Material"
            end
            return aType, tostring(aId)
        end
        local origGetImage = AnyHelper.GetImage
        local origGetDisName = AnyHelper.GetDisName
        local origGetRarity = AnyHelper.GetRarity
        local origGetPrice = AnyHelper.GetPrice
        local function safeResolveImage(itemType, itemId)
            local aType, aId = resolveItemIdentity(itemType, itemId)
            local img = nil
            pcall(function() img = origGetImage(aType, aId) end)
            if img and img ~= "" then return img end
            pcall(function() if MatHelper and MatHelper.GetImage then img = MatHelper.GetImage(aId) end end)
            if img and img ~= "" then return img end
            pcall(function() if OreHelper and OreHelper.GetImage then img = OreHelper.GetImage(aId) end end)
            if img and img ~= "" then return img end
            pcall(function() if EnchHelper and EnchHelper.GetImage then img = EnchHelper.GetImage(aId) end end)
            if img and img ~= "" then return img end
            pcall(function() if WeaponHelper and WeaponHelper.GetImage then img = WeaponHelper.GetImage(aId) end end)
            if img and img ~= "" then return img end
            pcall(function() if ArmorHelper and ArmorHelper.GetImage then img = ArmorHelper.GetImage(aId) end end)
            if img and img ~= "" then return img end
            return "rbxassetid://93499783424371"
        end
        local function safeResolveDisName(itemType, itemId)
            local aType, aId = resolveItemIdentity(itemType, itemId)
            local name = nil
            pcall(function() name = origGetDisName(aType, aId) end)
            if name and name ~= "" then return name end
            pcall(function() if MatHelper and MatHelper.GetDisName then name = MatHelper.GetDisName(aId) end end)
            if name and name ~= "" then return name end
            pcall(function() if OreHelper and OreHelper.GetDisName then name = OreHelper.GetDisName(aId) end end)
            if name and name ~= "" then return name end
            pcall(function() if EnchHelper and EnchHelper.GetDisName then name = EnchHelper.GetDisName(aId) end end)
            if name and name ~= "" then return name end
            pcall(function() if WeaponHelper and WeaponHelper.GetDisName then name = WeaponHelper.GetDisName(aId) end end)
            if name and name ~= "" then return name end
            pcall(function() if ArmorHelper and ArmorHelper.GetDisName then name = ArmorHelper.GetDisName(aId) end end)
            if name and name ~= "" then return name end
            return aId
        end
        local function safeResolveRarity(itemType, itemId)
            local aType, aId = resolveItemIdentity(itemType, itemId)
            local rar = nil
            pcall(function() rar = origGetRarity(aType, aId) end)
            if rar and rar ~= "" then return rar end
            pcall(function() if MatHelper and MatHelper.GetRarity then rar = MatHelper.GetRarity(aId) end end)
            if rar and rar ~= "" then return rar end
            pcall(function() if OreHelper and OreHelper.GetRarity then rar = OreHelper.GetRarity(aId) end end)
            if rar and rar ~= "" then return rar end
            return "Legendary"
        end
        local function safeResolvePrice(itemType, itemId)
            local aType, aId = resolveItemIdentity(itemType, itemId)
            local price = nil
            pcall(function() price = origGetPrice(aType, aId) end)
            if price and price > 0 then return price end
            return 50000
        end
        if not _G._TwoK_AnyHelperHooked then
            _G._TwoK_AnyHelperHooked = true
            AnyHelper.GetImage = safeResolveImage
            AnyHelper.GetDisName = safeResolveDisName
            AnyHelper.GetRarity = safeResolveRarity
            AnyHelper.GetPrice = safeResolvePrice
        end
        local isHealing = false
        local function healBackpackFrames()
            if isHealing then return end
            isHealing = true
            sanitizeBackpackData()
            local bpGui = LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("Backpack")
            if not bpGui then isHealing = false; return end
            local scroll = bpGui:FindFirstChild("Main") and bpGui.Main:FindFirstChild("Right") and bpGui.Main.Right:FindFirstChild("Bg") and bpGui.Main.Right.Bg:FindFirstChild("ScrollingFrame")
            if not scroll then isHealing = false; return end
            for _, cell in ipairs(scroll:GetChildren()) do
                if cell:IsA("Frame") and cell.Visible then
                    local item = BackpackData.GetItemData(cell.Name)
                    if item then
                        local btn = cell:FindFirstChild("Button")
                        if btn then
                            local frame = btn:FindFirstChild("Frame")
                            if frame then
                                local imgLabel = frame:FindFirstChild("ImageLabel")
                                if imgLabel and (imgLabel.Image == "" or not imgLabel.Image) then
                                    imgLabel.Image = safeResolveImage(item.Type, item.ID)
                                end
                                local zi = frame:FindFirstChild("zi")
                                if zi then
                                    local atkLabel = zi:FindFirstChild("ATK")
                                    if atkLabel and (atkLabel.Text == "" or not atkLabel.Text) then
                                        atkLabel.Text = safeResolveDisName(item.Type, item.ID)
                                    end
                                    local priceLabel = zi:FindFirstChild("Price")
                                    if priceLabel and (priceLabel.Text == "" or not priceLabel.Text) then
                                        local price = safeResolvePrice(item.Type, item.ID)
                                        local priceStr = AbbNumber and AbbNumber.AbbreviateNumber and AbbNumber.AbbreviateNumber(price) or tostring(price)
                                        priceLabel.Text = "Price:" .. priceStr
                                    end
                                end
                                if not frame:FindFirstChild("UIQIU") and RarityHelper and RarityHelper.SetUIQiu then
                                    pcall(function()
                                        local rarity = safeResolveRarity(item.Type, item.ID)
                                        RarityHelper.SetUIQiu(frame, rarity)
                                    end)
                                end
                                local qty = frame:FindFirstChild("Quantity")
                                local qtyLabel = qty and qty:FindFirstChild("TextLabel")
                                if qtyLabel and item.Number then
                                    local numStr = AbbNumber and AbbNumber.AbbreviateNumber and AbbNumber.AbbreviateNumber(item.Number) or tostring(item.Number)
                                    local expectedText = "x" .. tostring(numStr)
                                    if qtyLabel.Text ~= expectedText then
                                        qtyLabel.Text = expectedText
                                    end
                                    qty.Visible = (item.Number > 1)
                                end
                            end
                        end
                    end
                end
            end
            isHealing = false
        end
        _G._TwoK_HealBackpack = healBackpackFrames
        if BackpackGUI then
            local origOpen = _G._TwoK_OrigBackpackOpen or BackpackGUI.open
            _G._TwoK_OrigBackpackOpen = origOpen
            BackpackGUI.open = function(...)
                if origOpen then origOpen(...) end
                pcall(function()
                    if BackpackGUI.UpdateBackpack then
                        BackpackGUI.UpdateBackpack()
                    end
                    healBackpackFrames()
                end)
            end
            local origOpenScroList = _G._TwoK_OrigBackpackScroList or BackpackGUI.OpenItemScroList
            _G._TwoK_OrigBackpackScroList = origOpenScroList
            BackpackGUI.OpenItemScroList = function(tabName)
                sanitizeBackpackData()
                if origOpenScroList then origOpenScroList(tabName) end
                if tabName == "Ore" then
                    local bpGui = LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("Backpack")
                    local scroll = bpGui and bpGui:FindFirstChild("Main") and bpGui.Main:FindFirstChild("Right") and bpGui.Main.Right:FindFirstChild("Bg") and bpGui.Main.Right.Bg:FindFirstChild("ScrollingFrame")
                    if scroll then
                        for _, cell in ipairs(scroll:GetChildren()) do
                            if cell:IsA("Frame") then
                                local item = BackpackData.GetItemData(cell.Name)
                                if item and (item.Type ~= "Ore" or type(item.ID) == "table") then
                                    cell.Visible = false
                                end
                            end
                        end
                    end
                end
                task.defer(healBackpackFrames)
            end
            local origOpenMaterialInfo = _G._TwoK_OrigBackpackOpenMat or BackpackGUI.OpenMaterialInfo
            _G._TwoK_OrigBackpackOpenMat = origOpenMaterialInfo
            BackpackGUI.OpenMaterialInfo = function(uuid)
                _G._TwoK_SelectedMaterialUUID = uuid
                if origOpenMaterialInfo then origOpenMaterialInfo(uuid) end
            end
            local origCloseMaterialInfo = _G._TwoK_OrigBackpackCloseMat or BackpackGUI.CloseMaterialInfo
            _G._TwoK_OrigBackpackCloseMat = origCloseMaterialInfo
            BackpackGUI.CloseMaterialInfo = function(...)
                _G._TwoK_SelectedMaterialUUID = nil
                if origCloseMaterialInfo then origCloseMaterialInfo(...) end
            end
            local origUpdateItemFrame = _G._TwoK_OrigBackpackUpdateFrame or BackpackGUI.UpdateItemFrame
            _G._TwoK_OrigBackpackUpdateFrame = origUpdateItemFrame
            BackpackGUI.UpdateItemFrame = function(uuid, itemData)
                if origUpdateItemFrame then origUpdateItemFrame(uuid, itemData) end
                pcall(function()
                    local item = itemData or BackpackData.GetItemData(uuid)
                    if item and item.Number then
                        local bpGui = LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("Backpack")
                        local scroll = bpGui and bpGui:FindFirstChild("Main") and bpGui.Main:FindFirstChild("Right") and bpGui.Main.Right:FindFirstChild("Bg") and bpGui.Main.Right.Bg:FindFirstChild("ScrollingFrame")
                        local cell = scroll and scroll:FindFirstChild(uuid)
                        local qty = cell and cell:FindFirstChild("Button") and cell.Button:FindFirstChild("Frame") and cell.Button.Frame:FindFirstChild("Quantity")
                        local qtyLabel = qty and qty:FindFirstChild("TextLabel")
                        if qtyLabel then
                            local numStr = AbbNumber and AbbNumber.AbbreviateNumber and AbbNumber.AbbreviateNumber(item.Number) or tostring(item.Number)
                            local expectedText = "x" .. tostring(numStr)
                            if qtyLabel.Text ~= expectedText then
                                qtyLabel.Text = expectedText
                            end
                            qty.Visible = (item.Number > 1)
                        end
                    end
                end)
            end
        end
        BackpackData.AddCallback(function()
            task.defer(healBackpackFrames)
        end)
        local ProfileData = require(ReplicatedStorage.ProfileData)
        if ProfileData and ProfileData.AddStoreCallback then
            ProfileData.AddStoreCallback("Backpack", function()
                task.defer(healBackpackFrames)
            end)
        end
        task.spawn(function()
            local bpGui = LocalPlayer.PlayerGui:WaitForChild("Main"):WaitForChild("Backpack")
            local scroll = bpGui:WaitForChild("Main"):WaitForChild("Right"):WaitForChild("Bg"):WaitForChild("ScrollingFrame")
            local matInfo = bpGui:WaitForChild("MaterialInfo", 5)
            scroll.ChildAdded:Connect(function()
                task.defer(healBackpackFrames)
            end)
            while _G.TwoSkiRunning and _G.TwoSkiActiveToken == myToken do
                if bpGui.Visible then
                    for _, cell in ipairs(scroll:GetChildren()) do
                        if cell:IsA("Frame") and cell.Visible then
                            local item = BackpackData.GetItemData(cell.Name)
                            if item and item.Number then
                                local btn = cell:FindFirstChild("Button")
                                local frame = btn and btn:FindFirstChild("Frame")
                                local qty = frame and frame:FindFirstChild("Quantity")
                                local qtyLabel = qty and qty:FindFirstChild("TextLabel")
                                if qtyLabel then
                                    local numStr = AbbNumber and AbbNumber.AbbreviateNumber and AbbNumber.AbbreviateNumber(item.Number) or tostring(item.Number)
                                    local target = "x" .. tostring(numStr)
                                    if qtyLabel.Text ~= target then
                                        qtyLabel.Text = target
                                    end
                                    if qty.Visible ~= (item.Number > 1) then
                                        qty.Visible = (item.Number > 1)
                                    end
                                end
                            end
                        end
                    end
                    if matInfo and matInfo.Visible and _G._TwoK_SelectedMaterialUUID then
                        local selItem = BackpackData.GetItemData(_G._TwoK_SelectedMaterialUUID)
                        if selItem and selItem.Number then
                            local xinxi = matInfo:FindFirstChild("xinxi") and matInfo.xinxi:FindFirstChild("1")
                            local info = xinxi and xinxi:FindFirstChild("Info")
                            local numLabel = info and info:FindFirstChild("Number")
                            if numLabel then
                                local numStr = AbbNumber and AbbNumber.AbbreviateNumber and AbbNumber.AbbreviateNumber(selItem.Number) or tostring(selItem.Number)
                                local target = "x" .. tostring(numStr)
                                if numLabel.Text ~= target then
                                    numLabel.Text = target
                                end
                            end
                        end
                    end
                end
                task.wait(0.1)
            end
        end)
        sanitizeBackpackData()
        healBackpackFrames()
        pcall(function()
            local ForgeGUI = require(ReplicatedStorage.GuiUtils.ForgeGUI)
            if ForgeGUI and not _G._TwoK_ForgeGUIPatched then
                _G._TwoK_ForgeGUIPatched = true
                local oldCreateOreBtn = ForgeGUI.CreateOreButton
                ForgeGUI.CreateOreButton = function(uuid, itemData)
                    if not itemData or type(itemData.ID) == "table" or not (OreHelper and OreHelper.CheckID and OreHelper.CheckID(itemData.ID)) then
                        return nil
                    end
                    local ok, res = pcall(function()
                        return oldCreateOreBtn(uuid, itemData)
                    end)
                    if not ok then return nil end
                    return res
                end
                local oldUpdateRight = ForgeGUI.UpdateRight
                ForgeGUI.UpdateRight = function()
                    pcall(function()
                        if oldUpdateRight then oldUpdateRight() end
                    end)
                end
            end
        end)
    end)
end
local isPumpingEmber = false
local function pumpRealEmberStones(targetAmount)
    targetAmount = tonumber(targetAmount) or 5000
    if isPumpingEmber then return false end
    isPumpingEmber = true
    local function getStoneCount()
        local bp = BackpackData and BackpackData.GetData()
        if bp and bp.have then
            for k, item in pairs(bp.have) do
                if item.ID == "EnhantStone_1" and not tostring(k):find("^SSS%-MAT") then
                    return item.Number or 0
                end
            end
        end
        return 0
    end
    local initialCount = getStoneCount()
    local goal = initialCount + targetAmount
    task.spawn(function()
        notify("NAPHUB Ember Stone", "กำลังเสก Ember Stone +" .. tostring(targetAmount) .. " ก้อน (เซฟลง Server DataStore ถาวร)...", "flame")
        local stageRemote = getRemote("Stage", "StageFinishedRF")
        local stoneRemote = getRemote("Stage", "GetEnhantStoneRE")
        local current = getStoneCount()
        local t0 = os.clock()
        local maxWait = 35
        while current < goal and (os.clock() - t0) < maxWait and _G.TwoSkiRunning and _G.TwoSkiActiveToken == myToken do
            local batchSize = 35
            local needed = goal - current
            if needed < 50 then batchSize = 15 end
            for i = 1, batchSize do
                task.spawn(function()
                    local ok, drops = pcall(function()
                        return stageRemote:InvokeServer("Stage_27")
                    end)
                    if ok and type(drops) == "table" and stoneRemote then
                        for uuid, itm in pairs(drops) do
                            if type(itm) == "table" and (itm.ID == "EnhantStone_1" or itm.Type == "Material") then
                                pcall(function() stoneRemote:FireServer(uuid) end)
                            end
                        end
                    end
                end)
            end
            task.wait(0.12)
            current = getStoneCount()
            if _G._TwoK_HealBackpack then
                pcall(_G._TwoK_HealBackpack)
            end
        end
        local finalCount = getStoneCount()
        local gained = finalCount - initialCount
        isPumpingEmber = false
        notify("NAPHUB Ember Stone", "เสกสำเร็จ! ได้ Ember Stone +" .. tostring(gained) .. " ก้อน (มีทั้งหมด " .. tostring(finalCount) .. " ก้อน) บันทึก Server ถาวร 100%", "flame")
        pcall(function()
            local bpGui = require(ReplicatedStorage.GuiUtils.BackpackGUI)
            if bpGui and bpGui.UpdateBackpack then
                bpGui.UpdateBackpack()
            end
            if _G._TwoK_HealBackpack then
                _G._TwoK_HealBackpack()
            end
        end)
    end)
    return true
end


-- Visual-only: แก้ตัวเลขฝั่งไคลเอนต์ ไม่ได้เพิ่มของจริงบนเซิร์ฟเวอร์
-- ตั้งจำนวน ม้วนป้องกัน / ตั๋วทาวเวอร์ / หินปริซึม / หินเอมเบอร์ เป็น 150Dd (1.5e41)
local GOD_MATERIAL_AMOUNT = 1.5e41
local GOD_MATERIALS = {
    { Key = "SSS-MAT-PROTECT", ID = "EnhantProtect",  Type = "Material", Rarity = "Infinite"  },
    { Key = "SSS-MAT-TICKET",  ID = "Dungeon_Ticket", Type = "Material", Rarity = "Mythic"    },
    { Key = "SSS-MAT-PRISM",   ID = "EnhantStone_2",  Type = "Material", Rarity = "Mythic"    },
    { Key = "SSS-MAT-EMBER",   ID = "EnhantStone_1",  Type = "Material", Rarity = "Legendary" },
}

local function refreshBackpackGui(openMaterialTab)
    pcall(function()
        local bpg = require(ReplicatedStorage.GuiUtils.BackpackGUI)
        if not bpg then return end
        if bpg.UpdateBackpack then pcall(bpg.UpdateBackpack) end
        if bpg.update then pcall(bpg.update) end
        if openMaterialTab then
            if bpg.open then pcall(bpg.open) end
            if bpg.OpenItemScroList then pcall(bpg.OpenItemScroList, "Material") end
        end
    end)
end

local function setGodMaterials(amount, openGui)
    local ok = pcall(function()
        local data = BackpackData and BackpackData.GetData and BackpackData.GetData()
        if type(data) ~= "table" then return end
        if type(data.have) ~= "table" then data.have = {} end
        for _, m in ipairs(GOD_MATERIALS) do
            local found = false
            for _, it in pairs(data.have) do
                if type(it) == "table" then
                    local itId = tostring(type(it.ID) == "table" and it.ID.ID or it.ID)
                    if itId == m.ID then
                        it.Number = amount
                        it.Type = "Material"
                        if m.Rarity and not it.Rarity then it.Rarity = m.Rarity end
                        found = true
                    end
                end
            end
            if not found then
                data.have[m.Key] = { ID = m.ID, Type = "Material", Number = amount, Rarity = m.Rarity }
            end
        end
    end)
    refreshBackpackGui(openGui == true)
    return ok
end

local function restoreMaterialNumbers()
    pcall(function()
        local data = BackpackData and BackpackData.GetData and BackpackData.GetData()
        if type(data) ~= "table" or type(data.have) ~= "table" then return end
        for key, it in pairs(data.have) do
            if type(it) == "table" then
                local itId = tostring(type(it.ID) == "table" and it.ID.ID or it.ID)
                if itId == "EnhantProtect" or itId == "Dungeon_Ticket" or itId == "EnhantStone_2" then
                    it.Number = 10
                elseif itId == "EnhantStone_1" then
                    it.Number = 17000
                end
            end
        end
        -- ลบรายการปลอมที่เราเพิ่มเอง
        for _, m in ipairs(GOD_MATERIALS) do
            if data.have[m.Key] then data.have[m.Key] = nil end
        end
    end)
    refreshBackpackGui(false)
end

local function apply150DdMaterialSpoof(enable)
    if enable then
        Dynamic.GodMaterialsActive = true
        setGodMaterials(GOD_MATERIAL_AMOUNT, false)
        -- เซิร์ฟเวอร์ส่งข้อมูลกระเป๋าใหม่เมื่อไหร่ ให้ตั้งค่า 150Dd ซ้ำ (ลงทะเบียนครั้งเดียว)
        if not Dynamic.MaterialSpoofCallbackRegistered and BackpackData and BackpackData.AddCallback then
            Dynamic.MaterialSpoofCallbackRegistered = true
            pcall(function()
                BackpackData.AddCallback(function()
                    if Dynamic.GodMaterialsActive then
                        setGodMaterials(GOD_MATERIAL_AMOUNT, false)
                    end
                end)
            end)
        end
    else
        Dynamic.GodMaterialsActive = false
        restoreMaterialNumbers()
    end
end

local equipBestGearNow, autoEnchantEquippedGear -- forward declarations
local function runAlgorithmicGearSolver()
    local ok, count, score = equipBestGearNow("All")
    pcall(autoEnchantEquippedGear)
    return ok, count, score
end

equipBestGearNow = function(targetType)
    local items = getBackpackItems()
    local remote = getRemote("Backpack", "TryEquipItemRE")
    if not items or not remote then return false, 0 end
    local slots = (targetType == "Weapon" or targetType == "Armor" or targetType == "Hat")
        and { targetType } or { "Weapon", "Armor", "Hat" }
    local equipped, highestScore = 0, 0
    for _, slot in ipairs(slots) do
        local bestUuid, bestScore = nil, -1
        for uuid, item in pairs(items) do
            if type(item) == "table" and item.Type == slot then
                local score = itemGearScore(item)
                if score > bestScore then bestUuid, bestScore = uuid, score end
            end
        end
        if bestUuid then
            local ok = pcall(function() remote:FireServer(bestUuid, slot) end)
            if ok then equipped += 1; highestScore = math.max(highestScore, bestScore) end
        end
    end
    return equipped > 0, equipped, highestScore
end

local forgeCycleIndex = 1
local function executeForgeNow(forgeType, minOres)
    local items = getBackpackItems()
    local remote = getRemote("Forge", "ForgeRF")
    if not items or not remote or not remote:IsA("RemoteFunction") then
        return false, "Forge data or remote is unavailable"
    end

    forgeType = forgeType or State.ForgeType or "All"
    minOres = math.max(4, math.floor(tonumber(minOres or State.MinOreToForge) or 4))
    local totalOres, oreEntries = 0, {}
    for uuid, item in pairs(items) do
        if type(item) == "table" and item.Type == "Ore" then
            local count = math.max(1, math.floor(tonumber(item.Number) or 1))
            local power = 0
            if OreHelper and type(OreHelper.GetPower) == "function" then
                pcall(function() power = tonumber(OreHelper.GetPower(item.ID)) or 0 end)
            end
            totalOres += count
            oreEntries[#oreEntries + 1] = { UUID = uuid, Count = count, Power = power }
        end
    end
    if totalOres < 4 then return false, "Need at least 4 ores" end

    local rotating = forgeType == "All"
    local slot = forgeType
    if rotating then
        local rotation = { "Weapon", "Armor", "Hat" }
        slot = rotation[((forgeCycleIndex - 1) % #rotation) + 1]
    end
    if slot ~= "Weapon" and slot ~= "Armor" and slot ~= "Hat" then slot = "Weapon" end

    local targetCount
    if slot == "Weapon" then
        targetCount = math.clamp(minOres, 4, 13)
    elseif slot == "Hat" then
        targetCount = minOres >= 16 and 16 or 4
    elseif minOres >= 20 and totalOres >= 23 then
        targetCount = 23
    elseif minOres >= 11 and totalOres >= 11 then
        targetCount = 11
    elseif minOres >= 8 and totalOres >= 8 then
        targetCount = 8
    elseif rotating then
        slot, targetCount = "Hat", 4
    else
        return false, "Armor forging needs 8, 11, or 23 ores"
    end
    if totalOres < targetCount then return false, "Need " .. tostring(targetCount) .. " ores for " .. slot end

    if State.OreQualityMode == "High" then
        table.sort(oreEntries, function(a, b) return a.Power > b.Power end)
    elseif State.OreQualityMode == "Low" then
        table.sort(oreEntries, function(a, b) return a.Power < b.Power end)
    end
    local uuidList, selected = {}, 0
    for _, ore in ipairs(oreEntries) do
        local take = math.min(ore.Count, targetCount - selected)
        if take > 0 then uuidList[ore.UUID] = take; selected += take end
        if selected >= targetCount then break end
    end
    if selected < targetCount then return false, "Could not select enough ores" end

    local serverConfigType = slot == "Weapon" and "Weapon" or "Armor"
    local ok, result = pcall(function()
        return remote:InvokeServer({ ConfigType = serverConfigType, UUIDList = uuidList })
    end)
    if not ok or result == false then return false, "Forge request failed" end
    if rotating then
        forgeCycleIndex = slot == "Hat" and 1 or (forgeCycleIndex % 3) + 1
    end
    task.delay(0.25, function() equipBestGearNow(slot) end)
    return true, slot, selected
end

local STONE_GRADE_RANKS = {
    Common = 1,
    Uncommon = 2,
    Rare = 3,
    Epic = 4,
    Legendary = 5,
    Mythic = 6,
    Eternal = 7,
    Secret = 8,
    Ancient = 9,
    Infinite = 10,
}

local function getStoneGrade(item)
    if type(item) ~= "table" then return 1 end
    local r = item.RarityLevel or item.Rarity or item.RareLevel or item.Rare
    if tonumber(r) then return tonumber(r) end
    if type(r) == "string" and STONE_GRADE_RANKS[r] then return STONE_GRADE_RANKS[r] end
    local id = tostring(item.ID or item.id or "")
    for name, rank in pairs(STONE_GRADE_RANKS) do
        if id:find(name) then return rank end
    end
    return 1
end

autoEnchantEquippedGear = function()
    local bp = getBackpackItems()
    if not bp then return false, 0 end

    local maxAllowedRank = STONE_GRADE_RANKS[State.EnchantMaxGrade] or 6
    if State.EnchantMaxGrade == "All" then maxAllowedRank = 99 end

    local usableStones = {}
    for uuid, item in pairs(bp) do
        if type(item) == "table" then
            local isStone = item.Type == "EnchStone" or (item.ID and tostring(item.ID):find("Stone"))
            if isStone then
                local gradeRank = getStoneGrade(item)
                local skip = false
                if State.EnchantKeepHighGrade and gradeRank >= 7 then
                    skip = true -- keep Eternal, Secret, Ancient
                end
                if gradeRank > maxAllowedRank then
                    skip = true
                end
                if not skip then
                    local count = tonumber(item.Number or item.Count) or 1
                    for _ = 1, count do
                        table.insert(usableStones, { UUID = uuid, Rank = gradeRank })
                    end
                end
            end
        end
    end

    if #usableStones == 0 then return false, 0 end

    -- Sort stones: lowest grade first so user conserves best stones
    table.sort(usableStones, function(a, b) return a.Rank < b.Rank end)

    local targetSlots = (State.EnchantSlots == "Weapon" or State.EnchantSlots == "Armor" or State.EnchantSlots == "Hat")
        and { State.EnchantSlots } or { "Weapon", "Armor", "Hat" }

    local enchantRE = getRemote("Backpack", "EnchantRE")
    local stoneIdx = 1
    local totalEnchanted = 0

    for uuid, item in pairs(bp) do
        local isEquipped = false
        pcall(function()
            if BackpackData and BackpackData.IsEquipedUUID then
                isEquipped = BackpackData.IsEquipedUUID(uuid)
            end
        end)

        if isEquipped and type(item) == "table" and table.find(targetSlots, item.Type) then
            local maxSlots = tonumber(item.EnchanceNum or item.EnhanceNum) or 0
            if maxSlots > 0 then
                local currentList = item.EnchanceList or item.EnhanceList or {}
                local usedSlots = 0
                for _, s in ipairs(currentList) do
                    if s and (s.ID or s.id or s.Name) and (s.ID ~= "" and s.id ~= "") then
                        usedSlots = usedSlots + 1
                    end
                end

                local emptySlots = maxSlots - usedSlots
                while emptySlots > 0 and stoneIdx <= #usableStones do
                    local stone = usableStones[stoneIdx]
                    stoneIdx = stoneIdx + 1
                    local fired = false
                    pcall(function()
                        if BackpackData and BackpackData.EnchantEquipment then
                            BackpackData.EnchantEquipment(uuid, stone.UUID)
                            fired = true
                        elseif enchantRE then
                            enchantRE:FireServer(uuid, stone.UUID)
                            fired = true
                        end
                    end)
                    if fired then
                        totalEnchanted = totalEnchanted + 1
                        emptySlots = emptySlots - 1
                        task.wait(0.2)
                    end
                end
            end
        end
        if stoneIdx > #usableStones then break end
    end

    return totalEnchanted > 0, totalEnchanted
end

local function getBindable(category, name)
    local be = nil
    pcall(function()
        local CommunicationUtils = require(ReplicatedStorage.Utils.CommunicationUtils)
        be = CommunicationUtils.TryGetBindableEvent(category, name)
    end)
    return be
end

local ActiveThreads = {}
local function loop(flag, delay, fn)
    if ActiveThreads[flag] then return end
    ActiveThreads[flag] = true
    task.spawn(function()
        while State[flag] do
            local ok, err = pcall(fn)
            if not ok and State.Debug then warn("[NAPHUB Loop Error]:", flag, err) end
            local waitTime = type(delay) == "string" and State[delay] or delay
            task.wait(math.max(waitTime or 0.1, 0.05))
        end
        ActiveThreads[flag] = nil
    end)
end

local function toggleLoop(flag, delay, fn)
    return function(v)
        State[flag] = v
        if v then loop(flag, delay, fn) end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Discord Webhook Telemetry
-- ─────────────────────────────────────────────────────────────
local function sendWebhook(title, description, fields, color)
    if not State.WebhookEnabled or not State.WebhookUrl or State.WebhookUrl == "" then return end
    local req = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not req then return end

    task.spawn(function()
        local embed = {
            title = title,
            description = description,
            color = color or 16720962, -- NAPHUB Scarlet
            fields = fields or {},
            footer = { text = "NAPHUB +1 Loot a Forge | ระบบไก่ตัน Telemetry" },
            timestamp = DateTime.now():ToIsoDate(),
        }
        pcall(function()
            req({
                Url = State.WebhookUrl,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({ embeds = { embed } }),
            })
        end)
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Config File Persistence (JSON)
-- ─────────────────────────────────────────────────────────────
local ConfigFileName = "NAPHUB_Plus1LootForge.json"

local function saveConfig()
    if not writefile then return end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(State)
    end)
    if ok and encoded then
        writefile(ConfigFileName, encoded)
        if State.Debug then print("[NAPHUB] State successfully persisted to disk") end
    end
end

-- ★ ทุก Toggle ต้องเริ่มที่ 'ปิด' เสมอ — จะทำงานก็ต่อเมื่อผู้ใช้เลื่อนเปิดเอง
local function forceAllTogglesOff()
    for k, v in pairs(State) do
        if type(v) == "boolean" then State[k] = false end
    end
end
forceAllTogglesOff()

local function loadConfig()
    if not (isfile and readfile and isfile(ConfigFileName)) then return false end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(ConfigFileName))
    end)
    if ok and type(decoded) == "table" then
        for k, v in pairs(decoded) do
            if State[k] ~= nil and type(State[k]) == type(v) then
                State[k] = v
            end
        end
        forceAllTogglesOff() -- ห้ามให้ config เปิด Toggle เอง
        return true
    end
    return false
end

loadConfig()



local function getSelectedTrainZone()
    local sel = State and State.SelectedTrainZone
    if not sel or sel == TRAIN_AUTO_BEST then return getBestTrainZone() end
    return getZoneByName(sel) or getBestTrainZone()
end

local _currentTrainZoneId = nil
local _lastTrainTeleportTick = 0

local function disengageIdleTraining()
    pcall(function()
        local tc = TrainCTRL or (ReplicatedStorage:FindFirstChild("CTRL") and require(ReplicatedStorage.CTRL.TrainCTRL))
        if tc then
            if tc.GetIsAutoing and tc.GetIsAutoing() then
                tc.ExitAutoTrain()
            end
            if tc.GetIsTraining and tc.GetIsTraining() then
                tc.EndTrain()
            end
        end
    end)
    pcall(function()
        LocalPlayer:SetAttribute("AutoTrainAreaID", nil)
        call("Train", "ExitAutoTrainRE")
    end)
    _currentTrainZoneId = nil
end

local function engageIdleTraining()
    local inFight = LocalPlayer:GetAttribute("IntoFight")
    local inDung  = LocalPlayer:GetAttribute("Dungeoning")
    if inFight or inDung then return end
    local r = hrp()
    if not r then return end

    -- Safe Pad Selection:
    -- In bypass mode, physically stand on the best unlocked non-pay pad (safe pad)
    -- to avoid triggering the VIP pad's Touched event which prompts Robux purchase and wipes AutoTrainAreaID.
    local safePad = getBestLegitTrainZone() or TrainAreaConfig[1]
    local targetId = (State.ForceVIPTrain and 9) or (safePad and safePad.Id) or 1

    local part = safePad and getTrainZonePart(safePad.Id)
    local targetCF = (part and (part.CFrame + Vector3.new(0, 3.2, 0)))
        or (safePad and safePad.PadPos and CFrame.new(safePad.PadPos + Vector3.new(0, 1.5, 0)))
        or (safePad and safePad.FallbackPos and CFrame.new(safePad.FallbackPos + Vector3.new(0, 3.2, 0)))

    if targetCF then
        local dist = (r.Position - targetCF.Position).Magnitude
        local now = os.clock()
        if dist > 4.0 or _currentTrainZoneId ~= targetId then
            _currentTrainZoneId = targetId
            _lastTrainTeleportTick = now
            pcall(function()
                r.AssemblyLinearVelocity = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
                r.CFrame = targetCF
            end)
            task.wait(0.06)
            if part and typeof(firetouchinterest) == "function" then
                pcall(function()
                    firetouchinterest(r, part, 0)
                    task.wait(0.02)
                    firetouchinterest(r, part, 1)
                end)
            end
        end
    end

    -- Broadcast target ID + fire remote (in bypass mode, sets x100 multiplier)
    State.TrainArea = tostring(targetId)
    LocalPlayer:SetAttribute("AutoTrainAreaID", targetId)
    call("Train", "IntoAutoTrainRE", targetId)

    pcall(function()
        local tc = TrainCTRL or (ReplicatedStorage:FindFirstChild("CTRL") and require(ReplicatedStorage.CTRL.TrainCTRL))
        if tc then
            if tc.StartTrain and not (tc.GetIsTraining and tc.GetIsTraining()) then
                tc.StartTrain()
            end
            if tc.StartAutoTrain and not (tc.GetIsAutoing and tc.GetIsAutoing()) then
                tc.StartAutoTrain()
            end
            if State.ForceVIPTrain then
                LocalPlayer:SetAttribute("AutoTrainAreaID", 9)
                call("Train", "IntoAutoTrainRE", 9)
            end
            if tc.TrainOnce then tc.TrainOnce() end
        else
            if State.ForceVIPTrain then
                LocalPlayer:SetAttribute("AutoTrainAreaID", 9)
                call("Train", "IntoAutoTrainRE", 9)
            end
            call("Train", "TrainOnceRE")
        end
    end)
    Stats.CurrentActivity = TF("StatusTrain", (targetId == 9 and "9 (x100 VIP)" or (safePad and safePad.Name) or tostring(targetId)))
end

-- ★ เข้าแท่นฝึกพลังที่เลือก (วาร์ปไปที่แท่น หันหน้าเข้าหุ่น แล้วสั่งเข้าโซน)
local function enterTrainZone(zone)
    zone = zone or getSelectedTrainZone()
    if not zone then return end

    if State.ForceVIPTrain then
        engageIdleTraining()
        return
    end

    local standPad = zone
    if zone.IsPay then
        standPad = getBestLegitTrainZone() or TrainAreaConfig[1]
    end

    local r, h = hrp(), hum()
    if r and h and h.Health > 0 and standPad.PadPos then
        local cur = r.Position
        local dist = (Vector3.new(cur.X, standPad.PadPos.Y, cur.Z) - standPad.PadPos).Magnitude
        if dist > 6 then
            r.CFrame = CFrame.lookAt(standPad.PadPos + Vector3.new(0, 1.5, 0), standPad.DummyPos or (standPad.PadPos + Vector3.new(0, 0, 5)))
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            task.wait(0.1)
        end
    end
    local targetId = zone.Id
    if LocalPlayer:GetAttribute("AutoTrainAreaID") ~= targetId then
        call("Train", "IntoAutoTrainRE", targetId)
    end
    State.TrainArea = tostring(targetId)
end

-- ─────────────────────────────────────────────────────────────
-- Core Engine 1: Drop Magnet & Safe Loot
-- ─────────────────────────────────────────────────────────────
local function runDropMagnet()
    local oreCache = workspace:FindFirstChild("OreCache")
    if not oreCache then return end

    local targetCF
    if State.MagnetTarget == "Safe Zone" then
        targetCF = getSafeZoneCF() + Vector3.new(0, 2, 0)
    else
        local r = hrp()
        if not r then return end
        targetCF = r.CFrame
    end

    local children = oreCache:GetChildren()
    for _, drop in ipairs(children) do
        if drop:IsA("Model") then
            pcall(function()
                if drop.PrimaryPart then
                    drop.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
                    drop.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
                    drop.PrimaryPart.CanCollide = false
                end
                drop:PivotTo(targetCF)
            end)
        end
    end
end

local notifiedDrops = {}
local function runUltraPrompts()
    if not fireproximityprompt then return end

    local oreCache = workspace:FindFirstChild("OreCache")
    local prompts = {}
    if oreCache then
        for _, p in ipairs(oreCache:GetDescendants()) do
            if p:IsA("ProximityPrompt") and p.Enabled then
                table.insert(prompts, p)
            end
        end

        -- Check for rare drops to dispatch Webhook alert
        if State.NotifyRareDrops and State.WebhookEnabled then
            for _, drop in ipairs(oreCache:GetChildren()) do
                if drop:IsA("Model") and not notifiedDrops[drop] then
                    local name = drop.Name
                    local highlight = drop:FindFirstChildOfClass("Highlight")
                    if highlight and (name:find("Mythic") or name:find("Eternal") or name:find("Secret") or name:find("Ancient") or name:find("Infinite")) then
                        notifiedDrops[drop] = true
                        local isTH = State.Language == "TH"
                        sendWebhook(
                            isTH and "ตรวจพบไอเทมหายากระดับสูง!" or "Rare Item Acquired",
                            isTH and "ระบบดูดของปลอดภัยจัดเก็บไอเทมเข้ากระเป๋าเรียบร้อยแล้ว" or "A rare drop was generated and secured by Safe Magnet.",
                            {
                                { name = isTH and "ชื่อไอเทม" or "Drop Item", value = name, inline = true },
                                { name = isTH and "กิจกรรมปัจจุบัน" or "Location", value = tostring(Stats.CurrentActivity), inline = true },
                            },
                            0xF59E0B
                        )
                    end
                end
            end
        end
    end

    -- Targeted prompt activation: only scan OreCache (and Drops if exists), avoiding entire workspace scan
    for _, p in ipairs(prompts) do
        pcall(function()
            p.MaxActivationDistance = 1e6
            p.RequiresLineOfSight = false
            p.HoldDuration = 0
            fireproximityprompt(p, 0)
            Stats.OresCollected = Stats.OresCollected + 1
        end)
    end
end

local lastSafeEvacuationAt = 0
local function checkSafeEvacuate()
    local cur, maxNum = getPackInfo()
    local packFullPercent = (cur / math.max(maxNum, 1)) * 100

    local h = hum()
    local hpPercent = h and ((h.Health / math.max(h.MaxHealth, 1)) * 100) or 100

    local shouldEvacuate = false
    local reason = ""

    if State.AutoSafeEvacuate and packFullPercent >= State.EvacuateThreshold then
        shouldEvacuate = true
        reason = ("Pack Full (%d/%d)"):format(cur, maxNum)
    elseif State.LowHPEvacuate and hpPercent <= State.LowHPThreshold then
        shouldEvacuate = true
        reason = ("Critical HP (%.1f%%)"):format(hpPercent)
    end

    if shouldEvacuate then
        -- A full pack can remain full if the server rejects a claim/sell request.
        -- Avoid re-running the full evacuation sequence every Master loop tick.
        local now = os.clock()
        if now - lastSafeEvacuationAt < 20 then return true end
        lastSafeEvacuationAt = now

        Stats.CurrentActivity = TF("StatusSafeEvacuate", reason)
        call("Stage", "ClaimedAllOreRE")
        local safeCF = getSafeZoneCF()
        tpTo(safeCF)
        task.wait(0.3)
        call("Backpack", "TrySellAllRE")
        Stats.SellCycles = Stats.SellCycles + 1
        task.wait(0.2)
        call("Upgrade", "UpgradeOnceRE", "OrePack")
        task.wait(0.5)
        notify(
            State.Language == "TH" and "อพยพปลอดภัย" or "Safe Zone Evacuate",
            State.Language == "TH" and ("จัดเก็บแร่เข้าโซนปลอดภัยและขายเป็นเงินเรียบร้อยแล้ว (" .. reason .. ")") or ("Loot secured at Safe Zone and converted to cash (" .. reason .. ")"),
            "shield-check"
        )
        return true
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
-- Core Engine 2: Combat, Kill Aura & Instant Kill
-- ─────────────────────────────────────────────────────────────

-- Helper to retrieve DungeonManager environment and internal state table (u140)
local function getDungeonManagerEnv()
    local dmEnv, u140 = nil, nil
    pcall(function()
        local dmScript = LocalPlayer.PlayerScripts:FindFirstChild("Manager")
            and LocalPlayer.PlayerScripts.Manager:FindFirstChild("DungeonManager")
        if dmScript and getsenv then
            dmEnv = getsenv(dmScript)
            if dmEnv and debug and debug.getupvalues and dmEnv.CheckFinishedOnce then
                local upvals = debug.getupvalues(dmEnv.CheckFinishedOnce)
                if upvals and type(upvals[1]) == "table" then
                    u140 = upvals[1]
                end
            end
        end
    end)
    return dmEnv, u140
end

-- ★ INSTANT KILL — single enemy (multi-layer: BindableEvent + EnemyCTRL + HPCTRL + Humanoid)
local function instantKillEnemy(enemy)
    if not enemy or not enemy:IsA("Model") then return end
    local uuid = enemy:GetAttribute("UUID") or enemy.Name
    if not uuid then return end

    -- Dungeon Anti-Freeze: Ensure DeadCF is set so RewardUtils.CreateOres never errors
    pcall(function()
        local _, u140 = getDungeonManagerEnv()
        if u140 then
            local pivot = enemy:GetPivot()
            local r = hrp()
            u140.DeadCF = pivot or (r and r.CFrame) or CFrame.new(3482, 23, -4)
        end
    end)

    local _, hrpLocal = pcall(function() return (LocalPlayer.Character or workspace:FindFirstChild(LocalPlayer.Name)):FindFirstChild("HumanoidRootPart") end)
    pcall(function()
        -- Layer 1: native BindableEvent
        if Bindable_EnemyHit then
            Bindable_EnemyHit:Fire(uuid, 1e30)
        end
        -- Layer 2: EnemyCTRL direct hurt
        if EnemyCTRL then
            if EnemyCTRL.HurtEnemy then EnemyCTRL.HurtEnemy(uuid, 1e30) end
            if EnemyCTRL.DeadEnemyData then EnemyCTRL.DeadEnemyData(uuid) end
        end
        -- Layer 3: HP bar zero
        if HPCTRL and HPCTRL.SetCurrentHP then
            HPCTRL.SetCurrentHP(enemy, 0)
        end
        -- Layer 4: humanoid health zero + dead attribute
        enemy:SetAttribute("Dead", true)
        local hum = enemy:FindFirstChildOfClass("Humanoid")
        if hum then hum.Health = 0 end
        Stats.Kills = Stats.Kills + 1
    end)
end

-- ★ INSTANT KILL — all enemies in EnemyFolder
local function instantKillAllEnemies()
    local enemyFolder = workspace:FindFirstChild("EnemyFolder")
    if not enemyFolder then return 0 end
    local killed = 0
    for _, enemy in ipairs(enemyFolder:GetChildren()) do
        if enemy:IsA("Model") and not enemy:GetAttribute("Dead") then
            instantKillEnemy(enemy)
            killed = killed + 1
        end
    end
    return killed
end

-- Standard Kill Aura (lightweight, via BindableEvent only)
local function runKillAura()
    local hitBE = Bindable_EnemyHit or getBindable("Attack", "EnemyHitBE")
    if not hitBE then return end

    local enemyFolder = workspace:FindFirstChild("EnemyFolder")
    if not enemyFolder then return end

    local enemies = enemyFolder:GetChildren()
    if #enemies == 0 then return end

    for _, enemy in ipairs(enemies) do
        if enemy:IsA("Model") and not enemy:GetAttribute("Dead") then
            pcall(function()
                hitBE:Fire(enemy.Name, 99999999, { SkillID = "K_Skill_1_ATK" })
                Stats.Kills = Stats.Kills + 1
            end)
        end
    end

    local superLootFolder = workspace:FindFirstChild("SuperLootFolder")
    if superLootFolder then
        for _, s in ipairs(superLootFolder:GetChildren()) do
            pcall(function()
                hitBE:Fire(s.Name, 99999999, { SkillID = "K_Skill_1_ATK" })
            end)
        end
    end
end

local function runSafeFlight()
    if not State.SafeCombatFlight then return end
    local r = hrp()
    if not r then return end

    local enemyFolder = workspace:FindFirstChild("EnemyFolder")
    local hasEnemies = enemyFolder and #enemyFolder:GetChildren() > 0

    if hasEnemies then
        local firstEnemy = enemyFolder:GetChildren()[1]
        if firstEnemy and firstEnemy:IsA("Model") and firstEnemy.PrimaryPart then
            local enemyPos = firstEnemy.PrimaryPart.Position
            r.AssemblyLinearVelocity = Vector3.zero
            r.CFrame = CFrame.new(enemyPos.X, enemyPos.Y + State.FlightHeight, enemyPos.Z)
        end
    end
end

local function maintainGodMode()
    if State.GodMode then
        pcall(function()
            LocalPlayer:SetAttribute("Invincible", true)
            local HPCTRL = require(ReplicatedStorage.CTRL.HPCTRL)
            HPCTRL.SetCurrentHP(LocalPlayer, HPCTRL.GetMaxHP(LocalPlayer))
        end)
    end
end

-- ─────────────────────────────────────────────────────────────
-- Core Engine 3: Super Loot Boss Hunter (Auto Sniper)
-- ─────────────────────────────────────────────────────────────
local huntedBosses = {}
local function checkSuperLootHunter()
    if not State.SuperLootHunter then return end
    local superLootFolder = workspace:FindFirstChild("SuperLootFolder")
    if not superLootFolder or #superLootFolder:GetChildren() == 0 then return end

    for _, bossVal in ipairs(superLootFolder:GetChildren()) do
        local bossRarity = bossVal.Name
        if State.SuperLootTargetTier == "All" or State.SuperLootTargetTier == bossRarity then
            local enemyFolder = workspace:FindFirstChild("EnemyFolder")
            local targetBossModel = nil
            if enemyFolder then
                for _, e in ipairs(enemyFolder:GetChildren()) do
                    if e:GetAttribute("EnemyID") and tostring(e:GetAttribute("EnemyID")):find("Super") then
                        targetBossModel = e
                        break
                    end
                end
            end

            if targetBossModel and targetBossModel.PrimaryPart and not huntedBosses[targetBossModel] then
                Stats.CurrentActivity = TF("StatusSuperLootHunt", bossRarity)
                notify(
                    State.Language == "TH" and "ล่าบอสแร่ยักษ์" or "Super Loot Hunter",
                    TF("Notif_BossAcquired", bossRarity),
                    "crosshair"
                )

                if State.NotifySuperLoot then
                    local isTH = State.Language == "TH"
                    sendWebhook(
                        isTH and "ตรวจพบบอสแร่ยักษ์เป้าหมาย!" or "Super Loot Target Engaged",
                        isTH and "ระบบสไนป์บอสเข้าโจมตีและเก็บเกี่ยวของรางวัลเรียบร้อย" or "Autonomous sniper intercepted active Super Loot.",
                        {
                            { name = isTH and "ระดับความหายาก" or "Tier / Rarity", value = bossRarity, inline = true },
                            { name = isTH and "พิกัดเป้าหมาย" or "Coordinates", value = tostring(targetBossModel.PrimaryPart.Position), inline = true },
                        },
                        0xEF4444
                    )
                end

                tpTo(targetBossModel.PrimaryPart.CFrame + Vector3.new(0, 8, 0))
                task.wait(0.2)
                runKillAura()
                call("SuperLoot", "KillSuperLootRE", targetBossModel.Name)
                Stats.SuperLootKills = Stats.SuperLootKills + 1
                huntedBosses[targetBossModel] = true

                task.wait(0.5)
                runDropMagnet()
                runUltraPrompts()
                break
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Core Engine 4: Dungeon & Stage Loop (PRIMARY FARM LOOPS)
-- ─────────────────────────────────────────────────────────────

-- ★ DUNGEON — primary farm loop (runs when tickets available)
local function runDungeonLoop()
    if not State.AutoDungeon then return end
    if checkSafeEvacuate() then return end

    local isDungeoning = LocalPlayer:GetAttribute("Dungeoning")
    if not isDungeoning then
        Stats.CurrentActivity = TF("StatusDungeonEnter", tostring(State.DungeonRound))
        if State.AutoClaimTicket then
            call("Dungeon", "TryClaimDailyDunTicRE")
        end
        local ok = call("Dungeon", "TryIntoDungeonRF", State.DungeonRound)
        task.wait(0.8)
        if ok or LocalPlayer:GetAttribute("Dungeoning") then
            call("Dungeon", "StartRoundRE", State.DungeonRound)
        end
    else
        Stats.CurrentActivity = T("StatusDungeonWave")

        local dmEnv, u140 = getDungeonManagerEnv()

        -- Check if round 30 is reached and finished -> exit dungeon cleanly
        if u140 and u140.Round and u140.Round >= 30 and u140.Finished then
            if dmEnv and dmEnv.ExitDungeon then
                pcall(function() dmEnv.ExitDungeon() end)
                task.wait(1.0)
                return
            else
                call("Dungeon", "ExitDungeonRE")
                task.wait(1.0)
                return
            end
        end

        -- ★ INSTANT KILL dungeon mobs first (highest priority)
        if State.DungeonInstaKill then
            local killed = instantKillAllEnemies()
            -- If InstaKill fired, advance round cleanly via CheckFinishedOnce
            if killed > 0 then
                pcall(function()
                    if dmEnv and dmEnv.CheckFinishedOnce then
                        dmEnv.CheckFinishedOnce()
                    end
                end)
            end
        end

        -- Standard KillAura as secondary layer
        runKillAura()
        if State.DropMagnet then runDropMagnet() end
        if State.UltraPrompt then runUltraPrompts() end
        runSafeFlight()
    end
end

-- ★ STAGE — secondary farm loop (runs without tickets / always)
local function runStageLoop()
    if not State.AutoStage then return end
    if LocalPlayer:GetAttribute("Dungeoning") then return end
    if checkSafeEvacuate() then return end

    -- 1. Determine Target Stage (Handles "Auto Max" via ProfileData or manual selection)
    local targetStageId, stageNum = getTargetStageId()
    Stats.CurrentActivity = TF("StatusStageEnter", targetStageId)
    LocalPlayer:SetAttribute("StageID", targetStageId)

    -- 2. Remote Direct Invocation: Clear stage on server & claim drops instantly without walking
    local stageFinishedRF = getRemote("Stage", "StageFinishedRF")
    local getOreRF        = getRemote("Stage", "GetOreRF")
    local claimedAllOreRE = getRemote("Stage", "ClaimedAllOreRE")

    if stageFinishedRF and stageFinishedRF:IsA("RemoteFunction") then
        local ok, ores = pcall(function()
            return stageFinishedRF:InvokeServer(targetStageId)
        end)
        if ok and type(ores) == "table" then
            if getOreRF and getOreRF:IsA("RemoteFunction") then
                for oreUuid in pairs(ores) do
                    Stats.OresCollected = Stats.OresCollected + 1
                    pcall(function() getOreRF:InvokeServer(oreUuid) end)
                end
            end
            if claimedAllOreRE then
                pcall(function() claimedAllOreRE:FireServer() end)
            end
            Stats.LastStageClear = os.time()
        end
    end

    -- 3. If physically inside stage encounter, instant-kill active mobs as fallback
    local intoFight = LocalPlayer:GetAttribute("IntoFight")
    if intoFight then
        Stats.CurrentActivity = TF("StatusStageFight", targetStageId)
        if State.StageInstaKill then
            instantKillAllEnemies()
        end
        runKillAura()
        runSafeFlight()
    end

    -- 4. Magnet & UltraPrompt for ground drops
    if State.DropMagnet then runDropMagnet() end
    if State.UltraPrompt then runUltraPrompts() end

    -- 5. Auto Progressive Climbing if using manual mode with AutoClimbStages enabled
    if State.AutoClimbStages and not (State.SelectedStage and State.SelectedStage:find("Auto Max")) then
        local enemyFolder = workspace:FindFirstChild("EnemyFolder")
        local remainingEnemies = enemyFolder and #enemyFolder:GetChildren() or 0
        if remainingEnemies == 0 then
            local currentIndex = table.find(Dynamic.Stages, State.SelectedStage) or 1
            if currentIndex < #Dynamic.Stages then
                State.SelectedStage = Dynamic.Stages[currentIndex + 1]
                Stats.LastStageClear = os.time()
                notify(
                    State.Language == "TH" and "เลื่อนระดับด่าน" or "Stage Advance",
                    TF("Notif_StageAdvance", State.SelectedStage),
                    "arrow-up-right"
                )
                task.wait(0.5)
            end
        else
            if os.time() - Stats.LastStageClear > State.StageClimbTimeout then
                local currentIndex = table.find(Dynamic.Stages, State.SelectedStage) or 1
                if currentIndex > 2 then -- keep above Auto Max index 1
                    State.SelectedStage = Dynamic.Stages[currentIndex - 1]
                    Stats.LastStageClear = os.time()
                    notify(
                        State.Language == "TH" and "ถอยกลับด่านเดิม" or "Stage Retreat",
                        TF("Notif_StageRetreat", State.SelectedStage),
                        "shield-alert"
                    )
                    call("Stage", "ClaimedAllOreRE")
                    tpTo(getSafeZoneCF())
                    task.wait(0.8)
                end
            end
        end
    end
end

-- ★ GOD-Farm: High-Speed Stage Blitz (Pipeline 0.08–0.1s per stage)
local _isBlitzingStages = false
local function runStageBlitz()
    if _isBlitzingStages then return end
    if LocalPlayer:GetAttribute("Dungeoning") then return end
    if checkSafeEvacuate() then return end

    local stageFinishedRF = getRemote("Stage", "StageFinishedRF")
    local getOreRF        = getRemote("Stage", "GetOreRF")
    local claimedAllOreRE = getRemote("Stage", "ClaimedAllOreRE")
    if not (stageFinishedRF and stageFinishedRF:IsA("RemoteFunction")) then return end

    pcall(disengageIdleTraining)
    _isBlitzingStages = true
    Stats.CurrentActivity = State.Language == "TH" and "GOD-Farm: ทะลวง Stage 1-30" or "GOD-Farm: Stage Blitz 1-30"

    task.spawn(function()
        for i = 1, 30 do
            if not (State.GodFarmStageBlitz or (State.Master247 and State.MasterStageBlitz)) then break end
            if LocalPlayer:GetAttribute("Dungeoning") then break end
            if checkSafeEvacuate() then break end

            local stageId = "Stage_" .. i
            local ok, ores = pcall(function()
                return stageFinishedRF:InvokeServer(stageId)
            end)

            if ok and type(ores) == "table" then
                if getOreRF and getOreRF:IsA("RemoteFunction") then
                    for oreUuid in pairs(ores) do
                        Stats.OresCollected = Stats.OresCollected + 1
                        pcall(function() getOreRF:InvokeServer(oreUuid) end)
                    end
                end
                if claimedAllOreRE then
                    pcall(function() claimedAllOreRE:FireServer() end)
                end
                Stats.LastStageClear = os.time()
            end

            -- ★ Concurrent Forging during blitz pipeline
            if (State.MasterConcurrentForge or (State.Master247 and State.MasterAutoForgeWhenReady)) and (i == 15 or i == 30) then
                pcall(function()
                    local items = getBackpackItems()
                    if items then
                        local totalOres = 0
                        for _, item in pairs(items) do
                            if type(item) == "table" and item.Type == "Ore" then
                                totalOres = totalOres + (tonumber(item.Number) or 1)
                            end
                        end
                        if totalOres >= 8 then
                            executeForgeNow("Armor", 8)
                        elseif totalOres >= 4 then
                            executeForgeNow("Weapon", 4)
                        end
                    end
                end)
            end

            task.wait(State.StageBlitzInterval or 0.09)
        end

        if State.DropMagnet then pcall(runDropMagnet) end
        if State.UltraPrompt then pcall(runUltraPrompts) end
        _isBlitzingStages = false
    end)
end

-- ★ SWORD POWER CLICKER (Auto Click / Swing Sword)
local _lastSwordTrainTick = 0
local function runSwordClickFarm()
    local now = os.clock()
    local delay = tonumber(State.SwordClickDelay) or 0.16
    if now - _lastSwordTrainTick < delay then return end
    _lastSwordTrainTick = now

    if State.ForceVIPTrain then
        LocalPlayer:SetAttribute("AutoTrainAreaID", 9)
        call("Train", "IntoAutoTrainRE", 9)
    end

    local tc = TrainCTRL or (ReplicatedStorage:FindFirstChild("CTRL") and require(ReplicatedStorage.CTRL.TrainCTRL))
    if tc and type(tc.TrainOnce) == "function" then
        pcall(tc.TrainOnce)
    else
        call("Train", "TrainOnceRE")
    end
end

-- ─────────────────────────────────────────────────────────────
-- Core Engine 5: Class Gacha, Pet Equipper & Potions
-- ─────────────────────────────────────────────────────────────
local function runClassAndSkillRoll()
    if State.AutoRollClass then
        local currentClass = "Class_1"
        pcall(function()
            local ClassData = require(ReplicatedStorage.LocalData.ClassData)
            currentClass = ClassData.GetEquipedClass() or "Class_1"
        end)

        if currentClass ~= State.TargetClassToLock then
            Stats.CurrentActivity = TF("StatusRollClass", currentClass)
            call("Class", "LuckOnceRE", "1")
        else
            call("Class", "SetIndexLockRE", "1")
            call("Class", "ChangeEquipedIndexRE", "1")
            State.AutoRollClass = false
            notify(
                State.Language == "TH" and "สุ่มคลาสสำเร็จ" or "Class Gacha",
                TF("Notif_ClassLocked", currentClass),
                "check-circle"
            )
        end
    end

    if State.AutoRollSkills then
        call("Backpack", "LuckSkillCell_2RE")
    end
end

local function runPotionAndHatch()
    if State.AutoUsePotions then
        pcall(function()
            local BuffData = require(ReplicatedStorage.LocalData.BuffData)
            for _, pot in ipairs(Dynamic.Potions) do
                if not BuffData.IsHaveBuff(pot) then
                    call("Potion", "TryUsePotionRE", pot)
                    task.wait(0.1)
                end
            end
        end)
    end

    if State.AutoHatchEggs then
        call("Egg", "PutEggRE")
    end
end

-- ─────────────────────────────────────────────────────────────
-- Core Engine 6: Master ระบบไก่ตัน Automation Loop
-- ★ PRIORITY ORDER (CORRECTED):
--   1. Safety check (evac/HP)
--   2. Super Loot sniper (if enabled)
--   3. Claim daily tickets & rewards
--   4. DUNGEON (primary farm — if has tickets)
--   5. STAGE  (secondary farm — always when no dungeon)
--   6. TRAIN  (idle fallback — only when nothing else to do)
--   7. Magnet/Prompt sweep
--   8. UPGRADE (background, runs in separate loop)
--   9. FORGE  (only when ore count ≥ threshold — NOT every tick)
--  10. EQUIP / REBIRTH / POTIONS
-- ─────────────────────────────────────────────────────────────
local _masterUpgradeTick = 0
local _masterForgeTick   = 0
local _masterClaimTick   = 0
local _masterEnchantTick = 0

local function runMaster247Engine()
    if not State.Master247 then return end

    -- 1. Safety first
    if checkSafeEvacuate() then
        task.wait(0.8)
        return
    end

    -- 2. Super Loot Sniper (opportunistic — runs regardless of dungeon/stage)
    if State.SuperLootHunter then
        pcall(checkSuperLootHunter)
    end

    -- 3. Periodic claims (every 60 s to avoid spam)
    local now = os.clock()
    if now - _masterClaimTick >= 60 then
        _masterClaimTick = now
        pcall(function()
            call("Offline", "TryClaimOfflineRewardRE")
            call("Dungeon", "TryClaimDailyDunTicRE")
            for i = 1, 12 do call("Online", "TryClaimRE", i) end
        end)
    end

    -- 4 & 5. FARM LOOP — Dungeon > Stage (core of the bot)
    local hasTickets = false
    pcall(function()
        local bd = require(ReplicatedStorage.LocalData.BackpackData)
        local t = bd.GetItemDataByIDType and bd.GetItemDataByIDType("Dungeon_Ticket", "Material")
        hasTickets = t and (tonumber(t.Number) or 0) > 0
    end)

    if hasTickets and State.MasterDungeonTicket then
        -- ★ PRIMARY: Dungeon farm
        State.AutoDungeon = true
        State.AutoStage   = false
        State.AutoTrain   = false
        pcall(runDungeonLoop)
    else
        -- ★ SECONDARY: Stage farm (always on when no dungeon)
        State.AutoDungeon = false
        State.AutoStage   = true
        State.AutoTrain   = false
        if State.MasterStageBlitz or State.GodFarmStageBlitz then
            pcall(runStageBlitz)
        else
            pcall(runStageLoop)
        end
    end

    -- ★ SWORD POWER AUTO-CLICK: Continuous Power Point Accumulation (+2/swing)
    if State.MasterAutoClickSword then
        pcall(runSwordClickFarm)
    end

    -- 6. TRAIN fallback — only when explicitly idle (no fight, no dungeon)
    --    This is NOT the default; stage is always preferred.
    local inFight  = LocalPlayer:GetAttribute("IntoFight")
    local inDung   = LocalPlayer:GetAttribute("Dungeoning")
    if State.MasterTrainWhenIdle and not inFight and not inDung then
        if State.ForceVIPTrain then
            pcall(engageIdleTraining)
        else
            -- Use best available multiplier zone if AutoTrainBestZone is on
            if State.AutoTrainBestZone then
                pcall(enterTrainZone)
            end
            if not _isBlitzingStages then
                Stats.CurrentActivity = TF("StatusTrain", tostring(State.TrainArea))
            end
            local tc = TrainCTRL or (ReplicatedStorage:FindFirstChild("CTRL") and require(ReplicatedStorage.CTRL.TrainCTRL))
            if tc and type(tc.TrainOnce) == "function" then
                pcall(tc.TrainOnce)
            else
                call("Train", "TrainOnceRE")
            end
        end
    end

    -- 7. Magnet & Prompt sweep
    if State.DropMagnet then pcall(runDropMagnet) end
    if State.UltraPrompt then pcall(runUltraPrompts) end

    -- 8. UPGRADE (background — every 3 s so it doesn't flood)
    if State.MasterAutoUpgrade and (now - _masterUpgradeTick >= 3) then
        _masterUpgradeTick = now
        pcall(function()
            if State.UpgradeType == "All in One" then
                call("Upgrade", "UpgradeOnceRE", "Train")
                call("Upgrade", "UpgradeOnceRE", "OrePack")
                call("Upgrade", "UpgradeOnceRE", "Luck")
            elseif State.AutoUpgrade then
                call("Upgrade", "UpgradeOnceRE", State.UpgradeType)
            end
        end)
    end

    -- 9. FORGE — ONLY when ore count ≥ threshold (not every tick!)
    if State.MasterAutoForgeWhenReady and State.AutoForge and (now - _masterForgeTick >= 2) then
        _masterForgeTick = now
        pcall(function()
            -- Count ores first
            local items = getBackpackItems()
            if not items then return end
            local totalOres = 0
            for _, item in pairs(items) do
                if type(item) == "table" and item.Type == "Ore" then
                    totalOres = totalOres + (tonumber(item.Number) or 1)
                end
            end
            -- Only forge when ores >= configured threshold
            if totalOres >= State.MinOreToForge then
                local ok, result = executeForgeNow(State.ForgeType, State.MinOreToForge)
                if ok then
                    -- After forging, immediately equip best
                    task.delay(0.3, function() pcall(function() equipBestGearNow("All") end) end)
                elseif State.Debug then
                    warn("[NAPHUB Forge]: " .. tostring(result))
                end
            end
        end)
    end

    -- 10. Equip best gear (periodic)
    if State.AutoEquipBest then pcall(function() equipBestGearNow("All") end) end

    -- 11. Auto Enchant equipped gear with safe grade filtering (every 4 s)
    if State.AutoEnchant and (now - _masterEnchantTick >= (State.EnchantDelay or 2.0)) then
        _masterEnchantTick = now
        if State.AlgorithmicDPSSolver then
            pcall(runAlgorithmicGearSolver)
        else
            pcall(autoEnchantEquippedGear)
        end
    end

    -- 12. Rebirth check
    if State.AutoRebirth then
        pcall(function()
            call("Rebirth", "TryRebirthRE")
            Stats.RebirthCount = Stats.RebirthCount + 1
        end)
    end

    -- 13. Potions & Hatch
    pcall(runPotionAndHatch)
    pcall(runClassAndSkillRoll)
end

local function claimAllRewards()
    call("Offline", "TryClaimOfflineRewardRE")
    for i = 1, 12 do
        call("Online", "TryClaimRE", i)
        task.wait(0.05)
    end
    call("UpdateLog", "TryClaimUPDRewardRE")
    call("Dungeon", "TryClaimDailyDunTicRE")
    call("EnhantEvent", "TryClaimQuestRE")
    call("Index", "TryClaimIndexExpRF")
    call("Index", "TryClaimLevelRewardRF")
end

-- ─────────────────────────────────────────────────────────────
-- Theme Presets & UI Construction
-- ─────────────────────────────────────────────────────────────
local StatusCard, StatsCard, BagCard
local BuildUI
local ToggleUiConnection
local UIRebuilding = false
-- ─────────────────────────────────────────────────────────────
-- NAPHUB UI Engine : Metal Dragon Theme (เมนู + ลูกลอย จากไฟล์ Ui-NAPHUB)
-- API เดิมของ NapUI ครบทุกตัว (Tab/Section/Toggle/Button/Slider/Dropdown/Input/Paragraph)
-- ดังนั้น BuildUI และฟังก์ชันอื่นของต้นฉบับไม่ถูกแก้ไขเลย
-- ─────────────────────────────────────────────────────────────

-- รูปโลโก้ลูกลอย + รูปพื้นหลังเมนู ฝังอยู่ในสคริปต์ (ต้องใช้ executor ที่รองรับ writefile + getcustomasset)
-- ถ้าอยากใช้รูปอื่น ใส่ LOGO_IMAGE = "rbxassetid://เลขรูป" (เว้นว่าง = ใช้รูปที่ฝังไว้)
local NapAssets = {}
do
local LOGO_IMAGE = ""

local LOGO_B64 = [[
iVBORw0KGgoAAAANSUhEUgAAAJAAAACQCAYAAADnRuK4AAC4yUlEQVR42qz9d7hleV3ni79W3jnvffKpHLqqOlVqOlYnmiCooCBJ
EBBsRZ2LjOPoqAzjjDo6THJU1BETDNDkbprUdKQ6Vs7hVDinTj47571XvH9811pV7Z37e+69z6+ep+ii6pyz917ruz7h/Xm/3x+J
/w+/PM9TJElygv9/9erVTKvVu7NRq91jmuYeRVM3aZpaUlU1Aci2bQffh+u6SJIU/tl1XRRFAQ9sx0aRVVzXA0BWJDzPRVVV8CQU
RcV2TCRJQtM0VFVFkiRUVUWWZVRVxfP875VlZFlGURQURUGWZSRJQtd1NE1FksTXeJ6HJEnh9wBIkoSiKHgeeJ4bvk/XdfE8D03T
8DzvdZ8h+ByKomBZFsOhFf4s13UZDofIikI0oqOqGq4L4rp4OI4DBO9DwrZtbNsOX2M4NLFtC9u2xWs54udquoKuG4CHORxiWTYe
YFsOw6FJt9uh2+u45XKt0+6011zPvayr2pFoNH4wQ/TlD3/yw43/u3v6//SX9P/y4MiAJ0mSB2BZ1hsdx3nfcGg+NOgPp2zHplar
Ua1WqFTKNJtNXNfFcVwURfYPAriey2AwxNB1PM/DtCxxgz0YDAfYjhNefEkCVVVRVQ1NVXE9j39+IMXhAEmSw8Og6xqKooYHSZI8
PA90TcfQNRzPxbYdZEkGPGT/5uv+ewJxgy3LwvNcbNtGkWVUVcPxHwLHsXBdzz884jDLsoxlmZim+EyRSBTPE9dAU1VUTcW2bQaD
AaqiIvmH1nFs//M4qKqK4zi4LgyHQ//P4vDquo6iKGiahgQMTRNZlnEdR/zX8zBNk16vR6/XAw9UVSMSi2LoEXTdwLYsVFWbj8aM
pyMR7X/9zM/8zFP+9ZTEZZfc/6dnQv1/+oWf/vSnVUmSbBFxrr0nlUp8SlXVvaoqLsjBF1/wXn31VffChQtSubwmNZtNTNOUxE0F
RVHRNA1N0wBx0XXdQJUVFE1cfHMwZK1SDiOBaZriTariexVFxXVd+v2+OFCaiuPY/pMpnlbxrRKqqqEo4vA4joPngaIoRCMGuqaJ
C21Z2JaNrMivi2hBhLQsC9u2sCwbx3FviEziwAQ3NvieIIpIknxDdJNxPQdVUTB0AyTo9wd4nociy8iyhO042LZ4DRDvMzhUN0Zs
8VDJSLJEPBZDURQkJBzXEe/FCyKR6b9f8dAahuGl02lGSiPehg0bvKnpablUKk6lUplfUDX5F154/seHR0bHPitJ0pcB79lnn1Uf
eOAB+/8vEejGU/nDJ3+4N1cs/Ono2Pj9IyNFVlaX3CeeeML7zne+I1+4cEEyTTP8sI7jhBdY3GQHWVbCaBGkgeCpdRwHy7KIxWIM
BgOGwyGxWCxMDwCu66GqCtPT0ywuLtLtdkmn0yiKgmlafsh3/dQT/NkLo9CNKcoDbvifMMUFrxV8bfBZILiJnv8Z/QsohdfpdZdV
koL3AJLk4brilSQ8/7XEdQheT/wM8X7EzxJRU7wPGdd1wn8TXyf51068LwkJ1//M4KEoKrpuoGmKiPyI19I0jWKhwL49e709e/a6
0+s3SGMT43I2k8Xz7OcURfnNTCZz+J9nm/9PB+jTn/60/JnPfMYF+OY3v/NbiXj83xWLRd3DdZ577lnpm9/8pjw/f02ETtel1+vR
7/cwTdO/6NdvTHBQPM9DVVV6vR6qqhCNxl5XR6RSKXbs2MHa2hrnz58nEokQiUSwHRtJEvl98+ZNPPTQw8zPL/D00z9iOBySLxRE
veK4DIZDcRM874YnVwpDvLirfq0jy4D0z27k669ZkBYVVRGfy/9nVVGQZClMY94/ez1Re0l+BBNRMrgesiyDBJ5f74kbT/igBA/X
jXXjjYf69a/n3XDACf/+xgipqiq6rhOPJ4jGokQMg8nxcd5wxx3s27/f3bf/DV6hmFdMc2hKkvz7uq7/x39+Bv5fHaDgGx/77GPR
bs78+1Qm++5ELOKtriy53/jm15Vz584jSTKmOaDZbNLtdrFtO0w30Wg0vPmapl2/oJJMNpclFotTqVSoVivh17quS61WQ9M03vqW
tzIxOcGPf/xjZmdnicfj6KpGfzhgaWmJ8dFRPvaLH2XXbbfx5JPf5fixY2QzWRLxONVajW63i6prGJqO6zhYto2u60gSOI6D7Nc7
mqaFBeuNN8mxHZFmVCW8WbIs+3/vouk6sqygaSqDwSCsxQAGg4E4vPC6mwj4qVgRhbAMlm2haxogYVkmth0U6y6u62DbTpiKbdsO
f47jOKiqFhbhrutiWZafrr2wcB8Oh3Q6nbAmsv3rkEolicUSpFNpJkZH2HrTdn7xYx9ztm7dKluWJc3PLz525MihX3j3u9/d//Sn
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
]]

-- รูปพื้นหลังเมนู (JPEG ขาวดำ)
local BG_B64 = [[
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
Rr//2Q==
]]

local B64CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(s)
    s = s:gsub("%s", "")
    local lut = {}
    for i = 1, #B64CHARS do lut[B64CHARS:byte(i)] = i - 1 end
    local out, k = {}, 0
    for i = 1, #s, 4 do
        local a, b, c, d = s:byte(i, i + 3)
        local n = lut[a] * 262144 + lut[b] * 4096 + (lut[c] or 0) * 64 + (lut[d] or 0)
        local b1 = math.floor(n / 65536)
        local b2 = math.floor(n / 256) % 256
        local b3 = n % 256
        k = k + 1
        if c == 61 then
            out[k] = string.char(b1)
        elseif d == 61 then
            out[k] = string.char(b1, b2)
        else
            out[k] = string.char(b1, b2, b3)
        end
    end
    return table.concat(out)
end

-- เขียนรูปที่ฝังไว้ลงไฟล์ แล้วคืนค่า asset ที่ใช้กับ Image ได้ (ถ้าทำไม่ได้คืน "")
local function loadAsset(fileName, b64)
    if not (writefile and getcustomasset) then return "" end
    local result = ""
    pcall(function()
        writefile(fileName, b64decode(b64))
        result = getcustomasset(fileName)
    end)
    return result
end


local logoCache, bgCache
function NapAssets.Logo()
    if logoCache == nil then
        logoCache = LOGO_IMAGE
        if logoCache == "" then logoCache = loadAsset("naphub_logo_v3.png", LOGO_B64) end
    end
    return logoCache
end
function NapAssets.Bg()
    if bgCache == nil then bgCache = loadAsset("naphub_bg_v1.jpg", BG_B64) end
    return bgCache
end
end -- NapAssets

local NapUI = {
    Themes = {
        ["Metal Silver"]  = Color3.fromRGB(222, 224, 230),
        ["Cyber Cyan"]    = Color3.fromRGB(0, 191, 255),
        ["Mint"]          = Color3.fromRGB(0, 230, 190),
        ["Emerald"]       = Color3.fromRGB(0, 220, 130),
        ["Violet"]        = Color3.fromRGB(176, 110, 255),
        ["Rose"]          = Color3.fromRGB(255, 80, 130),
        ["Amber"]         = Color3.fromRGB(255, 183, 0),
        ["Electric Blue"] = Color3.fromRGB(61, 142, 255),
    },
    ThemeNames = { "Metal Silver", "Cyber Cyan", "Mint", "Emerald", "Violet", "Rose", "Amber", "Electric Blue" },
    Theme = "Metal Silver",
    Emoji = {
        ["layout-dashboard"] = "🏠", gem = "💎", swords = "⚔️", crosshair = "🎯", zap = "⚡",
        hammer = "🔨", sparkles = "✨", gift = "🎁", ["map-pin"] = "📍", settings = "⚙️",
    },
}

function NapUI.create(opts)
    opts = opts or {}
    if _G.NapHubCleanup then pcall(_G.NapHubCleanup) end

    local TweenService = game:GetService("TweenService")
    local Window = { Tabs = {} }
    local conns, renders, tabs = {}, {}, {}
    local accent = NapUI.Themes[opts.Theme or NapUI.Theme] or NapUI.Themes["Metal Silver"]

    -- พาเลตต์โลหะเข้มแบบ Metal Dragon
    local C = {
        bg    = Color3.fromRGB(20, 20, 22),
        panel = Color3.fromRGB(14, 14, 16),
        card  = Color3.fromRGB(32, 32, 36),
        line  = Color3.fromRGB(70, 70, 76),
        text  = Color3.fromRGB(240, 241, 245),
        sub   = Color3.fromRGB(168, 170, 178),
        off   = Color3.fromRGB(66, 66, 72),
        steel = Color3.fromRGB(215, 216, 222),
    }
    local CARD_T = 0.2

    local function track(c) table.insert(conns, c); return c end
    local function onAccent(fn) table.insert(renders, fn); pcall(fn) end
    local function applyAccent() for _, fn in ipairs(renders) do pcall(fn) end end

    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props or {}) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function round(o, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
    local function stroke(o, color, th, tr)
        return new("UIStroke", { Color = color or C.line, Thickness = th or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
    end
    local function pad(o, l, t, r, b)
        new("UIPadding", { PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t), PaddingRight = UDim.new(0, r or l), PaddingBottom = UDim.new(0, b or t) }, o)
    end
    local function list(o, gap)
        return new("UIListLayout", { Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder }, o)
    end
    local function label(parent, text, size, color, font, xa)
        return new("TextLabel", {
            BackgroundTransparency = 1, Text = tostring(text or ""), TextColor3 = color or C.text,
            Font = font or Enum.Font.GothamMedium, TextSize = size or 13,
            TextXAlignment = xa or Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true, TextTruncate = Enum.TextTruncate.None, RichText = false,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        }, parent)
    end

    -- ไล่เฉดสีโลหะเงิน (จาก Ui-NAPHUB)
    local function metal(parent, rot)
        return new("UIGradient", {
            Rotation = rot or 45,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 241, 245)),
                ColorSequenceKeypoint.new(0.35, Color3.fromRGB(130, 132, 138)),
                ColorSequenceKeypoint.new(0.65, Color3.fromRGB(200, 202, 208)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 97, 103)),
            }),
        }, parent)
    end

    -- เพชรสี่เหลี่ยมขนมเปียกปูน (เหมือนในโลโก้)
    local function diamond(parent, size, pos, z)
        local d = new("Frame", {
            Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = pos,
            Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = z or 5,
        }, parent)
        metal(d, 45)
        stroke(d, Color3.fromRGB(12, 12, 14), 1, 0)
        return d
    end

    -- ที่วาง GUI: gethui > CoreGui > PlayerGui (อยู่เหนือ UI ของเกม)
    local cloneref_ = cloneref or function(i) return i end
    local function getParent()
        if gethui then
            local ok, h = pcall(gethui)
            if ok and typeof(h) == "Instance" then return h end
        end
        local cg = cloneref_(game:GetService("CoreGui"))
        local ok = pcall(function() local t = Instance.new("Folder"); t.Parent = cg; t:Destroy() end)
        if ok then return cg end
        return LocalPlayer:WaitForChild("PlayerGui", 10)
    end
    local guiParent = getParent()

    -- ลบ UI เก่ากันซ้อน
    for _, root in ipairs({ guiParent, LocalPlayer:FindFirstChild("PlayerGui") }) do
        if root then
            for _, nm in ipairs({ "NAPHUBUI", "NAPHUB_UI", "NAPHUB_Float" }) do
                local old = root:FindFirstChild(nm)
                if old then pcall(function() old:Destroy() end) end
            end
        end
    end

    local gui = new("ScreenGui", { Name = "NAPHUBUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 2147483647, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
    gui.Parent = guiParent

    -- ───────── หน้าต่างหลัก ─────────
    local main = new("Frame", {
        Name = "MainFrame", Size = UDim2.fromScale(0.7, 0.85), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.bg, BorderSizePixel = 0, Visible = true, Active = true,
    }, gui)
    round(main, 14)
    new("UISizeConstraint", { MaxSize = Vector2.new(580, 360), MinSize = Vector2.new(300, 220) }, main)
    local scaleObj = new("UIScale", { Scale = 1 }, main)
    metal(stroke(main, Color3.new(1, 1, 1), 3, 0), 45)

    local plate = new("Frame", {
        Name = "Plate", Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Color3.fromRGB(36, 36, 39), BorderSizePixel = 0,
    }, main)
    round(plate, 10); stroke(plate, Color3.fromRGB(70, 70, 76), 1, 0)
    new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(52, 52, 56), Color3.fromRGB(28, 28, 31)) }, plate)

    -- รูปพื้นหลังเมนู (ถ้าโหลดไม่ได้จะใช้พื้นเทาเดิม)
    local bgAsset = NapAssets.Bg()
    if bgAsset ~= "" then
        local bgImg = new("ImageLabel", {
            Name = "BgImage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = bgAsset,
            ImageColor3 = Color3.fromRGB(150, 150, 150), ScaleType = Enum.ScaleType.Crop, ZIndex = 0,
        }, plate)
        round(bgImg, 10)
    end

    -- Header (ลากหน้าต่างจากตรงนี้)
    local header = new("Frame", {
        Name = "Header", Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Color3.fromRGB(10, 10, 12),
        BackgroundTransparency = 0.35, BorderSizePixel = 0,
    }, plate)
    round(header, 10)
    diamond(header, 9, UDim2.fromOffset(20, 21), 6)

    new("TextLabel", {
        Name = "TitleShadow", Size = UDim2.new(0, 120, 1, 0), Position = UDim2.fromOffset(36, 2), Text = tostring(opts.Title or "NAPHUB"),
        TextColor3 = Color3.new(0, 0, 0), TextTransparency = 0.2, TextSize = 30, Font = Enum.Font.Fantasy,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
    }, header)
    local titleLbl = new("TextLabel", {
        Name = "Title", Size = UDim2.new(0, 120, 1, 0), Position = UDim2.fromOffset(34, 0), Text = tostring(opts.Title or "NAPHUB"),
        TextColor3 = Color3.new(1, 1, 1), TextSize = 30, Font = Enum.Font.Fantasy,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
    }, header)
    new("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 192, 200)) }),
    }, titleLbl)

    local subtitle = new("TextLabel", {
        Name = "Subtitle", Size = UDim2.new(1, -250, 0, 16), Position = UDim2.fromOffset(150, 14), Text = tostring(opts.Subtitle or ""),
        TextColor3 = C.sub, TextSize = 11, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, BackgroundTransparency = 1,
    }, header)

    local verPill = new("Frame", {
        Size = UDim2.fromOffset(52, 20), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -46, 0.5, 0),
        BackgroundColor3 = Color3.fromRGB(30, 30, 33), BorderSizePixel = 0,
    }, header)
    round(verPill, 10); stroke(verPill, C.line, 1, 0)
    local verTxt = label(verPill, tostring(opts.Version or ""), 11, C.sub, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
    verTxt.Size = UDim2.new(1, 0, 1, 0); verTxt.AutomaticSize = Enum.AutomaticSize.None; verTxt.TextYAlignment = Enum.TextYAlignment.Center

    local closeBtn = new("TextButton", {
        Name = "CloseBtn", Size = UDim2.fromOffset(28, 28), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        BackgroundColor3 = Color3.fromRGB(30, 30, 33), Text = "X", TextColor3 = Color3.fromRGB(215, 216, 222),
        TextSize = 16, Font = Enum.Font.GothamBold, AutoButtonColor = true,
    }, header)
    round(closeBtn, 8)
    metal(stroke(closeBtn, Color3.new(1, 1, 1), 1.5, 0), 45)

    -- เส้นคั่นไล่เฉดมีเพชรตรงกลาง
    local divider = new("Frame", {
        Size = UDim2.new(1, -24, 0, 2), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 42),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, plate)
    new("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(215, 216, 222), Color3.fromRGB(215, 216, 222)),
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }),
    }, divider)
    diamond(divider, 8, UDim2.fromScale(0.5, 0.5), 6)

    -- พื้นที่เนื้อหา (แถบเมนูซ้าย + หน้าตั้งค่าขวา)
    local contentFrame = new("Frame", {
        Name = "Content", Size = UDim2.new(1, -24, 1, -64), Position = UDim2.fromOffset(12, 52),
        BackgroundColor3 = Color3.fromRGB(14, 14, 16), BackgroundTransparency = 0.45, BorderSizePixel = 0, ClipsDescendants = true,
    }, plate)
    round(contentFrame, 8); stroke(contentFrame, Color3.fromRGB(62, 62, 68), 1, 0)

    -- เพชรประดับกลางขอบทั้ง 4 ด้าน
    diamond(main, 12, UDim2.fromScale(0.5, 0), 8)
    diamond(main, 12, UDim2.fromScale(0.5, 1), 8)
    diamond(main, 12, UDim2.fromScale(0, 0.5), 8)
    diamond(main, 12, UDim2.fromScale(1, 0.5), 8)

    local sidebar = new("ScrollingFrame", {
        Position = UDim2.fromOffset(6, 6), Size = UDim2.new(0, 138, 1, -12), BackgroundColor3 = Color3.fromRGB(10, 10, 12),
        BackgroundTransparency = 0.3, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ClipsDescendants = true,
    }, contentFrame)
    round(sidebar, 8); stroke(sidebar, C.line, 1, 0.4); pad(sidebar, 6, 6, 6, 6); list(sidebar, 4)

    local content = new("ScrollingFrame", {
        Position = UDim2.fromOffset(150, 6), Size = UDim2.new(1, -156, 1, -12), BackgroundColor3 = Color3.fromRGB(10, 10, 12),
        BackgroundTransparency = 0.45, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ClipsDescendants = true,
    }, contentFrame)
    round(content, 8); stroke(content, C.line, 1, 0.4)

    onAccent(function()
        sidebar.ScrollBarImageColor3 = accent
        content.ScrollBarImageColor3 = accent
    end)

    -- ลากหน้าต่าง/ลูกลอย (แตะ = onTap, ลาก = ย้ายตำแหน่ง ไม่เด้งเปิดเมนู)
    local function makeDraggable(handle, target, onTap)
        local dragging, moved, dragStart, startPos = false, false, nil, nil
        track(handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging, moved = true, false
                dragStart, startPos = input.Position, target.Position
                local ended
                ended = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        ended:Disconnect()
                        dragging = false
                        if not moved and onTap then onTap() end
                    end
                end)
            end
        end))
        track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local d = input.Position - dragStart
                if d.Magnitude > 6 then moved = true end
                if moved then
                    local s = (target == main) and scaleObj.Scale or 1
                    target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X / s, startPos.Y.Scale, startPos.Y.Offset + d.Y / s)
                end
            end
        end))
    end
    makeDraggable(header, main, nil)

    -- เปิด/ปิดเมนู
    local lastToggle = 0
    function Window:Open()
        scaleObj.Scale = 0.92
        main.Visible = true
        TweenService:Create(scaleObj, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
    end
    function Window:Close() main.Visible = false end
    function Window:Toggle()
        local now = tick()
        if now - lastToggle < 0.2 then return end
        lastToggle = now
        if main.Visible then Window:Close() else Window:Open() end
    end
    track(closeBtn.MouseButton1Click:Connect(function() Window:Close() end))

    -- ───────── ลูกลอย (โลโก้ NAP) ─────────
    local BTN_SIZE = 48
    local floatBtn = new("TextButton", {
        Name = "FloatingToggleButton", Size = UDim2.fromOffset(BTN_SIZE, BTN_SIZE), Position = UDim2.new(0, 20, 0.5, -BTN_SIZE / 2),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Active = true,
    }, gui)

    -- แบบวาดเอง (สำรอง ใช้เมื่อโหลดรูปไม่ได้)
    local fallback = new("Frame", {
        Name = "Fallback", Size = UDim2.fromOffset(64, 64), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(34, 34, 37), BorderSizePixel = 0,
    }, floatBtn)
    round(fallback, 14)
    new("UIScale", { Scale = BTN_SIZE / 64 }, fallback)
    new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(58, 58, 62), Color3.fromRGB(22, 22, 24)) }, fallback)
    metal(stroke(fallback, Color3.new(1, 1, 1), 3, 0), 45)
    local inner = new("Frame", { Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5), BackgroundTransparency = 1 }, fallback)
    round(inner, 10); stroke(inner, Color3.fromRGB(85, 85, 92), 1, 0)
    local ring = new("Frame", {
        Size = UDim2.fromOffset(46, 46), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
    }, fallback)
    round(ring, 23)
    metal(stroke(ring, Color3.new(1, 1, 1), 2.5, 0), 135)
    local napText = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), Text = "NAP", TextColor3 = Color3.new(1, 1, 1), TextSize = 19,
        Font = Enum.Font.Fantasy, BackgroundTransparency = 1, ZIndex = 3,
    }, fallback)
    metal(napText, 90)
    diamond(fallback, 8, UDim2.new(0.5, 0, 0.5, -23), 4)
    diamond(fallback, 8, UDim2.new(0.5, 0, 0.5, 23), 4)
    diamond(fallback, 8, UDim2.new(0.5, -23, 0.5, 0), 4)
    diamond(fallback, 8, UDim2.new(0.5, 23, 0.5, 0), 4)

    local logoAsset = NapAssets.Logo()
    if logoAsset ~= "" then
        local img = new("ImageLabel", {
            Name = "Logo", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = logoAsset,
            ScaleType = Enum.ScaleType.Fit, ZIndex = 10,
        }, floatBtn)
        task.spawn(function()
            local t = 0
            while img.Parent and not img.IsLoaded and t < 5 do task.wait(0.1); t = t + 0.1 end
            if not img.Parent then return end
            if img.IsLoaded then fallback.Visible = false else img:Destroy() end
        end)
    end
    -- แตะ = เปิด/ปิดเมนู | ลาก = ย้ายลูกลอย
    makeDraggable(floatBtn, floatBtn, function() Window:Toggle() end)

    -- ───────── แจ้งเตือน (Toast) ─────────
    local toastBox = new("Frame", { Size = UDim2.new(0, 320, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(0.5, -160, 0, 14), BackgroundTransparency = 1 }, gui)
    list(toastBox, 6)
    function Window:Notify(ttl, msg)
        local t = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(24, 24, 27), BorderSizePixel = 0 }, toastBox)
        round(t, 12); metal(stroke(t, Color3.new(1, 1, 1), 1.5, 0.1), 45); pad(t, 12, 9, 12, 9)
        local innerF = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, t)
        list(innerF, 2)
        label(innerF, ttl, 13, accent, Enum.Font.GothamBold)
        label(innerF, msg, 12, C.text, Enum.Font.Gotham)
        task.delay(3.5, function() pcall(function() t:Destroy() end) end)
    end

    -- ───────── แท็บ ─────────
    local function selectTab(tab)
        for _, t in ipairs(tabs) do
            t.page.Visible = (t == tab)
            t.selected = (t == tab)
            pcall(t.render)
        end
        content.CanvasPosition = Vector2.new(0, 0)
        Window.ActiveTab = tab
    end
    function Window:SelectTab(target)
        if type(target) == "number" then target = tabs[target] end
        if target then selectTab(target) end
    end

    function Window:Tab(config)
        config = config or {}
        local tab = { order = 0, selected = false }
        tab.page = new("Frame", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -28, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false }, content)
        pad(tab.page, 0, 10, 0, 12)
        list(tab.page, 8)

        local head = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 0 }, tab.page)
        list(head, 5)
        label(head, config.Title or "", 18, C.text, Enum.Font.GothamBold)
        local headBar = new("Frame", { Size = UDim2.fromOffset(44, 3), BorderSizePixel = 0 }, head)
        round(headBar, 2)

        local btn = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Color3.fromRGB(48, 48, 53), BackgroundTransparency = 1, Text = "",
            AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = #tabs + 1,
        }, sidebar)
        round(btn, 9)
        local btnStroke = stroke(btn, C.steel, 1, 1)
        local mark = new("Frame", { Size = UDim2.new(0, 3, 0, 22), Position = UDim2.new(0, 0, 0.5, -11), BorderSizePixel = 0, Visible = false }, btn)
        round(mark, 2)
        local ico = label(btn, NapUI.Emoji[config.Icon] or "•", 18, C.text, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        ico.Position = UDim2.new(0, 6, 0, 0); ico.Size = UDim2.new(0, 30, 1, 0); ico.AutomaticSize = Enum.AutomaticSize.None; ico.TextYAlignment = Enum.TextYAlignment.Center; ico.TextWrapped = false
        local txt = label(btn, config.Short or config.Title or "", 13, C.sub, Enum.Font.GothamBold)
        txt.Position = UDim2.new(0, 40, 0, 0); txt.Size = UDim2.new(1, -44, 1, 0); txt.AutomaticSize = Enum.AutomaticSize.None; txt.TextYAlignment = Enum.TextYAlignment.Center
        txt.TextWrapped = false; txt.TextTruncate = Enum.TextTruncate.AtEnd

        tab.render = function()
            btn.BackgroundTransparency = tab.selected and 0.1 or 1
            btnStroke.Transparency = tab.selected and 0.2 or 1
            mark.Visible = tab.selected
            mark.BackgroundColor3 = accent
            txt.TextColor3 = tab.selected and C.text or C.sub
            headBar.BackgroundColor3 = accent
        end
        onAccent(tab.render)
        track(btn.MouseButton1Click:Connect(function() selectTab(tab) end))
        table.insert(tabs, tab)
        table.insert(Window.Tabs, tab)
        if #tabs == 1 then selectTab(tab) end

        local adapter = { Native = tab }
        local function nextOrder() tab.order = tab.order + 1; return tab.order end

        local function newCard(asButton, noMin)
            local c = new(asButton and "TextButton" or "Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.card,
                BackgroundTransparency = CARD_T, BorderSizePixel = 0, LayoutOrder = nextOrder(),
            }, tab.page)
            if asButton then c.Text = ""; c.AutoButtonColor = false end
            round(c, 10); stroke(c, C.line, 1, 0.2); pad(c, 12, 10, 12, 10)
            if not noMin then new("UISizeConstraint", { MinSize = Vector2.new(0, 52) }, c) end
            return c
        end
        local function infoBlock(parent, titleText, descText, rightPad)
            local info = new("Frame", { Size = UDim2.new(1, -(rightPad or 0), 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, parent)
            list(info, 3)
            local t = label(info, titleText, 14, C.text, Enum.Font.GothamBold)
            local d
            if descText and tostring(descText) ~= "" then d = label(info, descText, 11, C.sub, Enum.Font.Gotham) end
            return info, t, d
        end

        function adapter:Section(o)
            local f = new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, tab.page)
            local bar = diamond(f, 8, UDim2.new(0, 5, 1, -12), 5)
            local l = label(f, (o and (o.Title or o.Name)) or "", 13, accent, Enum.Font.GothamBold)
            l.Position = UDim2.new(0, 16, 1, -22); l.Size = UDim2.new(1, -16, 0, 20); l.AutomaticSize = Enum.AutomaticSize.None; l.TextYAlignment = Enum.TextYAlignment.Center
            l.TextWrapped = false; l.TextTruncate = Enum.TextTruncate.AtEnd
            onAccent(function() l.TextColor3 = accent end)
            return f
        end

        function adapter:Toggle(o)
            o = o or {}
            local state = o.Value == true
            local card = newCard(true)
            infoBlock(card, o.Title, o.Desc, 64)
            local trackF = new("Frame", { Size = UDim2.fromOffset(48, 26), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), BorderSizePixel = 0 }, card)
            round(trackF, 13)
            local trackStroke = stroke(trackF, C.steel, 1, 0.5)
            local knob = new("Frame", { Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, trackF)
            round(knob, 10)
            local function render(animate)
                local goal = { Position = state and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }
                if animate then TweenService:Create(knob, TweenInfo.new(0.12), goal):Play() else knob.Position = goal.Position end
                trackF.BackgroundColor3 = state and accent or C.off
                knob.BackgroundColor3 = state and Color3.fromRGB(20, 20, 22) or Color3.new(1, 1, 1)
                trackStroke.Color = state and accent or C.line
            end
            onAccent(function() render(false) end)
            local ctl = {}
            local function set(v, fire)
                state = v == true
                render(true)
                if fire and type(o.Callback) == "function" then pcall(o.Callback, state) end
            end
            function ctl:Set(v) set(v, true) end
            function ctl:SetValue(v) set(v, true) end
            function ctl:GetValue() return state end
            track(card.MouseButton1Click:Connect(function() set(not state, true) end))
            return ctl
        end

        function adapter:Button(o)
            o = o or {}
            local card = newCard(true)
            infoBlock(card, o.Title, o.Desc, 30)
            local arrow = label(card, "›", 24, accent, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
            arrow.AnchorPoint = Vector2.new(1, 0.5); arrow.Position = UDim2.new(1, 0, 0.5, 0); arrow.Size = UDim2.fromOffset(24, 28); arrow.AutomaticSize = Enum.AutomaticSize.None
            arrow.TextYAlignment = Enum.TextYAlignment.Center
            local st = stroke(card, accent, 1, 0.6)
            onAccent(function() arrow.TextColor3 = accent; st.Color = accent end)
            track(card.MouseButton1Click:Connect(function()
                TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = C.line }):Play()
                task.delay(0.12, function() TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = C.card }):Play() end)
                if type(o.Callback) == "function" then pcall(o.Callback) end
            end))
            return card
        end

        function adapter:Slider(o)
            o = o or {}
            local range = type(o.Value) == "table" and o.Value or {}
            local mn, mx = tonumber(range.Min) or 0, tonumber(range.Max) or 100
            local def = tonumber(range.Default) or mn
            local isInt = (mn % 1 == 0) and (mx % 1 == 0) and (def % 1 == 0)
            local step = range.Rounding and (10 ^ -range.Rounding) or (isInt and 1 or 0.01)
            local value = math.clamp(def, mn, mx)

            local card = newCard(false)
            list(card, 6)
            local top = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, card)
            local t = label(top, o.Title, 14, C.text, Enum.Font.GothamBold)
            t.Size = UDim2.new(1, -80, 0, 0)
            local valLbl = label(top, "", 14, accent, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
            valLbl.AnchorPoint = Vector2.new(1, 0); valLbl.Position = UDim2.new(1, 0, 0, 0); valLbl.Size = UDim2.fromOffset(76, 20); valLbl.AutomaticSize = Enum.AutomaticSize.None
            valLbl.TextWrapped = false; valLbl.TextTruncate = Enum.TextTruncate.AtEnd
            if o.Desc and tostring(o.Desc) ~= "" then
                local d = label(card, o.Desc, 11, C.sub, Enum.Font.Gotham); d.LayoutOrder = 2
            end
            local area = new("TextButton", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = 3 }, card)
            local bar = new("Frame", { Size = UDim2.new(1, -20, 0, 8), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), BackgroundColor3 = C.off, BorderSizePixel = 0 }, area)
            round(bar, 4)
            local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, bar)
            round(fill, 4)
            local knob = new("Frame", { Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, bar)
            round(knob, 10)
            metal(stroke(knob, Color3.new(1, 1, 1), 1.5, 0), 45)

            local function render()
                local ratio = (mx > mn) and ((value - mn) / (mx - mn)) or 0
                fill.Size = UDim2.new(ratio, 0, 1, 0)
                knob.Position = UDim2.new(ratio, 0, 0.5, 0)
                fill.BackgroundColor3 = accent
                valLbl.Text = tostring(math.floor(value * 100 + 0.5) / 100)
            end
            onAccent(render)
            local function set(v, fire)
                v = math.clamp(tonumber(v) or value, mn, mx)
                v = mn + math.floor((v - mn) / step + 0.5) * step
                v = math.floor(math.clamp(v, mn, mx) * 10000 + 0.5) / 10000
                local changed = v ~= value
                value = v
                render()
                if fire and changed and type(o.Callback) == "function" then pcall(o.Callback, value) end
            end
            local dragging = false
            local function fromX(x)
                local ratio = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
                set(mn + ratio * (mx - mn), true)
            end
            track(area.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    content.ScrollingEnabled = false
                    fromX(input.Position.X)
                end
            end))
            track(UserInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    fromX(input.Position.X)
                end
            end))
            track(UserInputService.InputEnded:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                    dragging = false
                    content.ScrollingEnabled = true
                end
            end))
            local ctl = {}
            function ctl:Set(v) set(v, true) end
            function ctl:SetValue(v) set(v, true) end
            function ctl:GetValue() return value end
            return ctl
        end

        function adapter:Dropdown(o)
            o = o or {}
            local values = o.Values or {}
            local current = o.Value
            if current == nil then current = values[1] end
            local card = newCard(false)
            list(card, 8)
            local head2 = new("TextButton", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = 1 }, card)
            local info = new("Frame", { Size = UDim2.new(1, -30, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, head2)
            list(info, 3)
            label(info, o.Title, 14, C.text, Enum.Font.GothamBold)
            if o.Desc and tostring(o.Desc) ~= "" then label(info, o.Desc, 11, C.sub, Enum.Font.Gotham) end
            local valLbl = label(info, tostring(current or ""), 13, accent, Enum.Font.GothamMedium)
            local arrow = label(head2, "▾", 16, C.sub, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
            arrow.AnchorPoint = Vector2.new(1, 0.5); arrow.Position = UDim2.new(1, 0, 0.5, 0); arrow.Size = UDim2.fromOffset(24, 24); arrow.AutomaticSize = Enum.AutomaticSize.None; arrow.TextYAlignment = Enum.TextYAlignment.Center

            local box = new("ScrollingFrame", {
                Size = UDim2.new(1, 0, 0, math.min(#values * 38 + 8, 190)), BackgroundColor3 = Color3.fromRGB(14, 14, 16), ClipsDescendants = true, BorderSizePixel = 0, Visible = false,
                ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
            }, card)
            round(box, 10); pad(box, 4, 4, 6, 4); list(box, 2)
            local items = {}
            local function renderItems()
                valLbl.Text = tostring(current or "")
                valLbl.TextColor3 = accent
                for _, it in ipairs(items) do
                    local sel = tostring(it.value) == tostring(current)
                    it.btn.BackgroundColor3 = sel and C.card or Color3.fromRGB(14, 14, 16)
                    it.lbl.TextColor3 = sel and accent or C.text
                    it.lbl.Text = (sel and "✓  " or "") .. tostring(it.value)
                end
            end
            for i, v in ipairs(values) do
                local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Color3.fromRGB(14, 14, 16), Text = "", AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i }, box)
                round(b, 8)
                local l = label(b, tostring(v), 13, C.text, Enum.Font.GothamMedium)
                l.Position = UDim2.new(0, 10, 0, 0); l.Size = UDim2.new(1, -16, 1, 0); l.AutomaticSize = Enum.AutomaticSize.None; l.TextYAlignment = Enum.TextYAlignment.Center
                l.TextWrapped = false; l.TextTruncate = Enum.TextTruncate.AtEnd
                table.insert(items, { btn = b, lbl = l, value = v })
                track(b.MouseButton1Click:Connect(function()
                    current = v
                    box.Visible = false
                    arrow.Text = "▾"
                    renderItems()
                    if type(o.Callback) == "function" then pcall(o.Callback, current) end
                end))
            end
            onAccent(renderItems)
            track(head2.MouseButton1Click:Connect(function()
                box.Visible = not box.Visible
                arrow.Text = box.Visible and "▴" or "▾"
            end))
            local ctl = {}
            function ctl:Select(v) current = v; renderItems(); if type(o.Callback) == "function" then pcall(o.Callback, current) end end
            function ctl:Set(v) self:Select(v) end
            function ctl:SetValue(v) self:Select(v) end
            function ctl:GetValue() return current end
            return ctl
        end

        function adapter:Input(o)
            o = o or {}
            local card = newCard(false)
            list(card, 8)
            local info = infoBlock(card, o.Title, o.Desc, 0)
            info.LayoutOrder = 1
            local box = new("TextBox", {
                Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Color3.fromRGB(14, 14, 16), BorderSizePixel = 0, LayoutOrder = 2,
                Text = tostring(o.Value or o.Default or ""), PlaceholderText = tostring(o.Placeholder or ""), PlaceholderColor3 = C.sub,
                TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 13, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true, TextTruncate = Enum.TextTruncate.AtEnd,
            }, card)
            round(box, 8); pad(box, 10, 0, 10, 0)
            local st = stroke(box, C.line, 1, 0)
            onAccent(function() st.Color = accent end)
            track(box.FocusLost:Connect(function()
                if type(o.Callback) == "function" then pcall(o.Callback, box.Text) end
            end))
            local ctl = {}
            function ctl:Set(v) box.Text = tostring(v or "") end
            function ctl:GetValue() return box.Text end
            return ctl
        end

        function adapter:Paragraph(o)
            o = o or {}
            local card = newCard(false, true)
            local _, _, body = infoBlock(card, o.Title, (o.Desc ~= nil and o.Desc ~= "") and o.Desc or " ", 0)
            local st = stroke(card, accent, 1, 0.6)
            onAccent(function() st.Color = accent end)
            local function set(_, text) if body then body.Text = tostring(text or "") end end
            return { SetDesc = set, Set = set, SetContent = set }
        end

        return adapter
    end

    function Window:SetTheme(name)
        local c = NapUI.Themes[name]
        if c then NapUI.Theme = name; accent = c; applyAccent() end
    end
    function Window:SetAccent(color) if typeof(color) == "Color3" then accent = color; applyAccent() end end
    function Window:ToggleTransparency(enabled) contentFrame.BackgroundTransparency = enabled and 0.45 or 0.1 end
    function Window:SetMotion() end
    function Window:SetEffects() end
    function Window:SetFloatingVisible(v) floatBtn.Visible = v and true or false end

    function Window:Destroy()
        if _G.TwoSkiActiveToken == myToken then _G.TwoSkiRunning = false end
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        pcall(function() gui:Destroy() end)
        if _G.NapHubCleanup == Window.__cleanup then _G.NapHubCleanup = nil end
    end
    Window.__cleanup = function() Window:Destroy() end
    _G.NapHubCleanup = Window.__cleanup

    return Window
end



-- ═════════════════════════════════════════════════════════════
--  ★ PORTED FROM PAYOMBØYZ: Selective Sell / Best Pet / Online Codes / Anti-Trip / Auto Reconnect
--  (wrapped in do-block + exported via NH so we don't spend top-level local slots)
-- ═════════════════════════════════════════════════════════════
local NH = {}
do
    local knownCodes = { "RELEASE", "LOOT", "FORGE", "ENHANCE", "UPDATE1", "FREEGEMS", "LIKE1000" }
    local RarityHelper = nil
    pcall(function() RarityHelper = require(ReplicatedStorage.Config.Rarity.Helper) end)

local function hasEquippedArmor()
    local bp = getBackpackItems()
    if not bp then return false end
    for uuid, item in pairs(bp) do
        if type(item) == "table" and item.Type == "Armor" then
            local isEquipped = false
            pcall(function()
                if BackpackData and BackpackData.IsEquipedUUID then
                    isEquipped = BackpackData.IsEquipedUUID(uuid)
                end
            end)
            if isEquipped then return true end
        end
    end
    return false
end

local RARITY_RANK = {
    Common    = 1,
    Uncommon  = 2,
    Rare      = 3,
    Epic      = 4,
    Legendary = 5,
    Mythic    = 6,
    Eternal   = 7,
    Secret    = 8,
    Ancient   = 9,
    Infinite  = 10,
}

local function getItemRarityLevel(item)
    if not item or type(item) ~= "table" then return 1 end
    local rarity = nil

    if item.Type == "Weapon" and WeaponHelper and WeaponHelper.GetRarity then
        pcall(function() rarity = WeaponHelper.GetRarity(item.ID) or rarity end)
    elseif (item.Type == "Armor" or item.Type == "Hat") and ArmorHelper and ArmorHelper.GetRarity then
        pcall(function() rarity = ArmorHelper.GetRarity(item.ID) or rarity end)
    elseif item.Type == "Ore" and OreHelper and OreHelper.GetRarity then
        pcall(function() rarity = OreHelper.GetRarity(item.ID) or rarity end)
    elseif (item.Type == "EnchStone" or (item.ID and item.ID:find("Stone"))) and EnchStoneHelper and EnchStoneHelper.GetRarity then
        pcall(function() rarity = EnchStoneHelper.GetRarity(item.ID) or rarity end)
    end

    if not rarity and item.Rarity then
        rarity = item.Rarity
    end

    if not rarity and item.ID then
        for _, rName in ipairs({ "Infinite", "Ancient", "Secret", "Eternal", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }) do
            if string.find(string.lower(item.ID), string.lower(rName), 1, true) then
                rarity = rName
                break
            end
        end
    end

    local lvl = 1
    if rarity and RarityHelper and RarityHelper.GetRarityLevel then
        pcall(function() lvl = RarityHelper.GetRarityLevel(rarity) or lvl end)
    elseif rarity and RARITY_RANK[rarity] then
        lvl = RARITY_RANK[rarity]
    end
    return lvl
end

local function sellTrashGearNow()
    if not BackpackData then return 0 end
    local bp = nil
    pcall(function() bp = BackpackData.GetData() end)
    if not bp or not bp.have then return 0 end

    -- Equip best gear first to protect highest-tier equipment
    if State.AutoEquipBest then
        pcall(function() equipBestGearNow("All") end)
        task.wait(0.08)
    end

    local keepThreshold = RARITY_RANK[State.MinGearRarityToKeep] or 5
    local isArmorEquipped = hasEquippedArmor()

    -- 1. Gather all unequipped equipment (Weapon, Armor, Hat)
    local unequippedGears = {}
    for uuid, item in pairs(bp.have) do
        if type(item) == "table" and (item.Type == "Weapon" or item.Type == "Armor" or item.Type == "Hat") then
            local isEquipped = false
            pcall(function()
                if BackpackData.IsEquipedUUID then
                    isEquipped = BackpackData.IsEquipedUUID(uuid)
                end
            end)
            if not isEquipped then
                -- Protection: Never sell armor if character is bare-chested
                if item.Type == "Armor" and not isArmorEquipped then
                    pcall(function() equipBestGearNow("Armor") end)
                    isArmorEquipped = true
                else
                    local score = 0
                    pcall(function() score = itemGearScore(item) end)
                    table.insert(unequippedGears, {
                        uuid = uuid,
                        item = item,
                        score = score,
                        rarity = getItemRarityLevel(item),
                    })
                end
            end
        end
    end

    -- 2. Sort unequipped gear descending by score (best items first)
    table.sort(unequippedGears, function(a, b)
        return a.score > b.score
    end)

    -- 3. Protect top 7 best alternate items for the user!
    local protectedUuids = {}
    for i = 1, math.min(7, #unequippedGears) do
        protectedUuids[unequippedGears[i].uuid] = true
    end

    -- 4. Only sell unequipped items that are NOT in the protected top 7 and are below keepThreshold
    local soldCount = 0
    for _, gear in ipairs(unequippedGears) do
        if not protectedUuids[gear.uuid] then
            if gear.rarity < keepThreshold then
                pcall(function()
                    call("Backpack", "TrySellItemRE", gear.uuid, 1)
                end)
                soldCount = soldCount + 1
                task.wait(0.02)
            end
        end
    end
    return soldCount
end

local LEVEL_TO_RARITY = {
    [1]  = "Common",
    [2]  = "UnCommon",
    [3]  = "Rare",
    [4]  = "Epic",
    [5]  = "Legendary",
    [6]  = "Mythic",
    [7]  = "Eternal",
    [8]  = "Secret",
    [9]  = "Ancient",
    [10] = "Infinite",
}

local function cleanRarityText(txt)
    if not txt or type(txt) ~= "string" then return "Common" end
    local lower = txt:lower()
    if lower:find("infinite") then return "Infinite" end
    if lower:find("ancient") then return "Ancient" end
    if lower:find("secret") then return "Secret" end
    if lower:find("eternal") then return "Eternal" end
    if lower:find("mythic") then return "Mythic" end
    if lower:find("legendary") then return "Legendary" end
    if lower:find("epic") then return "Epic" end
    if lower:find("rare") then return "Rare" end
    if lower:find("uncommon") then return "UnCommon" end
    if lower:find("common") then return "Common" end
    return "Common"
end

-- Selective Ore Selling (Keeps selected high-tier ores for forging & preserves minimum count)
local function sellOresNow()
    local bp = getBackpackItems()
    if not bp then return 0 end

    local keptRanks = {}
    for _, str in ipairs(State.OreRaritiesToKeep or {}) do
        keptRanks[cleanRarityText(str)] = true
    end

    local sold = 0
    local minKeep = tonumber(State.KeepMinOreAmount) or 0
    for uuid, item in pairs(bp) do
        if type(item) == "table" and item.Type == "Ore" then
            local rLevel = getItemRarityLevel(item)
            local rName = LEVEL_TO_RARITY[rLevel] or "Common"
            if not keptRanks[rName] then
                local curCount = tonumber(item.Number or item.Count) or 1
                local sellQty = (minKeep > 0) and (curCount - minKeep) or curCount
                if sellQty > 0 then
                    pcall(function()
                        call("Backpack", "TrySellItemRE", uuid, sellQty)
                    end)
                    sold = sold + sellQty
                    task.wait(0.02)
                end
            end
        end
    end
    return sold
end

-- Selective Enchant Stone Selling (Independent stone management & quantity protection)
local function sellEnchantStonesNow()
    local bp = getBackpackItems()
    if not bp then return 0 end

    local targetRanks = {}
    for _, str in ipairs(State.EnchantRaritiesToTarget or {}) do
        targetRanks[cleanRarityText(str)] = true
    end

    local isSellSelected = not State.EnchantFilterMode or State.EnchantFilterMode:find("Sell")
    local sold = 0
    local minKeep = tonumber(State.KeepMinStoneAmount) or 0
    for uuid, item in pairs(bp) do
        if type(item) == "table" and (item.Type == "EnchStone" or (item.ID and tostring(item.ID):find("Stone"))) then
            local rLevel = getItemRarityLevel(item)
            local rName = LEVEL_TO_RARITY[rLevel] or "Common"

            local shouldSell = false
            if isSellSelected then
                shouldSell = (targetRanks[rName] == true)
            else
                shouldSell = not (targetRanks[rName] == true)
            end

            if shouldSell then
                local curCount = tonumber(item.Number or item.Count) or 1
                local sellQty = (minKeep > 0) and (curCount - minKeep) or curCount
                if sellQty > 0 then
                    pcall(function()
                        call("Backpack", "TrySellItemRE", uuid, sellQty)
                    end)
                    sold = sold + sellQty
                    task.wait(0.02)
                end
            end
        end
    end
    return sold
end

local function runSelectiveSellBatch()
    local gearSold = (State.AutoSellTrashGear and sellTrashGearNow() or 0)
    local oreSold = (State.AutoSellOres and sellOresNow() or 0)
    local stoneSold = (State.AutoSellEnchantStones and sellEnchantStonesNow() or 0)
    return gearSold, oreSold, stoneSold
end

local function equipBestPet()
    pcall(function()
        local bp = getBackpackItems()
        if not bp then return end

        local bestUUID, bestPower = nil, -1

        for uuid, item in pairs(bp) do
            if type(item) == "table" and item.ID then
                local isPet = item.Type == "Pet"
                    or tostring(item.ID):lower():find("pet")
                    or tostring(item.ID):lower():find("animal")
                if isPet then
                    local power = 0
                    -- ลองดึงพลังจาก Pet.Helper
                    pcall(function()
                        local PetHelper = require(ReplicatedStorage.Config.Pet.Helper)
                        power = tonumber(PetHelper.GetPower and PetHelper.GetPower(item.ID))
                            or tonumber(PetHelper.GetDamage and PetHelper.GetDamage(item.ID))
                            or 0
                    end)
                    -- Fallback: ใช้ rarity + level เป็น proxy
                    if power == 0 then
                        power = getItemRarityLevel(item) * 100000
                            + (tonumber(item.Level) or 0) * 100
                            + (tonumber(item.EnchanceNum or item.EnhanceNum) or 0)
                    end
                    if power > bestPower then
                        bestUUID  = uuid
                        bestPower = power
                    end
                end
            end
        end

        if bestUUID then
            -- ลองทุก remote ที่เกมอาจใช้สำหรับ equip pet
            call("Pet",      "TryEquipPetRE",   bestUUID)
            call("Backpack", "TryEquipPetRE",   bestUUID)
            call("Pet",      "EquipPetRE",       bestUUID)
            call("Egg",      "EquipPetRE",       bestUUID)
        end
    end)
end

local function fetchOnlineCodes()
    local list = {}
    for _, c in ipairs(knownCodes) do table.insert(list, c) end
    pcall(function()
        local urls = {
            "https://raw.githubusercontent.com/Payomboyz0028/Yaranikaaaa/refs/heads/main/Codes.json",
            "https://raw.githubusercontent.com/Payomboyz0028/Yaranikaaaa/refs/heads/main/Codes.txt",
        }
        for _, u in ipairs(urls) do
            local ok, resp = pcall(game.HttpGet, game, u)
            if ok and type(resp) == "string" and #resp > 5 then
                local okJson, decoded = pcall(function() return HttpService:JSONDecode(resp) end)
                if okJson and type(decoded) == "table" then
                    for _, c in ipairs(decoded) do
                        if type(c) == "string" and not table.find(list, c) then
                            table.insert(list, c)
                        end
                    end
                else
                    for word in resp:gmatch("[%w_]+") do
                        if #word >= 3 and not table.find(list, word) then
                            table.insert(list, word)
                        end
                    end
                end
                break
            end
        end
    end)
    return list
end

local function redeemAllOnlineCodes(silent)
    local activeCodes = fetchOnlineCodes()
    local count = 0
    State.RedeemedCodes = State.RedeemedCodes or {}
    for _, c in ipairs(activeCodes) do
        if not State.RedeemedCodes[c] then
            pcall(function()
                call("Code", "TryUseCodeRF", c)
            end)
            State.RedeemedCodes[c] = true
            count = count + 1
            task.wait(0.25)
        end
    end
    if count > 0 and State.AutoSaveConfig then
        pcall(saveConfig)
    end
    if not silent then
        notify("Codes", State.Language == "TH" and ("ส่งคำขอรับโค้ดใหม่ " .. tostring(count) .. " โค้ดแล้ว!") or ("Redeemed " .. tostring(count) .. " new promo codes!"), "check-circle")
    end
    return count
end

local function applyAntiTrip(humanoid)
    if not humanoid then return end
    pcall(function()
        if State.AntiTrip ~= false then
            humanoid.MaxSlopeAngle = 89
            humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        end
    end)
end

    local function attemptAutoReconnect()
        if not State.AutoReconnect then return end
        if State.AutoDungeon or State.AutoStage then
            task.wait(2.5)
            pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
            task.wait(3.5)
            pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
        end
    end

    pcall(function()
        local CoreGui = game:GetService("CoreGui")
        local promptGui = CoreGui:FindFirstChild("RobloxPromptGui") or CoreGui:WaitForChild("RobloxPromptGui", 5)
        local overlay = promptGui and (promptGui:FindFirstChild("promptOverlay") or promptGui:WaitForChild("promptOverlay", 5))
        if overlay then
            overlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" or child:FindFirstChild("MessageArea") or child:FindFirstChild("ErrorTitle") then
                    attemptAutoReconnect()
                end
            end)
        end
    end)

    LocalPlayer.CharacterAdded:Connect(function(c)
        local h = c:WaitForChild("Humanoid", 8)
        if h and State.AntiTrip then applyAntiTrip(h) end
    end)

    NH.sellTrashGearNow, NH.sellOresNow, NH.sellEnchantStonesNow = sellTrashGearNow, sellOresNow, sellEnchantStonesNow
    NH.runSelectiveSellBatch, NH.equipBestPet = runSelectiveSellBatch, equipBestPet
    NH.redeemAllOnlineCodes, NH.applyAntiTrip = redeemAllOnlineCodes, applyAntiTrip
end


BuildUI = function()
    if CurrentWindow then
        UIRebuilding = true
        pcall(function() CurrentWindow:Destroy() end)
        CurrentWindow = nil
        UIRebuilding = false
    end

    NAPHUB_DEBUG("creating window...")
    local startTheme = NapUI.Theme
    local Window = NapUI.create({
        Title = "NAPHUB",
        Subtitle = State.Language == "TH" and "+1 Loot A Forge  •  ศูนย์ควบคุมฟาร์มอัตโนมัติ" or "+1 Loot A Forge  •  Automation Hub",
        Version = tostring(T("VersionTag")),
        Theme = startTheme,
    })
    NAPHUB_DEBUG("window created")

    local thaiTabNames = { "หน้าหลัก", "ฟาร์มแร่", "ดันเจี้ยน", "ล่าบอส", "ฝึกพลัง", "หลอมดาบ", "คลาส/สัตว์", "รางวัล", "เดินทาง", "ตั้งค่า" }
    local englishTabNames = { "Home", "Loot", "Dungeon", "Boss Hunt", "Training", "Forge", "Classes", "Rewards", "Travel", "Settings" }
    local tabCount = 0
    local rawTab = Window.Tab
    function Window:Tab(config)
        tabCount = tabCount + 1
        config = config or {}
        config.Short = (State.Language == "TH" and thaiTabNames or englishTabNames)[tabCount]
        return rawTab(self, config)
    end
    CurrentWindow = Window

    if not ToggleUiConnection then
        ToggleUiConnection = UserInputService.InputBegan:Connect(function(input, processed)
            if not processed and input.KeyCode == Enum.KeyCode.RightShift and CurrentWindow then
                CurrentWindow:Toggle()
            end
        end)
    end

    -- ═════════════════════════════════════════════════════════════
    --  TAB 1: Dashboard ระบบไก่ตัน (Live Monitoring & Master AI)
    -- ═════════════════════════════════════════════════════════════
    local T1 = Window:Tab({ Title = T("Tab1"), Icon = "layout-dashboard" })

    T1:Section({
        Title = State.Language == "TH" and "สถานะและการทำงานสด (Live Dashboard)" or "Live Telemetry & Dashboard",
        Side = "Right",
    })

    StatusCard = T1:Paragraph({
        Title = State.Language == "TH" and "ระบบฟาร์ม" or "FARM ENGINE",
        Desc  = T(Stats.CurrentActivity),
        Kind  = "Success",
    })

    StatsCard = T1:Paragraph({
        Title = State.Language == "TH" and "สรุปรอบนี้" or "SESSION SUMMARY",
        Desc  = State.Language == "TH" and "เวลาที่เปิดบอท: 00:00:00\nแร่ที่เก็บได้: 0\nรอบที่ขายของ: 0\nมอนสเตอร์ที่กำจัด: 0\nจำนวนครั้งที่เกิดใหม่: 0\nบอสยักษ์ที่จัดการ: 0" or "Elapsed Time: 00:00:00\nOres Collected: 0\nSales Executed: 0\nMonsters Defeated: 0\nRebirths: 0\nSuper Loot Defeated: 0",
        Kind  = "Info",
    })

    BagCard = T1:Paragraph({
        Title = State.Language == "TH" and "กระเป๋า / พลังชีวิต" or "INVENTORY / VITALS",
        Desc  = State.Language == "TH" and "ความจุสัมภาระ: 0 / 10\nพลังชีวิต: 100%" or "Backpack Capacity: 0 / 10\nHealth: 100%",
        Kind  = "Warning",
    })

    T1:Section({ Title = T("Sec_Master"), Side = "Left" })

    T1:Toggle({
        Title = T("Tgl_Master247"),
        Desc  = T("Desc_Master247"),
        Value = State.Master247,
        Callback = function(v)
            State.Master247 = v
            if v then
                -- ★ Master ON: farm loop is the core, forge/upgrade are secondary
                State.DropMagnet           = true
                State.UltraPrompt          = true
                State.AutoSafeEvacuate     = true
                State.GodMode              = true
                State.KillAura             = true
                State.AntiAFK              = true
                State.DungeonInstaKill     = true
                State.StageInstaKill       = true
                State.MasterAutoUpgrade    = true
                State.MasterAutoForgeWhenReady = true
                State.AutoEnchant          = true
                notify("Master ระบบไก่ตัน",
                    State.Language == "TH"
                        and "เปิดระบบไก่ตัน — ดันเจี้ยน > ด่าน > หลอม (เมื่อแร่พอ) > ตีบวก/อักขระ"
                        or  "Master farm engaged — Dungeon > Stage > Forge > Auto Enchant",
                    "zap")
            else
                Stats.CurrentActivity = "StatusPaused"
            end
            if State.AutoSaveConfig then saveConfig() end
        end,
    })

    T1:Toggle({
        Title = State.Language == "TH" and "เปิดระบบ Forge อัตโนมัติ (เมื่อแร่ครบ)" or "Auto Forge when Ores Ready",
        Desc  = State.Language == "TH" and "หลอมเฉพาะเมื่อแร่ถึงเกณฑ์ ไม่รัน Forge ทุกรอบ" or "Forge only when ore count hits threshold — not every tick",
        Value = State.MasterAutoForgeWhenReady,
        Callback = function(v) State.MasterAutoForgeWhenReady = v end,
    })

    T1:Toggle({
        Title = State.Language == "TH" and "เปิดระบบอัปเกรดอัตโนมัติ (พื้นหลัง)" or "Auto Upgrade in Background",
        Desc  = State.Language == "TH" and "อัปเกรด Train/OrePack/Luck ทุก 3 วิเมื่อมีเงิน" or "Upgrade Train/OrePack/Luck every 3 s when funds available",
        Value = State.MasterAutoUpgrade,
        Callback = function(v) State.MasterAutoUpgrade = v end,
    })

    T1:Toggle({
        Title = State.Language == "TH" and "เปิดระบบลงอักขระ (Auto Enchant) อัตโนมัติ" or "Auto Enchant in Background",
        Desc  = State.Language == "TH" and "สลักหินอักขระลงเกียร์ที่ใส่อัตโนมัติ (กรองหินระดับเทพไว้)" or "Applies enchant stones onto equipped gear while preserving top-tier stones",
        Value = State.AutoEnchant,
        Callback = function(v) State.AutoEnchant = v end,
    })

    T1:Toggle({
        Title = State.Language == "TH" and "เปิดโหมด GOD-Farm ในระบบไก่ตัน (Stage Blitz)" or "GOD-Farm Blitz in Master Loop",
        Desc  = State.Language == "TH" and "ทะลวงผ่าน Stage 1 ถึง 30 ด้วยความเร็วสูง 0.08–0.1s เมื่อไม่มีตั๋วดันเจี้ยน" or "Speed-blitz stages 1-30 at 0.08-0.1s per stage when dungeon tickets are out",
        Value = State.MasterStageBlitz,
        Callback = function(v) State.MasterStageBlitz = v end,
    })

    T1:Toggle({
        Title = State.Language == "TH" and "หลอมอุปกรณ์อัตโนมัติคู่ขนานขณะฟาร์ม (Concurrent Forge)" or "Concurrent Forging During Farm",
        Desc  = State.Language == "TH" and "หลอมอุปกรณ์ทันทีที่แร่ครบในด่านที่ 15 และ 30 โดยไม่ต้องหยุดลูปฟาร์ม" or "Forges gear immediately at stages 15 and 30 without pausing stage pipeline",
        Value = State.MasterConcurrentForge,
        Callback = function(v) State.MasterConcurrentForge = v end,
    })

    T1:Toggle({
        Title = State.Language == "TH" and "เปิดระบบคลิกฟาร์มคะแนนดาบอัตโนมัติ (Sword Power)" or "Auto Click Sword Power in Master Loop",
        Desc  = State.Language == "TH" and "เหวี่ยงดาบเก็บคะแนนพลัง (+2) ตลอดเวลาอย่างปลอดภัย" or "Continuously swings sword to gain Power points safely",
        Value = State.MasterAutoClickSword,
        Callback = function(v) State.MasterAutoClickSword = v end,
    })

    T1:Toggle({
        Title = State.Language == "TH" and "เปิดสมองกล AI คำนวณ DPS สูงสุด (Algorithmic DPS)" or "Algorithmic DPS & Affix Solver AI",
        Desc  = State.Language == "TH" and "วิเคราะห์ตัวคูณ Attack, Crit, และ Enchant เพื่อสวมใส่เซ็ตดาเมจสูงสุด" or "Solves maximum effective DPS mathematically and auto-equips best synergy",
        Value = State.AlgorithmicDPSSolver,
        Callback = function(v) State.AlgorithmicDPSSolver = v end,
    })

    T1:Toggle({
        Title = T("Tgl_MasterDungeonTicket"),
        Desc  = T("Desc_MasterDungeonTicket"),
        Value = State.MasterDungeonTicket,
        Callback = function(v) State.MasterDungeonTicket = v end,
    })

    T1:Toggle({
        Title = T("Tgl_MasterTrainWhenIdle"),
        Desc  = T("Desc_MasterTrainWhenIdle"),
        Value = State.MasterTrainWhenIdle,
        Callback = function(v) State.MasterTrainWhenIdle = v end,
    })

    T1:Toggle({
        Title = State.Language == "TH" and "เปิดบัคแท่น x100 VIP ในระบบไก่ตัน (Force VIP x100)" or "Force VIP x100 in Master Automation",
        Desc  = State.Language == "TH" and "รับตัวคูณฝึกพลัง 100 เท่าอัตโนมัติเมื่ออยู่ในช่วงพักฝึกพลัง" or "Automatically apply 100x multiplier during idle training periods",
        Value = State.ForceVIPTrain,
        Callback = function(v) State.ForceVIPTrain = v end,
    })

    T1:Section({ Title = T("Sec_QuickActions"), Side = "Right" })

    T1:Button({
        Title = T("Btn_EmergencyEvac"),
        Desc  = T("Desc_EmergencyEvac"),
        Callback = function()
            call("Stage", "ClaimedAllOreRE")
            tpTo(getSafeZoneCF())
            call("Backpack", "TrySellAllRE")
            Stats.SellCycles = Stats.SellCycles + 1
            notify(State.Language == "TH" and "โซนปลอดภัย" or "Safe Zone", T("Notif_SafeZoneSecured"), "shield")
        end,
    })

    T1:Button({
        Title = T("Btn_SellAllNow"),
        Callback = function()
            call("Backpack", "TrySellAllRE")
            Stats.SellCycles = Stats.SellCycles + 1
            notify(State.Language == "TH" and "พ่อค้าขายของ" or "Merchant", T("Notif_SellExecuted"), "coins")
        end,
    })

    T1:Button({
        Title = T("Btn_InstantMagnet"),
        Callback = function()
            runDropMagnet()
            runUltraPrompts()
            notify(State.Language == "TH" and "ดูดแร่ทันที" or "Magnet", T("Notif_MagnetCollected"), "sparkles")
        end,
    })

    -- ═════════════════════════════════════════════════════════════
    --  TAB 2: Safe Loot & Magnet (Drop Teleportation)
    -- ═════════════════════════════════════════════════════════════
    local T2 = Window:Tab({ Title = T("Tab2"), Icon = "gem" })

    T2:Section({ Title = T("Sec_Magnet"), Side = "Left" })

    T2:Toggle({
        Title = T("Tgl_DropMagnet"),
        Desc  = T("Desc_DropMagnet"),
        Value = State.DropMagnet,
        Callback = toggleLoop("DropMagnet", "MagnetInterval", runDropMagnet),
    })

    T2:Dropdown({
        Title = T("Drop_MagnetTarget"),
        Desc  = T("Desc_MagnetTarget"),
        Values = { T("Opt_SafeZone"), T("Opt_ToPlayer") },
        Value = (State.MagnetTarget == "Safe Zone" and T("Opt_SafeZone") or T("Opt_ToPlayer")),
        Callback = function(v)
            if v:find("Safe") or v:find("ปลอดภัย") then
                State.MagnetTarget = "Safe Zone"
            else
                State.MagnetTarget = "To Player"
            end
        end,
    })

    T2:Slider({
        Title = T("Sld_MagnetInterval"),
        Value = { Min = 0.05, Max = 1.0, Default = State.MagnetInterval },
        Callback = function(v) State.MagnetInterval = v end,
    })

    T2:Toggle({
        Title = T("Tgl_UltraPrompt"),
        Desc  = T("Desc_UltraPrompt"),
        Value = State.UltraPrompt,
        Callback = toggleLoop("UltraPrompt", 0.15, runUltraPrompts),
    })

    T2:Section({ Title = T("Sec_SafeEvac"), Side = "Right" })

    T2:Toggle({
        Title = T("Tgl_AutoSafeEvac"),
        Desc  = T("Desc_AutoSafeEvac"),
        Value = State.AutoSafeEvacuate,
        Callback = function(v) State.AutoSafeEvacuate = v end,
    })

    T2:Slider({
        Title = T("Sld_EvacThreshold"),
        Value = { Min = 50, Max = 100, Default = State.EvacuateThreshold },
        Callback = function(v) State.EvacuateThreshold = v end,
    })

    T2:Toggle({
        Title = T("Tgl_LowHPEvac"),
        Desc  = T("Desc_LowHPEvac"),
        Value = State.LowHPEvacuate,
        Callback = function(v) State.LowHPEvacuate = v end,
    })

    T2:Slider({
        Title = T("Sld_LowHPThreshold"),
        Value = { Min = 10, Max = 50, Default = State.LowHPThreshold },
        Callback = function(v) State.LowHPThreshold = v end,
    })

    T2:Section({ Title = T("Sec_AutoSell"), Side = "Right" })

    T2:Toggle({
        Title = T("Tgl_AutoSell"),
        Desc  = T("Desc_AutoSell"),
        Value = State.AutoSell,
        Callback = toggleLoop("AutoSell", "SellDelay", function()
            call("Backpack", "TrySellAllRE")
            Stats.SellCycles = Stats.SellCycles + 1
        end),
    })

    T2:Slider({
        Title = T("Sld_SellDelay"),
        Value = { Min = 1, Max = 60, Default = State.SellDelay },
        Callback = function(v) State.SellDelay = v end,
    })


    T2:Section({ Title = State.Language == "TH" and "ขายอุปกรณ์/แร่/หินแบบเลือกเกรด (จาก PAYOMBØYZ)" or "Selective Merchant (ported)", Side = "Right" })

    T2:Toggle({
        Title = State.Language == "TH" and "ขายเฉพาะอุปกรณ์ขยะ (Smart Sell Trash)" or "Smart Sell Trash Gear",
        Desc  = State.Language == "TH" and "ขายดาบ/ชุด/หมวกเกรดต่ำที่ไม่ได้สวมใส่ ไม่แตะแร่/หิน" or "Sell unequipped gear below the chosen rarity — ores untouched",
        Value = State.AutoSellTrashGear,
        Callback = toggleLoop("AutoSellTrashGear", "SellDelay", function()
            NH.sellTrashGearNow()
            Stats.SellCycles = Stats.SellCycles + 1
        end),
    })

    T2:Dropdown({
        Title  = State.Language == "TH" and "เก็บระดับนี้และสูงกว่า" or "Keep Rarity & Above",
        Values = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Eternal", "Ancient" },
        Value  = State.MinGearRarityToKeep,
        Callback = function(v) State.MinGearRarityToKeep = v end,
    })

    T2:Button({
        Title = State.Language == "TH" and "ขายอุปกรณ์ขยะทันที" or "Sell Trash Gear Now",
        Callback = function()
            local sold = NH.sellTrashGearNow()
            notify(State.Language == "TH" and "พ่อค้า" or "Merchant", (State.Language == "TH" and "ขายแล้ว " or "Sold ") .. tostring(sold), "coins")
        end,
    })

    T2:Toggle({
        Title = State.Language == "TH" and "ขายแร่อัตโนมัติ (เก็บเกรดที่เลือก)" or "Auto Sell Ores (keep selected rarities)",
        Value = State.AutoSellOres,
        Callback = toggleLoop("AutoSellOres", "SellDelay", function() NH.sellOresNow() end),
    })

    T2:Dropdown({
        Title  = State.Language == "TH" and "เกรดแร่ที่จะเก็บไว้" or "Ore Rarities To Keep",
        Values = { "👑 Infinite", "💠 Ancient", "⭐ Secret", "🔮 Eternal", "🔴 Mythic", "🟡 Legendary", "🟣 Epic", "🟢 Rare", "⚪ Common" },
        Value  = State.OreRaritiesToKeep,
        Multi  = true,
        Callback = function(val)
            State.OreRaritiesToKeep = type(val) == "table" and val or { val }
            if State.AutoSaveConfig then saveConfig() end
        end,
    })

    T2:Slider({
        Title = State.Language == "TH" and "จำนวนแร่ขั้นต่ำที่เก็บไว้" or "Minimum Ore Count To Keep",
        Value = { Min = 0, Max = 100, Default = State.KeepMinOreAmount or 0 },
        Callback = function(v) State.KeepMinOreAmount = v end,
    })

    T2:Button({
        Title = State.Language == "TH" and "ขายแร่ทันที" or "Sell Ores Now",
        Callback = function()
            local n = NH.sellOresNow()
            notify("Ore Sell", (State.Language == "TH" and "ขายแร่ " or "Sold ores: ") .. tostring(n), "coins")
        end,
    })

    T2:Toggle({
        Title = State.Language == "TH" and "ขายหินเอนจันท์อัตโนมัติ" or "Auto Sell Enchant Stones",
        Value = State.AutoSellEnchantStones,
        Callback = toggleLoop("AutoSellEnchantStones", "SellDelay", function() NH.sellEnchantStonesNow() end),
    })

    T2:Dropdown({
        Title  = State.Language == "TH" and "โหมดหินเอนจันท์" or "Stone Mode",
        Values = { "Sell Selected", "Keep Selected" },
        Value  = State.EnchantFilterMode,
        Callback = function(v) State.EnchantFilterMode = v end,
    })

    T2:Dropdown({
        Title  = State.Language == "TH" and "เกรดหินที่เลือก" or "Stone Rarities (selected)",
        Values = { "👑 Infinite", "💠 Ancient", "⭐ Secret", "🔮 Eternal", "🔴 Mythic", "🟡 Legendary", "🟣 Epic", "🟢 Rare", "🟩 Uncommon", "⚪ Common" },
        Value  = State.EnchantRaritiesToTarget,
        Multi  = true,
        Callback = function(val)
            State.EnchantRaritiesToTarget = type(val) == "table" and val or { val }
            if State.AutoSaveConfig then saveConfig() end
        end,
    })

    T2:Slider({
        Title = State.Language == "TH" and "จำนวนหินขั้นต่ำที่เก็บไว้" or "Minimum Stone Count To Keep",
        Value = { Min = 0, Max = 100, Default = State.KeepMinStoneAmount or 0 },
        Callback = function(v) State.KeepMinStoneAmount = v end,
    })

    T2:Toggle({
        Title = State.Language == "TH" and "สวมสัตว์เลี้ยงที่แรงที่สุดอัตโนมัติ" or "Auto Equip Best Pet",
        Value = State.AutoEquipBestPet,
        Callback = toggleLoop("AutoEquipBestPet", "PetEquipDelay", function() NH.equipBestPet() end),
    })

    T2:Toggle({
        Title = State.Language == "TH" and "ป้องกันสะดุดล้ม (Anti-Trip)" or "Anti-Trip & Ragdoll Immunity",
        Value = State.AntiTrip,
        Callback = function(v)
            State.AntiTrip = v
            local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if h then
                if v then NH.applyAntiTrip(h)
                else pcall(function()
                    h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
                    h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
                end) end
            end
        end,
    })

    T2:Toggle({
        Title = State.Language == "TH" and "รีคอนเนคอัตโนมัติเมื่อหลุด" or "Auto Reconnect On Disconnect",
        Desc  = State.Language == "TH" and "ทำงานเมื่อเปิด Auto Dungeon / Auto Stage อยู่" or "Active while Auto Dungeon / Auto Stage is on",
        Value = State.AutoReconnect,
        Callback = function(v) State.AutoReconnect = v end,
    })

    -- ═════════════════════════════════════════════════════════════
    --  TAB 3: Dungeon & Combat (★ PRIMARY FARM CORE)
    -- ═════════════════════════════════════════════════════════════
    local T3 = Window:Tab({ Title = T("Tab3"), Icon = "swords" })

    T3:Section({ Title = T("Sec_Dungeon"), Side = "Left" })

    T3:Toggle({
        Title = T("Tgl_AutoDungeon"),
        Desc  = T("Desc_AutoDungeon"),
        Value = State.AutoDungeon,
        Callback = toggleLoop("AutoDungeon", 0.5, runDungeonLoop),
    })

    T3:Slider({
        Title = T("Sld_DungeonRound"),
        Value = { Min = 1, Max = 30, Default = State.DungeonRound },
        Callback = function(v) State.DungeonRound = v end,
    })

    T3:Toggle({
        Title = T("Tgl_ClaimTicket"),
        Value = State.AutoClaimTicket,
        Callback = function(v) State.AutoClaimTicket = v end,
    })

    -- ★ INSTANT KILL toggles
    T3:Toggle({
        Title = State.Language == "TH" and "★ Instant Kill มอนสเตอร์ในดันเจี้ยนทันที" or "★ Instant Kill Dungeon Mobs",
        Desc  = State.Language == "TH" and "กำจัดมอนสเตอร์ด้วย EnemyCTRL+BindableEvent ในทันที (เร็วที่สุด)" or "Eliminate mobs via EnemyCTRL + BindableEvent instantly",
        Value = State.DungeonInstaKill,
        Callback = function(v) State.DungeonInstaKill = v end,
    })

    T3:Section({ Title = T("Sec_Stage"), Side = "Right" })

    T3:Dropdown({
        Title = T("Drop_Stage"),
        Desc  = T("Desc_Stage"),
        Values = Dynamic.Stages,
        Value = State.SelectedStage,
        Callback = function(v) State.SelectedStage = v end,
    })

    T3:Toggle({
        Title = T("Tgl_AutoStage"),
        Desc  = T("Desc_AutoStage"),
        Value = State.AutoStage,
        Callback = toggleLoop("AutoStage", 0.5, runStageLoop),
    })

    -- ★ Stage Instant Kill toggle
    T3:Toggle({
        Title = State.Language == "TH" and "★ Instant Kill มอนสเตอร์ในด่านทันที" or "★ Instant Kill Stage Mobs",
        Desc  = State.Language == "TH" and "กำจัดมอนสเตอร์ในด่านทันที ทั้ง InstaKill + KillAura" or "Eliminate stage mobs instantly via InstaKill + KillAura layers",
        Value = State.StageInstaKill,
        Callback = function(v) State.StageInstaKill = v end,
    })

    T3:Toggle({
        Title = T("Tgl_ClimbStages"),
        Desc  = T("Desc_ClimbStages"),
        Value = State.AutoClimbStages,
        Callback = function(v) State.AutoClimbStages = v end,
    })

    T3:Slider({
        Title = T("Sld_ClimbTimeout"),
        Desc  = T("Desc_ClimbTimeout"),
        Value = { Min = 10, Max = 60, Default = State.StageClimbTimeout },
        Callback = function(v) State.StageClimbTimeout = v end,
    })

    T3:Toggle({
        Title = State.Language == "TH" and "★ GOD-Farm: ทะลวง 30 ด่านความเร็วแสง (Fast Pipeline)" or "★ GOD-Farm: Stage Blitz 1-30 Pipeline",
        Desc  = State.Language == "TH" and "ยิงเคลียร์ Stage 1 ถึง 30 รวดเดียวหน่วง 0.08–0.1s ไม่ต้องเดินตัวละคร" or "Direct remote pipeline clearing Stage 1 to 30 in ~2.5s with zero walking",
        Value = State.GodFarmStageBlitz,
        Callback = function(v)
            State.GodFarmStageBlitz = v
            if v then task.spawn(runStageBlitz) end
        end,
    })

    T3:Slider({
        Title = State.Language == "TH" and "ความเร็วทะลวงด่าน (วินาทีต่อด่าน)" or "Blitz Stage Delay (Seconds)",
        Value = { Min = 0.08, Max = 0.3, Default = State.StageBlitzInterval },
        Callback = function(v) State.StageBlitzInterval = v end,
    })

    T3:Button({
        Title = State.Language == "TH" and "ยิง GOD-Farm ทะลวง 30 ด่านทันที (Run Blitz Now)" or "Trigger GOD-Farm Blitz Now",
        Callback = function()
            task.spawn(runStageBlitz)
            notify("GOD-Farm", State.Language == "TH" and "เริ่มทะลวง Stage 1-30 ด้วยความเร็วสูง!" or "Dispatched 30-stage blitz pipeline", "zap")
        end,
    })

    T3:Section({ Title = T("Sec_Combat"), Side = "Left" })

    T3:Toggle({
        Title = T("Tgl_KillAura"),
        Desc  = T("Desc_KillAura"),
        Value = State.KillAura,
        Callback = toggleLoop("KillAura", "KillAuraDelay", runKillAura),
    })

    T3:Slider({
        Title = T("Sld_KillAuraDelay"),
        Value = { Min = 0.05, Max = 1.0, Default = State.KillAuraDelay },
        Callback = function(v) State.KillAuraDelay = v end,
    })

    T3:Toggle({
        Title = T("Tgl_GodMode"),
        Desc  = T("Desc_GodMode"),
        Value = State.GodMode,
        Callback = function(v)
            State.GodMode = v
            maintainGodMode()
        end,
    })

    T3:Section({ Title = State.Language == "TH" and "โหมดบินปลอดภัย (Combat Flight)" or "Combat Safe Flight", Side = "Right" })

    T3:Toggle({
        Title = T("Tgl_SafeFlight"),
        Desc  = T("Desc_SafeFlight"),
        Value = State.SafeCombatFlight,
        Callback = function(v) State.SafeCombatFlight = v end,
    })

    T3:Slider({
        Title = T("Sld_FlightHeight"),
        Value = { Min = 8, Max = 30, Default = State.FlightHeight },
        Callback = function(v) State.FlightHeight = v end,
    })

    -- ═════════════════════════════════════════════════════════════
    --  TAB 4: Super Loot Boss Hunter (Rare Ore Sniper)
    -- ═════════════════════════════════════════════════════════════
    local T4 = Window:Tab({ Title = T("Tab4"), Icon = "crosshair" })

    T4:Section({ Title = T("Sec_BossHunter"), Side = "Left" })

    T4:Toggle({
        Title = T("Tgl_BossHunter"),
        Desc  = T("Desc_BossHunter"),
        Value = State.SuperLootHunter,
        Callback = function(v) State.SuperLootHunter = v end,
    })

    T4:Dropdown({
        Title = T("Drop_BossTier"),
        Desc  = T("Desc_BossTier"),
        Values = Dynamic.SuperLootTiers,
        Value = State.SuperLootTargetTier,
        Callback = function(v) State.SuperLootTargetTier = v end,
    })

    T4:Toggle({
        Title = T("Tgl_BossNotify"),
        Value = State.SuperLootNotify,
        Callback = function(v) State.SuperLootNotify = v end,
    })

    T4:Button({
        Title = T("Btn_ScanBoss"),
        Callback = function()
            checkSuperLootHunter()
            notify(State.Language == "TH" and "สไนป์บอสยักษ์" or "Boss Hunter", State.Language == "TH" and "สแกนค้นหาบอสแร่ยักษ์ข้ามแมพเรียบร้อย" or "Manual sweep for Super Loot executed", "crosshair")
        end,
    })

    T4:Section({ Title = State.Language == "TH" and "เรดาร์บอสและข้อมูลสด (Boss Intel)" or "Boss Radar & Intel", Side = "Right" })

    T4:Paragraph({
        Title = State.Language == "TH" and "เรดาร์ค้นหาบอสข้ามแมพ" or "SUPER LOOT RADAR",
        Desc  = State.Language == "TH" and "ระบบตรวจจับ: สแกนบอสยักษ์ทุกจุดเกิดอัตโนมัติ\nสถานะการล่า: พร้อมวาร์ปและดูดแร่ทันทีเมื่อบอสเกิด" or "Radar Status: Scanning across entire server map\nTarget: Super Loot / Giant Ore\nMode: Auto Sweep & Snipe",
        Kind  = "Info",
    })

    T4:Button({
        Title = State.Language == "TH" and "วาร์ปไปหาบอสใกล้ที่สุดทันที" or "Teleport to Nearest Super Loot",
        Callback = function()
            checkSuperLootHunter()
        end,
    })

    -- ═════════════════════════════════════════════════════════════
    --  TAB 5: Train & Upgrades (Stat Progression)
    -- ═════════════════════════════════════════════════════════════
    local T5 = Window:Tab({ Title = T("Tab5"), Icon = "zap" })

    T5:Section({ Title = T("Sec_Train"), Side = "Left" })

    T5:Toggle({
        Title = State.Language == "TH" and "★ ยืนแท่นฝึกพลังที่เลือกอัตโนมัติ (Auto Train Zone)" or "★ Auto Stand on Selected Train Zone",
        Desc  = State.Language == "TH" and "วาร์ปไปยืนแท่นที่เลือกด้านล่าง (หรือแท่นสูงสุดที่ปลดล็อคเมื่อเลือก Auto Best)" or "Teleport to the zone selected below (or the best unlocked one with Auto Best)",
        Value = State.AutoTrainBestZone,
        Callback = function(v)
            State.AutoTrainBestZone = v
            if v then
                local zone = getSelectedTrainZone()
                if zone then
                    task.spawn(function() pcall(enterTrainZone, zone) end)
                    notify(
                        State.Language == "TH" and "แท่นฝึกพลัง" or "Train Zone",
                        (State.Language == "TH" and "เดินทางไปแท่น: " or "Teleported to: ") .. (zone.Name or "?"),
                        "zap"
                    )
                end
            elseif State.AutoTrain == false and State.AutoTrainMode == false then
                call("Train", "ExitAutoTrainRE")
            end
        end,
    })

    T5:Dropdown({
        Title = State.Language == "TH" and "เลือกแท่นฝึกพลัง (Select Training Zone)" or "Select Training Zone",
        Desc  = T("Desc_TrainArea"),
        Values = getTrainZoneNames(),
        Value = State.SelectedTrainZone,
        Callback = function(v)
            State.SelectedTrainZone = v
            local z = getZoneByName(v)
            if z then State.TrainArea = tostring(z.Id) end
            if State.AutoTrainBestZone then
                task.spawn(function() pcall(enterTrainZone) end)
            end
        end,
    })

    T5:Toggle({
        Title = T("Tgl_AutoTrain"),
        Desc  = T("Desc_AutoTrain"),
        Value = State.AutoTrain,
        Callback = toggleLoop("AutoTrain", "TrainDelay", function()
            if State.ForceVIPTrain then
                LocalPlayer:SetAttribute("AutoTrainAreaID", 9)
                call("Train", "IntoAutoTrainRE", 9)
            elseif State.AutoTrainBestZone then
                pcall(enterTrainZone)
            end
            local tc = TrainCTRL or (ReplicatedStorage:FindFirstChild("CTRL") and require(ReplicatedStorage.CTRL.TrainCTRL))
            if tc and type(tc.TrainOnce) == "function" then
                tc.TrainOnce()
            else
                call("Train", "TrainOnceRE")
            end
        end),
    })

    T5:Slider({
        Title = T("Sld_TrainDelay"),
        Value = { Min = 0.05, Max = 1.5, Default = State.TrainDelay },
        Callback = function(v) State.TrainDelay = v end,
    })

    T5:Toggle({
        Title = State.Language == "TH" and "★ คลิกฟาร์มคะแนนดาบอัตโนมัติ (Auto Click Sword)" or "★ Auto Click / Swing Sword Power",
        Desc  = State.Language == "TH" and "คลิกเหวี่ยงดาบเก็บคะแนน Power (+2) รัวๆ อัตโนมัติ" or "Rapidly swings sword to accumulate Power score automatically",
        Value = State.AutoClickSword,
        Callback = function(v) State.AutoClickSword = v end,
    })

    T5:Slider({
        Title = State.Language == "TH" and "ความเร็วคลิกดาบต่อครั้ง (วินาที)" or "Sword Click Interval (Seconds)",
        Value = { Min = 0.08, Max = 0.5, Default = State.SwordClickDelay },
        Callback = function(v) State.SwordClickDelay = v end,
    })

    T5:Toggle({
        Title = T("Tgl_NativeAutoTrain"),
        Desc  = T("Desc_NativeAutoTrain"),
        Value = State.AutoTrainMode,
        Callback = function(v)
            State.AutoTrainMode = v
            if v then call("Train", "IntoAutoTrainRE", (getSelectedTrainZone() or TrainAreaConfig[1]).Id)
            else      call("Train", "ExitAutoTrainRE") end
        end,
    })

    T5:Toggle({
        Title = State.Language == "TH" and "★ ฟาร์มแท่นผ่าน Remote (ไม่ต้องยืนแท่น)" or "★ Remote-Only Train Farm (No Teleport)",
        Desc  = State.Language == "TH"
            and "ยิงคำสั่ง TrainOnceRE ตรงๆ ทุก 0.15s โดยไม่ต้อง Teleport ไปแท่นเลย เซิร์ฟเวอร์ตรวจแค่ UUID ไม่ใช่ตำแหน่ง"
            or  "Fires TrainOnceRE directly every 0.15s — server validates UUID only, no position required",
        Value = State.RemoteOnlyTrain,
        Callback = function(v)
            State.RemoteOnlyTrain = v
            notify(
                State.Language == "TH" and "Remote Train Farm" or "Remote Train Farm",
                v and (State.Language == "TH" and "⚡ เปิดโหมด Remote Train — ยิง TrainOnceRE ไม่ต้องยืนแท่น" or "⚡ Remote Train active — firing without teleport")
                   or (State.Language == "TH" and "ปิดโหมด Remote Train แล้ว" or "Remote Train disabled"),
                "zap"
            )
        end,
    })

    T5:Toggle({
        Title = State.Language == "TH" and "★ บัคแท่น x100 VIP (Force Zone 9 Bypass)" or "★ Force x100 VIP Zone Bug (Zone 9 Bypass)",
        Desc  = State.Language == "TH"
            and "บายพาสระบบตรวจ Gamepass ของเซิร์ฟเวอร์ ให้ได้รับโบนัสฝึกพลัง x100 ตลอดเวลา โดยยืนบนแท่นธรรมดาอย่างปลอดภัย ไม่โดนป๊อปอัพ Robux บังหน้าจอ"
            or  "Bypasses server Gamepass check to receive 100x training multiplier permanently while safely standing on regular pads without Robux prompts",
        Value = State.ForceVIPTrain,
        Callback = function(v)
            State.ForceVIPTrain = v
            if v then
                pcall(function()
                    LocalPlayer:SetAttribute("AutoTrainAreaID", 9)
                    call("Train", "IntoAutoTrainRE", 9)
                    local tc = TrainCTRL or (ReplicatedStorage:FindFirstChild("CTRL") and require(ReplicatedStorage.CTRL.TrainCTRL))
                    if tc then
                        if tc.StartAutoTrain and not (tc.GetIsAutoing and tc.GetIsAutoing()) then tc.StartAutoTrain() end
                        if tc.TrainOnce then tc.TrainOnce() end
                    end
                end)
                notify(
                    State.Language == "TH" and "x100 VIP Bypass" or "x100 VIP Bypass",
                    State.Language == "TH" and "⚡ เปิดใช้งานแท่น x100 VIP สำเร็จ (โบนัส 100 เท่า)" or "⚡ x100 VIP Training Bypass Active (100x Multiplier)",
                    "zap"
                )
            else
                pcall(disengageIdleTraining)
                notify(
                    State.Language == "TH" and "x100 VIP Bypass" or "x100 VIP Bypass",
                    State.Language == "TH" and "ปิดโหมด x100 VIP แล้ว" or "x100 VIP Training Bypass disabled",
                    "info"
                )
            end
        end,
    })

    T5:Section({ Title = T("Sec_Upgrade"), Side = "Right" })

    T5:Dropdown({
        Title = T("Drop_UpgradeType"),
        Desc  = T("Desc_UpgradeType"),
        Values = { T("Opt_UpgradeAll"), "Train", "OrePack", "Luck" },
        Value = (State.UpgradeType == "All in One" and T("Opt_UpgradeAll") or State.UpgradeType),
        Callback = function(o)
            if o:find("All") or o:find("ทั้งหมด") then
                State.UpgradeType = "All in One"
            else
                State.UpgradeType = o
            end
        end,
    })

    T5:Toggle({
        Title = T("Tgl_AutoUpgrade"),
        Desc  = T("Desc_AutoUpgrade"),
        Value = State.AutoUpgrade,
        Callback = toggleLoop("AutoUpgrade", "UpgradeDelay", function()
            if State.UpgradeType == "All in One" then
                call("Upgrade", "UpgradeOnceRE", "Train")
                call("Upgrade", "UpgradeOnceRE", "OrePack")
                call("Upgrade", "UpgradeOnceRE", "Luck")
            else
                call("Upgrade", "UpgradeOnceRE", State.UpgradeType)
            end
        end),
    })

    T5:Slider({
        Title = T("Sld_UpgradeDelay"),
        Value = { Min = 0.5, Max = 5.0, Default = State.UpgradeDelay },
        Callback = function(v) State.UpgradeDelay = v end,
    })

    T5:Section({ Title = T("Sec_Rebirth"), Side = "Right" })

    T5:Toggle({
        Title = T("Tgl_AutoRebirth"),
        Desc  = T("Desc_AutoRebirth"),
        Value = State.AutoRebirth,
        Callback = toggleLoop("AutoRebirth", "RebirthDelay", function()
            call("Rebirth", "TryRebirthRE")
            Stats.RebirthCount = Stats.RebirthCount + 1
        end),
    })

    T5:Slider({
        Title = T("Sld_RebirthDelay"),
        Value = { Min = 2, Max = 60, Default = State.RebirthDelay },
        Callback = function(v) State.RebirthDelay = v end,
    })

    T5:Toggle({
        Title = T("Tgl_NativeRebirth"),
        Value = State.NativeAutoRebirth,
        Callback = function(v)
            State.NativeAutoRebirth = v
            call("Rebirth", "UpdateAutoRebirthRE", v)
        end,
    })

    -- ═════════════════════════════════════════════════════════════
    --  TAB 6: Forge & Equipment (★ SECONDARY — runs AFTER farming)
    -- ═════════════════════════════════════════════════════════════
    local T6 = Window:Tab({ Title = T("Tab6"), Icon = "hammer" })

    T6:Section({
        Title = State.Language == "TH"
            and "★ Forge คือระบบรอง — ระบบหลักคือ Dungeon & Stage"
            or  "★ Forge is SECONDARY — Primary = Dungeon & Stage farming",
        Description = State.Language == "TH"
            and "หลอมอุปกรณ์เฉพาะเมื่อแร่ครบตามที่ตั้ง ไม่หลอมทุกรอบ"
            or  "Forge only triggers when ore count meets threshold — not every tick",
        Side = "Left",
    })

    T6:Section({ Title = T("Sec_Forge"), Side = "Left" })

    T6:Dropdown({
        Title = T("Drop_ForgeType"),
        Values = { T("ForgeTypeAll"), T("ForgeTypeWeapon"), T("ForgeTypeArmor"), T("ForgeTypeHat") },
        Value = T(State.ForgeType == "Weapon" and "ForgeTypeWeapon" or State.ForgeType == "Armor" and "ForgeTypeArmor" or State.ForgeType == "Hat" and "ForgeTypeHat" or "ForgeTypeAll"),
        Callback = function(value)
            if value == T("ForgeTypeWeapon") then State.ForgeType = "Weapon"
            elseif value == T("ForgeTypeArmor") then State.ForgeType = "Armor"
            elseif value == T("ForgeTypeHat") then State.ForgeType = "Hat"
            else State.ForgeType = "All" end
        end,
    })

    T6:Slider({
        Title = T("Sld_MinOres"),
        Desc = State.Language == "TH" and "อาวุธ 4–13 • เกราะ 8/11/23 • หมวก 4/16" or "Weapon 4–13 • Armor 8/11/23 • Hat 4/16",
        Value = { Min = 4, Max = 23, Default = State.MinOreToForge },
        Callback = function(value) State.MinOreToForge = math.floor(value) end,
    })

    T6:Dropdown({
        Title = T("Drop_OreQuality"),
        Values = { T("OreQualityAny"), T("OreQualityHigh"), T("OreQualityLow") },
        Value = T(State.OreQualityMode == "High" and "OreQualityHigh" or State.OreQualityMode == "Low" and "OreQualityLow" or "OreQualityAny"),
        Callback = function(value)
            if value == T("OreQualityHigh") then State.OreQualityMode = "High"
            elseif value == T("OreQualityLow") then State.OreQualityMode = "Low"
            else State.OreQualityMode = "Any" end
        end,
    })

    T6:Toggle({
        Title = T("Tgl_AutoForge"),
        Desc  = T("Desc_AutoForge"),
        Value = State.AutoForge,
        Callback = toggleLoop("AutoForge", "ForgeDelay", function()
            local ok, result = executeForgeNow(State.ForgeType, State.MinOreToForge)
            if not ok and State.Debug then warn("[NAPHUB Forge]:", result) end
        end),
    })

    T6:Slider({
        Title = T("Sld_ForgeDelay"),
        Value = { Min = 0.3, Max = 5.0, Default = State.ForgeDelay },
        Callback = function(v) State.ForgeDelay = v end,
    })

    T6:Button({
        Title = T("Btn_ForgeOnce"),
        Callback = function()
            local ok, slot, count = executeForgeNow(State.ForgeType, State.MinOreToForge)
            local message = ok
                and ((State.Language == "TH" and "หลอม " or "Forged ") .. tostring(slot) .. " / " .. tostring(count) .. (State.Language == "TH" and " แร่" or " ores"))
                or tostring(slot)
            notify(State.Language == "TH" and "โรงหลอม" or "Forge", message, "hammer")
        end,
    })

    T6:Button({
        Title = T("Btn_EquipBest"),
        Callback = function()
            local ok, count = equipBestGearNow("All")
            notify(State.Language == "TH" and "คลังอุปกรณ์" or "Equipment", ok and ((State.Language == "TH" and "สวมใส่แล้ว " or "Equipped ") .. tostring(count) .. (State.Language == "TH" and " ชิ้นที่ดีที่สุด" or " best items")) or (State.Language == "TH" and "ไม่พบอุปกรณ์ที่สวมใส่ได้" or "No gear available"), "check")
        end,
    })

    T6:Section({ Title = T("Sec_Enhance"), Side = "Right" })

    T6:Toggle({
        Title = T("Tgl_EquipBest"),
        Desc  = T("Desc_EquipBest"),
        Value = State.AutoEquipBest,
        Callback = toggleLoop("AutoEquipBest", 3.0, function()
            equipBestGearNow("All")
        end),
    })

    T6:Toggle({
        Title = T("Tgl_AutoEnhance"),
        Desc  = T("Desc_AutoEnhance"),
        Value = State.AutoEnhance,
        Callback = toggleLoop("AutoEnhance", "EnhanceDelay", function()
            call("Backpack", "EnhantEquipmentRF")
        end),
    })

    T6:Toggle({
        Title = T("Tgl_AutoEnchant"),
        Desc  = State.Language == "TH" and "นำหิน Enchant ในกระเป๋ามาสลักใส่อุปกรณ์ที่สวมใส่อยู่อัตโนมัติ" or "Auto apply inventory enchant stones onto equipped gear",
        Value = State.AutoEnchant,
        Callback = toggleLoop("AutoEnchant", "EnchantDelay", autoEnchantEquippedGear),
    })

    T6:Dropdown({
        Title = State.Language == "TH" and "ระดับหินสูงสุดที่ยอมให้ใช้ (Max Grade)" or "Max Stone Grade Allowed",
        Desc  = State.Language == "TH" and "ป้องกันไม่ให้เผลอใช้หินระดับสูงที่ต้องการเก็บไว้" or "Caps the maximum rarity of stones used for auto enchant",
        Values = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Eternal", "All" },
        Value = State.EnchantMaxGrade,
        Callback = function(v) State.EnchantMaxGrade = v end,
    })

    T6:Toggle({
        Title = State.Language == "TH" and "★ เก็บหินเกรดสูงไว้ (Eternal / Secret / Ancient)" or "★ Preserve Top-Tier Stones",
        Desc  = State.Language == "TH" and "ไม่นำหินระดับเทพไปใช้สุ่มสลักอักขระพื้นฐาน" or "Prevents using Eternal, Secret, and Ancient stones automatically",
        Value = State.EnchantKeepHighGrade,
        Callback = function(v) State.EnchantKeepHighGrade = v end,
    })

    T6:Dropdown({
        Title = State.Language == "TH" and "ส่วนอุปกรณ์ที่ต้องการลงอักขระ" or "Target Enchant Gear Slot",
        Values = { "All", "Weapon", "Armor", "Hat" },
        Value = State.EnchantSlots,
        Callback = function(v) State.EnchantSlots = v end,
    })

    T6:Slider({
        Title = State.Language == "TH" and "ความเร็วในการลงอักขระ (วินาที)" or "Enchant Interval (Seconds)",
        Value = { Min = 0.5, Max = 5.0, Default = State.EnchantDelay },
        Callback = function(v) State.EnchantDelay = v end,
    })

    T6:Button({
        Title = T("Btn_UnequipAll"),
        Callback = function()
            call("Backpack", "TryUnEquipItemRE")
            call("Backpack", "UnEnchantRE")
            notify(State.Language == "TH" and "คลังอุปกรณ์" or "Inventory", State.Language == "TH" and "ถอดอุปกรณ์และล้างอักขระเรียบร้อย" or "Unequipped items and stripped enchants", "trash-2")
        end,
    })

    T6:Toggle({
        Title = State.Language == "TH" and "★ Algorithmic DPS & Affix Solver AI (สูตรคณิตศาสตร์)" or "★ Algorithmic DPS & Affix Solver AI",
        Desc  = State.Language == "TH" and "คำนวณ DPS สุทธิตามสูตรจริง (Base * Crit * Speed * Enchant) และสวมใส่ชิ้นเทพ" or "Solves live DPS formula and auto-equips optimal gear & enchants",
        Value = State.AlgorithmicDPSSolver,
        Callback = function(v) State.AlgorithmicDPSSolver = v end,
    })

    T6:Button({
        Title = State.Language == "TH" and "คำนวณและสวมใส่เซ็ตดาเมจสูงสุดทันที (Solve Best DPS)" or "Solve & Equip Best DPS Gear Now",
        Callback = function()
            local ok, count, score = runAlgorithmicGearSolver()
            notify("DPS Solver", State.Language == "TH" and ("คำนวณเสร็จสิ้น! สวมใส่ " .. tostring(count) .. " ชิ้น DPS: " .. tostring(math.floor(score))) or ("Solved & equipped " .. tostring(count) .. " items. DPS: " .. tostring(math.floor(score))), "sparkles")
        end,
    })

    -- ★ ASTRAL SERVER SPAWNER (ported from PAYOMBØYZ)
    T6:Section({ Title = T("Sec_AstralSpawner"), Side = "Right" })
    T6:Button({
        Title = T("Btn_SpawnApocalypse"),
        Desc  = T("Desc_SpawnApocalypse"),
        Callback = function()
            spawnGodSet("Apocalypse")
            notify(
                State.Language == "TH" and "เสกเซ็ตสำเร็จ!" or "Spawned Set!",
                State.Language == "TH" and "เสกและสวมใส่เซ็ต Apocalypse (Chaoseater + War's Horn) เรียบร้อย" or "Spawned & Equipped Apocalypse Set",
                "sword"
            )
        end,
    })
    T6:Button({
        Title = T("Btn_SpawnTriWyrm"),
        Desc  = T("Desc_SpawnTriWyrm"),
        Callback = function()
            spawnGodSet("TriWyrm")
            notify(
                State.Language == "TH" and "เสกเซ็ตสำเร็จ!" or "Spawned Set!",
                State.Language == "TH" and "เสกและสวมใส่เซ็ต The Tri-Wyrm (มังกร 3 หัว) เรียบร้อย" or "Spawned & Equipped Tri-Wyrm Set",
                "sword"
            )
        end,
    })
    T6:Button({
        Title = T("Btn_SpawnCataclysm"),
        Desc  = T("Desc_SpawnCataclysm"),
        Callback = function()
            spawnGodSet("Cataclysm")
            notify(
                State.Language == "TH" and "เสกเซ็ตสำเร็จ!" or "Spawned Set!",
                State.Language == "TH" and "เสกและสวมใส่เซ็ต Cataclysm (หายนะ ครา) เรียบร้อย" or "Spawned & Equipped Cataclysm Set",
                "sword"
            )
        end,
    })
    T6:Button({
        Title = T("Btn_SpawnVoidOverlord"),
        Desc  = T("Desc_SpawnVoidOverlord"),
        Callback = function()
            spawnGodSet("VoidOverlord")
            notify(
                State.Language == "TH" and "เสกเซ็ตสำเร็จ!" or "Spawned Set!",
                State.Language == "TH" and "เสกและสวมใส่เซ็ต Void Overlord (เซ็ตวอยด์สูงสุด) เรียบร้อย" or "Spawned & Equipped Void Overlord Set",
                "sword"
            )
        end,
    })
    T6:Button({
        Title = T("Btn_SpawnApexOres"),
        Desc  = T("Desc_SpawnApexOres"),
        Callback = function()
            spawnApexOresDirect(10)
            notify(
                State.Language == "TH" and "เสกแร่สำเร็จ!" or "Ores Spawned!",
                State.Language == "TH" and "เสกแร่ The Apex (Ore_48) 10 ก้อนเข้ากระเป๋าเรียบร้อย" or "Injected 10 Apex Ores to inventory",
                "gem"
            )
        end,
    })
    T6:Button({
        Title = T("Btn_SpawnRunes"),
        Desc  = T("Desc_SpawnRunes"),
        Callback = function()
            spawnAllRunesDirect()
            notify(
                State.Language == "TH" and "เสกรูนสำเร็จ!" or "Runes Spawned!",
                State.Language == "TH" and "เสกหินรูนทั้งหมดเข้ากระเป๋าเรียบร้อย" or "Injected all Runes to inventory",
                "sparkles"
            )
        end,
    })
    T6:Toggle({
        Title = T("Tgl_SpoofMaterials"),
        Desc  = T("Desc_SpoofMaterials"),
        Value = State.GodSpoofMaterials150Dd,
        Callback = function(v)
            State.GodSpoofMaterials150Dd = v
            apply150DdMaterialSpoof(v)
            if State.AutoSaveConfig then saveConfig() end
        end,
    })

    -- ★ เสก Ember Stone (ย้ายมาจาก 2K)
    T6:Section({ Title = T("Sec_EmberStone"), Desc = T("Desc_EmberSection"), Icon = "flame", Side = "Right" })
    task.defer(function() pcall(applyBackpackVisualEngine) end)
    T6:Button({
        Title = T("Btn_EmberStone"),
        Desc  = T("Desc_EmberStone"),
        Callback = function()
            if not pumpRealEmberStones(5000) then
                notify("NAPHUB", State.Language == "TH" and "กำลังเสกอยู่ หรือไม่พบ Remote ของด่าน" or "Already running or stage remote missing", "flame")
            end
        end,
    })

    -- ★ เสก Race Roll (เพิ่มใหม่ท้ายสุดของเมนูหลอม)
    T6:Button({
        Title = "เสก Race Roll",
        Desc = "เรียก TryClaimUPDRewardRE สำหรับ Reward 4, 5, 6",
        Callback = function()
            getgenv().rayvinz = true
            local Event = game:GetService("ReplicatedStorage"):WaitForChild("Remote"):WaitForChild("UpdateLog_Server"):WaitForChild("TryClaimUPDRewardRE")
            local targetRewards = {"4", "5", "6"}
            task.spawn(function()
                while getgenv().rayvinz do
                    for _, rewardNumber in ipairs(targetRewards) do
                        local randomPrefix = ""
                        local length = math.random(5, 15)
                        for i = 1, length do
                            if math.random(1, 2) == 1 then
                                randomPrefix = randomPrefix .. " "
                            else
                                randomPrefix = randomPrefix .. "\t"
                            end
                        end
                        Event:FireServer(randomPrefix .. rewardNumber)
                    end

                    task.wait(0.1)
                end
            end)
        end,
    })
    if State.GodSpoofMaterials150Dd then task.defer(function() apply150DdMaterialSpoof(true) end) end

    -- ═════════════════════════════════════════════════════════════
    --  TAB 7: Class, Pets & Potions (Gacha & Buffs)
    -- ═════════════════════════════════════════════════════════════
    local T7 = Window:Tab({ Title = T("Tab7"), Icon = "sparkles" })

    T7:Section({ Title = T("Sec_Class"), Side = "Left" })

    T7:Dropdown({
        Title = T("Drop_TargetClass"),
        Desc  = T("Desc_TargetClass"),
        Values = Dynamic.Classes,
        Value = State.TargetClassToLock,
        Callback = function(v) State.TargetClassToLock = v end,
    })

    T7:Toggle({
        Title = T("Tgl_RollClass"),
        Desc  = T("Desc_RollClass"),
        Value = State.AutoRollClass,
        Callback = toggleLoop("AutoRollClass", "RollClassDelay", runClassAndSkillRoll),
    })

    T7:Slider({
        Title = T("Sld_RollClassDelay"),
        Value = { Min = 0.5, Max = 5.0, Default = State.RollClassDelay },
        Callback = function(v) State.RollClassDelay = v end,
    })

    T7:Toggle({
        Title = T("Tgl_RollSkills"),
        Desc  = T("Desc_RollSkills"),
        Value = State.AutoRollSkills,
        Callback = toggleLoop("AutoRollSkills", "RollSkillDelay", runClassAndSkillRoll),
    })

    T7:Section({ Title = T("Sec_Pets"), Side = "Right" })

    T7:Toggle({
        Title = T("Tgl_AutoPotions"),
        Desc  = T("Desc_AutoPotions"),
        Value = State.AutoUsePotions,
        Callback = toggleLoop("AutoUsePotions", "PotionDelay", runPotionAndHatch),
    })

    T7:Toggle({
        Title = T("Tgl_AutoHatch"),
        Desc  = T("Desc_AutoHatch"),
        Value = State.AutoHatchEggs,
        Callback = toggleLoop("AutoHatchEggs", "HatchEggDelay", runPotionAndHatch),
    })

    -- ═════════════════════════════════════════════════════════════
    --  TAB 8: Rewards & Promo Codes
    -- ═════════════════════════════════════════════════════════════
    local T8 = Window:Tab({ Title = T("Tab8"), Icon = "gift" })

    T8:Section({ Title = T("Sec_Rewards"), Side = "Left" })

    T8:Toggle({
        Title = T("Tgl_AutoClaim"),
        Desc  = T("Desc_AutoClaim"),
        Value = State.AutoClaimRewards,
        Callback = toggleLoop("AutoClaimRewards", "ClaimDelay", claimAllRewards),
    })

    T8:Slider({
        Title = T("Sld_ClaimDelay"),
        Value = { Min = 10, Max = 300, Default = State.ClaimDelay },
        Callback = function(v) State.ClaimDelay = v end,
    })

    T8:Button({
        Title = T("Btn_ClaimAllNow"),
        Callback = function()
            task.spawn(claimAllRewards)
            notify(State.Language == "TH" and "ของรางวัล" or "Rewards", State.Language == "TH" and "ส่งคำสั่งกดรับรางวัลทุกประเภทเรียบร้อย" or "Dispatched claim requests for all categories", "gift")
        end,
    })

    T8:Section({ Title = T("Sec_Codes"), Side = "Right" })

    T8:Button({
        Title = State.Language == "TH" and "ดึงโค้ดล่าสุดจากออนไลน์ & กดรับทั้งหมด" or "Fetch & Redeem Latest Codes (Online)",
        Callback = function()
            task.spawn(function() NH.redeemAllOnlineCodes(false) end)
        end,
    })


    local codeInput = ""
    T8:Input({
        Title = State.Language == "TH" and "กรอกโค้ดรับไอเทม" or "Redeem Promo Code",
        Placeholder = T("Input_Code"),
        Callback = function(t) codeInput = t end,
    })

    T8:Button({
        Title = T("Btn_SubmitCode"),
        Callback = function()
            if codeInput == "" then return notify("Codes", State.Language == "TH" and "กรุณากรอกรหัสโค้ดก่อนกดยืนยัน" or "Input code cannot be empty", "alert-triangle") end
            local res = call("Code", "TryUseCodeRF", codeInput)
            notify("Codes", "Server response: " .. tostring(res), "ticket")
        end,
    })

    local knownCodes = { "RELEASE", "LOOT", "FORGE", "ENHANCE", "UPDATE1", "FREEGEMS", "LIKE1000" }
    T8:Button({
        Title = T("Btn_BatchCodes"),
        Callback = function()
            task.spawn(function()
                for _, c in ipairs(knownCodes) do
                    call("Code", "TryUseCodeRF", c)
                    task.wait(0.2)
                end
                notify("Codes", State.Language == "TH" and "กดรับโค้ดแจกฟรียอดนิยมทั้งหมดแล้ว" or "Dispatched batch redemption requests", "check-circle")
            end)
        end,
    })

    -- ═════════════════════════════════════════════════════════════
    --  TAB 9: Teleports & Navigation
    -- ═════════════════════════════════════════════════════════════
    local T9 = Window:Tab({ Title = T("Tab9"), Icon = "map-pin" })

    T9:Section({ Title = T("Sec_Locations"), Side = "Left" })

    T9:Button({
        Title = T("Btn_TpSafeZone"),
        Callback = function()
            tpTo(getSafeZoneCF())
            notify("Waypoint", State.Language == "TH" and "เดินทางถึงโซนปลอดภัยเรียบร้อย" or "Arrived at Safe Zone", "shield")
        end,
    })

    T9:Button({
        Title = T("Btn_TpTrainMap"),
        Callback = function()
            local tm = workspace:FindFirstChild("WorldModel") and workspace.WorldModel:FindFirstChild("TrainMap")
            if tm then
                tpTo(tm:GetPivot())
                notify("Waypoint", State.Language == "TH" and "เดินทางถึงพื้นที่ฝึกพลังเรียบร้อย" or "Arrived at Train Map", "map-pin")
            else
                notify("Waypoint", State.Language == "TH" and "ไม่พบพื้นที่ฝึกพลัง" or "Train Map model not found", "alert-triangle")
            end
        end,
    })

    T9:Button({
        Title = T("Btn_TpDungeon"),
        Callback = function()
            local dm = workspace:FindFirstChild("WorldModel") and workspace.WorldModel:FindFirstChild("DungeonMap")
            local sp = dm and dm:FindFirstChild("StartPoint")
            if sp then
                tpTo(sp.CFrame)
                notify("Waypoint", State.Language == "TH" and "เดินทางถึงหน้าดันเจี้ยนเรียบร้อย" or "Arrived at Dungeon Entrance", "map-pin")
            else
                notify("Waypoint", State.Language == "TH" and "ไม่พบทางเข้าดันเจี้ยน" or "Dungeon Entrance not found", "alert-triangle")
            end
        end,
    })

    local savedPosition = nil
    T9:Button({
        Title = T("Btn_SavePos"),
        Callback = function()
            local r = hrp()
            if r then
                savedPosition = r.CFrame
                notify("Waypoint", State.Language == "TH" and "บันทึกพิกัดตำแหน่งปัจจุบันแล้ว" or "Coordinates saved", "check")
            end
        end,
    })

    T9:Button({
        Title = T("Btn_LoadPos"),
        Callback = function()
            if savedPosition then
                tpTo(savedPosition)
                notify("Waypoint", State.Language == "TH" and "วาร์ปกลับสู่ตำแหน่งที่บันทึกไว้แล้ว" or "Returned to saved coordinates", "map-pin")
            else
                notify("Waypoint", State.Language == "TH" and "ยังไม่มีการบันทึกพิกัดตำแหน่ง" or "No saved coordinates found", "alert-triangle")
            end
        end,
    })

    T9:Section({ Title = T("Sec_Server"), Side = "Right" })

    T9:Button({
        Title = T("Btn_Rejoin"),
        Callback = function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end,
    })

    T9:Button({
        Title = T("Btn_ServerHop"),
        Callback = function()
            local ok, data = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(
                    ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
                ))
            end)
            if ok and data and data.data then
                for _, s in ipairs(data.data) do
                    if s.id ~= game.JobId and s.playing < s.maxPlayers then
                        notify("Server Hop", State.Language == "TH" and "กำลังเชื่อมต่อเข้าเซิร์ฟเวอร์ใหม่..." or "Connecting to new server instance...", "server")
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                        return
                    end
                end
            end
            notify("Server Hop", State.Language == "TH" and "ไม่พบเซิร์ฟเวอร์อื่นที่เหมาะสม" or "No alternative server found", "alert-triangle")
        end,
    })

    T9:Button({
        Title = T("Btn_CopyJobId"),
        Desc  = tostring(game.JobId),
        Callback = function()
            if setclipboard then
                setclipboard(game.JobId)
                notify("JobId", State.Language == "TH" and "คัดลอกรหัสเซิร์ฟเวอร์ลงคลิปบอร์ดแล้ว" or "Copied JobId to clipboard", "copy")
            end
        end,
    })

    -- ═════════════════════════════════════════════════════════════
    --  TAB 10: Webhook & Settings (Profile & Performance)
    -- ═════════════════════════════════════════════════════════════
    local T10 = Window:Tab({ Title = T("Tab10"), Icon = "settings" })

    T10:Section({ Title = T("Sec_Interface"), Side = "Left" })

    T10:Dropdown({
        Title = T("Drop_Language"),
        Desc  = T("Desc_Language"),
        Values = { "ไทย (Thai)", "English (EN)" },
        Value = (State.Language == "EN" and "English (EN)" or "ไทย (Thai)"),
        Callback = function(v)
            local newLang = (v:find("English") or v:find("EN")) and "EN" or "TH"
            if State.Language ~= newLang then
                State.Language = newLang
                if State.AutoSaveConfig then saveConfig() end
                notify(
                    newLang == "TH" and "เปลี่ยนภาษา" or "Language",
                    newLang == "TH" and "เปลี่ยนภาษาเป็น ภาษาไทย เรียบร้อยแล้ว" or "Language switched to English",
                    "globe"
                )
                task.delay(0.2, function()
                    BuildUI()
                end)
            end
        end,
    })

    T10:Dropdown({
        Title = T("Drop_Theme"),
        Desc = State.Language == "TH" and "เปลี่ยนสีหลักของเมนู NAPHUB" or "Change the NAPHUB accent color",
        Values = NapUI.ThemeNames,
        Value = NapUI.Theme,
        Callback = function(themeName) Window:SetTheme(themeName) end,
    })

    T10:Toggle({
        Title = T("Tgl_Transparency"),
        Value = false,
        Callback = function(v) pcall(function() Window:ToggleTransparency(v) end) end,
    })

    T10:Section({ Title = T("Sec_Webhook"), Side = "Right" })

    T10:Toggle({
        Title = T("Tgl_Webhook"),
        Value = State.WebhookEnabled,
        Callback = function(v) State.WebhookEnabled = v end,
    })

    T10:Input({
        Title = State.Language == "TH" and "ลิงก์ Discord Webhook URL" or "Discord Webhook URL",
        Placeholder = T("Input_Webhook"),
        Callback = function(t)
            State.WebhookUrl = t
            if State.AutoSaveConfig then saveConfig() end
        end,
    })

    T10:Toggle({
        Title = T("Tgl_NotifyRare"),
        Value = State.NotifyRareDrops,
        Callback = function(v) State.NotifyRareDrops = v end,
    })

    T10:Toggle({
        Title = T("Tgl_NotifyHourly"),
        Value = State.NotifyHourlyReport,
        Callback = function(v) State.NotifyHourlyReport = v end,
    })

    T10:Toggle({
        Title = T("Tgl_NotifyRebirth"),
        Value = State.NotifyRebirth,
        Callback = function(v) State.NotifyRebirth = v end,
    })

    T10:Button({
        Title = T("Btn_TestWebhook"),
        Callback = function()
            if not State.WebhookUrl or State.WebhookUrl == "" then
                return notify("Webhook", State.Language == "TH" and "ยังไม่ได้ตั้งค่า Webhook URL" or "Webhook URL not configured", "alert-triangle")
            end
            local isTH = State.Language == "TH"
            sendWebhook(
                isTH and "ทดสอบการส่งข้อความ Webhook" or "NAPHUB Webhook Test",
                isTH and "เชื่อมต่อระบบส่งข้อมูลสำเร็จพร้อมทำงานตลอด 24 ชั่วโมง" or "Communication link established successfully.",
                {
                    { name = isTH and "ชื่อผู้เล่น" or "Player", value = LocalPlayer.Name, inline = true },
                { name = isTH and "เวอร์ชันระบบ" or "Engine", value = "v4.9.2", inline = true },
                },
                0x10B981
            )
            notify("Webhook", State.Language == "TH" and "ส่งข้อความทดสอบไปยัง Discord เรียบร้อย" or "Dispatched test payload", "send")
        end,
    })

    T10:Section({ Title = T("Sec_Player"), Side = "Right" })

    T10:Slider({
        Title = T("Sld_WalkSpeed"),
        Value = { Min = 16, Max = 250, Default = State.WalkSpeed },
        Callback = function(v)
            State.WalkSpeed = v
            local h = hum()
            if h then h.WalkSpeed = v end
        end,
    })

    T10:Slider({
        Title = T("Sld_JumpPower"),
        Value = { Min = 50, Max = 300, Default = State.JumpPower },
        Callback = function(v)
            State.JumpPower = v
            local h = hum()
            if h then
                h.UseJumpPower = true
                h.JumpPower = v
            end
        end,
    })

    T10:Toggle({ Title = T("Tgl_InfJump"), Value = State.InfJump, Callback = function(v) State.InfJump = v end })
    T10:Toggle({ Title = T("Tgl_Noclip"), Value = State.Noclip, Callback = function(v) State.Noclip = v end })
    T10:Toggle({ Title = T("Tgl_AntiAFK"), Value = State.AntiAFK, Callback = function(v) State.AntiAFK = v end })

    T10:Section({ Title = T("Sec_Optimize"), Side = "Right" })

    T10:Toggle({
        Title = T("Tgl_CpuSaver"),
        Value = State.CpuSaver,
        Callback = function(v)
            State.CpuSaver = v
            pcall(function()
                RunService:Set3dRenderingEnabled(not v)
                if setfpscap then setfpscap(v and 15 or 60) end
            end)
            notify(
                State.Language == "TH" and "ระบบประหยัดพลังงาน" or "Optimizer",
                v and (State.Language == "TH" and "ปิดการแสดงภาพ 3D (จำกัด 15 FPS เรียบร้อย)" or "3D Rendering disabled (15 FPS mode active)") or (State.Language == "TH" and "เปิดการแสดงภาพ 3D ปกติแล้ว" or "3D Rendering restored"),
                "zap"
            )
        end,
    })

    T10:Section({ Title = T("Sec_Config"), Side = "Left" })

    T10:Button({
        Title = T("Btn_SaveConfig"),
        Callback = function()
            saveConfig()
            notify("Config", T("Notif_ConfigSaved"), "save")
        end,
    })

    T10:Button({
        Title = T("Btn_LoadConfig"),
        Callback = function()
            if loadConfig() then
                notify("Config", T("Notif_ConfigLoaded"), "folder")
                task.delay(0.2, function() BuildUI() end)
            else
                notify("Config", State.Language == "TH" and "ไม่พบไฟล์บันทึกการตั้งค่า" or "Configuration file not found or corrupted", "alert-triangle")
            end
        end,
    })

    T10:Toggle({
        Title = T("Tgl_AutoSave"),
        Value = State.AutoSaveConfig,
        Callback = function(v) State.AutoSaveConfig = v end,
    })

    T10:Button({
        Title = T("Btn_DestroyUI"),
        Callback = function()
            for k, v in pairs(State) do
                if type(v) == "boolean" then State[k] = false end
            end
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
            Window:Destroy()
        end,
    })

    T1:Section({ Title = State.Language == "TH" and "ทางลัด" or "Quick Actions" })
    T1:Button({
        Title = State.Language == "TH" and "เก็บแร่ฉุกเฉิน" or "Emergency Loot Run",
        Desc = State.Language == "TH" and "เก็บแร่ กลับ Safe Zone และขายของในกระเป๋า" or "Collect ores, return to the Safe Zone, and sell the backpack",
        Callback = function()
            call("Stage", "ClaimedAllOreRE")
            tpTo(getSafeZoneCF())
            call("Backpack", "TrySellAllRE")
            Stats.SellCycles = Stats.SellCycles + 1
            notify("NAPHUB", T("Notif_SafeZoneSecured"), "shield")
        end,
    })
    Window:SelectTab(1)
end

-- ─────────────────────────────────────────────────────────────
-- Event Listeners & Hardware Simulation
-- ─────────────────────────────────────────────────────────────
LocalPlayer.CharacterAdded:Connect(function(c)
    local h = c:WaitForChild("Humanoid", 8)
    if h then
        h.WalkSpeed = State.WalkSpeed
        h.UseJumpPower = true
        h.JumpPower = State.JumpPower
    end
    if State.GodMode then
        task.wait(0.5)
        maintainGodMode()
    end
end)

UserInputService.JumpRequest:Connect(function()
    if State.InfJump then
        local h = hum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

RunService.Stepped:Connect(function()
    if State.Noclip and char() then
        for _, p in ipairs(char():GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end
    if State.GodMode then
        maintainGodMode()
    end
end)

LocalPlayer.Idled:Connect(function()
    if State.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

pcall(function()
    GuiService.ErrorMessageChanged:Connect(function()
        if State.Master247 or State.AutoDungeon or State.AutoStage then
            task.wait(3)
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end)
end)

-- ─────────────────────────────────────────────────────────────
-- Background Worker Threads
-- ─────────────────────────────────────────────────────────────
-- ★ MASTER ENGINE LOOP — tighter tick (0.15 s) for responsive farm loop
task.spawn(function()
    while true do
        if State.Master247 then
            pcall(runMaster247Engine)
        end
        task.wait(0.15)
    end
end)

-- Standalone dungeon/stage loops (when enabled independently without Master)
task.spawn(function()
    while true do
        if not State.Master247 then
            if State.AutoDungeon then pcall(runDungeonLoop) end
            if State.GodFarmStageBlitz then
                pcall(runStageBlitz)
            elseif State.AutoStage then
                pcall(runStageLoop)
            end
        end
        task.wait(0.5)
    end
end)

-- ★ Sword Power Auto-Clicker Background Thread
task.spawn(function()
    while true do
        if State.AutoClickSword or (State.Master247 and State.MasterAutoClickSword) then
            pcall(runSwordClickFarm)
        end
        task.wait(State.SwordClickDelay or 0.16)
    end
end)

-- ★ Feature A: Remote-Only Train Farm — ยิง TrainOnceRE ตรงๆ ทุก TrainDelay วิ ไม่ต้องวาร์ปเลย
task.spawn(function()
    while true do
        local delay = tonumber(State.TrainDelay) or 0.15
        if State.RemoteOnlyTrain then
            local inFight = LocalPlayer:GetAttribute("IntoFight")
            local inDung  = LocalPlayer:GetAttribute("Dungeoning")
            if not inFight and not inDung then
                pcall(function()
                    if State.ForceVIPTrain then
                        LocalPlayer:SetAttribute("AutoTrainAreaID", 9)
                        call("Train", "IntoAutoTrainRE", 9)
                    end
                    local tc = TrainCTRL or (ReplicatedStorage:FindFirstChild("CTRL") and require(ReplicatedStorage.CTRL.TrainCTRL))
                    if tc and type(tc.TrainOnce) == "function" then
                        tc.TrainOnce()
                    else
                        call("Train", "TrainOnceRE")
                    end
                end)
            end
        end
        task.wait(delay)
    end
end)

-- ★ Feature B: Force VIP Zone 9 (x100) Packet Maintainer
-- Silently re-injects AutoTrainAreaID = 9 if server clears it, without physical TP
task.spawn(function()
    while true do
        if State.ForceVIPTrain then
            local inFight = LocalPlayer:GetAttribute("IntoFight")
            local inDung  = LocalPlayer:GetAttribute("Dungeoning")
            if not inFight and not inDung then
                local currentZoneId = LocalPlayer:GetAttribute("AutoTrainAreaID")
                if currentZoneId ~= 9 then
                    pcall(function()
                        LocalPlayer:SetAttribute("AutoTrainAreaID", 9)
                        call("Train", "IntoAutoTrainRE", 9)
                        local tc = TrainCTRL or (ReplicatedStorage:FindFirstChild("CTRL") and require(ReplicatedStorage.CTRL.TrainCTRL))
                        if tc then
                            if tc.StartAutoTrain and not (tc.GetIsAutoing and tc.GetIsAutoing()) then
                                tc.StartAutoTrain()
                            end
                        end
                    end)
                end
            end
        end
        task.wait(3.0)
    end
end)

-- ─────────────────────────────────────────────────────────────
-- Live Dashboard: ข้อมูลจริงจากตัวเกม
-- ─────────────────────────────────────────────────────────────
local Live = { RealKills = 0, RealSuper = 0, OresGained = 0, LastOres = nil, StartRebirth = nil, Watched = {} }

local function getEcoStats()
    local rebirth, stagePass = nil, nil
    pcall(function()
        local pd = ProfileData and ProfileData.GetTotalData and ProfileData.GetTotalData()
        rebirth = pd and pd.Eco and tonumber(pd.Eco.rebirth)
        stagePass = pd and pd.Stats and tonumber(pd.Stats.StagePass)
    end)
    return rebirth, stagePass
end

local function getOreInventoryTotal()
    local items = getBackpackItems()
    if not items then return nil end
    local total = 0
    for _, it in pairs(items) do
        if type(it) == "table" and it.Type == "Ore" then
            total = total + (tonumber(it.Number) or 1)
        end
    end
    return total
end

local function getDungeonTickets()
    local n = nil
    pcall(function()
        local t = BackpackData and BackpackData.GetItemDataByIDType and BackpackData.GetItemDataByIDType("Dungeon_Ticket", "Material")
        n = t and tonumber(t.Number) or 0
    end)
    return n
end

-- นับมอนสเตอร์/บอสที่ "หายไปจากแมพจริง" (ถูกกำจัด) แทนการนับจำนวนครั้งที่ยิงคำสั่ง
local function watchFolder(name, onRemoved)
    local f = workspace:FindFirstChild(name)
    if f and Live.Watched[name] ~= f then
        Live.Watched[name] = f
        f.ChildRemoved:Connect(onRemoved)
    end
end

local function isAnyAutomationOn()
    return State.Master247 or State.AutoDungeon or State.AutoStage or State.GodFarmStageBlitz
        or State.AutoTrain or State.AutoTrainBestZone or State.AutoTrainMode or State.AutoClickSword
        or State.RemoteOnlyTrain or State.ForceVIPTrain
        or State.SuperLootHunter or State.AutoRollClass or State.AutoForge or State.KillAura
end

task.spawn(function()
    while true do
        pcall(function()
            local elapsed = os.time() - Stats.StartTime
            local h = math.floor(elapsed / 3600)
            local m = math.floor((elapsed % 3600) / 60)
            local s = elapsed % 60
            local timeStr = ("%02d:%02d:%02d"):format(h, m, s)

            local curBag, maxBag = getPackInfo()
            local hPart = hum()
            local curHp = hPart and math.floor(hPart.Health) or 100
            local maxHp = hPart and math.floor(hPart.MaxHealth) or 100
            local isTH = State.Language == "TH"

            -- เฝ้าดูโฟลเดอร์มอนสเตอร์/บอส (ต่อใหม่อัตโนมัติถ้าเกมสร้างโฟลเดอร์ใหม่)
            watchFolder("EnemyFolder", function(c) if c:IsA("Model") then Live.RealKills = Live.RealKills + 1 end end)
            watchFolder("SuperLootFolder", function() Live.RealSuper = Live.RealSuper + 1 end)

            -- แร่: จำนวนในกระเป๋าจริง + แร่ที่ได้เพิ่มรอบนี้ (นับจากส่วนต่างที่เพิ่มขึ้นจริง)
            local oreNow = getOreInventoryTotal()
            if oreNow then
                if Live.LastOres and oreNow > Live.LastOres then
                    Live.OresGained = Live.OresGained + (oreNow - Live.LastOres)
                end
                Live.LastOres = oreNow
            end

            -- เกิดใหม่: ค่าจริงจากข้อมูลผู้เล่น
            local rebNow, stagePass = getEcoStats()
            if rebNow and not Live.StartRebirth then Live.StartRebirth = rebNow end
            local rebGained = (rebNow and Live.StartRebirth) and math.max(rebNow - Live.StartRebirth, 0) or 0

            -- ซิงก์กลับเข้า Stats เพื่อให้รายงาน Webhook ใช้ค่าจริงเดียวกัน
            Stats.OresCollected  = Live.OresGained
            Stats.Kills          = Live.RealKills
            Stats.SuperLootKills = Live.RealSuper
            Stats.RebirthCount   = rebGained

            local orePerHour = elapsed > 0 and math.floor(Live.OresGained / elapsed * 3600) or 0
            local tickets = getDungeonTickets()
            local inDungeon = LocalPlayer:GetAttribute("Dungeoning")

            if StatusCard then
                local actText = Stats.CurrentActivity
                if Locales[State.Language] and Locales[State.Language][actText] then
                    actText = Locales[State.Language][actText]
                elseif Locales.TH[actText] then
                    actText = Locales.TH[actText]
                end
                if not isAnyAutomationOn() then
                    actText = isTH and "ยังไม่ได้เปิดระบบอัตโนมัติ" or "No automation enabled"
                elseif inDungeon then
                    actText = T("StatusDungeonWave")
                end
                local lines = {}
                lines[#lines + 1] = (isTH and "สถานะ: " or "Status: ") .. tostring(actText)
                lines[#lines + 1] = (isTH and "ระบบไก่ตัน: " or "Master AI: ") .. (State.Master247 and (isTH and "เปิด" or "ON") or (isTH and "ปิด" or "OFF"))
                lines[#lines + 1] = (isTH and "ตำแหน่ง: " or "Location: ") .. (inDungeon and (isTH and "ในดันเจี้ยน" or "In Dungeon") or (LocalPlayer:GetAttribute("IntoFight") and (isTH and "กำลังต่อสู้ในด่าน" or "In Stage Fight") or (isTH and "แมพหลัก" or "Main Map")))
                StatusCard:SetDesc(table.concat(lines, "\n"))
            end

            if StatsCard then
                local oreLine = oreNow and tostring(oreNow) or "-"
                if isTH then
                    StatsCard:SetDesc(
                        ("เวลาที่เปิดบอท: %s\nแร่ในกระเป๋าตอนนี้: %s\nแร่ที่ได้เพิ่มรอบนี้: %d (%d/ชม.)\nรอบที่ขายของ: %d\nมอนสเตอร์ที่กำจัด: %d\nเกิดใหม่: %s (+%d รอบนี้)\nด่านที่ผ่านสูงสุด: %s\nตั๋วดันเจี้ยน: %s\nบอสยักษ์ที่จัดการ: %d")
                        :format(timeStr, oreLine, Live.OresGained, orePerHour, Stats.SellCycles, Live.RealKills,
                            rebNow and tostring(rebNow) or "-", rebGained, stagePass and tostring(stagePass) or "-",
                            tickets and tostring(tickets) or "-", Live.RealSuper)
                    )
                else
                    StatsCard:SetDesc(
                        ("Elapsed Time: %s\nOres in Bag: %s\nOres Gained: %d (%d/hr)\nSales Executed: %d\nMonsters Defeated: %d\nRebirths: %s (+%d this session)\nBest Stage Cleared: %s\nDungeon Tickets: %s\nSuper Loot Defeated: %d")
                        :format(timeStr, oreLine, Live.OresGained, orePerHour, Stats.SellCycles, Live.RealKills,
                            rebNow and tostring(rebNow) or "-", rebGained, stagePass and tostring(stagePass) or "-",
                            tickets and tostring(tickets) or "-", Live.RealSuper)
                    )
                end
            end

            if BagCard then
                local bagPct = math.floor((curBag / math.max(maxBag, 1)) * 100)
                local hpPct = math.floor((curHp / math.max(maxHp, 1)) * 100)
                if isTH then
                    BagCard:SetDesc(("ความจุสัมภาระ: %d / %d (%d%%)\nพลังชีวิต: %d / %d (%d%%)"):format(curBag, maxBag, bagPct, curHp, maxHp, hpPct))
                else
                    BagCard:SetDesc(("Backpack: %d / %d (%d%%)\nHealth: %d / %d (%d%%)"):format(curBag, maxBag, bagPct, curHp, maxHp, hpPct))
                end
            end

            -- Hourly Webhook Telemetry
            if State.WebhookEnabled and State.NotifyHourlyReport and (os.time() - Stats.LastHourlyPost >= 3600) then
                Stats.LastHourlyPost = os.time()
                sendWebhook(
                    isTH and "รายงานสถิติระบบไก่ตัน (รายชั่วโมง)" or "Hourly ระบบไก่ตัน Telemetry",
                    isTH and "สรุปผลการทำงานของระบบฟาร์มอัตโนมัติ" or "Status report for active farming session.",
                    {
                        { name = isTH and "เวลาที่เปิดทำงาน" or "Elapsed Time", value = timeStr, inline = true },
                        { name = isTH and "แร่ที่เก็บได้" or "Ores Collected", value = tostring(Stats.OresCollected), inline = true },
                        { name = isTH and "มอนสเตอร์ที่กำจัด" or "Monsters Defeated", value = tostring(Stats.Kills), inline = true },
                        { name = isTH and "รอบการขาย" or "Sales Executed", value = tostring(Stats.SellCycles), inline = true },
                        { name = isTH and "บอสยักษ์ที่จัดการ" or "Super Loot Defeated", value = tostring(Stats.SuperLootKills), inline = true },
                        { name = isTH and "จำนวนเกิดใหม่" or "Rebirths", value = tostring(Stats.RebirthCount), inline = true },
                        { name = isTH and "สถานะปัจจุบัน" or "Current Activity", value = tostring(Stats.CurrentActivity), inline = false },
                    },
                    0xFF2442
                )
            end
        end)
        task.wait(1)
    end
end)

-- ─────────────────────────────────────────────────────────────
-- Launch
-- ─────────────────────────────────────────────────────────────
NAPHUB_DEBUG("building UI...")
local NAPHUB_BuildDone = false
task.delay(25, function() if not NAPHUB_BuildDone then NAPHUB_DEBUG("STUCK: BuildUI still running after 25s", true) end end)
local buildOk, buildErr = xpcall(BuildUI, function(e) return tostring(e) .. " | " .. debug.traceback() end)
NAPHUB_BuildDone = true
if not buildOk then
    warn("[NAPHUB] UI build error:", tostring(buildErr))
    NAPHUB_DEBUG("UI ERROR: " .. tostring(buildErr), true)
else
    NAPHUB_DEBUG("UI built OK")
end
notify(
    "NAPHUB +1 LOOT A FORGE",
    State.Language == "TH" and "ระบบพร้อมแล้ว กด RightShift เพื่อซ่อนหรือเปิดหน้าต่าง UI" or "Interface ready. Press RightShift to toggle the window",
    "sparkles"
)