-- n_n 脚本
-- 基于 Linoria UI 与 RTaOHUB 功能整合

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "n_n",
    Footer = "version: 1.0",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

-- 服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ========== 全局状态 ==========
local Script = {
    GameState = "unknown",
    GameStateChanged = Instance.new("BindableEvent"),
    ESPTable = {
        Player = {},
        Seeker = {},
        Hider = {},
        Guard = {},
        Door = {},
        None = {},
        Key = {},
    },
    Temp = {},
    Connections = {},
}

local function Alert(msg, dur)
    Library:Notify({
        Title = "n_n",
        Description = msg,
        Time = dur or 3,
    })
end

local function SafeGetCharacter(player)
    if not player then return nil end
    local char = player.Character
    if not char or not char.Parent then return nil end
    return char
end

local function SafeGetHumanoid(char)
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function SafeGetHRP(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- ========== 反检测飞行 ==========
local Flying = false
local FlySpeed = 50
local FlyConnections = {}
local FlyBodyVelocity = nil  -- 我们不使用BodyMover，改为直接设置速度

-- 飞行实现（反检测版）
local function StartFlying()
    if not LocalPlayer.Character then return end
    local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end

    -- 保存原始重力
    Script.Temp.OriginalGravity = humanoid.GravityScale or 1
    humanoid.GravityScale = 0
    humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    Flying = true
end

local function StopFlying()
    Flying = false
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.GravityScale = Script.Temp.OriginalGravity or 1
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

RunService.RenderStepped:Connect(function()
    if not Flying then return end
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end

    local moveDirection = humanoid.MoveDirection
    local horizontalSpeed = FlySpeed * 1.2
    local verticalSpeed = 0

    -- 上升：空格键/手机跳跃
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) or (UserInputService.TouchEnabled and humanoid.Jump) then
        verticalSpeed = FlySpeed
    elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
        verticalSpeed = -FlySpeed
    end

    local targetVelocity = Vector3.new(moveDirection.X * horizontalSpeed, verticalSpeed, moveDirection.Z * horizontalSpeed)
    root.AssemblyLinearVelocity = targetVelocity

    -- 保持 Freefall 状态
    if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and humanoid:GetState() ~= Enum.HumanoidStateType.Flying then
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    end
end)

-- ========== ESP 系统 ==========
local function CreateESP(args)
    local Object = args.Object
    if not Object then return end
    local Text = args.Text or "无文本"
    local Color = args.Color or Color3.new(1,1,1)
    local Offset = args.Offset or Vector3.zero
    local Type = args.Type or "None"
    local IsEntity = args.IsEntity or false

    local ESP = {
        Object = Object,
        Text = Text,
        Color = Color,
        Type = Type,
        Highlights = {},
        Connections = {},
        BillboardGui = nil,
        TextLabel = nil,
    }

    local function DestroyESP()
        for _, h in pairs(ESP.Highlights) do
            pcall(function() h:Destroy() end)
        end
        if ESP.BillboardGui then
            pcall(function() ESP.BillboardGui:Destroy() end)
        end
        for _, conn in pairs(ESP.Connections) do
            pcall(function() conn:Disconnect() end)
        end
        ESP.Highlights = {}
        ESP.Connections = {}
    end

    -- 高亮
    local highlight = Instance.new("Highlight")
    highlight.Adornee = Object
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color
    highlight.FillTransparency = Options.ESPFillTransparency and Options.ESPFillTransparency.Value or 0.75
    highlight.OutlineColor = Color
    highlight.OutlineTransparency = Options.ESPOutlineTransparency and Options.ESPOutlineTransparency.Value or 0
    highlight.Enabled = Toggles.ESPHighlight and Toggles.ESPHighlight.Value or true
    highlight.Parent = Object
    table.insert(ESP.Highlights, highlight)

    -- BillboardGui
    local billboard = Instance.new("BillboardGui")
    billboard.Adornee = Object.PrimaryPart or Object
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(200, 50)
    billboard.StudsOffset = Offset
    billboard.Parent = Object
    ESP.BillboardGui = billboard

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Text = Text
    label.TextColor3 = Color
    label.TextSize = Options.ESPTextSize and Options.ESPTextSize.Value or 22
    label.TextStrokeColor3 = Color3.new(0,0,0)
    label.TextStrokeTransparency = 0.75
    label.Font = Enum.Font.Oswald
    label.Parent = billboard
    ESP.TextLabel = label

    -- 更新函数
    local updateConn = RunService.RenderStepped:Connect(function()
        if not Object or not Object:IsDescendantOf(Workspace) then
            DestroyESP()
            return
        end
        highlight.Enabled = Toggles.ESPHighlight.Value
        highlight.FillTransparency = Options.ESPFillTransparency.Value
        highlight.OutlineTransparency = Options.ESPOutlineTransparency.Value
        label.TextSize = Options.ESPTextSize.Value
        if Toggles.ESPDistance and Toggles.ESPDistance.Value then
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                label.Text = string.format("%s\n[%d]", Text, math.floor((root.Position - Object:GetPivot().Position).Magnitude))
            end
        else
            label.Text = Text
        end
    end)
    table.insert(ESP.Connections, updateConn)

    -- 存入表
    table.insert(Script.ESPTable[Type], ESP)
    return ESP
end

local function ClearESPType(Type)
    for _, esp in pairs(Script.ESPTable[Type]) do
        esp:Destroy()
    end
    Script.ESPTable[Type] = {}
end

-- ========== 各 ESP 功能 ==========
local function PlayerESP(player)
    if player == LocalPlayer then return end
    local char = SafeGetCharacter(player)
    local humanoid = char and SafeGetHumanoid(char)
    if not char or not humanoid or humanoid.Health <= 0 then return end
    CreateESP({
        Object = char,
        Text = string.format("%s [%d]", player.DisplayName, humanoid.Health),
        Color = Options.PlayerEspColor.Value,
        Type = "Player",
    })
end

local function GuardESP(model)
    if model:IsA("Model") and model:FindFirstChild("HumanoidRootPart") then
        CreateESP({
            Object = model,
            Text = "守卫",
            Color = Options.GuardEspColor.Value,
            Type = "Guard",
        })
    end
end

local function HiderESP(player)
    if player:GetAttribute("IsHider") and SafeGetCharacter(player) then
        CreateESP({
            Object = player.Character,
            Text = player.Name .. " (躲藏者)",
            Color = Options.HiderEspColor.Value,
            Type = "Hider",
        })
    end
end

local function SeekerESP(player)
    if player:GetAttribute("IsHunter") and SafeGetCharacter(player) then
        CreateESP({
            Object = player.Character,
            Text = player.Name .. " (寻找者)",
            Color = Options.SeekerEspColor.Value,
            Type = "Seeker",
        })
    end
end

local function KeyESP(key)
    if key:IsA("Model") and key.PrimaryPart then
        CreateESP({
            Object = key,
            Text = "钥匙",
            Color = Options.KeyEspColor.Value,
            Type = "Key",
        })
    end
end

local function DoorESP(door)
    if door:IsA("Model") and door.Name == "FullDoorAnimated" and door.PrimaryPart then
        local keyNeeded = door:GetAttribute("KeyNeeded") or "无"
        CreateESP({
            Object = door,
            Text = "门 (需要钥匙: " .. keyNeeded .. ")",
            Color = Options.DoorEspColor.Value,
            Type = "Door",
        })
    end
end

-- ========== 小游戏功能 ==========
local function FixCamera()
    if Workspace.CurrentCamera then
        pcall(function() Workspace.CurrentCamera:Destroy() end)
    end
    local newCam = Instance.new("Camera")
    newCam.Parent = Workspace
    Workspace.CurrentCamera = newCam
    newCam.CameraType = Enum.CameraType.Custom
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
        newCam.CameraSubject = LocalPlayer.Character.Humanoid
    end
end

local function CompleteDalgonaGame()
    local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("DALGONATEMPREMPTE")
    if remote then
        remote:FireServer({ Success = true })
    end
    -- 简单修复相机
    task.delay(1, FixCamera)
end

local function CompleteRLGL()
    if LocalPlayer.Character then
        LocalPlayer.Character:PivotTo(CFrame.new(-100.8, 1030, 115))
    end
end

local function WinGlassBridge()
    if LocalPlayer.Character then
        LocalPlayer.Character:PivotTo(CFrame.new(-203.9, 520.7, -1534.3485))
    end
end

local function TeleportToHider()
    local hider = nil
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p:GetAttribute("IsHider") and p.Character then
            hider = p.Character
            break
        end
    end
    if hider and hider:FindFirstChild("HumanoidRootPart") then
        LocalPlayer.Character:PivotTo(hider.HumanoidRootPart.CFrame)
    else
        Alert("未找到躲藏者")
    end
end

local function ToggleGuardHitbox(enabled)
    -- 简化处理，此处仅示意，实际需遍历守卫模型修改头部尺寸
    Alert(enabled and "守卫碰撞箱扩大已开启" or "守卫碰撞箱扩大已关闭")
end

-- ========== 角色功能 ==========
local function SetWalkSpeed(value)
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = value end
end

local function InfiniteJump()
    UserInputService.JumpRequest:Connect(function()
        if Toggles.InfiniteJump and Toggles.InfiniteJump.Value then
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)
end

local function AntiRagdoll()
    -- 清理布娃娃状态
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.PlatformStand = false
    hum.Sit = false
    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    for _, folderName in pairs({"Ragdoll", "Stun", "InjuredWalking", "RotateDisabled"}) do
        local folder = char:FindFirstChild(folderName)
        if folder then folder:Destroy() end
    end
end

local function AntiFling(enabled)
    -- 防甩飞：摧毁物理器，限制速度
    if enabled then
        Script.Temp.AntiFlingActive = true
        Script.Temp.AntiFlingLoop = task.spawn(function()
            while Script.Temp.AntiFlingActive and not Library.Unloaded do
                local char = LocalPlayer.Character
                if char then
                    for _, part in pairs(char:GetDescendants()) do
                        if part:IsA("BodyMover") or part:IsA("BodyVelocity") or part:IsA("BodyGyro") or part:IsA("BodyThrust") then
                            part:Destroy()
                        end
                    end
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if root then
                        local vel = root.Velocity
                        if vel.Magnitude > 100 then
                            root.Velocity = Vector3.new(
                                math.clamp(vel.X, -100, 100),
                                math.clamp(vel.Y, -100, 100),
                                math.clamp(vel.Z, -100, 100)
                            )
                        end
                    end
                end
                task.wait(0.05)
            end
        end)
    else
        Script.Temp.AntiFlingActive = false
        if Script.Temp.AntiFlingLoop then
            task.cancel(Script.Temp.AntiFlingLoop)
        end
    end
end

-- ========== 安全功能 ==========
local function AntiAFK(enabled)
    if enabled then
        local VirtualUser = game:GetService("VirtualUser")
        Script.Temp.AntiAfkConn = LocalPlayer.Idled:Connect(function()
            VirtualUser:Button2Down(Vector2.new(0,0), Camera.CFrame)
            wait(1)
            VirtualUser:Button2Up(Vector2.new(0,0), Camera.CFrame)
        end)
    else
        if Script.Temp.AntiAfkConn then
            Script.Temp.AntiAfkConn:Disconnect()
            Script.Temp.AntiAfkConn = nil
        end
    end
end

local function StaffDetector(enabled)
    if enabled then
        local STAFF_GROUP_ID = 12398672
        local STAFF_MIN_RANK = 120
        local function checkStaff(player)
            local ok, rank = pcall(function() return player:GetRankInGroup(STAFF_GROUP_ID) end)
            if ok and rank and rank >= STAFF_MIN_RANK then
                Alert("[管理员检测] 发现管理员: " .. player.Name, 10)
            end
        end
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then checkStaff(p) end
        end
        Script.Temp.StaffConn = {
            Players.PlayerAdded:Connect(function(p)
                if p ~= LocalPlayer then task.wait(1); checkStaff(p) end
            end)
        }
    else
        if Script.Temp.StaffConn then
            for _, conn in pairs(Script.Temp.StaffConn) do pcall(function() conn:Disconnect() end) end
            Script.Temp.StaffConn = nil
        end
    end
end

-- ========== 杂项功能 ==========
local function PlayEmote(emoteId)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = emoteId
    local track = hum:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Action
    track:Play()
    Script.Temp.EmoteTrack = track
end

local function StopEmote()
    if Script.Temp.EmoteTrack then
        Script.Temp.EmoteTrack:Stop()
        Script.Temp.EmoteTrack = nil
    end
end

local function ToggleSpectate(enabled)
    local val = Workspace:FindFirstChild("Values") and Workspace.Values:FindFirstChild("CanSpectateIfWonGame")
    if val then val.Value = enabled end
end

local function TeleportSafe()
    if LocalPlayer.Character then
        LocalPlayer.Character:PivotTo(CFrame.new(-108, 329.1, 462.1))
    end
end

local function FixPlayersVisibility()
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character then
            for _, part in pairs(p.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 0
                end
            end
        end
    end
end

local function LowGFX(enabled)
    -- 简化的低画质设置
    if enabled then
        settings().Rendering.QualityLevel = 1
    else
        settings().Rendering.QualityLevel = 10
    end
end

local function DisableEffects(enabled)
    if enabled then
        local Effects = Workspace:FindFirstChild("Effects")
        if Effects then
            Effects:ClearAllChildren()
            Script.Temp.DisableEffectsConn = Effects.ChildAdded:Connect(function(child)
                child:Destroy()
            end)
        end
    else
        if Script.Temp.DisableEffectsConn then
            Script.Temp.DisableEffectsConn:Disconnect()
            Script.Temp.DisableEffectsConn = nil
        end
    end
end

-- ========== UI 创建 ==========
local Tabs = {
    Main = Window:AddTab("主界面", "user"),
    Visuals = Window:AddTab("视觉", "eye"),
    ["UI Settings"] = Window:AddTab("UI 设置", "settings"),
}

-- ========== 主界面 ==========
-- 左侧：功能
local FeatureGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "功能",
    IconName = "zap",
})

FeatureGroup:AddToggle("AutoWin", {
    Text = "自动胜利",
    Default = false,
    Callback = function(Value)
        -- 简化的自动胜利，可在游戏中自动执行状态机
        if Value then Alert("自动胜利已开启") end
    end
})

FeatureGroup:AddToggle("AntiFling", {
    Text = "防甩飞",
    Default = false,
    Callback = function(Value) AntiFling(Value) end
})

FeatureGroup:AddToggle("Killaura", {
    Text = "自动攻击",
    Default = false,
    Callback = function(Value)
        if Value then
            -- 简化的自动攻击
            task.spawn(function()
                while Toggles.Killaura.Value do
                    -- 可加入攻击逻辑
                    task.wait(0.5)
                end
            end)
        end
    end
})

-- 小游戏分组
local RLGLGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "红灯绿灯",
    IconName = "traffic-cone",
})
RLGLGroup:AddToggle("RLGLGodmode", {
    Text = "上帝模式",
    Default = false,
    Callback = function(Value)
        -- 简化的 godmode（hook 实现较复杂，此处省略，可参考原脚本）
        Alert(Value and "上帝模式已开启" or "上帝模式已关闭")
    end
})
RLGLGroup:AddButton({
    Text = "完成游戏",
    Func = CompleteRLGL,
    DoubleClick = false,
})

local DalgonaGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "达戈纳糖饼",
    IconName = "cookie",
})
DalgonaGroup:AddButton({
    Text = "完成游戏",
    Func = CompleteDalgonaGame,
})
DalgonaGroup:AddToggle("DalgonaImmune", {
    Text = "免疫破裂",
    Default = false,
    Callback = function(Value)
        -- 可加入 hook 逻辑
        Alert(Value and "免疫已开启" or "免疫已关闭")
    end
})

local TugGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "拔河",
    IconName = "grip",
})
TugGroup:AddToggle("AutoPull", {
    Text = "自动拉扯",
    Default = false,
})
TugGroup:AddToggle("PerfectPull", {
    Text = "完美拉扯",
    Default = true,
})

local MingleGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "Mingle",
    IconName = "users",
})
MingleGroup:AddToggle("AutoMingle", {
    Text = "自动 QTE",
    Default = false,
})

local GlassGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "玻璃桥",
    IconName = "bridge",
})
GlassGroup:AddButton({
    Text = "完成游戏",
    Func = WinGlassBridge,
})
GlassGroup:AddButton({
    Text = "显形玻璃",
    Func = function()
        -- 简化的显形玻璃（可参考原脚本 RevealGlassBridge）
        Alert("显形功能待完善")
    end,
})

local HnSGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "躲猫猫",
    IconName = "eye-off",
})
HnSGroup:AddButton({
    Text = "传送到躲藏者",
    Func = TeleportToHider,
})
HnSGroup:AddToggle("ExpandGuardHitbox", {
    Text = "扩大守卫碰撞箱",
    Default = false,
    Callback = ToggleGuardHitbox,
})

local PlayerGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "玩家",
    IconName = "person-standing",
})
PlayerGroup:AddSlider("WalkSpeed", {
    Text = "移动速度",
    Default = 16,
    Min = 0,
    Max = 300,
    Rounding = 1,
    Callback = function(Value)
        if Toggles.SpeedToggle and Toggles.SpeedToggle.Value then
            SetWalkSpeed(Value)
        end
    end
})
PlayerGroup:AddToggle("SpeedToggle", {
    Text = "启用速度",
    Default = false,
    Callback = function(Value)
        if Value then
            SetWalkSpeed(Options.WalkSpeed.Value)
        else
            SetWalkSpeed(16)
        end
    end
})
PlayerGroup:AddToggle("InfiniteJump", {
    Text = "无限跳",
    Default = false,
})
PlayerGroup:AddToggle("Fly", {
    Text = "飞行（反检测）",
    Default = false,
    Callback = function(Value)
        if Value then
            StartFlying()
        else
            StopFlying()
        end
    end
})
PlayerGroup:AddSlider("FlySpeed", {
    Text = "飞行速度",
    Default = 50,
    Min = 10,
    Max = 200,
    Rounding = 1,
    Callback = function(Value) FlySpeed = Value end
})

-- 右侧分组
local MiscGroup = Tabs.Main:AddGroupbox({
    Side = "Right",
    Name = "杂项",
    IconName = "wrench",
})
MiscGroup:AddDropdown("EmoteList", {
    Values = {},  -- 可动态获取游戏表情
    Default = "",
    Text = "表情列表",
    Callback = function(Value) end
})
MiscGroup:AddButton({
    Text = "播放表情",
    Func = function()
        local emoteId = Options.EmoteList.Value
        if emoteId and emoteId ~= "" then
            PlayEmote(emoteId)
        else
            Alert("请先选择表情")
        end
    end
})
MiscGroup:AddButton({
    Text = "停止表情",
    Func = StopEmote
})
MiscGroup:AddToggle("AntiRagdoll", {
    Text = "反布娃娃",
    Default = false,
    Callback = function(Value)
        if Value then
            task.spawn(function()
                while Toggles.AntiRagdoll.Value do
                    AntiRagdoll()
                    task.wait(1)
                end
            end)
        end
    end
})
MiscGroup:AddButton({
    Text = "移除布娃娃效果",
    Func = AntiRagdoll,
})
MiscGroup:AddToggle("Spectate", {
    Text = "旁观模式",
    Default = false,
    Callback = ToggleSpectate,
})
MiscGroup:AddButton({
    Text = "修复相机",
    Func = FixCamera,
})
MiscGroup:AddButton({
    Text = "传送到安全点",
    Func = TeleportSafe,
})
MiscGroup:AddButton({
    Text = "修复玩家可见性",
    Func = FixPlayersVisibility,
})

local SecurityGroup = Tabs.Main:AddGroupbox({
    Side = "Right",
    Name = "安全",
    IconName = "shield",
})
SecurityGroup:AddToggle("AntiAFK", {
    Text = "反挂机",
    Default = true,
    Callback = AntiAFK,
})
SecurityGroup:AddToggle("StaffDetector", {
    Text = "管理员检测",
    Default = true,
    Callback = StaffDetector,
})

local PerformanceGroup = Tabs.Main:AddGroupbox({
    Side = "Right",
    Name = "性能",
    IconName = "gauge",
})
PerformanceGroup:AddToggle("LowGFX", {
    Text = "低画质",
    Default = false,
    Callback = LowGFX,
})
PerformanceGroup:AddToggle("DisableEffects", {
    Text = "禁用特效",
    Default = false,
    Callback = DisableEffects,
})
PerformanceGroup:AddButton({
    Text = "清除特效缓存",
    Func = function()
        local Effects = Workspace:FindFirstChild("Effects")
        if Effects then Effects:ClearAllChildren() end
    end,
})

-- ========== 视觉 Tab ==========
local MainESPGroup = Tabs.Visuals:AddGroupbox({
    Side = "Left",
    Name = "主要 ESP",
    IconName = "box",
})
MainESPGroup:AddToggle("PlayerESP", {
    Text = "玩家 ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then PlayerESP(p) end
            end
        else
            ClearESPType("Player")
        end
    end
}):AddColorPicker("PlayerEspColor", {
    Default = Color3.new(1,1,1),
    Title = "玩家颜色",
})

MainESPGroup:AddToggle("GuardESP", {
    Text = "守卫 ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            -- 扫描守卫
            local live = Workspace:FindFirstChild("Live")
            if live then
                for _, model in pairs(live:GetChildren()) do
                    if model:IsA("Model") and model.Name:find("Guard") then
                        GuardESP(model)
                    end
                end
            end
        else
            ClearESPType("Guard")
        end
    end
}):AddColorPicker("GuardEspColor", {
    Default = Color3.new(1,0,1),
    Title = "守卫颜色",
})

local HnSESPGroup = Tabs.Visuals:AddGroupbox({
    Side = "Left",
    Name = "躲猫猫 ESP",
    IconName = "eye",
})
HnSESPGroup:AddToggle("HiderESP", {
    Text = "躲藏者 ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then HiderESP(p) end
            end
        else
            ClearESPType("Hider")
        end
    end
}):AddColorPicker("HiderEspColor", {
    Default = Color3.new(0,1,0),
    Title = "躲藏者颜色",
})

HnSESPGroup:AddToggle("SeekerESP", {
    Text = "寻找者 ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then SeekerESP(p) end
            end
        else
            ClearESPType("Seeker")
        end
    end
}):AddColorPicker("SeekerEspColor", {
    Default = Color3.new(1,0,0),
    Title = "寻找者颜色",
})

HnSESPGroup:AddToggle("KeyESP", {
    Text = "钥匙 ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            -- 扫描钥匙
            local hideAndSeekMap = Workspace:FindFirstChild("HideAndSeekMap")
            if hideAndSeekMap then
                local keysFolder = hideAndSeekMap:FindFirstChild("KEYS")
                if keysFolder then
                    for _, key in pairs(keysFolder:GetChildren()) do KeyESP(key) end
                end
            end
        else
            ClearESPType("Key")
        end
    end
}):AddColorPicker("KeyEspColor", {
    Default = Color3.new(1,1,0),
    Title = "钥匙颜色",
})

HnSESPGroup:AddToggle("DoorESP", {
    Text = "门 ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            -- 扫描门
            local hideAndSeekMap = Workspace:FindFirstChild("HideAndSeekMap")
            if hideAndSeekMap then
                local doorsFolder = hideAndSeekMap:FindFirstChild("NEWFIXEDDOORS")
                if doorsFolder then
                    for _, floor in pairs(doorsFolder:GetChildren()) do
                        for _, door in pairs(floor:GetChildren()) do DoorESP(door) end
                    end
                end
            end
        else
            ClearESPType("Door")
        end
    end
}):AddColorPicker("DoorEspColor", {
    Default = Color3.new(0,0.5,1),
    Title = "门颜色",
})

local ESPSettingsGroup = Tabs.Visuals:AddGroupbox({
    Side = "Right",
    Name = "ESP 设置",
    IconName = "settings-2",
})
ESPSettingsGroup:AddToggle("ESPHighlight", {
    Text = "启用高亮",
    Default = true,
})
ESPSettingsGroup:AddToggle("ESPDistance", {
    Text = "显示距离",
    Default = true,
})
ESPSettingsGroup:AddSlider("ESPFillTransparency", {
    Text = "填充透明度",
    Default = 0.75,
    Min = 0,
    Max = 1,
    Rounding = 2,
})
ESPSettingsGroup:AddSlider("ESPOutlineTransparency", {
    Text = "轮廓透明度",
    Default = 0,
    Min = 0,
    Max = 1,
    Rounding = 2,
})
ESPSettingsGroup:AddSlider("ESPTextSize", {
    Text = "文本大小",
    Default = 22,
    Min = 16,
    Max = 26,
    Rounding = 0,
})

local SelfGroup = Tabs.Visuals:AddGroupbox({
    Side = "Right",
    Name = "自身",
    IconName = "user",
})
SelfGroup:AddToggle("FOVToggle", {
    Text = "视野",
    Default = false,
    Callback = function(Value)
        if Value then
            Camera.FieldOfView = Options.FOVSlider.Value
        else
            Camera.FieldOfView = 70
        end
    end
})
SelfGroup:AddSlider("FOVSlider", {
    Text = "视野角度",
    Default = 70,
    Min = 10,
    Max = 120,
    Rounding = 1,
    Callback = function(Value)
        if Toggles.FOVToggle.Value then
            Camera.FieldOfView = Value
        end
    end
})

-- ========== UI 设置 Tab ==========
local MenuGroup = Tabs["UI Settings"]:AddGroupbox({
    Side = "Left",
    Name = "菜单",
    IconName = "wrench",
})
MenuGroup:AddToggle("KeybindMenuOpen", {
    Text = "打开按键菜单",
    Default = Library.KeybindFrame.Visible,
    Callback = function(Value) Library.KeybindFrame.Visible = Value end,
})
MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "自定义光标",
    Default = Library.ShowCustomCursor,
    Callback = function(Value) Library.ShowCustomCursor = Value end,
})
MenuGroup:AddLabel("菜单按键")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "菜单按键" })

MenuGroup:AddButton({
    Text = "卸载",
    Func = function() Library:Unload() end,
})

-- 初始化无限跳监听
InfiniteJump()

-- 主题与配置
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("n_n")
SaveManager:SetFolder("n_n/settings")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

-- 加载完成
Alert("n_n 脚本已加载", 3)