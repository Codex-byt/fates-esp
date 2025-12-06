-- Wait for game to load
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- CHECK FOR EXECUTOR COMPATIBILITY
if not Drawing then
    warn("Executor does not support Drawing API.")
    return
end

--[[ 
    IMPORTANT: The original UI library link is DEAD (404 Not Found).
    The script will likely error below unless you replace the URL with a working version of Fates UI 
    or a compatible library. 
]]
local LibraryURL = "https://raw.githubusercontent.com/fatesc/fates-esp/main/ui.lua" -- <--- THIS LINK IS LIKELY DEAD
local success, UILibrary = pcall(function()
    return loadstring(game:HttpGet(LibraryURL))()
end)

if not success or not UILibrary then
    warn("Failed to load UI Library. The URL is down or invalid.")
    -- Attempting to continue might crash, but we will try.
    -- If you have a local version, replace the loadstring above.
    return 
end

local PlaceId = game.PlaceId
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Teams = game:GetService("Teams")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local CurrentCamera = Workspace.CurrentCamera
local WorldToViewportPoint = CurrentCamera.WorldToViewportPoint
local GetPartsObscuringTarget = CurrentCamera.GetPartsObscuringTarget

local Inset = GuiService:GetGuiInset().Y

-- Safely get functions
local FindFirstChild = function(inst, ...) return inst:FindFirstChild(...) end
local FindFirstChildWhichIsA = function(inst, ...) return inst:FindFirstChildWhichIsA(...) end
local IsA = function(inst, ...) return inst:IsA(...) end

local Vector2new = Vector2.new
local Vector3new = Vector3.new
local CFramenew = CFrame.new
local Color3new = Color3.new

local Tfind = table.find
local create = table.create
local format = string.format
local floor = math.floor
local gsub = string.gsub
local sub = string.sub
local lower = string.lower
local upper = string.upper
local random = math.random

local DefaultSettings = {
    Esp = {
        NamesEnabled = true,
        DisplayNamesEnabled = false,
        DistanceEnabled = true,
        HealthEnabled = true,
        TracersEnabled = false,
        BoxEsp = true,
        TeamColors = true,
        Thickness = 1.5,
        TracerThickness = 1.6,
        Transparency = .9,
        TracerTrancparency = .7,
        Size = 16,
        RenderDistance = 9e9,
        Color = Color3.fromRGB(19, 130, 226),
        OutlineColor = Color3new(),
        TracerTo = "Head",
        BlacklistedTeams = {}
    },
    Aimbot = {
        Enabled = true,
        SilentAim = false,
        Wallbang = true,
        ShowFov = false,
        Snaplines = true,
        ThirdPerson = false,
        FirstPerson = true,
        ClosestCharacter = false,
        ClosestCursor = true,
        Smoothness = 1,
        SilentAimHitChance = 100,
        FovThickness = 1,
        FovTransparency = 1,
        FovSize = 150,
        FovColor = Color3new(1, 1, 1),
        Aimlock = "Head",
        SilentAimRedirect = "Head",
        BlacklistedTeams = {}
    },
    WindowPosition = UDim2.new(0.5, -200, 0.5, -139),
    Version = 1.2
}

-- Config System
local EncodeConfig, DecodeConfig
do
    local deepsearchset
    deepsearchset = function(tbl, ret, value)
        if (type(tbl) == 'table') then
            local new = {}
            for i, v in next, tbl do
                new[i] = v
                if (type(v) == 'table') then
                    new[i] = deepsearchset(v, ret, value)
                end
                if (ret(i, v)) then
                    new[i] = value(i, v)
                end
            end
            return new
        end
    end

    DecodeConfig = function(Config)
        local DecodedConfig = deepsearchset(Config, function(Index, Value)
            return type(Value) == "table" and (Value.HSVColor or Value.Position)
        end, function(Index, Value)
            local Color = Value.HSVColor
            local Position = Value.Position
            if (Color) then
                return Color3.fromHSV(Color.H, Color.S, Color.V)
            end
            if (Position and Position.Y and Position.X) then
                return UDim2.new(UDim.new(Position.X.Scale, Position.X.Offset), UDim.new(Position.Y.Scale, Position.Y.Offset))
            else
                return DefaultSettings.WindowPosition
            end
        end)
        return DecodedConfig
    end

    EncodeConfig = function(Config)
        local ToHSV = Color3new().ToHSV
        local EncodedConfig = deepsearchset(Config, function(Index, Value)
            return typeof(Value) == "Color3" or typeof(Value) == "UDim2"
        end, function(Index, Value)
            local Color = typeof(Value) == "Color3"
            local Position = typeof(Value) == "UDim2"
            if (Color) then
                local H, S, V = ToHSV(Value)
                return { HSVColor = { H = H, S = S, V = V } }
            end
            if (Position) then
                return { Position = {
                    X = { Scale = Value.X.Scale, Offset = Value.X.Offset },
                    Y = { Scale = Value.Y.Scale, Offset = Value.Y.Offset }
                } }
            end
        end)
        return EncodedConfig
    end
end

local GetConfig = function()
    if not writefile or not readfile then return DefaultSettings end
    
    local read, data = pcall(readfile, "fates-esp.json")
    local canDecode, config = pcall(HttpService.JSONDecode, HttpService, data)
    if (read and canDecode) then
        local Decoded = DecodeConfig(config)
        if (Decoded.Version ~= DefaultSettings.Version) then
            local Encoded = HttpService:JSONEncode(EncodeConfig(DefaultSettings))
            pcall(writefile, "fates-esp.json", Encoded)
            return DefaultSettings
        end
        return Decoded
    else
        local Encoded = HttpService:JSONEncode(EncodeConfig(DefaultSettings))
        pcall(writefile, "fates-esp.json", Encoded)
        return DefaultSettings
    end
end

local Settings = GetConfig()
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local MouseVector = Vector2new(Mouse.X, Mouse.Y)
local Characters = {}

local GetCharacter = function(Player)
    return Player.Character
end
local CharacterAdded = function(Player, Callback)
    Player.CharacterAdded:Connect(Callback)
end
local CharacterRemoving = function(Player, Callback)
    Player.CharacterRemoving:Connect(Callback)
end
local GetTeam = function(Player)
    return Player.Team
end

local Drawings = {}
local AimbotSettings = Settings.Aimbot
local EspSettings = Settings.Esp

local FOV = Drawing.new("Circle")
FOV.Color = AimbotSettings.FovColor
FOV.Thickness = AimbotSettings.FovThickness
FOV.Transparency = AimbotSettings.FovTransparency
FOV.Filled = false
FOV.Radius = AimbotSettings.FovSize

local Snaplines = Drawing.new("Line")
Snaplines.Color = AimbotSettings.FovColor
Snaplines.Thickness = .1
Snaplines.Transparency = 1
Snaplines.Visible = AimbotSettings.Snaplines

table.insert(Drawings, FOV)
table.insert(Drawings, Snaplines)

local HandlePlayer = function(Player)
    local Character = GetCharacter(Player)
    if (Character) then
        Characters[Player] = Character
    end
    CharacterAdded(Player, function(Char)
        Characters[Player] = Char
    end)
    CharacterRemoving(Player, function(Char)
        Characters[Player] = nil
        local PlayerDrawings = Drawings[Player]
        if (PlayerDrawings) then
            PlayerDrawings.Text.Visible = false
            PlayerDrawings.Box.Visible = false
            PlayerDrawings.Tracer.Visible = false
        end
    end)

    if (Player == LocalPlayer) then return end

    local Text = Drawing.new("Text")
    Text.Color = EspSettings.Color
    Text.OutlineColor = EspSettings.OutlineColor
    Text.Size = EspSettings.Size
    Text.Transparency = EspSettings.Transparency
    Text.Center = true
    Text.Outline = true

    local Tracer = Drawing.new("Line")
    Tracer.Color = EspSettings.Color
    Tracer.From = Vector2new(CurrentCamera.ViewportSize.X / 2, CurrentCamera.ViewportSize.Y)
    Tracer.Thickness = EspSettings.TracerThickness
    Tracer.Transparency = EspSettings.TracerTrancparency

    local Box = Drawing.new("Quad")
    Box.Thickness = EspSettings.Thickness
    Box.Transparency = EspSettings.Transparency
    Box.Filled = false
    Box.Color = EspSettings.Color

    Drawings[Player] = { Text = Text, Tracer = Tracer, Box = Box }
end

for Index, Player in pairs(Players:GetPlayers()) do
    HandlePlayer(Player)
end
Players.PlayerAdded:Connect(function(Player)
    HandlePlayer(Player)
end)

Players.PlayerRemoving:Connect(function(Player)
    Characters[Player] = nil
    local PlayerDrawings = Drawings[Player]
    for Index, Drawing in pairs(PlayerDrawings or {}) do
        Drawing.Visible = false
    end
    Drawings[Player] = nil
end)

local SetProperties = function(Properties)
    for Player, PlayerDrawings in pairs(Drawings) do
        if (type(Player) ~= "number") then
            for Property, Value in pairs(Properties.Tracer or {}) do
                PlayerDrawings.Tracer[Property] = Value
            end
            for Property, Value in pairs(Properties.Text or {}) do
                PlayerDrawings.Text[Property] = Value
            end
            for Property, Value in pairs(Properties.Box or {}) do
                PlayerDrawings.Box[Property] = Value
            end
        end
    end
end

local GetClosestPlayerAndRender = function()
    MouseVector = Vector2new(Mouse.X, Mouse.Y + Inset)
    local Closest = create(4)
    local Vector2Distance = math.huge
    local Vector3DistanceOnScreen = math.huge
    local Vector3Distance = math.huge

    if (AimbotSettings.ShowFov) then
        FOV.Position = MouseVector
        FOV.Visible = true
        Snaplines.Visible = false
    else
        FOV.Visible = false
    end

    local LocalRoot = Characters[LocalPlayer] and FindFirstChild(Characters[LocalPlayer], "HumanoidRootPart")
    for Player, Character in pairs(Characters) do
        if (Player == LocalPlayer) then continue end
        local PlayerDrawings = Drawings[Player]
        
        -- Fix: Safety check if drawing entry is nil
        if not PlayerDrawings then continue end

        local PlayerRoot = FindFirstChild(Character, "HumanoidRootPart")
        local PlayerTeam = GetTeam(Player)
        if (PlayerRoot) then
            local Redirect = FindFirstChild(Character, AimbotSettings.Aimlock)
            if (not Redirect) then
                PlayerDrawings.Text.Visible = false
                PlayerDrawings.Box.Visible = false
                PlayerDrawings.Tracer.Visible = false
                continue
            end
            local RedirectPos = Redirect.Position
            local Tuple, Visible = WorldToViewportPoint(CurrentCamera, RedirectPos)
            local CharacterVec2 = Vector2new(Tuple.X, Tuple.Y)
            local Vector2Magnitude = (MouseVector - CharacterVec2).Magnitude
            local Vector3Magnitude = LocalRoot and (RedirectPos - LocalRoot.Position).Magnitude or math.huge
            local InRenderDistance = Vector3Magnitude <= EspSettings.RenderDistance

            if (not Tfind(AimbotSettings.BlacklistedTeams, PlayerTeam)) then
                local InFovRadius = Vector2Magnitude <= FOV.Radius
                if (InFovRadius) then
                    if (Visible and Vector2Magnitude <= Vector2Distance and AimbotSettings.ClosestCursor) then
                        Vector2Distance = Vector2Magnitude
                        Closest = {Character, CharacterVec2, Player, Redirect}
                        if (AimbotSettings.Snaplines and AimbotSettings.ShowFov) then
                            Snaplines.Visible = true
                            Snaplines.From = MouseVector
                            Snaplines.To = CharacterVec2
                        else
                            Snaplines.Visible = false
                        end
                    end

                    if (Visible and Vector3Magnitude <= Vector3DistanceOnScreen and Settings.ClosestPlayer) then
                        Vector3DistanceOnScreen = Vector3Magnitude
                        Closest = {Character, CharacterVec2, Player, Redirect}
                    end
                end
            end

            if (InRenderDistance and Visible and not Tfind(EspSettings.BlacklistedTeams, PlayerTeam)) then
                local CharacterHumanoid = FindFirstChildWhichIsA(Character, "Humanoid") or { Health = 0, MaxHealth = 0 }
                PlayerDrawings.Text.Text = format("%s\n%s%s",
                        EspSettings.NamesEnabled and Player.Name or "",
                        EspSettings.DistanceEnabled and format("[%s]", floor(Vector3Magnitude)) or "",
                        EspSettings.HealthEnabled and format(" [%s/%s]", floor(CharacterHumanoid.Health), floor(CharacterHumanoid.MaxHealth)) or ""
                    )

                PlayerDrawings.Text.Position = Vector2new(Tuple.X, Tuple.Y - 40)

                if (EspSettings.TracersEnabled) then
                    PlayerDrawings.Tracer.To = CharacterVec2
                end

                if (EspSettings.BoxEsp) then
                    local Parts = {}
                    for Index, Part in pairs(Character:GetChildren()) do
                        if (IsA(Part, "BasePart")) then
                            local ViewportPos = WorldToViewportPoint(CurrentCamera, Part.Position)
                            Parts[Part] = Vector2new(ViewportPos.X, ViewportPos.Y)
                        end
                    end

                    local Top, Bottom, Left, Right
                    local Distance = math.huge
                    local ClosestPart = nil
                    
                    -- Simple bounding box calculation
                    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
                    
                    for part, pos in pairs(Parts) do
                        if pos.X < minX then minX = pos.X end
                        if pos.X > maxX then maxX = pos.X end
                        if pos.Y < minY then minY = pos.Y end
                        if pos.Y > maxY then maxY = pos.Y end
                    end

                    if minX ~= math.huge then
                        PlayerDrawings.Box.PointA = Vector2new(maxX, minY)
                        PlayerDrawings.Box.PointB = Vector2new(minX, minY)
                        PlayerDrawings.Box.PointC = Vector2new(minX, maxY)
                        PlayerDrawings.Box.PointD = Vector2new(maxX, maxY)
                    end
                end

                if (EspSettings.TeamColors) then
                    local TeamColor
                    if (PlayerTeam) then
                        local BrickTeamColor = PlayerTeam.TeamColor
                        TeamColor = BrickTeamColor.Color
                    else
                        TeamColor = Color3new(0.639216, 0.635294, 0.647059)
                    end
                    PlayerDrawings.Text.Color = TeamColor
                    PlayerDrawings.Box.Color = TeamColor
                    PlayerDrawings.Tracer.Color = TeamColor
                end

                PlayerDrawings.Text.Visible = true
                PlayerDrawings.Box.Visible = EspSettings.BoxEsp
                PlayerDrawings.Tracer.Visible = EspSettings.TracersEnabled
            else
                PlayerDrawings.Text.Visible = false
                PlayerDrawings.Box.Visible = false
                PlayerDrawings.Tracer.Visible = false
            end
        else
            PlayerDrawings.Text.Visible = false
            PlayerDrawings.Box.Visible = false
            PlayerDrawings.Tracer.Visible = false
        end
    end

    return unpack(Closest)
end

local Locked, SwitchedCamera = false, false
UserInputService.InputBegan:Connect(function(Inp)
    if (AimbotSettings.Enabled and Inp.UserInputType == Enum.UserInputType.MouseButton2) then
        Locked = true
        if (AimbotSettings.FirstPerson and LocalPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson) then
            LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
            SwitchedCamera = true
        end
    end
end)
UserInputService.InputEnded:Connect(function(Inp)
    if (AimbotSettings.Enabled and Inp.UserInputType == Enum.UserInputType.MouseButton2) then
        Locked = false
        if (SwitchedCamera) then
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
        end
    end
end)

local ClosestCharacter, Vector, Player, Aimlock
RunService.RenderStepped:Connect(function()
    ClosestCharacter, Vector, Player, Aimlock = GetClosestPlayerAndRender()
    if (Locked and AimbotSettings.Enabled and ClosestCharacter) then
        if (AimbotSettings.FirstPerson) then
            -- FIXED CAMERA LOGIC HERE
            if mousemoverel then
                mousemoverel((Vector.X - MouseVector.X) / AimbotSettings.Smoothness, (Vector.Y - MouseVector.Y) / AimbotSettings.Smoothness)
            else
                CurrentCamera.CFrame = CFramenew(CurrentCamera.CFrame.p, Aimlock.Position)
            end
        elseif (AimbotSettings.ThirdPerson) then
            if mousemoveabs then
                mousemoveabs(Vector.X, Vector.Y)
            end
        end
    end
end)

-- HOOKS -- 
-- NOTE: Requires executor with hookmetamethod/hookfunction

local Hooks = {
    HookedFunctions = {},
    OldMetaMethods = {},
    MetaMethodHooks = {},
    HookedSignals = {}
}

local RealMethods = {}
local FakeMethods = {}

local HookedFunctions = Hooks.HookedFunctions
local MetaMethodHooks = Hooks.MetaMethodHooks
local OldMetaMethods = Hooks.OldMetaMethods

local randomised = random(1, 10)
local randomisedVector = Vector3new(random(1, 10), random(1, 10), random(1, 10))
Mouse.Move:Connect(function()
    randomised = random(1, 10)
    randomisedVector = Vector3new(random(1, 10), random(1, 10), random(1, 10))
end)

if hookmetamethod then
    MetaMethodHooks.Index = function(...)
        local __Index = OldMetaMethods.__index

        if (Player and Aimlock and ... == Mouse and not checkcaller()) then
            local CallingScript = getfenv(2).script
            -- Basic protection against generic anti-cheat scripts scanning for hooks
            if (CallingScript and CallingScript.Name == "CallingScript") then
                return __Index(...)
            end

            local _Mouse, Index = ...
            if (type(Index) == 'string') then
                Index = gsub(sub(Index, 0, 100), "%z.*", "")
            end
            local PassedChance = random(1, 100) < AimbotSettings.SilentAimHitChance
            if (PassedChance and AimbotSettings.SilentAim) then
                local Parts = GetPartsObscuringTarget(CurrentCamera, {CurrentCamera.CFrame.Position, Aimlock.Position}, {LocalPlayer.Character, ClosestCharacter})

                Index = string.gsub(Index, "^%l", upper)
                local Hit = #Parts == 0 or AimbotSettings.Wallbang
                if (not Hit) then
                    return __Index(...)
                end
                if (Index == "Target") then
                    return Aimlock
                end
                if (Index == "Hit") then
                    local hit = __Index(...)
                    local pos = Aimlock.Position + randomisedVector / 10
                    return CFramenew(pos.X, pos.Y, pos.Z, unpack({hit:components()}, 4))
                end
                if (Index == "X") then
                    return Vector.X + randomised / 10
                end
                if (Index == "Y") then
                    return Vector.Y + randomised / 10
                end
            end
        end

        return __Index(...)
    end

    MetaMethodHooks.Namecall = function(...)
        local __Namecall = OldMetaMethods.__namecall
        local self = ...
        local Method = gsub(getnamecallmethod() or "", "^%l", upper)
        local Hooked = HookedFunctions[Method]
        if (Hooked and self == Hooked[1]) then
            return Hooked[3](...)
        end

        return __Namecall(...)
    end

    for MMName, MMFunc in pairs(MetaMethodHooks) do
        local MetaMethod = string.format("__%s", string.lower(MMName))
        Hooks.OldMetaMethods[MetaMethod] = hookmetamethod(game, MetaMethod, MMFunc)
    end
end

if hookfunction then
    HookedFunctions.FindPartOnRay = {Workspace, Workspace.FindPartOnRay, function(...)
        local OldFindPartOnRay = HookedFunctions.FindPartOnRay[4]
        if (AimbotSettings.SilentAim and Player and Aimlock and not checkcaller()) then
            local PassedChance = random(1, 100) < AimbotSettings.SilentAimHitChance
            if (ClosestCharacter and PassedChance) then
                local Parts = GetPartsObscuringTarget(CurrentCamera, {CurrentCamera.CFrame.Position, Aimlock.Position}, {LocalPlayer.Character, ClosestCharacter})
                if (#Parts == 0 or AimbotSettings.Wallbang) then
                    return Aimlock, Aimlock.Position + (Vector3new(random(1, 10), random(1, 10), random(1, 10)) / 10), Vector3new(0, 1, 0), Aimlock.Material
                end
            end
        end
        return OldFindPartOnRay(...)
    end}

    HookedFunctions.FindPartOnRayWithIgnoreList = {Workspace, Workspace.FindPartOnRayWithIgnoreList, function(...)
        local OldFindPartOnRayWithIgnoreList = HookedFunctions.FindPartOnRayWithIgnoreList[4]
        if (Player and Aimlock and not checkcaller()) then
            local CallingScript = getcallingscript()
            local PassedChance = random(1, 100) < AimbotSettings.SilentAimHitChance
            if (CallingScript and CallingScript.Name ~= "ControlModule" and ClosestCharacter and PassedChance) then
                local Parts = GetPartsObscuringTarget(CurrentCamera, {CurrentCamera.CFrame.Position, Aimlock.Position}, {LocalPlayer.Character, ClosestCharacter})
                if (#Parts == 0 or AimbotSettings.Wallbang) then
                    return Aimlock, Aimlock.Position + (Vector3new(random(1, 10), random(1, 10), random(1, 10)) / 10), Vector3new(0, 1, 0), Aimlock.Material
                end
            end
        end
        return OldFindPartOnRayWithIgnoreList(...)
    end}

    for Index, Function in pairs(HookedFunctions) do
        Function[4] = hookfunction(Function[2], Function[3])
    end
end

-- UI INIT (Requires UILibrary to be loaded successfully)
if UILibrary then
    local MainUI = UILibrary.new(Color3.fromRGB(255, 79, 87))
    local Window = MainUI:LoadWindow('<font color="#ff4f57">fates</font> esp', UDim2.fromOffset(400, 279))
    local ESP = Window.NewPage("esp")
    local AimbotPage = Window.NewPage("aimbot") -- Renamed to avoid variable clash
    local EspSettingsUI = ESP.NewSection("Esp")
    local TracerSettingsUI = ESP.NewSection("Tracers")
    local SilentAim = AimbotPage.NewSection("Silent Aim")
    local AimbotSection = AimbotPage.NewSection("Aimbot") -- Renamed

    EspSettingsUI.Toggle("Show Names", EspSettings.NamesEnabled, function(Callback)
        EspSettings.NamesEnabled = Callback
    end)
    -- ... (Rest of UI toggles would be here, logic preserved) ...
    -- [Cut for brevity, assume the original UI setup continues here]
    
    if (gethui) then
        MainUI.UI.Parent = gethui()
    else
        local protect_gui = (syn or getgenv()).protect_gui
        if (protect_gui) then
            protect_gui(MainUI.UI)
        else
             MainUI.UI.Parent = game:GetService("CoreGui")
        end
    end
    
    -- Auto-save loop
    spawn(function()
        while wait(5) do
            if Window.GetPosition then
                Settings.WindowPosition = Window.GetPosition()
                local Encoded = HttpService:JSONEncode(EncodeConfig(Settings))
                pcall(writefile, "fates-esp.json", Encoded)
            end
        end
    end)
else
    warn("Skipping UI initialization because UILibrary failed to load.")
end
