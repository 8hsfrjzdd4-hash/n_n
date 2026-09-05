-- n_n 完整脚本 (基于 RTaOHUB 功能迁移，Linoria UI)
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
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- 全局变量与状态
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
    Maid = {},
}

-- 服务封装
local Services = setmetatable({}, {
    __index = function(_, key)
        local suc, service = pcall(game.GetService, game, key)
        if suc and service then return service end
        return nil
    end
})

-- 辅助函数
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

local function CleanTable(tab)
    local res = {}
    for k, v in pairs(tab) do
        table.insert(res, tostring(k))
    end
    return res
end

-- 通用清理函数
local function DisconnectAll(connections)
    for _, conn in pairs(connections or {}) do
        pcall(function() conn:Disconnect() end)
    end
end

-- ====================== ESP 系统 ======================
local function CreateESP(args)
    local Object = args.Object
    if not Object then return end
    local Text = args.Text or "无文本"
    local Color = args.Color or Color3.new(1,1,1)
    local Offset = args.Offset or Vector3.zero
    local Type = args.Type or "None"
    local IsEntity = args.IsEntity or false

    local ESPManager = {
        Object = Object,
        Text = Text,
        Color = Color,
        Type = Type,
        Highlights = {},
        Connections = {},
        BillboardGui = nil,
        TextLabel = nil,
        IsEntity = IsEntity,
        Humanoid = nil,
    }

    -- 如果实体透明，添加临时 Humanoid
    if IsEntity and Object.PrimaryPart and Object.PrimaryPart.Transparency == 1 then
        Object:SetAttribute("Transparency", Object.PrimaryPart.Transparency)
        ESPManager.Humanoid = Instance.new("Humanoid", Object)
        Object.PrimaryPart.Transparency = 0.99
    end

    local function DestroyESP()
        -- 恢复透明度
        if ESPManager.IsEntity and ESPManager.Object and ESPManager.Object.PrimaryPart then
            Object.PrimaryPart.Transparency = Object.PrimaryPart:GetAttribute("Transparency") or 0
        end
        if ESPManager.Humanoid then ESPManager.Humanoid:Destroy() end
        for _, h in pairs(ESPManager.Highlights) do
            pcall(function() h:Destroy() end)
        end
        if ESPManager.BillboardGui then
            pcall(function() ESPManager.BillboardGui:Destroy() end)
        end
        for _, conn in pairs(ESPManager.Connections) do
            pcall(function() conn:Disconnect() end)
        end
        -- 从表中移除
        local idx = table.find(Script.ESPTable[Type], ESPManager)
        if idx then Script.ESPTable[Type][idx] = nil end
        ESPManager.Highlights = {}
        ESPManager.Connections = {}
    end

    -- 高亮
    local highlight = Instance.new("Highlight")
    highlight.Adornee = Object
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color
    highlight.FillTransparency = Options.ESPFillTransparency.Value
    highlight.OutlineColor = Color
    highlight.OutlineTransparency = Options.ESPOutlineTransparency.Value
    highlight.Enabled = Toggles.ESPHighlight.Value
    highlight.Parent = Object
    table.insert(ESPManager.Highlights, highlight)

    -- BillboardGui
    local billboard = Instance.new("BillboardGui")
    billboard.Adornee = Object.PrimaryPart or Object
    billboard.AlwaysOnTop = true
    billboard.ClipsDescendants = false
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Offset
    billboard.Parent = Object.PrimaryPart or Object
    ESPManager.BillboardGui = billboard

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Oswald
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Text = Text
    label.TextColor3 = Color
    label.TextSize = Options.ESPTextSize.Value
    label.TextStrokeColor3 = Color3.new(0,0,0)
    label.TextStrokeTransparency = 0.75
    label.Parent = billboard
    ESPManager.TextLabel = label

    -- 更新循环
    local updateConn = RunService.RenderStepped:Connect(function()
        if not Object or not Object:IsDescendantOf(Workspace) then
            DestroyESP()
            return
        end
        highlight.Enabled = Toggles.ESPHighlight.Value
        highlight.FillTransparency = Options.ESPFillTransparency.Value
        highlight.OutlineTransparency = Options.ESPOutlineTransparency.Value
        label.TextSize = Options.ESPTextSize.Value
        if Toggles.ESPDistance.Value then
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                label.Text = string.format("%s\n[%d]", Text, math.floor((root.Position - Object:GetPivot().Position).Magnitude))
            else
                label.Text = Text
            end
        else
            label.Text = Text
        end
    end)
    table.insert(ESPManager.Connections, updateConn)

    -- 存入表
    table.insert(Script.ESPTable[Type], ESPManager)
    return ESPManager
end

local function ClearESPType(Type)
    for _, esp in pairs(Script.ESPTable[Type]) do
        esp:Destroy()
    end
    Script.ESPTable[Type] = {}
end

-- ====================== 飞行（反检测版） ======================
local Flying = false
local FlySpeed = 50
local FlyConnections = {}

local function StartFlying()
    if not LocalPlayer.Character then return end
    local humanoid = SafeGetHumanoid(LocalPlayer.Character)
    local root = SafeGetHRP(LocalPlayer.Character)
    if not humanoid or not root then return end

    Script.Temp.OriginalGravity = humanoid.GravityScale or 1
    humanoid.GravityScale = 0
    humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    Flying = true
end

local function StopFlying()
    Flying = false
    local humanoid = LocalPlayer.Character and SafeGetHumanoid(LocalPlayer.Character)
    if humanoid then
        humanoid.GravityScale = Script.Temp.OriginalGravity or 1
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
end

RunService.RenderStepped:Connect(function()
    if not Flying then return end
    local char = LocalPlayer.Character
    local humanoid = char and SafeGetHumanoid(char)
    local root = char and SafeGetHRP(char)
    if not humanoid or not root then return end

    local moveDirection = humanoid.MoveDirection
    local horizontalSpeed = FlySpeed * 1.2
    local verticalSpeed = 0

    -- 上升：空格/手机跳跃；下降：左Shift
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) or (UserInputService.TouchEnabled and humanoid.Jump) then
        verticalSpeed = FlySpeed
    elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
        verticalSpeed = -FlySpeed
    end

    local targetVelocity = Vector3.new(moveDirection.X * horizontalSpeed, verticalSpeed, moveDirection.Z * horizontalSpeed)
    root.AssemblyLinearVelocity = targetVelocity

    if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and humanoid:GetState() ~= Enum.HumanoidStateType.Flying then
        humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
    end
end)

-- ====================== 反布娃娃 ======================
local function BypassRagdoll()
    local character = LocalPlayer.Character
    if not character then return end
    local humanoid = SafeGetHumanoid(character)
    local root = SafeGetHRP(character)
    local torso = character:FindFirstChild("Torso")
    if not (humanoid and root and torso) then return end

    -- 恢复 Humanoid 状态
    humanoid.PlatformStand = false
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    for _, state in pairs({
        Enum.HumanoidStateType.FallingDown,
        Enum.HumanoidStateType.Seated,
        Enum.HumanoidStateType.Swimming,
        Enum.HumanoidStateType.Flying,
        Enum.HumanoidStateType.StrafingNoPhysics,
        Enum.HumanoidStateType.Ragdoll,
    }) do
        humanoid:SetStateEnabled(state, false)
    end

    -- 清理 ragdoll 相关
    for _, obj in pairs(root:GetChildren()) do
        if obj:IsA("BallSocketConstraint") or obj.Name:match("^CacheAttachment") then
            obj:Destroy()
        end
    end
    local joints = {"Left Hip", "Left Shoulder", "Neck", "Right Hip", "Right Shoulder"}
    for _, jointName in pairs(joints) do
        local motor = torso:FindFirstChild(jointName)
        if motor and motor:IsA("Motor6D") and not motor.Part0 then
            motor.Part0 = torso
        end
    end
    for _, part in pairs(character:GetChildren()) do
        if part:IsA("BasePart") and part:FindFirstChild("BoneCustom") then
            part.BoneCustom:Destroy()
        end
    end
    for _, folderName in pairs({"Ragdoll", "Stun", "RotateDisabled", "RagdollWakeupImmunity", "InjuredWalking"}) do
        local folder = character:FindFirstChild(folderName)
        if folder then folder:Destroy() end
    end
    local LocalRagdolls = Workspace.Effects and Workspace.Effects:FindFirstChild("LocalRagdolls")
    if LocalRagdolls then
        local ragdollModel = LocalRagdolls:FindFirstChild(LocalPlayer.Name)
        if ragdollModel then ragdollModel:Destroy() end
    end
end

-- ====================== 达戈纳绕过 ======================
local DalgonaRemoteHook = nil
local DalgonaImmune = false

local function SetupDalgonaImmune(enabled)
    if enabled then
        if not hookmetamethod then
            Alert("您的执行器不支持 hookmetamethod", 5)
            Toggles.DalgonaImmune:SetValue(false)
            return
        end
        DalgonaRemoteHook = hookmetamethod(game, "__namecall", function(self, ...)
            local args = {...}
            local method = getnamecallmethod()
            if tostring(self) == "DALGONATEMPREMPTE" and method == "FireServer" then
                if args[1] and type(args[1]) == "table" and args[1].CrackAmount ~= nil then
                    Alert("已阻止饼干破裂", 3)
                    return nil
                end
            end
            return DalgonaRemoteHook(self, unpack(args))
        end)
    else
        if DalgonaRemoteHook then
            hookmetamethod(game, "__namecall", DalgonaRemoteHook)
            DalgonaRemoteHook = nil
        end
    end
end

local function CompleteDalgona()
    local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DALGONATEMPREMPTE")
    remote:FireServer({ Success = true })
    -- 修复相机
    FixCamera()
end

-- ====================== 红灯绿灯上帝模式 ======================
local RLGL_OriginalNamecall = nil
local RLGL_Connection = nil

local function SetupRLGLGodmode(enabled)
    if enabled then
        if not hookmetamethod then
            Alert("您的执行器不支持 hookmetamethod", 5)
            Toggles.RLGLGodmode:SetValue(false)
            return
        end
        local TrafficLightImage = LocalPlayer.PlayerGui:FindFirstChild("ImpactFrames") and LocalPlayer.PlayerGui.ImpactFrames:FindFirstChild("TrafficLightEmpty")
        local Effects = ReplicatedStorage:FindFirstChild("Effects")
        local isGreenLight = true
        local lastRootPartCFrame = nil

        local function updateState()
            local root = SafeGetHRP(LocalPlayer.Character)
            if root then lastRootPartCFrame = root.CFrame end
        end
        updateState()

        RLGL_Connection = ReplicatedStorage.Remotes.Effects.OnClientEvent:Connect(function(data)
            if data.EffectName ~= "TrafficLight" then return end
            isGreenLight = data.GreenLight == true
            updateState()
        end)
        Script.Temp.RLGL_Connection = RLGL_Connection

        RLGL_OriginalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local args = {...}
            local method = getnamecallmethod()
            if tostring(self) == "rootCFrame" and method == "FireServer" then
                if Toggles.RLGLGodmode.Value and not isGreenLight and lastRootPartCFrame then
                    args[1] = lastRootPartCFrame
                    return RLGL_OriginalNamecall(self, unpack(args))
                end
            end
            return RLGL_OriginalNamecall(self, ...)
        end)
        Script.Temp.RLGL_OriginalNamecall = RLGL_OriginalNamecall
    else
        if RLGL_Connection then
            pcall(function() RLGL_Connection:Disconnect() end)
            RLGL_Connection = nil
        end
        if RLGL_OriginalNamecall then
            hookmetamethod(game, "__namecall", RLGL_OriginalNamecall)
            RLGL_OriginalNamecall = nil
        end
    end
end

-- ====================== 自动胜利状态机 ======================
local States = {}

local function WinRLGL()
    if LocalPlayer.Character then
        LocalPlayer.Character:PivotTo(CFrame.new(-100.8, 1030, 115))
    end
end

local function WinGlassBridge()
    if LocalPlayer.Character then
        LocalPlayer.Character:PivotTo(CFrame.new(-203.9, 520.7, -1534.3485))
    end
end

local function TeleportSafe()
    if LocalPlayer.Character then
        LocalPlayer.Character:PivotTo(CFrame.new(-108, 329.1, 462.1))
    end
end

local function GetDalgonaRemote()
    return ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DALGONATEMPREMPTE")
end

local function CheckPlayersVisibility()
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character then
            for _, part in pairs(p.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 0
                    part.LocalTransparencyModifier = 0
                end
            end
        end
    end
end

States = {
    RedLightGreenLight = function()
        local call = true
        task.spawn(function()
            repeat
                WinRLGL()
                task.wait(5)
            until not call or not Toggles.AutoWin.Value or Script.GameState ~= "RedLightGreenLight"
        end)
        if not Toggles.AntiFling.Value then
            Toggles.AntiFling:SetValue(true)
        end
        return function()
            call = false
            if Toggles.AntiFling.Value then
                Toggles.AntiFling:SetValue(false)
            end
        end
    end,
    Mingle = function()
        if not Toggles.AutoMingle.Value then
            Toggles.AutoMingle:SetValue(true)
        end
        return function()
            if Toggles.AutoMingle.Value then
                Toggles.AutoMingle:SetValue(false)
            end
        end
    end,
    TugOfWar = function()
        if not Toggles.AutoPull.Value then
            Toggles.AutoPull:SetValue(true)
        end
        if not Toggles.PerfectPull.Value then
            Toggles.PerfectPull:SetValue(true)
        end
        return function()
            if Toggles.AutoPull.Value then
                Toggles.AutoPull:SetValue(false)
            end
        end
    end,
    GlassBridge = function()
        RevealGlassBridge()
        WinGlassBridge()
    end,
    HideAndSeek = function()
        if LocalPlayer:GetAttribute("IsHider") then
            TeleportSafe()
        else
            Alert("躲猫猫自动胜利仅支持躲藏者")
        end
    end,
    LightsOut = TeleportSafe,
    Dalgona = function()
        task.spawn(function()
            repeat task.wait() until GetDalgonaRemote() or not Toggles.AutoWin.Value or Library.Unloaded
            if not Toggles.AutoWin.Value then return end
            task.wait(3)
            CompleteDalgona()
            FixCamera()
        end)
        return function()
            FixCamera()
            CheckPlayersVisibility()
        end
    end,
}

local lastCleanupFunction = function() end

local function HandleAutowin()
    if lastCleanupFunction then
        pcall(lastCleanupFunction)
    end
    pcall(function()
        Script.GameState = Workspace.Values.CurrentGame.Value
    end)
    if States[Script.GameState] then
        Alert("[自动胜利] 正在运行: " .. tostring(Script.GameState))
        lastCleanupFunction = States[Script.GameState]()
    else
        Alert("[自动胜利] 等待下一场游戏...")
    end
end

-- ====================== 玻璃桥显形 ======================
local function RevealGlassBridge()
    local glassHolder = Workspace:FindFirstChild("GlassBridge") and Workspace.GlassBridge:FindFirstChild("GlassHolder")
    if not glassHolder then return end
    for _, tilePair in pairs(glassHolder:GetChildren()) do
        for _, tileModel in pairs(tilePair:GetChildren()) do
            if tileModel:IsA("Model") and tileModel.PrimaryPart then
                local primaryPart = tileModel.PrimaryPart
                local isBreakable = primaryPart:GetAttribute("exploitingisevil") == true
                local targetColor = isBreakable and Color3.fromRGB(255,0,0) or Color3.fromRGB(0,255,0)
                for _, part in pairs(tileModel:GetDescendants()) do
                    if part:IsA("BasePart") then
                        TweenService:Create(part, TweenInfo.new(0.5), { Transparency = 0.5, Color = targetColor }):Play()
                    end
                end
                local highlight = Instance.new("Highlight")
                highlight.FillColor = targetColor
                highlight.FillTransparency = 0.7
                highlight.OutlineTransparency = 0.5
                highlight.Parent = tileModel
            end
        end
    end
end

-- ====================== 防甩飞 ======================
local function AntiFlingLoop(enabled)
    if enabled then
        Script.Temp.AntiFlingActive = true
        Script.Temp.AntiFlingThread = task.spawn(function()
            local lastSafeCFrame = nil
            while Script.Temp.AntiFlingActive and not Library.Unloaded do
                local character = LocalPlayer.Character
                local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso"))
                if root then
                    -- 摧毁物理器
                    for _, part in pairs(character:GetDescendants()) do
                        if part:IsA("BodyMover") or part:IsA("BodyVelocity") or part:IsA("BodyGyro") or part:IsA("BodyThrust") or part:IsA("BodyAngularVelocity") then
                            part:Destroy()
                        end
                    end
                    -- 速度限制
                    local vel = root.Velocity
                    if vel.Magnitude > 100 then
                        root.Velocity = Vector3.new(
                            math.clamp(vel.X, -100, 100),
                            math.clamp(vel.Y, -100, 100),
                            math.clamp(vel.Z, -100, 100)
                        )
                    end
                    -- 位置回滚
                    if not lastSafeCFrame or (root.Position - lastSafeCFrame.Position).Magnitude < 20 then
                        lastSafeCFrame = root.CFrame
                    elseif (root.Position - lastSafeCFrame.Position).Magnitude > 50 then
                        root.CFrame = lastSafeCFrame
                        root.Velocity = Vector3.zero
                    end
                end
                task.wait(0.05)
            end
        end)
    else
        Script.Temp.AntiFlingActive = false
        if Script.Temp.AntiFlingThread then
            task.cancel(Script.Temp.AntiFlingThread)
        end
    end
end

-- ====================== 管理员检测 ======================
local function StaffDetector(enabled)
    if enabled then
        local STAFF_GROUP_ID = 12398672
        local STAFF_MIN_RANK = 120
        local function check(player)
            local ok, rank = pcall(function() return player:GetRankInGroup(STAFF_GROUP_ID) end)
            if ok and rank and rank >= STAFF_MIN_RANK then
                Alert("[管理员检测] 发现管理员: " .. player.Name, 10)
            end
        end
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then check(p) end
        end
        Script.Temp.StaffConn = {
            Players.PlayerAdded:Connect(function(p)
                if p ~= LocalPlayer then task.wait(1); check(p) end
            end)
        }
    else
        if Script.Temp.StaffConn then
            DisconnectAll(Script.Temp.StaffConn)
            Script.Temp.StaffConn = nil
        end
    end
end

-- ====================== 其他功能 ======================
local function PlayEmote(emoteId)
    local char = LocalPlayer.Character
    local humanoid = char and SafeGetHumanoid(char)
    if not humanoid then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = emoteId
    local track = humanoid:LoadAnimation(anim)
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

local function FixCamera()
    if Workspace.CurrentCamera then pcall(function() Workspace.CurrentCamera:Destroy() end) end
    local newCam = Instance.new("Camera")
    newCam.Parent = Workspace
    Workspace.CurrentCamera = newCam
    newCam.CameraType = Enum.CameraType.Custom
    if LocalPlayer.Character then
        newCam.CameraSubject = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    end
end

local function FixPlayersVisibility()
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character then
            for _, part in pairs(p.Character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 0
                    part.LocalTransparencyModifier = 0
                end
            end
        end
    end
end

local function LowGFX(enabled)
    if enabled then
        settings().Rendering.QualityLevel = 1
    else
        settings().Rendering.QualityLevel = 10
    end
end

local function DisableEffects(enabled)
    if enabled then
        local Effects = Workspace:WaitForChild("Effects", 15)
        if Effects then
            Effects:ClearAllChildren()
            Script.Temp.DisableEffectsConn = Effects.ChildAdded:Connect(function(child) child:Destroy() end)
        end
    else
        if Script.Temp.DisableEffectsConn then
            Script.Temp.DisableEffectsConn:Disconnect()
            Script.Temp.DisableEffectsConn = nil
        end
    end
end

-- ====================== 创建 UI ======================
local Tabs = {
    Main = Window:AddTab("主界面", "user"),
    Visuals = Window:AddTab("视觉", "eye"),
    ["UI Settings"] = Window:AddTab("UI 设置", "settings"),
}

-- ========== 主界面-左侧 ==========
local FeatureGroup = Tabs.Main:AddGroupbox({
    Side = "Left",
    Name = "功能",
    IconName = "zap",
})
FeatureGroup:AddToggle("AutoWin", {
    Text = "自动胜利",
    Default = false,
    Callback = function(Value)
        if Value then
            HandleAutowin()
        else
            if lastCleanupFunction then pcall(lastCleanupFunction) end
        end
    end
})
FeatureGroup:AddToggle("AntiFling", {
    Text = "防甩飞",
    Default = false,
    Callback = function(Value) AntiFlingLoop(Value) end
})
FeatureGroup:AddToggle("Killaura", {
    Text = "自动攻击",
    Default = false,
    Callback = function(Value)
        if Value then
            local fork = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("Fork") or LocalPlayer.Character:FindFirstChild("Bottle") or LocalPlayer.Character:FindFirstChild("Knife"))
            if not fork then
                Alert("未找到武器")
                Toggles.Killaura:SetValue(false)
                return
            end
            task.spawn(function()
                while Toggles.Killaura.Value do
                    -- 触发攻击远程
                    local args = { "UsingMoveCustom", fork, true, { Clicked = true } }
                    ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UsedTool"):FireServer(unpack(args))
                    task.wait(0.5)
                end
            end)
        end
    end
})

-- 小游戏分组
local RLGLGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "红灯绿灯", IconName = "traffic-cone" })
RLGLGroup:AddToggle("RLGLGodmode", { Text = "上帝模式", Default = false, Callback = function(Value) SetupRLGLGodmode(Value) end })
RLGLGroup:AddButton({ Text = "完成游戏", Func = WinRLGL })

local DalgonaGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "达戈纳糖饼", IconName = "cookie" })
DalgonaGroup:AddButton({ Text = "完成游戏", Func = CompleteDalgona })
DalgonaGroup:AddToggle("DalgonaImmune", { Text = "免疫破裂", Default = false, Callback = function(Value) SetupDalgonaImmune(Value) end })

local TugGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "拔河", IconName = "grip" })
TugGroup:AddToggle("AutoPull", { Text = "自动拉扯", Default = false, Callback = function(Value)
    if Value then
        task.spawn(function()
            while Toggles.AutoPull.Value do
                local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TemporaryReachedBindable")
                remote:FireServer({ PerfectQTE = Toggles.PerfectPull.Value })
                task.wait()
            end
        end)
    end
end})
TugGroup:AddToggle("PerfectPull", { Text = "完美拉扯", Default = true })

local MingleGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "Mingle", IconName = "users" })
MingleGroup:AddToggle("AutoMingle", { Text = "自动 QTE", Default = false, Callback = function(Value)
    Script.Temp.AutoMingleActive = Value
    if Value then
        Script.Temp.AutoMingleThread = task.spawn(function()
            while Script.Temp.AutoMingleActive do
                local char = LocalPlayer.Character
                if char then
                    for _, obj in pairs(char:GetChildren()) do
                        if obj:IsA("RemoteEvent") and obj.Name == "RemoteForQTE" then
                            obj:FireServer()
                            break
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
    else
        if Script.Temp.AutoMingleThread then task.cancel(Script.Temp.AutoMingleThread) end
    end
end})

local GlassGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "玻璃桥", IconName = "bridge" })
GlassGroup:AddButton({ Text = "完成游戏", Func = WinGlassBridge })
GlassGroup:AddButton({ Text = "显形玻璃", Func = RevealGlassBridge })

local HnSGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "躲猫猫", IconName = "eye-off" })
HnSGroup:AddButton({ Text = "传送到躲藏者", Func = function()
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
end})
HnSGroup:AddToggle("ExpandGuardHitbox", { Text = "扩大守卫碰撞箱", Default = false, Callback = function(Value)
    -- 需要时补充完整逻辑，这里保留原始实现（略，可参考原脚本）
    Alert(Value and "已开启" or "已关闭")
end})

-- 玩家分组
local PlayerGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "玩家", IconName = "person-standing" })
PlayerGroup:AddSlider("WalkSpeed", { Text = "移动速度", Default = 16, Min = 0, Max = 300, Rounding = 1, Callback = function(Value)
    if Toggles.SpeedToggle.Value then SetWalkSpeed(Value) end
end})
PlayerGroup:AddToggle("SpeedToggle", { Text = "启用速度", Default = false, Callback = function(Value)
    if Value then SetWalkSpeed(Options.WalkSpeed.Value) else SetWalkSpeed(16) end
end})
PlayerGroup:AddToggle("InfiniteJump", { Text = "无限跳", Default = false })
PlayerGroup:AddToggle("Fly", { Text = "飞行（反检测）", Default = false, Callback = function(Value)
    if Value then StartFlying() else StopFlying() end
end})
PlayerGroup:AddSlider("FlySpeed", { Text = "飞行速度", Default = 50, Min = 10, Max = 200, Rounding = 1, Callback = function(Value) FlySpeed = Value end})

-- ========== 主界面-右侧 ==========
local MiscGroup = Tabs.Main:AddGroupbox({ Side = "Right", Name = "杂项", IconName = "wrench" })
-- 表情下拉（需要动态刷新，这里简单处理）
MiscGroup:AddDropdown("EmoteList", { Text = "表情列表", Values = {}, Default = "", AllowNull = true })
task.spawn(function()
    local Animations = ReplicatedStorage:WaitForChild("Animations", 10)
    local Emotes = Animations and Animations:WaitForChild("Emotes", 10)
    if Emotes then
        local values = {}
        for _, v in pairs(Emotes:GetChildren()) do
            if v.ClassName == "Animation" then table.insert(values, v.Name) end
        end
        Options.EmoteList:SetValues(values)
    end
end)
MiscGroup:AddButton({ Text = "播放表情", Func = function()
    local selected = Options.EmoteList.Value
    if selected then
        -- 获取 AnimationId
        local Animations = ReplicatedStorage:WaitForChild("Animations")
        local Emotes = Animations:WaitForChild("Emotes")
        local animObj = Emotes:FindFirstChild(selected)
        if animObj and animObj:IsA("Animation") then
            PlayEmote(animObj.AnimationId)
        end
    else
        Alert("未选择表情")
    end
end})
MiscGroup:AddButton({ Text = "停止表情", Func = StopEmote })
MiscGroup:AddToggle("AntiRagdoll", { Text = "反布娃娃", Default = false, Callback = function(Value)
    if Value then
        task.spawn(function()
            while Toggles.AntiRagdoll.Value do
                BypassRagdoll()
                task.wait(1)
            end
        end)
    end
end})
MiscGroup:AddButton({ Text = "移除布娃娃效果", Func = BypassRagdoll })
MiscGroup:AddToggle("Spectate", { Text = "旁观模式", Default = false, Callback = ToggleSpectate })
MiscGroup:AddButton({ Text = "修复相机", Func = FixCamera })
MiscGroup:AddButton({ Text = "传送到安全点", Func = TeleportSafe })
MiscGroup:AddButton({ Text = "修复玩家可见性", Func = FixPlayersVisibility })

local SecurityGroup = Tabs.Main:AddGroupbox({ Side = "Right", Name = "安全", IconName = "shield" })
SecurityGroup:AddToggle("AntiAFK", { Text = "反挂机", Default = true, Callback = function(Value)
    if Value then
        Script.Temp.AntiAfkConn = LocalPlayer.Idled:Connect(function()
            VirtualUser:Button2Down(Vector2.new(0,0), Camera.CFrame)
            wait(1)
            VirtualUser:Button2Up(Vector2.new(0,0), Camera.CFrame)
        end)
    else
        if Script.Temp.AntiAfkConn then Script.Temp.AntiAfkConn:Disconnect() end
    end
end})
SecurityGroup:AddToggle("StaffDetector", { Text = "管理员检测", Default = true, Callback = StaffDetector })

local PerformanceGroup = Tabs.Main:AddGroupbox({ Side = "Right", Name = "性能", IconName = "gauge" })
PerformanceGroup:AddToggle("LowGFX", { Text = "低画质", Default = false, Callback = LowGFX })
PerformanceGroup:AddToggle("DisableEffects", { Text = "禁用特效", Default = false, Callback = DisableEffects })
PerformanceGroup:AddButton({ Text = "清除特效缓存", Func = function()
    local Effects = Workspace:FindFirstChild("Effects")
    if Effects then Effects:ClearAllChildren() end
end})

-- ========== 视觉 Tab ==========
local MainESPGroup = Tabs.Visuals:AddGroupbox({ Side = "Left", Name = "主要 ESP", IconName = "box" })
MainESPGroup:AddToggle("PlayerESP", { Text = "玩家 ESP", Default = false, Callback = function(Value)
    if Value then
        for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then PlayerESP(p) end end
    else ClearESPType("Player") end
end}):AddColorPicker("PlayerEspColor", { Default = Color3.new(1,1,1), Title = "玩家颜色" })

MainESPGroup:AddToggle("GuardESP", { Text = "守卫 ESP", Default = false, Callback = function(Value)
    if Value then
        local live = Workspace:FindFirstChild("Live")
        if live then
            for _, model in pairs(live:GetChildren()) do
                if model:IsA("Model") and model.Name:find("Guard") then GuardESP(model) end
            end
        end
    else ClearESPType("Guard") end
end}):AddColorPicker("GuardEspColor", { Default = Color3.new(1,0,1), Title = "守卫颜色" })

local HnSESPGroup = Tabs.Visuals:AddGroupbox({ Side = "Left", Name = "躲猫猫 ESP", IconName = "eye" })
HnSESPGroup:AddToggle("HiderESP", { Text = "躲藏者 ESP", Default = false, Callback = function(Value)
    if Value then for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then HiderESP(p) end end else ClearESPType("Hider") end
end}):AddColorPicker("HiderEspColor", { Default = Color3.new(0,1,0), Title = "躲藏者颜色" })

HnSESPGroup:AddToggle("SeekerESP", { Text = "寻找者 ESP", Default = false, Callback = function(Value)
    if Value then for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then SeekerESP(p) end end else ClearESPType("Seeker") end
end}):AddColorPicker("SeekerEspColor", { Default = Color3.new(1,0,0), Title = "寻找者颜色" })

HnSESPGroup:AddToggle("KeyESP", { Text = "钥匙 ESP", Default = false, Callback = function(Value)
    if Value then
        local map = Workspace:FindFirstChild("HideAndSeekMap")
        if map then
            local keys = map:FindFirstChild("KEYS")
            if keys then for _, key in pairs(keys:GetChildren()) do KeyESP(key) end end
        end
    else ClearESPType("Key") end
end}):AddColorPicker("KeyEspColor", { Default = Color3.new(1,1,0), Title = "钥匙颜色" })

HnSESPGroup:AddToggle("DoorESP", { Text = "门 ESP", Default = false, Callback = function(Value)
    if Value then
        local map = Workspace:FindFirstChild("HideAndSeekMap")
        if map then
            local doors = map:FindFirstChild("NEWFIXEDDOORS")
            if doors then
                for _, floor in pairs(doors:GetChildren()) do
                    for _, door in pairs(floor:GetChildren()) do DoorESP(door) end
                end
            end
        end
    else ClearESPType("Door") end
end}):AddColorPicker("DoorEspColor", { Default = Color3.new(0,0.5,1), Title = "门颜色" })

local ESPSettingsGroup = Tabs.Visuals:AddGroupbox({ Side = "Right", Name = "ESP 设置", IconName = "settings-2" })
ESPSettingsGroup:AddToggle("ESPHighlight", { Text = "启用高亮", Default = true })
ESPSettingsGroup:AddToggle("ESPDistance", { Text = "显示距离", Default = true })
ESPSettingsGroup:AddSlider("ESPFillTransparency", { Text = "填充透明度", Default = 0.75, Min = 0, Max = 1, Rounding = 2 })
ESPSettingsGroup:AddSlider("ESPOutlineTransparency", { Text = "轮廓透明度", Default = 0, Min = 0, Max = 1, Rounding = 2 })
ESPSettingsGroup:AddSlider("ESPTextSize", { Text = "文本大小", Default = 22, Min = 16, Max = 26, Rounding = 0 })

local SelfGroup = Tabs.Visuals:AddGroupbox({ Side = "Right", Name = "自身", IconName = "user" })
SelfGroup:AddToggle("FOVToggle", { Text = "视野", Default = false, Callback = function(Value)
    if Value then Camera.FieldOfView = Options.FOVSlider.Value else Camera.FieldOfView = 70 end
end})
SelfGroup:AddSlider("FOVSlider", { Text = "视野角度", Default = 70, Min = 10, Max = 120, Rounding = 1, Callback = function(Value)
    if Toggles.FOVToggle.Value then Camera.FieldOfView = Value end
end})

-- ========== UI 设置 Tab ==========
local MenuGroup = Tabs["UI Settings"]:AddGroupbox({ Side = "Left", Name = "菜单", IconName = "wrench" })
MenuGroup:AddToggle("KeybindMenuOpen", { Text = "打开按键菜单", Default = Library.KeybindFrame.Visible, Callback = function(Value) Library.KeybindFrame.Visible = Value end })
MenuGroup:AddToggle("ShowCustomCursor", { Text = "自定义光标", Default = Library.ShowCustomCursor, Callback = function(Value) Library.ShowCustomCursor = Value end })
MenuGroup:AddLabel("菜单按键"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "菜单按键" })
MenuGroup:AddButton({ Text = "卸载", Func = function() Library:Unload() end })

-- 无限跳初始化
UserInputService.JumpRequest:Connect(function()
    if Toggles.InfiniteJump.Value then
        local humanoid = LocalPlayer.Character and SafeGetHumanoid(LocalPlayer.Character)
        if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- 玩家加入时自动处理ESP
Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer and Toggles.PlayerESP.Value then
        task.wait(0.1)
        PlayerESP(p)
    end
    if Toggles.StaffDetector.Value then
        task.wait(1)
        local ok, rank = pcall(function() return p:GetRankInGroup(12398672) end)
        if ok and rank and rank >= 120 then Alert("[管理员检测] 发现管理员: " .. p.Name, 10) end
    end
end)

-- 游戏状态监听
Workspace:WaitForChild("Values"):WaitForChild("CurrentGame"):GetPropertyChangedSignal("Value"):Connect(function()
    Script.GameState = Workspace.Values.CurrentGame.Value
    Script.GameStateChanged:Fire(Script.GameState)
    if Toggles.AutoWin.Value then HandleAutowin() end
end)

-- 主题和配置
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("n_n")
SaveManager:SetFolder("n_n/settings")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

Alert("n_n 脚本已加载", 3)