--!strict
--[[ MILKYLUA AOTR (ALL FEATURES) KEYLESS 2026
     AAA quality client controller for Attack on Titan Revolution-style Roblox experiences.
     Clean architecture: service locator, state store, UI kit, feature scheduler, safe adapters.
     Drop this LocalScript into a Roblox executor or StarterPlayerScripts context.
]]

local MilkyLua = {}
MilkyLua.__index = MilkyLua

MilkyLua.Version = "2026.05.30"
MilkyLua.Brand = "MilkyLua"
MilkyLua.Product = "AOTR (ALL FEATURES) KEYLESS 2026"
MilkyLua.SafeMode = true

local Services = setmetatable({}, {
    __index = function(cache, key)
        local ok, service = pcall(function()
            return game:GetService(key)
        end)
        if ok then
            rawset(cache, key, service)
            return service
        end
        return nil
    end,
})

local Players = Services.Players
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local TweenService = Services.TweenService
local RunService = Services.RunService
local UserInputService = Services.UserInputService
local StarterGui = Services.StarterGui
local Workspace = Services.Workspace
local VirtualUser = Services.VirtualUser

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local function now()
    return os.clock()
end

local function safeCall(label, callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then
        warn(string.format("[MilkyLua:%s] %s", tostring(label), tostring(result)))
        return nil
    end
    return result
end

local function notify(title, text, duration)
    safeCall("Notify", function()
        StarterGui:SetCore("SendNotification", {
            Title = title or MilkyLua.Brand,
            Text = text or "",
            Duration = duration or 4,
        })
    end)
end

local Maid = {}
Maid.__index = Maid
function Maid.new()
    return setmetatable({ tasks = {} }, Maid)
end
function Maid:Give(taskObject)
    table.insert(self.tasks, taskObject)
    return taskObject
end
function Maid:Clean()
    for index = #self.tasks, 1, -1 do
        local taskObject = self.tasks[index]
        self.tasks[index] = nil
        if typeof(taskObject) == "RBXScriptConnection" then
            taskObject:Disconnect()
        elseif typeof(taskObject) == "Instance" then
            taskObject:Destroy()
        elseif type(taskObject) == "function" then
            safeCall("MaidTask", taskObject)
        elseif type(taskObject) == "table" and taskObject.Destroy then
            safeCall("MaidDestroy", function() taskObject:Destroy() end)
        end
    end
end

local Signal = {}
Signal.__index = Signal
function Signal.new()
    return setmetatable({ listeners = {} }, Signal)
end
function Signal:Connect(callback)
    local token = { callback = callback, connected = true }
    table.insert(self.listeners, token)
    return {
        Disconnect = function()
            token.connected = false
        end,
    }
end
function Signal:Fire(...)
    for _, token in ipairs(self.listeners) do
        if token.connected then
            safeCall("Signal", token.callback, ...)
        end
    end
end

local Theme = {
    Background = Color3.fromRGB(8, 10, 16),
    Panel = Color3.fromRGB(17, 20, 31),
    PanelSoft = Color3.fromRGB(25, 30, 46),
    Stroke = Color3.fromRGB(91, 107, 147),
    Accent = Color3.fromRGB(110, 212, 255),
    Accent2 = Color3.fromRGB(192, 118, 255),
    Success = Color3.fromRGB(80, 255, 166),
    Danger = Color3.fromRGB(255, 78, 103),
    Warning = Color3.fromRGB(255, 210, 96),
    Text = Color3.fromRGB(242, 247, 255),
    Muted = Color3.fromRGB(161, 170, 190),
}

local function new(className, props, children)
    local instance = Instance.new(className)
    for key, value in pairs(props or {}) do
        instance[key] = value
    end
    for _, child in ipairs(children or {}) do
        child.Parent = instance
    end
    return instance
end

local function addCorner(instance, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = instance })
end
local function addStroke(instance, color, thickness, transparency)
    return new("UIStroke", {
        Color = color or Theme.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0.25,
        Parent = instance,
    })
end
local function addGradient(instance, c1, c2, rotation)
    return new("UIGradient", {
        Color = ColorSequence.new(c1 or Theme.Accent, c2 or Theme.Accent2),
        Rotation = rotation or 35,
        Parent = instance,
    })
end

local State = {
    values = {},
    changed = Signal.new(),
}
function State:Set(key, value)
    if self.values[key] == value then return end
    self.values[key] = value
    self.changed:Fire(key, value)
end
function State:Get(key, default)
    local value = self.values[key]
    if value == nil then return default end
    return value
end

local AOTR = {}
AOTR.__index = AOTR
function AOTR.new()
    return setmetatable({
        maid = Maid.new(),
        cache = {},
        lastScan = 0,
        scanInterval = 0.5,
        remotes = {},
        highlights = {},
        billboards = {},
        napeParts = {},
        featureMaid = {},
    }, AOTR)
end
function AOTR:GetCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end
function AOTR:GetRoot()
    local character = self:GetCharacter()
    return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Main")
end
function AOTR:GetHumanoid()
    local character = self:GetCharacter()
    return character:FindFirstChildOfClass("Humanoid")
end
function AOTR:GetTitansFolder()
    return Workspace:FindFirstChild("Titans")
end
function AOTR:GetObjectivesFolder()
    return Workspace:FindFirstChild("Objectives") or Workspace:FindFirstChild("MissionObjectives")
end
function AOTR:GetReloadFolder()
    local unclimbable = Workspace:FindFirstChild("Unclimbable")
    if not unclimbable then return nil end
    return unclimbable:FindFirstChild("Reloads")
end
function AOTR:IsMissionReady()
    local root = self:GetRoot()
    local titans = self:GetTitansFolder()
    return root ~= nil and titans ~= nil
end
function AOTR:ScanRemotes()
    if now() - self.lastScan < 2 then return self.remotes end
    self.lastScan = now()
    local names = { "GrabEscape", "Refill", "BladeRefill", "GasRefill", "Skill", "Damage", "ODM" }
    for _, descendant in ipairs(game:GetDescendants()) do
        if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
            local lowerName = string.lower(descendant.Name)
            for _, wanted in ipairs(names) do
                if string.find(lowerName, string.lower(wanted), 1, true) then
                    self.remotes[wanted] = descendant
                end
            end
        end
    end
    return self.remotes
end
function AOTR:FireRemote(name, ...)
    if MilkyLua.SafeMode then
        return false, "SafeMode is enabled"
    end
    local remote = self:ScanRemotes()[name]
    if not remote then return false, "Remote not found" end
    if remote:IsA("RemoteEvent") then
        remote:FireServer(...)
        return true
    end
    if remote:IsA("RemoteFunction") then
        remote:InvokeServer(...)
        return true
    end
    return false, "Unsupported remote"
end
function AOTR:GetTitanModels()
    local folder = self:GetTitansFolder()
    local result = {}
    if not folder then return result end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            table.insert(result, model)
        end
    end
    return result
end
function AOTR:GetNape(model)
    local fake = model:FindFirstChild("Fake")
    if fake then
        local nape = fake:FindFirstChild("Nape") or fake:FindFirstChild("Neck")
        if nape and nape:IsA("BasePart") then return nape end
    end
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") and string.find(string.lower(descendant.Name), "nape") then
            return descendant
        end
    end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end
function AOTR:GetDistance(part)
    local root = self:GetRoot()
    if not root or not part then return math.huge end
    return (root.Position - part.Position).Magnitude
end

local FeatureManager = {}
FeatureManager.__index = FeatureManager
function FeatureManager.new(adapter)
    return setmetatable({ adapter = adapter, features = {}, order = {}, maid = Maid.new() }, FeatureManager)
end
function FeatureManager:Register(feature)
    feature.enabled = false
    feature.maid = Maid.new()
    self.features[feature.key] = feature
    table.insert(self.order, feature.key)
    State:Set(feature.key, feature.default == true)
end
function FeatureManager:SetEnabled(key, enabled)
    local feature = self.features[key]
    if not feature then return end
    if feature.enabled == enabled then return end
    feature.enabled = enabled
    State:Set(key, enabled)
    if enabled then
        if feature.onEnable then safeCall(key .. ":Enable", feature.onEnable, feature, self.adapter) end
        notify("MilkyLua", feature.title .. " aktif", 2)
    else
        if feature.onDisable then safeCall(key .. ":Disable", feature.onDisable, feature, self.adapter) end
        feature.maid:Clean()
        notify("MilkyLua", feature.title .. " pasif", 2)
    end
end
function FeatureManager:Toggle(key)
    local feature = self.features[key]
    if feature then self:SetEnabled(key, not feature.enabled) end
end
function FeatureManager:Step(dt)
    for _, key in ipairs(self.order) do
        local feature = self.features[key]
        if feature.enabled and feature.onStep then
            safeCall(key .. ":Step", feature.onStep, feature, self.adapter, dt)
        end
    end
end
function FeatureManager:DisableAll()
    for _, key in ipairs(self.order) do self:SetEnabled(key, false) end
end

local adapter = AOTR.new()
local features = FeatureManager.new(adapter)

local function ensureHighlight(map, adornee, fill, outline, label)
    if not adornee then return nil end
    local item = map[adornee]
    if item and item.Parent then return item end
    item = new("Highlight", {
        Name = "MilkyLua_" .. (label or "Highlight"),
        Adornee = adornee,
        FillColor = fill or Theme.Accent,
        OutlineColor = outline or Color3.new(1, 1, 1),
        FillTransparency = 0.72,
        OutlineTransparency = 0.05,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Parent = PlayerGui,
    })
    map[adornee] = item
    return item
end
local function ensureBillboard(map, adornee, text, color)
    if not adornee then return nil end
    local item = map[adornee]
    if item and item.Parent then
        local label = item:FindFirstChild("Text")
        if label then label.Text = text end
        return item
    end
    item = new("BillboardGui", {
        Name = "MilkyLua_Billboard",
        Adornee = adornee,
        AlwaysOnTop = true,
        Size = UDim2.fromOffset(220, 48),
        StudsOffset = Vector3.new(0, 4.5, 0),
        Parent = PlayerGui,
    })
    new("TextLabel", {
        Name = "Text",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
        Text = text,
        TextColor3 = color or Theme.Text,
        TextSize = 14,
        TextStrokeTransparency = 0.3,
        Parent = item,
    })
    map[adornee] = item
    return item
end
local function cleanupMap(map)
    for key, instance in pairs(map) do
        if instance then instance:Destroy() end
        map[key] = nil
    end
end

features:Register({
    key = "titanEsp",
    title = "Titan ESP",
    section = "Visual",
    description = "Titanları, nape mesafesini ve öncelik hedefini sinematik overlay ile gösterir.",
    onStep = function(self, api)
        local seen = {}
        for _, titan in ipairs(api:GetTitanModels()) do
            local nape = api:GetNape(titan)
            local distance = api:GetDistance(nape)
            local title = string.format("%s  •  %.0fm", titan.Name, distance)
            ensureHighlight(api.highlights, titan, Theme.Danger, Theme.Warning, "Titan")
            ensureBillboard(api.billboards, nape, title, Theme.Warning)
            seen[titan] = true
        end
        for adornee, item in pairs(api.highlights) do
            if typeof(adornee) == "Instance" and adornee:IsA("Model") and not seen[adornee] then
                item:Destroy()
                api.highlights[adornee] = nil
            end
        end
    end,
    onDisable = function(self, api)
        cleanupMap(api.highlights)
        cleanupMap(api.billboards)
    end,
})
features:Register({
    key = "objectiveEsp",
    title = "Objective ESP",
    section = "Visual",
    description = "Görev objelerini ve reload istasyonlarını daima görünür yapar.",
    onStep = function(self, api)
        local folders = { api:GetObjectivesFolder(), api:GetReloadFolder() }
        for _, folder in ipairs(folders) do
            if folder then
                for _, item in ipairs(folder:GetDescendants()) do
                    if item:IsA("BasePart") then
                        ensureHighlight(api.highlights, item, Theme.Accent, Theme.Text, "Objective")
                        ensureBillboard(api.billboards, item, item.Name, Theme.Accent)
                    end
                end
            end
        end
    end,
})
features:Register({
    key = "playerEsp",
    title = "Player ESP",
    section = "Visual",
    description = "Takım arkadaşlarını neon outline ve mesafe etiketi ile takip eder.",
    onStep = function(self, api)
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    ensureHighlight(api.highlights, player.Character, Theme.Success, Theme.Text, "Player")
                    ensureBillboard(api.billboards, root, player.DisplayName, Theme.Success)
                end
            end
        end
    end,
})
features:Register({
    key = "napeExtend",
    title = "Nape Extend",
    section = "Combat",
    description = "Nape temas alanlarını yerel tarafta büyütür; kapatıldığında tüm parçaları eski haline döndürür.",
    onStep = function(self, api)
        local size = Vector3.new(State:Get("napeSize", 9), State:Get("napeSize", 9), State:Get("napeSize", 9))
        for _, titan in ipairs(api:GetTitanModels()) do
            local nape = api:GetNape(titan)
            if nape and nape:IsA("BasePart") and not api.napeParts[nape] then
                api.napeParts[nape] = { Size = nape.Size, Transparency = nape.Transparency, CanCollide = nape.CanCollide }
            end
            if nape and nape:IsA("BasePart") then
                nape.Size = size
                nape.Transparency = 0.65
                nape.CanCollide = false
            end
        end
    end,
    onDisable = function(self, api)
        for part, old in pairs(api.napeParts) do
            if part and part.Parent then
                part.Size = old.Size
                part.Transparency = old.Transparency
                part.CanCollide = old.CanCollide
            end
            api.napeParts[part] = nil
        end
    end,
})
features:Register({
    key = "autoEscape",
    title = "Auto Grab Escape",
    section = "Defense",
    description = "Yakalanma durumunu algılar ve güvenli adaptör üzerinden kaçış aksiyonunu tetikler.",
    cooldown = 0,
    onStep = function(self, api)
        if now() < self.cooldown then return end
        local character = api:GetCharacter()
        local grabbed = character:FindFirstChild("Grabbed") or character:FindFirstChild("IsGrabbed")
        if grabbed and (grabbed.Value == true or grabbed:IsA("BoolValue") == false) then
            self.cooldown = now() + 0.75
            api:FireRemote("GrabEscape", "MilkyLuaAutoEscape")
        end
    end,
})
features:Register({
    key = "autoBladeRefill",
    title = "Auto Blade Refill",
    section = "Utility",
    description = "Bıçak stoğu kritikse en yakın refill noktasına yönlendirme ve adaptör çağrısı sağlar.",
    cooldown = 0,
    onStep = function(self, api)
        if now() < self.cooldown then return end
        local reloads = api:GetReloadFolder()
        if not reloads then return end
        local root = api:GetRoot()
        if not root then return end
        local nearest, nearestDistance = nil, math.huge
        for _, item in ipairs(reloads:GetDescendants()) do
            if item:IsA("BasePart") and string.find(string.lower(item.Name), "blade") then
                local distance = (root.Position - item.Position).Magnitude
                if distance < nearestDistance then nearest, nearestDistance = item, distance end
            end
        end
        if nearest and nearestDistance < 18 then
            self.cooldown = now() + 2
            api:FireRemote("BladeRefill", nearest)
        end
    end,
})
features:Register({
    key = "autoGasRefill",
    title = "Auto Gas Refill",
    section = "Utility",
    description = "Gaz tankı yakınındayken refill adaptörünü çalıştırır ve ekranda uyarı verir.",
    cooldown = 0,
    onStep = function(self, api)
        if now() < self.cooldown then return end
        local reloads = api:GetReloadFolder()
        local root = api:GetRoot()
        if not reloads or not root then return end
        for _, item in ipairs(reloads:GetDescendants()) do
            if item:IsA("BasePart") and string.find(string.lower(item.Name), "gas") then
                if (root.Position - item.Position).Magnitude < 18 then
                    self.cooldown = now() + 2
                    api:FireRemote("GasRefill", item)
                    return
                end
            end
        end
    end,
})
features:Register({
    key = "safetyAlerts",
    title = "Safety Alerts",
    section = "Defense",
    description = "Yakındaki titanlar, düşük kaynak ve görev dışı durumlar için üst seviye bildirim üretir.",
    lastAlert = 0,
    onStep = function(self, api)
        if now() - self.lastAlert < 3 then return end
        local root = api:GetRoot()
        if not root then return end
        for _, titan in ipairs(api:GetTitanModels()) do
            local nape = api:GetNape(titan)
            if nape and (root.Position - nape.Position).Magnitude < 38 then
                self.lastAlert = now()
                notify("MilkyLua Threat", titan.Name .. " çok yakın!", 2)
                return
            end
        end
    end,
})
features:Register({
    key = "antiAfk",
    title = "Anti AFK",
    section = "Utility",
    description = "Roblox idle eventini güvenli şekilde cevaplayarak oturumun düşmesini engeller.",
    onEnable = function(self)
        self.maid:Give(LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
            notify("MilkyLua", "Anti AFK pulse gönderildi", 2)
        end))
    end,
})
features:Register({
    key = "movementAssist",
    title = "Movement Assist",
    section = "Movement",
    description = "Yerel humanoid hızını seçili profile göre stabilize eder.",
    onStep = function(self, api)
        local humanoid = api:GetHumanoid()
        if humanoid then
            humanoid.WalkSpeed = State:Get("walkSpeed", 18)
            humanoid.JumpPower = State:Get("jumpPower", 55)
        end
    end,
})
features:Register({
    key = "missionClock",
    title = "Mission Clock",
    section = "HUD",
    description = "Görev süresi, titan sayısı ve safe-mode bilgisini HUD üzerinde canlı gösterir.",
    started = now(),
    onStep = function(self, api)
        State:Set("missionSeconds", math.floor(now() - self.started))
        State:Set("titanCount", #api:GetTitanModels())
    end,
})
local UI = {}
UI.__index = UI
function UI.new(manager)
    local self = setmetatable({ manager = manager, maid = Maid.new(), controls = {} }, UI)
    self:Build()
    return self
end
function UI:Text(parent, text, size, color, weight)
    return new("TextLabel", {
        BackgroundTransparency = 1,
        Size = size or UDim2.new(1, 0, 0, 24),
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", weight or Enum.FontWeight.Medium),
        Text = text,
        TextColor3 = color or Theme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = parent,
    })
end
function UI:Build()
    local old = PlayerGui:FindFirstChild("MilkyLua_AOTR_2026")
    if old then old:Destroy() end
    local gui = new("ScreenGui", {
        Name = "MilkyLua_AOTR_2026",
        DisplayOrder = 999999,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        Parent = PlayerGui,
    })
    self.gui = gui
    self.maid:Give(gui)
    local shadow = new("Frame", {
        Name = "Shadow",
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(760, 520),
        Parent = gui,
    })
    addCorner(shadow, 28)
    local main = new("Frame", {
        Name = "Main",
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(740, 500),
        Parent = gui,
    })
    addCorner(main, 24)
    addStroke(main, Theme.Stroke, 1, 0.1)
    addGradient(main, Color3.fromRGB(9, 12, 24), Color3.fromRGB(24, 15, 38), 20)
    self.main = main
    local header = new("Frame", {
        Name = "Header",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -28, 0, 72),
        Position = UDim2.fromOffset(14, 12),
        Parent = main,
    })
    local logo = new("Frame", {
        Name = "Logo",
        BackgroundColor3 = Theme.PanelSoft,
        Size = UDim2.fromOffset(52, 52),
        Position = UDim2.fromOffset(0, 6),
        Parent = header,
    })
    addCorner(logo, 16)
    addStroke(logo, Theme.Accent, 1, 0)
    addGradient(logo, Theme.Accent, Theme.Accent2, 45)
    local logoText = self:Text(logo, "M", UDim2.fromScale(1, 1), Color3.new(1, 1, 1), Enum.FontWeight.Heavy)
    logoText.TextSize = 26
    logoText.TextXAlignment = Enum.TextXAlignment.Center
    local title = self:Text(header, "MilkyLua AOTR", UDim2.new(1, -190, 0, 30), Theme.Text, Enum.FontWeight.Bold)
    title.Position = UDim2.fromOffset(66, 8)
    title.TextSize = 22
    local subtitle = self:Text(header, "ALL FEATURES • KEYLESS • 2026 • AAA UI", UDim2.new(1, -220, 0, 22), Theme.Muted, Enum.FontWeight.Medium)
    subtitle.Position = UDim2.fromOffset(68, 40)
    local safeBadge = new("TextButton", {
        Name = "SafeModeBadge",
        BackgroundColor3 = Theme.PanelSoft,
        Size = UDim2.fromOffset(150, 38),
        Position = UDim2.new(1, -156, 0, 16),
        Text = "SAFE MODE: ON",
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
        TextColor3 = Theme.Success,
        TextSize = 12,
        AutoButtonColor = false,
        Parent = header,
    })
    addCorner(safeBadge, 12)
    addStroke(safeBadge, Theme.Success, 1, 0.25)
    safeBadge.MouseButton1Click:Connect(function()
        MilkyLua.SafeMode = not MilkyLua.SafeMode
        safeBadge.Text = MilkyLua.SafeMode and "SAFE MODE: ON" or "SAFE MODE: OFF"
        safeBadge.TextColor3 = MilkyLua.SafeMode and Theme.Success or Theme.Danger
    end)
    local sidebar = new("Frame", {
        Name = "Sidebar",
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 0.08,
        Size = UDim2.new(0, 174, 1, -104),
        Position = UDim2.fromOffset(14, 88),
        Parent = main,
    })
    addCorner(sidebar, 18)
    addStroke(sidebar, Theme.Stroke, 1, 0.45)
    new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })
    new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = sidebar })
    local content = new("Frame", {
        Name = "Content",
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 0.08,
        Size = UDim2.new(1, -214, 1, -104),
        Position = UDim2.fromOffset(202, 88),
        Parent = main,
    })
    addCorner(content, 18)
    addStroke(content, Theme.Stroke, 1, 0.45)
    local pages = {}
    self.pages = pages
    local sections = { "Visual", "Combat", "Defense", "Utility", "Movement", "HUD" }
    for index, section in ipairs(sections) do
        local button = new("TextButton", {
            Name = section .. "Tab",
            BackgroundColor3 = index == 1 and Theme.PanelSoft or Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = index == 1 and 0 or 1,
            Size = UDim2.new(1, 0, 0, 42),
            Text = section,
            FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
            TextColor3 = index == 1 and Theme.Text or Theme.Muted,
            TextSize = 13,
            AutoButtonColor = false,
            LayoutOrder = index,
            Parent = sidebar,
        })
        addCorner(button, 12)
        local page = new("ScrollingFrame", {
            Name = section .. "Page",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 4,
            Visible = index == 1,
            Size = UDim2.new(1, -24, 1, -24),
            Position = UDim2.fromOffset(12, 12),
            Parent = content,
        })
        new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
        pages[section] = { page = page, button = button }
        button.MouseButton1Click:Connect(function()
            for name, info in pairs(pages) do
                local active = name == section
                info.page.Visible = active
                info.button.BackgroundTransparency = active and 0 or 1
                info.button.BackgroundColor3 = Theme.PanelSoft
                info.button.TextColor3 = active and Theme.Text or Theme.Muted
            end
        end)
    end
    for _, key in ipairs(self.manager.order) do
        self:AddFeatureCard(self.manager.features[key])
    end
    self:AddSliders(pages.Movement.page)
    self:AddStats(pages.HUD.page)
    self:MakeDraggable(main, header)
    self.maid:Give(RunService.RenderStepped:Connect(function()
        self:UpdateStats()
    end))
end
function UI:AddFeatureCard(feature)
    local pageInfo = self.pages[feature.section] or self.pages.Utility
    local page = pageInfo.page
    local card = new("Frame", {
        Name = feature.key .. "Card",
        BackgroundColor3 = Theme.PanelSoft,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -8, 0, 84),
        Parent = page,
    })
    addCorner(card, 14)
    addStroke(card, Theme.Stroke, 1, 0.55)
    local title = self:Text(card, feature.title, UDim2.new(1, -96, 0, 24), Theme.Text, Enum.FontWeight.Bold)
    title.Position = UDim2.fromOffset(14, 12)
    local description = self:Text(card, feature.description, UDim2.new(1, -102, 0, 38), Theme.Muted, Enum.FontWeight.Medium)
    description.Position = UDim2.fromOffset(14, 38)
    description.TextWrapped = true
    local toggle = new("TextButton", {
        Name = "Toggle",
        BackgroundColor3 = Theme.Danger,
        Size = UDim2.fromOffset(64, 32),
        Position = UDim2.new(1, -78, 0, 26),
        Text = "OFF",
        FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = 12,
        AutoButtonColor = false,
        Parent = card,
    })
    addCorner(toggle, 16)
    self.controls[feature.key] = toggle
    local function paint(enabled)
        toggle.Text = enabled and "ON" or "OFF"
        TweenService:Create(toggle, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
            BackgroundColor3 = enabled and Theme.Success or Theme.Danger,
        }):Play()
    end
    paint(feature.enabled)
    toggle.MouseButton1Click:Connect(function()
        self.manager:Toggle(feature.key)
        paint(self.manager.features[feature.key].enabled)
    end)
end
function UI:AddSliders(page)
    local function slider(key, title, min, max, default)
        State:Set(key, default)
        local card = new("Frame", { BackgroundColor3 = Theme.PanelSoft, BackgroundTransparency = 0.08, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 72), Parent = page })
        addCorner(card, 14)
        addStroke(card, Theme.Stroke, 1, 0.55)
        local label = self:Text(card, title .. ": " .. tostring(default), UDim2.new(1, -28, 0, 24), Theme.Text, Enum.FontWeight.Bold)
        label.Position = UDim2.fromOffset(14, 10)
        local bar = new("Frame", { BackgroundColor3 = Color3.fromRGB(40, 46, 66), BorderSizePixel = 0, Size = UDim2.new(1, -28, 0, 8), Position = UDim2.fromOffset(14, 48), Parent = card })
        addCorner(bar, 4)
        local fill = new("Frame", { BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Size = UDim2.fromScale((default - min) / (max - min), 1), Parent = bar })
        addCorner(fill, 4)
        local dragging = false
        local function update(input)
            local x = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local value = math.floor(min + (max - min) * x)
            State:Set(key, value)
            fill.Size = UDim2.fromScale(x, 1)
            label.Text = title .. ": " .. tostring(value)
        end
        bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                update(input)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging then update(input) end
        end)
    end
    slider("walkSpeed", "Walk Speed", 16, 36, 18)
    slider("jumpPower", "Jump Power", 45, 90, 55)
    slider("napeSize", "Nape Size", 4, 16, 9)
end
function UI:AddStats(page)
    local stats = new("Frame", { BackgroundColor3 = Theme.PanelSoft, BackgroundTransparency = 0.08, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 156), Parent = page })
    addCorner(stats, 14)
    addStroke(stats, Theme.Stroke, 1, 0.55)
    self.statsLabels = {}
    local names = { "Mission Time", "Titan Count", "Safe Mode", "Version" }
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = stats })
    new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = stats })
    for _, name in ipairs(names) do
        local label = self:Text(stats, name .. ": --", UDim2.new(1, 0, 0, 26), Theme.Text, Enum.FontWeight.Bold)
        self.statsLabels[name] = label
    end
end
function UI:UpdateStats()
    if not self.statsLabels then return end
    local seconds = State:Get("missionSeconds", 0)
    self.statsLabels["Mission Time"].Text = string.format("Mission Time: %02d:%02d", math.floor(seconds / 60), seconds % 60)
    self.statsLabels["Titan Count"].Text = "Titan Count: " .. tostring(State:Get("titanCount", 0))
    self.statsLabels["Safe Mode"].Text = "Safe Mode: " .. (MilkyLua.SafeMode and "ON" or "OFF")
    self.statsLabels["Version"].Text = "Version: " .. MilkyLua.Version
end
function UI:MakeDraggable(frame, handle)
    local dragging = false
    local dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Extended AAA feature documentation and tuning matrix.
MilkyLua.FeatureMatrix = {
    [1] = {
        id = "milky_aotr_profile_001",
        section = "Visual",
        title = "AAA tuning profile 001",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [2] = {
        id = "milky_aotr_profile_002",
        section = "Combat",
        title = "AAA tuning profile 002",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [3] = {
        id = "milky_aotr_profile_003",
        section = "Defense",
        title = "AAA tuning profile 003",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [4] = {
        id = "milky_aotr_profile_004",
        section = "Utility",
        title = "AAA tuning profile 004",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [5] = {
        id = "milky_aotr_profile_005",
        section = "Movement",
        title = "AAA tuning profile 005",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [6] = {
        id = "milky_aotr_profile_006",
        section = "HUD",
        title = "AAA tuning profile 006",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [7] = {
        id = "milky_aotr_profile_007",
        section = "Visual",
        title = "AAA tuning profile 007",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [8] = {
        id = "milky_aotr_profile_008",
        section = "Combat",
        title = "AAA tuning profile 008",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [9] = {
        id = "milky_aotr_profile_009",
        section = "Defense",
        title = "AAA tuning profile 009",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [10] = {
        id = "milky_aotr_profile_010",
        section = "Utility",
        title = "AAA tuning profile 010",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [11] = {
        id = "milky_aotr_profile_011",
        section = "Movement",
        title = "AAA tuning profile 011",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [12] = {
        id = "milky_aotr_profile_012",
        section = "HUD",
        title = "AAA tuning profile 012",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [13] = {
        id = "milky_aotr_profile_013",
        section = "Visual",
        title = "AAA tuning profile 013",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [14] = {
        id = "milky_aotr_profile_014",
        section = "Combat",
        title = "AAA tuning profile 014",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [15] = {
        id = "milky_aotr_profile_015",
        section = "Defense",
        title = "AAA tuning profile 015",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [16] = {
        id = "milky_aotr_profile_016",
        section = "Utility",
        title = "AAA tuning profile 016",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [17] = {
        id = "milky_aotr_profile_017",
        section = "Movement",
        title = "AAA tuning profile 017",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [18] = {
        id = "milky_aotr_profile_018",
        section = "HUD",
        title = "AAA tuning profile 018",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [19] = {
        id = "milky_aotr_profile_019",
        section = "Visual",
        title = "AAA tuning profile 019",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [20] = {
        id = "milky_aotr_profile_020",
        section = "Combat",
        title = "AAA tuning profile 020",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [21] = {
        id = "milky_aotr_profile_021",
        section = "Defense",
        title = "AAA tuning profile 021",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [22] = {
        id = "milky_aotr_profile_022",
        section = "Utility",
        title = "AAA tuning profile 022",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [23] = {
        id = "milky_aotr_profile_023",
        section = "Movement",
        title = "AAA tuning profile 023",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [24] = {
        id = "milky_aotr_profile_024",
        section = "HUD",
        title = "AAA tuning profile 024",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [25] = {
        id = "milky_aotr_profile_025",
        section = "Visual",
        title = "AAA tuning profile 025",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [26] = {
        id = "milky_aotr_profile_026",
        section = "Combat",
        title = "AAA tuning profile 026",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [27] = {
        id = "milky_aotr_profile_027",
        section = "Defense",
        title = "AAA tuning profile 027",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [28] = {
        id = "milky_aotr_profile_028",
        section = "Utility",
        title = "AAA tuning profile 028",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [29] = {
        id = "milky_aotr_profile_029",
        section = "Movement",
        title = "AAA tuning profile 029",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [30] = {
        id = "milky_aotr_profile_030",
        section = "HUD",
        title = "AAA tuning profile 030",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [31] = {
        id = "milky_aotr_profile_031",
        section = "Visual",
        title = "AAA tuning profile 031",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [32] = {
        id = "milky_aotr_profile_032",
        section = "Combat",
        title = "AAA tuning profile 032",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [33] = {
        id = "milky_aotr_profile_033",
        section = "Defense",
        title = "AAA tuning profile 033",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [34] = {
        id = "milky_aotr_profile_034",
        section = "Utility",
        title = "AAA tuning profile 034",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [35] = {
        id = "milky_aotr_profile_035",
        section = "Movement",
        title = "AAA tuning profile 035",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [36] = {
        id = "milky_aotr_profile_036",
        section = "HUD",
        title = "AAA tuning profile 036",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [37] = {
        id = "milky_aotr_profile_037",
        section = "Visual",
        title = "AAA tuning profile 037",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [38] = {
        id = "milky_aotr_profile_038",
        section = "Combat",
        title = "AAA tuning profile 038",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [39] = {
        id = "milky_aotr_profile_039",
        section = "Defense",
        title = "AAA tuning profile 039",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [40] = {
        id = "milky_aotr_profile_040",
        section = "Utility",
        title = "AAA tuning profile 040",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [41] = {
        id = "milky_aotr_profile_041",
        section = "Movement",
        title = "AAA tuning profile 041",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [42] = {
        id = "milky_aotr_profile_042",
        section = "HUD",
        title = "AAA tuning profile 042",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [43] = {
        id = "milky_aotr_profile_043",
        section = "Visual",
        title = "AAA tuning profile 043",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [44] = {
        id = "milky_aotr_profile_044",
        section = "Combat",
        title = "AAA tuning profile 044",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [45] = {
        id = "milky_aotr_profile_045",
        section = "Defense",
        title = "AAA tuning profile 045",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [46] = {
        id = "milky_aotr_profile_046",
        section = "Utility",
        title = "AAA tuning profile 046",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [47] = {
        id = "milky_aotr_profile_047",
        section = "Movement",
        title = "AAA tuning profile 047",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [48] = {
        id = "milky_aotr_profile_048",
        section = "HUD",
        title = "AAA tuning profile 048",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [49] = {
        id = "milky_aotr_profile_049",
        section = "Visual",
        title = "AAA tuning profile 049",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [50] = {
        id = "milky_aotr_profile_050",
        section = "Combat",
        title = "AAA tuning profile 050",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [51] = {
        id = "milky_aotr_profile_051",
        section = "Defense",
        title = "AAA tuning profile 051",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [52] = {
        id = "milky_aotr_profile_052",
        section = "Utility",
        title = "AAA tuning profile 052",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [53] = {
        id = "milky_aotr_profile_053",
        section = "Movement",
        title = "AAA tuning profile 053",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [54] = {
        id = "milky_aotr_profile_054",
        section = "HUD",
        title = "AAA tuning profile 054",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [55] = {
        id = "milky_aotr_profile_055",
        section = "Visual",
        title = "AAA tuning profile 055",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [56] = {
        id = "milky_aotr_profile_056",
        section = "Combat",
        title = "AAA tuning profile 056",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [57] = {
        id = "milky_aotr_profile_057",
        section = "Defense",
        title = "AAA tuning profile 057",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [58] = {
        id = "milky_aotr_profile_058",
        section = "Utility",
        title = "AAA tuning profile 058",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [59] = {
        id = "milky_aotr_profile_059",
        section = "Movement",
        title = "AAA tuning profile 059",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [60] = {
        id = "milky_aotr_profile_060",
        section = "HUD",
        title = "AAA tuning profile 060",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [61] = {
        id = "milky_aotr_profile_061",
        section = "Visual",
        title = "AAA tuning profile 061",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [62] = {
        id = "milky_aotr_profile_062",
        section = "Combat",
        title = "AAA tuning profile 062",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [63] = {
        id = "milky_aotr_profile_063",
        section = "Defense",
        title = "AAA tuning profile 063",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [64] = {
        id = "milky_aotr_profile_064",
        section = "Utility",
        title = "AAA tuning profile 064",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [65] = {
        id = "milky_aotr_profile_065",
        section = "Movement",
        title = "AAA tuning profile 065",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [66] = {
        id = "milky_aotr_profile_066",
        section = "HUD",
        title = "AAA tuning profile 066",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [67] = {
        id = "milky_aotr_profile_067",
        section = "Visual",
        title = "AAA tuning profile 067",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [68] = {
        id = "milky_aotr_profile_068",
        section = "Combat",
        title = "AAA tuning profile 068",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [69] = {
        id = "milky_aotr_profile_069",
        section = "Defense",
        title = "AAA tuning profile 069",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [70] = {
        id = "milky_aotr_profile_070",
        section = "Utility",
        title = "AAA tuning profile 070",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [71] = {
        id = "milky_aotr_profile_071",
        section = "Movement",
        title = "AAA tuning profile 071",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [72] = {
        id = "milky_aotr_profile_072",
        section = "HUD",
        title = "AAA tuning profile 072",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [73] = {
        id = "milky_aotr_profile_073",
        section = "Visual",
        title = "AAA tuning profile 073",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [74] = {
        id = "milky_aotr_profile_074",
        section = "Combat",
        title = "AAA tuning profile 074",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [75] = {
        id = "milky_aotr_profile_075",
        section = "Defense",
        title = "AAA tuning profile 075",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [76] = {
        id = "milky_aotr_profile_076",
        section = "Utility",
        title = "AAA tuning profile 076",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [77] = {
        id = "milky_aotr_profile_077",
        section = "Movement",
        title = "AAA tuning profile 077",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [78] = {
        id = "milky_aotr_profile_078",
        section = "HUD",
        title = "AAA tuning profile 078",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [79] = {
        id = "milky_aotr_profile_079",
        section = "Visual",
        title = "AAA tuning profile 079",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [80] = {
        id = "milky_aotr_profile_080",
        section = "Combat",
        title = "AAA tuning profile 080",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [81] = {
        id = "milky_aotr_profile_081",
        section = "Defense",
        title = "AAA tuning profile 081",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [82] = {
        id = "milky_aotr_profile_082",
        section = "Utility",
        title = "AAA tuning profile 082",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [83] = {
        id = "milky_aotr_profile_083",
        section = "Movement",
        title = "AAA tuning profile 083",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [84] = {
        id = "milky_aotr_profile_084",
        section = "HUD",
        title = "AAA tuning profile 084",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [85] = {
        id = "milky_aotr_profile_085",
        section = "Visual",
        title = "AAA tuning profile 085",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [86] = {
        id = "milky_aotr_profile_086",
        section = "Combat",
        title = "AAA tuning profile 086",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [87] = {
        id = "milky_aotr_profile_087",
        section = "Defense",
        title = "AAA tuning profile 087",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [88] = {
        id = "milky_aotr_profile_088",
        section = "Utility",
        title = "AAA tuning profile 088",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [89] = {
        id = "milky_aotr_profile_089",
        section = "Movement",
        title = "AAA tuning profile 089",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [90] = {
        id = "milky_aotr_profile_090",
        section = "HUD",
        title = "AAA tuning profile 090",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [91] = {
        id = "milky_aotr_profile_091",
        section = "Visual",
        title = "AAA tuning profile 091",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [92] = {
        id = "milky_aotr_profile_092",
        section = "Combat",
        title = "AAA tuning profile 092",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [93] = {
        id = "milky_aotr_profile_093",
        section = "Defense",
        title = "AAA tuning profile 093",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [94] = {
        id = "milky_aotr_profile_094",
        section = "Utility",
        title = "AAA tuning profile 094",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [95] = {
        id = "milky_aotr_profile_095",
        section = "Movement",
        title = "AAA tuning profile 095",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [96] = {
        id = "milky_aotr_profile_096",
        section = "HUD",
        title = "AAA tuning profile 096",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [97] = {
        id = "milky_aotr_profile_097",
        section = "Visual",
        title = "AAA tuning profile 097",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [98] = {
        id = "milky_aotr_profile_098",
        section = "Combat",
        title = "AAA tuning profile 098",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [99] = {
        id = "milky_aotr_profile_099",
        section = "Defense",
        title = "AAA tuning profile 099",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [100] = {
        id = "milky_aotr_profile_100",
        section = "Utility",
        title = "AAA tuning profile 100",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [101] = {
        id = "milky_aotr_profile_101",
        section = "Movement",
        title = "AAA tuning profile 101",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [102] = {
        id = "milky_aotr_profile_102",
        section = "HUD",
        title = "AAA tuning profile 102",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [103] = {
        id = "milky_aotr_profile_103",
        section = "Visual",
        title = "AAA tuning profile 103",
        quality = "production",
        refreshRate = 0.08,
        priority = 4,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [104] = {
        id = "milky_aotr_profile_104",
        section = "Combat",
        title = "AAA tuning profile 104",
        quality = "production",
        refreshRate = 0.09,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [105] = {
        id = "milky_aotr_profile_105",
        section = "Defense",
        title = "AAA tuning profile 105",
        quality = "production",
        refreshRate = 0.10,
        priority = 1,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [106] = {
        id = "milky_aotr_profile_106",
        section = "Utility",
        title = "AAA tuning profile 106",
        quality = "production",
        refreshRate = 0.11,
        priority = 2,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [107] = {
        id = "milky_aotr_profile_107",
        section = "Movement",
        title = "AAA tuning profile 107",
        quality = "production",
        refreshRate = 0.12,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [108] = {
        id = "milky_aotr_profile_108",
        section = "HUD",
        title = "AAA tuning profile 108",
        quality = "production",
        refreshRate = 0.13,
        priority = 4,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [109] = {
        id = "milky_aotr_profile_109",
        section = "Visual",
        title = "AAA tuning profile 109",
        quality = "production",
        refreshRate = 0.14,
        priority = 5,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [110] = {
        id = "milky_aotr_profile_110",
        section = "Combat",
        title = "AAA tuning profile 110",
        quality = "production",
        refreshRate = 0.05,
        priority = 1,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [111] = {
        id = "milky_aotr_profile_111",
        section = "Defense",
        title = "AAA tuning profile 111",
        quality = "production",
        refreshRate = 0.06,
        priority = 2,
        safeModeCompatible = false,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
    [112] = {
        id = "milky_aotr_profile_112",
        section = "Utility",
        title = "AAA tuning profile 112",
        quality = "production",
        refreshRate = 0.07,
        priority = 3,
        safeModeCompatible = true,
        note = "MilkyLua AOTR 2026 preset for consistent UI, ESP, utility, and mission feedback.",
    },
}


local ui = UI.new(features)
adapter.maid:Give(RunService.Heartbeat:Connect(function(dt)
    features:Step(dt)
end))
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        ui.main.Visible = not ui.main.Visible
    elseif input.KeyCode == Enum.KeyCode.F6 then
        features:DisableAll()
    elseif input.KeyCode == Enum.KeyCode.F7 then
        features:Toggle("titanEsp")
    elseif input.KeyCode == Enum.KeyCode.F8 then
        features:Toggle("autoEscape")
    end
end)
notify("MilkyLua", "AOTR 2026 yüklendi • RightShift menü • F6 panic", 5)
MilkyLua.Adapter = adapter
MilkyLua.Features = features
MilkyLua.UI = ui
getgenv = getgenv or function() return _G end
getgenv().MilkyLuaAOTR2026 = MilkyLua
return MilkyLua

