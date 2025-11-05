if not game:IsLoaded() then 
    game.Loaded:Wait()
end

if not syn or not protectgui then
    getgenv().protectgui = function() end
end

local SilentAimSettings = {
    Enabled = false,
    
    ClassName = "Universal Silent Aim - Averiias, Stefanuk12, xaxa",
    ToggleKey = "RightAlt",
    
    TeamCheck = false,
    VisibleCheck = false, 
    TargetPart = "HumanoidRootPart",
    SilentAimMethod = "Raycast",
    
    FOVRadius = 130,
    FOVVisible = false,
    ShowSilentAimTarget = false, 
    
    MouseHitPrediction = false,
    MouseHitPredictionAmount = 0.165,
    HitChance = 100,

    Autoshot = false,
    AutoshotDelay = 50
}

getgenv().SilentAimSettings = SilentAimSettings
local MainFileName = "UniversalSilentAim"
local SelectedFile, FileToSave = "", ""

local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local GetChildren = game.GetChildren
local GetPlayers = Players.GetPlayers
local WorldToScreen = Camera.WorldToScreenPoint
local WorldToViewportPoint = Camera.WorldToViewportPoint
local GetPartsObscuringTarget = Camera.GetPartsObscuringTarget
local FindFirstChild = game.FindFirstChild
local RenderStepped = RunService.RenderStepped
local GuiInset = GuiService.GetGuiInset
local GetMouseLocation = UserInputService.GetMouseLocation

local resume = coroutine.resume 
local create = coroutine.create

local ValidTargetParts = {"Head", "HumanoidRootPart"}
local PredictionAmount = 0.165

-- Attribute-based team helpers for Team Check
local function getTeamAttr(p)
	if not p then return nil end
	return p:GetAttribute("Team")
end

local function isEnemyAttr(p)
	local myTeam = getTeamAttr(LocalPlayer)
	local theirTeam = getTeamAttr(p)
	if not myTeam or not theirTeam then return false end
	return myTeam ~= theirTeam
end

-- FOV circles: separate fill and outline for independent colors
local fov_circle_fill = Drawing.new("Circle")
fov_circle_fill.Thickness = 1
fov_circle_fill.NumSides = 100
fov_circle_fill.Radius = 180
fov_circle_fill.Filled = true
fov_circle_fill.Visible = false
fov_circle_fill.ZIndex = 998
fov_circle_fill.Transparency = 0.15
fov_circle_fill.Color = Color3.fromRGB(54, 57, 241)

local fov_circle_outline = Drawing.new("Circle")
fov_circle_outline.Thickness = 1
fov_circle_outline.NumSides = 100
fov_circle_outline.Radius = 180
fov_circle_outline.Filled = false
fov_circle_outline.Visible = false
fov_circle_outline.ZIndex = 999
fov_circle_outline.Transparency = 1
fov_circle_outline.Color = Color3.fromRGB(54, 57, 241)

-- Crosshair removed as requested

-- Target info UI (nickname, avatar, HP) below the center
local TargetGui, AvatarImage, NameLabel, HpLabel
local lastAvatarUserId
local lastTargetUserId
local lastHpShown
local function ensureTargetGui()
	if TargetGui and TargetGui.Parent then return end
	TargetGui = Instance.new("ScreenGui")
	TargetGui.Name = "chinozec_TargetInfo"
	protectgui(TargetGui)
	TargetGui.Parent = game:GetService("CoreGui")

    local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 0.2
	holder.BackgroundColor3 = Color3.fromRGB(10,10,10)
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(240, 72)
	holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Position = UDim2.new(0.5, 0, 0.5, 100)
	holder.Parent = TargetGui
    local holderCorner = Instance.new("UICorner")
    holderCorner.CornerRadius = UDim.new(0, 10)
    holderCorner.Parent = holder

    AvatarImage = Instance.new("ImageLabel")
	AvatarImage.BackgroundTransparency = 1
	AvatarImage.Size = UDim2.fromOffset(64,64)
	AvatarImage.Position = UDim2.fromOffset(6,4)
	AvatarImage.Parent = holder
    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(1, 0)
    avatarCorner.Parent = AvatarImage

	NameLabel = Instance.new("TextLabel")
	NameLabel.BackgroundTransparency = 1
	NameLabel.Font = Enum.Font.GothamBold
	NameLabel.TextSize = 16
	NameLabel.TextColor3 = Color3.new(1,1,1)
	NameLabel.TextXAlignment = Enum.TextXAlignment.Left
	NameLabel.Size = UDim2.fromOffset(160, 22)
	NameLabel.Position = UDim2.fromOffset(78, 6)
	NameLabel.Parent = holder

	HpLabel = Instance.new("TextLabel")
	HpLabel.BackgroundTransparency = 1
	HpLabel.Font = Enum.Font.Gotham
	HpLabel.TextSize = 14
	HpLabel.TextColor3 = Color3.fromRGB(200,200,200)
	HpLabel.TextXAlignment = Enum.TextXAlignment.Left
	HpLabel.Size = UDim2.fromOffset(160, 20)
	HpLabel.Position = UDim2.fromOffset(78, 32)
	HpLabel.Parent = holder

    TargetGui.Enabled = false
end

local function updateTargetGui(player, humanoid)
	ensureTargetGui()
	if not player then
		TargetGui.Enabled = false
        lastTargetUserId = nil
        lastHpShown = nil
		return
	end
	TargetGui.Enabled = true
    if player.UserId ~= lastTargetUserId then
        NameLabel.Text = player.DisplayName .. " (@" .. player.Name .. ")"
        lastTargetUserId = player.UserId
    end
    local hpNow = humanoid and math.floor(humanoid.Health) or nil
    if hpNow ~= lastHpShown then
        HpLabel.Text = hpNow and ("HP: " .. tostring(hpNow)) or "HP: ?"
        lastHpShown = hpNow
    end
	if player.UserId ~= lastAvatarUserId then
		lastAvatarUserId = player.UserId
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then AvatarImage.Image = content end
	end
end


local ExpectedArguments = {
    FindPartOnRayWithIgnoreList = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Ray", "table", "boolean", "boolean"
        }
    },
    FindPartOnRayWithWhitelist = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Ray", "table", "boolean"
        }
    },
    FindPartOnRay = {
        ArgCountRequired = 2,
        Args = {
            "Instance", "Ray", "Instance", "boolean", "boolean"
        }
    },
    Raycast = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Vector3", "Vector3", "RaycastParams"
        }
    }
}

function CalculateChance(Percentage)
    Percentage = math.floor(Percentage)

    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100

    return chance <= Percentage / 100
end


 do 
    if not isfolder(MainFileName) then 
        makefolder(MainFileName);
    end
    
    if not isfolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) then 
        makefolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))
    end
end

local Files = listfiles(string.format("%s/%s", "UniversalSilentAim", tostring(game.PlaceId)))

local function GetFiles() -- credits to the linoria lib for this function, listfiles returns the files full path and its annoying
	local out = {}
	for i = 1, #Files do
		local file = Files[i]
		if file:sub(-4) == '.lua' then

			local pos = file:find('.lua', 1, true)
			local start = pos

			local char = file:sub(pos, pos)
			while char ~= '/' and char ~= '\\' and char ~= '' do
				pos = pos - 1
				char = file:sub(pos, pos)
			end

			if char == '/' or char == '\\' then
				table.insert(out, file:sub(pos + 1, start - 1))
			end
		end
	end
	
	return out
end

local function UpdateFile(FileName)
    assert(FileName or FileName == "string", "oopsies");
    writefile(string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName), HttpService:JSONEncode(SilentAimSettings))
end

local function LoadFile(FileName)
    assert(FileName or FileName == "string", "oopsies");
    
    local File = string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName)
    local ConfigData = HttpService:JSONDecode(readfile(File))
    for Index, Value in next, ConfigData do
        SilentAimSettings[Index] = Value
    end
end

local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToScreen(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function ValidateArguments(Args, RayMethod)
    local Matches = 0
    if #Args < RayMethod.ArgCountRequired then
        return false
    end
    for Pos, Argument in next, Args do
        if typeof(Argument) == RayMethod.Args[Pos] then
            Matches = Matches + 1
        end
    end
    return Matches >= RayMethod.ArgCountRequired
end

local function getDirection(Origin, Position)
    return (Position - Origin).Unit * 1000
end

local function getMousePosition()
    return GetMouseLocation(UserInputService)
end

local function IsPlayerVisible(Player)
    local PlayerCharacter = Player.Character
    local LocalPlayerCharacter = LocalPlayer.Character
    
    if not (PlayerCharacter or LocalPlayerCharacter) then return end 
    
    local PlayerRoot = FindFirstChild(PlayerCharacter, Options.TargetPart.Value) or FindFirstChild(PlayerCharacter, "HumanoidRootPart")
    
    if not PlayerRoot then return end 
    
    local CastPoints, IgnoreList = {PlayerRoot.Position, LocalPlayerCharacter, PlayerCharacter}, {LocalPlayerCharacter, PlayerCharacter}
    local ObscuringObjects = #GetPartsObscuringTarget(Camera, CastPoints, IgnoreList)
    
    return ((ObscuringObjects == 0 and true) or (ObscuringObjects > 0 and false))
end

local function getClosestPlayer()
    if not Options.TargetPart.Value then return end
    local Closest
    local DistanceToMouse
    for _, Player in next, GetPlayers(Players) do
        if Player == LocalPlayer then continue end
		if Toggles.TeamCheck.Value and not isEnemyAttr(Player) then continue end

        local Character = Player.Character
        if not Character then continue end
        
        if Toggles.VisibleCheck.Value and not IsPlayerVisible(Player) then continue end

        local HumanoidRootPart = FindFirstChild(Character, "HumanoidRootPart")
        local Humanoid = FindFirstChild(Character, "Humanoid")
        if not HumanoidRootPart or not Humanoid or Humanoid and Humanoid.Health <= 0 then continue end

        local ScreenPosition, OnScreen = getPositionOnScreen(HumanoidRootPart.Position)
        if not OnScreen then continue end

        local Distance = (getMousePosition() - ScreenPosition).Magnitude
        if Distance <= (DistanceToMouse or Options.Radius.Value or 2000) then
            Closest = ((Options.TargetPart.Value == "Random" and Character[ValidTargetParts[math.random(1, #ValidTargetParts)]]) or Character[Options.TargetPart.Value])
            DistanceToMouse = Distance
        end
    end
    return Closest
end

local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'

local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

local Window = Library:CreateWindow({Title = 'chinozec.lol', Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0})
local GeneralTab = Window:AddTab("Combat")
local MainBOX = GeneralTab:AddLeftTabbox("Main") do
    local Main = MainBOX:AddTab("Main")
    
    Main:AddToggle("aim_Enabled", {Text = "Enabled"}):AddKeyPicker("aim_Enabled_KeyPicker", {Default = "RightAlt", SyncToggleState = true, Mode = "Toggle", Text = "Enabled", NoUI = false});
    Options.aim_Enabled_KeyPicker:OnClick(function()
    SilentAimSettings.Enabled = not SilentAimSettings.Enabled
    
    Toggles.aim_Enabled.Value = SilentAimSettings.Enabled
    Toggles.aim_Enabled:SetValue(SilentAimSettings.Enabled)

    Library:Notify(SilentAimSettings.Enabled and 'Enable aim' or 'Disable aim')
end)

    Main:AddToggle("Autoshot", {Text = "Autoshot", Default = SilentAimSettings.Autoshot}):OnChanged(function()
        SilentAimSettings.Autoshot = Toggles.Autoshot.Value
    end)

    Main:AddSlider("AutoshotDelay", {Text = "Autoshot Delay (ms)", Min = 0, Max = 1000, Default = SilentAimSettings.AutoshotDelay, Rounding = 0}):OnChanged(function()
        SilentAimSettings.AutoshotDelay = Options.AutoshotDelay.Value
    end)
    
    Main:AddToggle("TeamCheck", {Text = "Team Check", Default = SilentAimSettings.TeamCheck}):OnChanged(function()
        SilentAimSettings.TeamCheck = Toggles.TeamCheck.Value
    end)
    Main:AddToggle("VisibleCheck", {Text = "Visible Check", Default = SilentAimSettings.VisibleCheck}):OnChanged(function()
        SilentAimSettings.VisibleCheck = Toggles.VisibleCheck.Value
    end)
    Main:AddDropdown("TargetPart", {AllowNull = true, Text = "Target Part", Default = SilentAimSettings.TargetPart, Values = {"Head", "HumanoidRootPart", "Random"}}):OnChanged(function()
        SilentAimSettings.TargetPart = Options.TargetPart.Value
    end)
    Main:AddSlider('HitChance', {
        Text = 'Hit chance',
        Default = 100,
        Min = 0,
        Max = 100,
        Rounding = 1,
    
        Compact = false,
    })
    Options.HitChance:OnChanged(function()
        SilentAimSettings.HitChance = Options.HitChance.Value
    end)
end

local MiscellaneousBOX = GeneralTab:AddLeftTabbox("Miscellaneous")
local FieldOfViewBOX = GeneralTab:AddRightTabbox("Field Of View") do
    local Main = FieldOfViewBOX:AddTab("")
    
	Main:AddToggle("Visible", {Text = "Show FOV Circle"})
		:AddColorPicker("FOVFillColor", {Default = Color3.fromRGB(54, 57, 241)})
		:AddColorPicker("FOVOutlineColor", {Default = Color3.fromRGB(54, 57, 241)})
		:OnChanged(function()
			local vis = Toggles.Visible.Value
			fov_circle_fill.Visible = vis
			fov_circle_outline.Visible = vis
			SilentAimSettings.FOVVisible = vis
		end)

	Main:AddSlider("Radius", {Text = "FOV Circle Radius", Min = 0, Max = 360, Default = 130, Rounding = 0}):OnChanged(function()
		fov_circle_fill.Radius = Options.Radius.Value
		fov_circle_outline.Radius = Options.Radius.Value
		SilentAimSettings.FOVRadius = Options.Radius.Value
	end)

	Main:AddSlider("FOVOutlineThickness", {Text = "Outline Thickness", Min = 1, Max = 6, Default = 1, Rounding = 0}):OnChanged(function()
		fov_circle_outline.Thickness = Options.FOVOutlineThickness.Value
	end)

	Main:AddSlider("FOVFillAlpha", {Text = "Fill Alpha", Min = 0, Max = 1, Default = 0.15, Rounding = 2}):OnChanged(function()
		fov_circle_fill.Transparency = Options.FOVFillAlpha.Value
	end)
    Main:AddToggle("MousePosition", {Text = "Show Silent Aim Target"})
		:AddColorPicker("MouseVisualizeColor", {Default = Color3.fromRGB(54, 57, 241)})
		:OnChanged(function()
			SilentAimSettings.ShowSilentAimTarget = Toggles.MousePosition.Value 
		end)
    local PredictionTab = MiscellaneousBOX:AddTab("Prediction")
    PredictionTab:AddToggle("Prediction", {Text = "Mouse.Hit/Target Prediction"}):OnChanged(function()
        SilentAimSettings.MouseHitPrediction = Toggles.Prediction.Value
    end)
    PredictionTab:AddSlider("Amount", {Text = "Prediction Amount", Min = 0.165, Max = 1, Default = 0.165, Rounding = 3}):OnChanged(function()
        PredictionAmount = Options.Amount.Value
        SilentAimSettings.MouseHitPredictionAmount = Options.Amount.Value
    end)
end

resume(create(function()
    RenderStepped:Connect(function()
        -- Target info without circle indicator (cached updates to avoid FPS drops)
        if Toggles.MousePosition.Value and Toggles.aim_Enabled.Value then
            local part = getClosestPlayer()
            if part and part.Parent then
                local targetPlayer = Players:GetPlayerFromCharacter(part.Parent)
                local hum = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
                updateTargetGui(targetPlayer, hum)
            else
                updateTargetGui(nil, nil)
            end
        end
        
		-- FOV draw
		local mousePos = getMousePosition()
		if Toggles.Visible.Value then 
			fov_circle_fill.Visible = true
			fov_circle_outline.Visible = true
			fov_circle_fill.Position = mousePos
			fov_circle_outline.Position = mousePos
			if Options.FOVFillColor and Options.FOVFillColor.Value then
				fov_circle_fill.Color = Options.FOVFillColor.Value
			end
			if Options.FOVOutlineColor and Options.FOVOutlineColor.Value then
				fov_circle_outline.Color = Options.FOVOutlineColor.Value
			end
        end
    end)
end))

local autoshotConnection
local lastShot = 0

Toggles.Autoshot:OnChanged(function()
    if Toggles.Autoshot.Value then
		autoshotConnection = RunService.Heartbeat:Connect(function()
			if not Toggles.aim_Enabled.Value then return end
			local part = getClosestPlayer()
			if not part then return end
			-- On-screen and within current FOV radius
			local sp, onScr = WorldToViewportPoint(Camera, part.Position)
			if not onScr then return end
			local distToMouse = (getMousePosition() - Vector2.new(sp.X, sp.Y)).Magnitude
			local maxR = Options.Radius and Options.Radius.Value or 130
			if distToMouse > maxR then return end
			-- hitchance roll
			if not CalculateChance(SilentAimSettings.HitChance or 100) then return end
			-- cooldown
			if tick() - lastShot < (SilentAimSettings.AutoshotDelay / 1000 + 0.005) then return end
			mouse1press()
			task.wait(0.02)
			mouse1release()
			lastShot = tick()
		end)
    else
        if autoshotConnection then
            autoshotConnection:Disconnect()
            autoshotConnection = nil
        end
    end
end)

-- Removed __namecall hook - using Mouse.Hit/Target only

local oldIndex = nil 
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
    if self == Mouse and not checkcaller() and Toggles.aim_Enabled.Value and getClosestPlayer() then
        local HitPart = getClosestPlayer()
         
        if Index == "Target" or Index == "target" then 
            return HitPart
        elseif Index == "Hit" or Index == "hit" then 
            return ((Toggles.Prediction.Value and (HitPart.CFrame + (HitPart.Velocity * PredictionAmount))) or (not Toggles.Prediction.Value and HitPart.CFrame))
        elseif Index == "X" or Index == "x" then 
            return self.X 
        elseif Index == "Y" or Index == "y" then 
            return self.Y 
        elseif Index == "UnitRay" then 
            return Ray.new(self.Origin, (self.Hit - self.Origin).Unit)
        end
    end

    return oldIndex(self, Index)
end))

local rage = Window:AddTab("Rage")

local rage_left = rage:AddLeftTabbox()

local players_tab = rage_left:AddTab("Players")

-- reuse top-level Players
-- reuse top-level UserInputService
-- reuse top-level RunService
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local AUTO_CLICK_DELAY = 0.001  -- Супер-спам кликов (миллисекунды)
local AUTO_WIN_DELAY = 0.001    -- Авто-вин спам (еще быстрее, 1000 раз/сек)
local MAX_TARGET_DIST = math.huge  -- Бесконечная дистанция для киллов через всю карту
local TOOL_EQUIP_DELAY = 0.2   -- Задержка экипировки (НЕ ИСПОЛЬЗУЕТСЯ)
local SLASH_SPAM_COUNT = 1     -- Количество вызовов kill за один тик на каждого (мгновенно, но не переспам)
local ENEMY_CACHE_TIME = 0.1   -- Кэш врагов каждые 0.1 сек для оптимизации

local autoClickEnabled = false   -- Изначально ВЫКЛ, управляется тогглом
local autoWinEnabled = false     -- Изначально ВЫКЛ, управляется тогглом
local autoToolGrabEnabled = true -- ВКЛ для лупа поиска тула с kill
local autoEquipFirstToolEnabled = false  -- ВЫКЛ! НИЧЕГО НЕ ЭКИПИРУЕТСЯ В РУКИ
local killRemote = nil
local enemyCache = {}
local lastCacheUpdate = 0
local clickConnection = nil  -- Для отключения Heartbeat

local function getKillRemote()
    local tool = nil
    for _, item in pairs(LocalPlayer.Backpack:GetChildren()) do
        if item:IsA("Tool") and item:FindFirstChild("kill") and item.kill:IsA("RemoteEvent") then
            tool = item
            break
        end
    end
    if not tool and LocalPlayer.Character then
        for _, item in pairs(LocalPlayer.Character:GetChildren()) do
            if item:IsA("Tool") and item:FindFirstChild("kill") and item.kill:IsA("RemoteEvent") then
                tool = item
                break
            end
        end
    end
    if not tool then
        for _, item in pairs(LocalPlayer.Backpack:GetChildren()) do
            if item:IsA("Tool") and item:FindFirstChild("Slash") then
                tool = item
                break
            end
        end
        if not tool and LocalPlayer.Character then
            for _, item in pairs(LocalPlayer.Character:GetChildren()) do
                if item:IsA("Tool") and item:FindFirstChild("Slash") then
                    tool = item
                    break
                end
            end
        end
    end
    killRemote = tool and tool:FindFirstChild("kill") or tool and tool:FindFirstChild("Slash")
    if killRemote then
    end
    return killRemote
end

local function getRunningGame(player)
    for _, gameFolder in pairs(workspace:WaitForChild("RunningGames"):GetChildren()) do
        if gameFolder.Name:match(tostring(player.UserId)) then
            return gameFolder
        end
    end
    return nil
end

local function getAllEnemies()
    local currentTime = tick()
    if currentTime - lastCacheUpdate < ENEMY_CACHE_TIME then
        return enemyCache
    end
    enemyCache = {}
    lastCacheUpdate = currentTime
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return enemyCache end
    
    local myGame = LocalPlayer:GetAttribute("Game") or "nothing"
    local myTeam = LocalPlayer:GetAttribute("Team") or "nothing"
    local myMap = LocalPlayer:GetAttribute("Map") or "nothing"
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
            local theirGame = player:GetAttribute("Game") or "nothing"
            local theirTeam = player:GetAttribute("Team") or "nothing"
            local theirMap = player:GetAttribute("Map") or "nothing"
            
            if theirGame == myGame and theirMap == myMap and theirTeam ~= myTeam then
                table.insert(enemyCache, player)
            end
        end
    end
    return enemyCache
end

local function performKillSpam()
    if not killRemote then return end
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
    
    local enemies = getAllEnemies()
    local totalFires = 0
    for _, target in pairs(enemies) do
        if totalFires >= 100 then break end
        pcall(function()  -- Error handling
            if killRemote.Name == "kill" then
                for i = 1, SLASH_SPAM_COUNT do
                    killRemote:FireServer(target)
                    totalFires += 1
                end
            else
                local direction = (target.Character.HumanoidRootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Unit
                for i = 1, SLASH_SPAM_COUNT do
                    killRemote:FireServer(target, direction)
                    totalFires += 1
                end
            end
        end)
    end
    if #enemies > 0 then
        print("Killed " .. #enemies .. " enemies this tick")  -- Debug
    end
end

local function startAutoClick()
    if clickConnection then clickConnection:Disconnect() end
    if autoClickEnabled then
        clickConnection = RunService.Heartbeat:Connect(function()
            performKillSpam()
        end)
    end
end

local winConnection
local function startAutoWin()
    if winConnection then winConnection:Disconnect() end
    if autoWinEnabled then
        winConnection = task.spawn(function()
            while autoWinEnabled do
                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") and LocalPlayer.Character.Humanoid.Health > 0 then
                    performKillSpam()
                end
                task.wait(AUTO_WIN_DELAY)
            end
        end)
    end
end

task.spawn(function()
    while true do
        if autoToolGrabEnabled then
            getKillRemote()
        end
        task.wait(0.5)  -- Проверяем каждые 0.5 секунды
    end
end)

getKillRemote()

players_tab:AddToggle('killall', { 
    Text = 'auto win', 
    Default = false,  -- По умолчанию выкл
    Callback = function(Value)
        autoWinEnabled = Value
        autoClickEnabled = Value  -- Связываем с Heartbeat
        startAutoClick()  -- Перезапускаем/отключаем Heartbeat
        startAutoWin()    -- Перезапускаем/отключаем быстрый луп
    end
})

local visuals = Window:AddTab("Visuals")

local visuals_right = visuals:AddLeftTabbox()

local localplayer_tabb = visuals_right:AddTab("Enemy")

local visuals_left = visuals:AddRightTabbox()

local localplayer_tab = visuals_left:AddTab("LocalPlayer")

-- reuse top-level Players
local player = Players.LocalPlayer
local coneColor = Color3.fromRGB(54, 57, 241) -- Начальный цвет
local conePart = nil -- Хранит текущий конус
local enabled = false -- Флаг для включения/выключения

local function createCone(character)
    if not enabled or not character or not character:FindFirstChild("Head") then return end

    if conePart and conePart.Parent then
        conePart:Destroy()
    end

    local head = character.Head

    conePart = Instance.new("Part")
    conePart.Name = "ChinaHat"
    conePart.Size = Vector3.new(1, 1, 1)
    conePart.Color = coneColor
    conePart.Transparency = 0.3
    conePart.Anchored = false
    conePart.CanCollide = false

    local mesh = Instance.new("SpecialMesh", conePart)
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = "rbxassetid://1033714"
    mesh.Scale = Vector3.new(1.7, 1.1, 1.7)

    local weld = Instance.new("Weld")
    weld.Part0 = head
    weld.Part1 = conePart
    weld.C0 = CFrame.new(0, 0.9, 0)

    conePart.Parent = character
    weld.Parent = conePart

    return conePart
end

local function checkCone()
    if not enabled or not player.Character then 
        if conePart and conePart.Parent then
            conePart:Destroy()
        end
        return 
    end
    
    local hatExists = player.Character:FindFirstChild("ChinaHat")
    if not hatExists then
        createCone(player.Character)
    else
        hatExists.Color = coneColor
    end
end

player.CharacterAdded:Connect(function(character)
    createCone(character)
    
    while character and character:IsDescendantOf(game) do
        checkCone()
        task.wait(1)
    end
end)

if player.Character then
    createCone(player.Character)
end

localplayer_tab:AddToggle('ChinahatToggle', { Text = 'Chinahat', Default = false })
    :AddColorPicker('ChinahatColor', { Default = Color3.fromRGB(54, 57, 241) })

Toggles.ChinahatToggle:OnChanged(function()
    enabled = Toggles.ChinahatToggle.Value
    checkCone()
end)

Options.ChinahatColor:OnChanged(function()
    coneColor = Options.ChinahatColor.Value
    checkCone()
end)

local highlights = {}
local espEnabled = false
local espConnection = nil
local currentColor = Color3.fromRGB(54, 57, 241)
local maxDistance = 1000
local lastESPUpdate = 0

local function getTeam(player)
    local team = player:GetAttribute("Team")
    if not team then
    else
    end
    return team
end

local function isEnemy(player)
    local localPlayer = game.Players.LocalPlayer
    local localTeam = getTeam(localPlayer)
    local targetTeam = getTeam(player)

    if not localTeam or not targetTeam then
 
        return false
    end

    local isEnemyCheck = localTeam ~= targetTeam
    if isEnemyCheck then

    else

    end
    return isEnemyCheck
end

local function isAlive(character)
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end
    local died = character:GetAttribute("Died")
    local aliveCheck = humanoid.Health > 0 and (died == nil or not died)
    return aliveCheck
end

local function createHighlight(character)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = currentColor
    highlight.OutlineColor = currentColor
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.Parent = character
    return highlight
end

local function getDistance()
    local localChar = game.Players.LocalPlayer.Character
    if not localChar or not localChar:FindFirstChild("HumanoidRootPart") then
        return function() return math.huge end
    end
    local localPos = localChar.HumanoidRootPart.Position
    return function(player)
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local dist = (localPos - player.Character.HumanoidRootPart.Position).Magnitude
            return dist
        end
        return math.huge
    end
end

local function addHighlight(player)
    if player == game.Players.LocalPlayer then return end
    if not isEnemy(player) then return end

    local character = player.Character
    if isAlive(character) then
        if highlights[player] then
            highlights[player]:Destroy()
        end
        highlights[player] = createHighlight(character)
    else
    end
end

local function removeHighlight(player)
    if highlights[player] then
        highlights[player]:Destroy()
        highlights[player] = nil
    end
end

local function setupPlayer(player)
    local distFunc = getDistance()
    local dist = distFunc(player)
    local character = player.Character
    local alive = isAlive(character)
    if dist <= maxDistance and isEnemy(player) and alive then
        addHighlight(player)
    end

    player.CharacterAdded:Connect(function()
        task.wait(0.5)  -- Ждём загрузки
        local newDistFunc = getDistance()
        local newDist = newDistFunc(player)
        local newCharacter = player.Character
        local newAlive = isAlive(newCharacter)
        if newDist <= maxDistance and isEnemy(player) and newAlive then
            addHighlight(player)
        end
    end)

    player:GetAttributeChangedSignal("Team"):Connect(function()
        if espEnabled then
            if isEnemy(player) then
                addHighlight(player)
            else
                removeHighlight(player)
            end
        end
    end)

    if player.Character then
        player.Character:GetAttributeChangedSignal("Died"):Connect(function()
            if espEnabled then
                local aliveNow = isAlive(player.Character)
                if isEnemy(player) and aliveNow and highlights[player] == nil then
                    addHighlight(player)
                elseif not aliveNow and highlights[player] then
                    removeHighlight(player)
                end
            end
        end)
    end

    player.AncestryChanged:Connect(function()
        if not player.Parent then
            removeHighlight(player)
        end
    end)
end

local function updateDistances()
    local distFunc = getDistance()
    for _, player in ipairs(game.Players:GetPlayers()) do
        if player ~= game.Players.LocalPlayer then
            local dist = distFunc(player)
            local character = player.Character
            local alive = isAlive(character)
            local hasHL = highlights[player] and highlights[player].Parent
            local enemy = isEnemy(player)

            if enemy and dist <= maxDistance and alive and not hasHL then
                addHighlight(player)
            elseif (not enemy or dist > maxDistance or not alive) and hasHL then
                removeHighlight(player)
            end
        end
    end
end

local function refreshAllWithinDistance()
    local distFunc = getDistance()
    for _, player in ipairs(game.Players:GetPlayers()) do
        if player ~= game.Players.LocalPlayer then
            local dist = distFunc(player)
            local character = player.Character
            local alive = isAlive(character)
            local enemy = isEnemy(player)

            if enemy and dist <= maxDistance and alive then
                addHighlight(player)
            else
                removeHighlight(player)
            end
        end
    end
end

local function startDistanceLoop()
    if distanceCoroutine then return end
    distanceCoroutine = coroutine.create(function()
        while espEnabled do
            updateDistances()
            task.wait(1)
        end
    end)
    coroutine.resume(distanceCoroutine)
end

local function startRefreshLoop()
    if refreshCoroutine then return end
    refreshCoroutine = coroutine.create(function()
        while espEnabled do
            task.wait(15)
            if espEnabled then
                refreshAllWithinDistance()
            end
        end
    end)
    coroutine.resume(refreshCoroutine)
end

local function stopLoops()
    espEnabled = false
    if refreshCoroutine then
        coroutine.close(refreshCoroutine)
        refreshCoroutine = nil
    end
    if distanceCoroutine then
        coroutine.close(distanceCoroutine)
        distanceCoroutine = nil
    end
end

localplayer_tabb:AddToggle('EspToggle', { Text = 'Esp', Default = false })
    :AddColorPicker('EspColor', { Default = Color3.fromRGB(54, 57, 241) })

Toggles.EspToggle:OnChanged(function(value)
    espEnabled = value
    currentColor = Options.EspColor.Value

    if value then
        local localTeam = getTeam(Players.LocalPlayer)
        if not localTeam then
            espEnabled = false
            return
        end

        for _, player in ipairs(Players:GetPlayers()) do
            setupPlayer(player)
        end

        Players.PlayerAdded:Connect(setupPlayer)
        
        -- Single optimized Heartbeat loop (throttled to 1 update per second)
        if espConnection then espConnection:Disconnect() end
        espConnection = RunService.Heartbeat:Connect(function()
            local now = tick()
            if now - lastESPUpdate >= 0.1 then
                lastESPUpdate = now
                updateESP()
            end
        end)
    else
        if espConnection then
            espConnection:Disconnect()
            espConnection = nil
        end
        for _, player in ipairs(Players:GetPlayers()) do
            removeHighlight(player)
        end
        highlights = {}
    end
end)

Options.EspColor:OnChanged(function(newColor)
    currentColor = newColor
    for player, highlight in pairs(highlights) do
        if highlight and highlight.Parent then
            highlight.FillColor = currentColor
            highlight.OutlineColor = currentColor
        end
    end
end)

localplayer_tabb:AddSlider('DistanceEsp', {
    Text = 'distance',
    Default = 1000,
    Min = 0,
    Max = 10000,
    Rounding = 0,
    Compact = false,
    Callback = function(Value)
        maxDistance = Value
    end
})

local playerEnabled = false
local toolEnabled = false
local toolCol = Color3.fromRGB(255, 0, 0)
local playerCol = Color3.fromRGB(255, 255, 255)

-- reuse top-level Players
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

function applyPlayer()
    if not Character then return end

    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Material = Enum.Material.ForceField
            part.Color = playerCol
            part.CanCollide = part.CanCollide
        end
    end
end

function resetPlayer()
    if not Character then return end

    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Material = Enum.Material.Plastic
            part.Color = Color3.fromRGB(255, 255, 255)
            part.CanCollide = part.CanCollide
        end
    end
end

function applyTool(tool)
    if not tool:IsA("Tool") then return end
    for _, part in pairs(tool:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Material = Enum.Material.ForceField
            part.Color = toolCol
            part.CanCollide = part.CanCollide
        end
    end
end

function resetTool(tool)
    if not tool:IsA("Tool") then return end
    for _, part in pairs(tool:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Material = Enum.Material.Plastic
            part.Color = Color3.fromRGB(255, 255, 255)
            part.CanCollide = part.CanCollide
        end
    end
end

function applyAllTools()
    for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
        applyTool(tool)
    end
    for _, tool in pairs(Character:GetChildren()) do
        if tool:IsA("Tool") then
            applyTool(tool)
        end
    end
end

function resetTools()
    for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") then
            resetTool(tool)
        end
    end
    for _, tool in pairs(Character:GetChildren()) do
        if tool:IsA("Tool") then
            resetTool(tool)
        end
    end
end

local function setupCharacterEvents()
    Character.ChildAdded:Connect(function(child)
        if toolEnabled and child:IsA("Tool") then
            applyTool(child)
        end
    end)
end

LocalPlayer.Backpack.ChildAdded:Connect(function(child)
    if toolEnabled and child:IsA("Tool") then
        applyTool(child)
    end
end)

setupCharacterEvents()

LocalPlayer.CharacterAdded:Connect(function(newChar)
    Character = newChar
    if playerEnabled then
        applyPlayer()
    end
    if toolEnabled then
        for _, tool in pairs(Character:GetChildren()) do
            if tool:IsA("Tool") then
                applyTool(tool)
            end
        end
    end
    setupCharacterEvents()
end)

spawn(function()
    while true do
        if playerEnabled then
            applyPlayer()
        end
        if toolEnabled then
            applyAllTools()
        end
        task.wait(2)
    end
end)


localplayer_tab:AddToggle("ForceFieldPlayerToggle", {
    Text = "ForceField on Player",
    Default = false
}) :AddColorPicker('PlayerColor', {
    Default = Color3.fromRGB(255, 255, 255)
})

localplayer_tab:AddToggle("ToolMaterialToggle", {
    Text = "Tool FF",
    Default = false
}) :AddColorPicker('ToolColor', {
    Default = Color3.fromRGB(255, 0, 0)
})

Toggles.ForceFieldPlayerToggle:OnChanged(function()
    playerEnabled = Toggles.ForceFieldPlayerToggle.Value
    if playerEnabled then
        applyPlayer()
    else
        resetPlayer()
    end
end)

Options.PlayerColor:OnChanged(function()
    playerCol = Options.PlayerColor.Value
    if playerEnabled then
        applyPlayer()
    end
end)

Toggles.ToolMaterialToggle:OnChanged(function()
    toolEnabled = Toggles.ToolMaterialToggle.Value
    if toolEnabled then
        applyAllTools()
    else
        resetTools()
    end
end)

Options.ToolColor:OnChanged(function()
    toolCol = Options.ToolColor.Value
    if toolEnabled then
        applyAllTools()
    end
end)

localplayer_tab:AddDivider()

-- reuse top-level RunService
-- reuse top-level UserInputService
local TweenService = game:GetService("TweenService")

local OtherTab   = Window:AddTab("Other")

local LeftTabbox = OtherTab:AddLeftTabbox()

local SelfTab = LeftTabbox:AddTab("Self")

-- reuse top-level Players
-- reuse top-level RunService

local player = Players.LocalPlayer
local rootPart, humanoid = nil, nil

local fakeLagEnabled = false
local lagChance = 0.6
local freezeTime = 0.2
local skipTime = 0.1

local function setupChar(char)
    rootPart = char:WaitForChild("HumanoidRootPart")
    humanoid = char:WaitForChild("Humanoid")
end

player.CharacterAdded:Connect(setupChar)
if player.Character then setupChar(player.Character) end

local function applyFakeLag()
    if not humanoid or not fakeLagEnabled then return end
    if math.random() < lagChance then
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in pairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(0)
            end
            task.wait(freezeTime)
            for _, track in pairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(3)
            end
            task.wait(skipTime)
            for _, track in pairs(animator:GetPlayingAnimationTracks()) do
                track:AdjustSpeed(1)
            end
        end
    end
end

RunService.RenderStepped:Connect(function(dt)
    if not rootPart or not humanoid then return end

    if fakeLagEnabled then
        applyFakeLag()
    end
end)

SelfTab:AddToggle('FakeLagEnabled', {
    Text = 'Fake Lag',
    Default = false,
    Callback = function(Value)
        fakeLagEnabled = Value
    end
})

-- reuse top-level RunService
-- reuse top-level Players

local player = Players.LocalPlayer

local hrp, humanoid
local connection -- для хранения RenderStepped

local fakeAAEnabled = false

local function setFakeAA(enabled)
    fakeAAEnabled = enabled
    if enabled then
        if player.Character then
            humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if humanoid and hrp then
                humanoid.AutoRotate = false
                connection = RunService.RenderStepped:Connect(function()
                    if not fakeAAEnabled then return end
                    local moveDir = humanoid.MoveDirection
                    if moveDir.Magnitude > 0.01 then
                        local opposite = -moveDir.Unit
                        opposite = Vector3.new(opposite.X, 0, opposite.Z)
                        if opposite.Magnitude > 0.001 then
                            hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + opposite)
                        end
                    end
                end)
            end
        end
    else
        if connection then
            connection:Disconnect()
            connection = nil
        end
        if humanoid then
            humanoid.AutoRotate = true
        end
    end
end

player.CharacterAdded:Connect(function(char)
    humanoid = char:WaitForChild("Humanoid")
    hrp = char:WaitForChild("HumanoidRootPart")
    if not fakeAAEnabled then
        humanoid.AutoRotate = true
    end
end)

SelfTab:AddToggle('FakeAAEnabled', {
    Text = 'Fake AA', 
    Default = false,
    Callback = function(Value)
        setFakeAA(Value)
    end
})

-- reuse top-level Players
-- reuse top-level RunService
-- reuse top-level UserInputService

local player = Players.LocalPlayer
local rootPart, humanoid = nil, nil

-- bhop state
local bunnyHopEnabled = false
local rotationMode = "-180"
local bhopSpeed = 50
local spinSpeed = 10 -- deg per frame
local jitterAngle = 8 -- deg
local jumped = false
local wasOnGround = false
local stopPulseUntil = 0 -- tick() до которого держим горизонтальную скорость = 0

-- Character
local function setupChar(char)
    rootPart = char:WaitForChild("HumanoidRootPart")
    humanoid = char:WaitForChild("Humanoid")
    humanoid.AutoRotate = true
    wasOnGround = true
end
player.CharacterAdded:Connect(setupChar)
if player.Character then setupChar(player.Character) end

-- Jump input
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Space then
        jumped = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then
        jumped = false
        -- короткий стоп-импульс 0.01с для стабилизации после отжатия
        if bunnyHopEnabled and rootPart then
            stopPulseUntil = tick() + 0.01
        end
    end
end)

-- Camera planar dirs
local function getCameraDirs()
    local camCF = workspace.CurrentCamera.CFrame
    local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
    local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
    return forward, right
end

local function anyMovementDown()
    return UserInputService:IsKeyDown(Enum.KeyCode.W)
        or UserInputService:IsKeyDown(Enum.KeyCode.A)
        or UserInputService:IsKeyDown(Enum.KeyCode.S)
        or UserInputService:IsKeyDown(Enum.KeyCode.D)
end

local function isBhopActive()
    -- активен, если тумблер включён и (кейбинд не задан или зажат)
    local picker = Options.BhopKeybind
    local keyOk = true
    if picker and picker.GetState then
        keyOk = picker:GetState() or (picker.Value == nil or picker.Value == 'None')
    end
    return bunnyHopEnabled and keyOk
end

RunService.RenderStepped:Connect(function(dt)
    if not rootPart or not humanoid then return end

    if not isBhopActive() then
        humanoid.AutoRotate = true
        wasOnGround = true
        return
    end

    local state = humanoid:GetState()
    local onGround = (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics)

    -- На приземлении не обнуляем скорость, чтобы не "тормозить".
    -- Если нет нажатых кнопок — чуть подрезаем скольжение.
    if onGround and not wasOnGround then
        if not anyMovementDown() then
            rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
        end
    end
    wasOnGround = onGround

    -- короткий стоп-импульс после отпускания Space
    if stopPulseUntil > tick() then
        rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
        return
    end

    if onGround then
        -- на земле в штатный режим
        humanoid.AutoRotate = true
        return
    end

    local forward, right = getCameraDirs()

    -- В воздухе — основной bhop
    local move = Vector3.new()
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += forward end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= forward end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
    if move.Magnitude == 0 then move = forward end

    -- Включаем/выключаем авторотейт в зависимости от режима
    if rotationMode == "Jitter" then
        humanoid.AutoRotate = false
    else
        humanoid.AutoRotate = not jumped and true or false
    end

    if jumped then
        rootPart.AssemblyLinearVelocity = move.Unit * bhopSpeed + Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)

        if rotationMode == "spin" then
            rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(spinSpeed), 0)
        elseif rotationMode == "180" then
            local lookAt = rootPart.Position - forward
            rootPart.CFrame = CFrame.new(rootPart.Position, Vector3.new(lookAt.X, rootPart.Position.Y, lookAt.Z))
        elseif rotationMode == "-180" then
            local lookAt = rootPart.Position + forward
            rootPart.CFrame = CFrame.new(rootPart.Position, Vector3.new(lookAt.X, rootPart.Position.Y, lookAt.Z))
        elseif rotationMode == "jitter" then
            -- быстрый раскач по yaw, авто-ротейт выключен
            local sign = (math.floor(os.clock()*1000) % 2 == 0) and 1 or -1
            rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(sign * jitterAngle), 0)
        end
    else
        -- без Space в воздухе не трогаем горизонтальную скорость
    end
end)

local LeftTabbbox = OtherTab:AddLeftTabbox()
-- Tabs for bhop (в том же Tabbox, где 'Self')
local Tab11 = LeftTabbbox:AddTab('bhop')
local Tab22 = LeftTabbbox:AddTab('bhop settings')

Tab11:AddToggle('BunnyHopEnabled', {
    Text = 'bhop',
    Default = false,
    Callback = function(Value)
        bunnyHopEnabled = Value
    end
})
    :AddKeyPicker('bhopKeybind', {
        Default = 'None',
        SyncToggleState = true,
        Mode = 'Toggle',
        Text = 'bhop',
        NoUI = false
    })

Tab11:AddSlider('BhopSpeed', {
    Text = 'bhop speed',
    Default = 50,
    Min = 10,
    Max = 360,
    Rounding = 0,
    Compact = false,
    Callback = function(Value)
        bhopSpeed = Value
    end
})

Tab11:AddDropdown('RotationMode', {
    Values = { 'spin', '180', '-180', 'jitter' },
    Default = 4,
    Multi = false,
    Text = 'rotation mode',
    Callback = function(Value)
        rotationMode = Value
    end
})

Tab22:AddSlider('SpinSpeed', {
    Text = 'spin speed (deg/frame)',
    Default = 10,
    Min = 1,
    Max = 45,
    Rounding = 0,
    Callback = function(Value)
        spinSpeed = Value
    end
})

-- Разделитель и секция Jitter
Tab22:AddDivider()

Tab22:AddSlider('JitterAngle', {
    Text = 'jitter angle (deg)',
    Default = 8,
    Min = 1,
    Max = 30,
    Rounding = 0,
    Callback = function(Value)
        jitterAngle = Value
    end
})

SelfTab:AddDivider()

local flyEnabled = false
local flySpeed = 30 -- базовая скорость
local bodyGyro, bodyVel
local flyConnection
local noclipConnection

-- reuse top-level Players
-- reuse top-level UserInputService
-- reuse top-level RunService
local LocalPlayer = Players.LocalPlayer
-- reuse top-level Camera

local function disableFly()
    if flyConnection then
        flyConnection:Disconnect()
        flyConnection = nil
    end
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    if bodyGyro then
        bodyGyro:Destroy()
        bodyGyro = nil
    end
    if bodyVel then
        bodyVel:Destroy()
        bodyVel = nil
    end

    local character = LocalPlayer.Character
    if character then
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if humanoidRootPart then
            humanoidRootPart.CanCollide = true
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
            humanoid.WalkSpeed = 16
        end
    end
end

local function toggleFly(enabled)
    if enabled == flyEnabled then return end
    flyEnabled = enabled

    if not enabled then
        disableFly()
        return
    end

    local character = LocalPlayer.Character
    if not character then return end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    humanoid.WalkSpeed = 0
    humanoid.PlatformStand = true

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end

    noclipConnection = RunService.Stepped:Connect(function()
        if not flyEnabled then return end
        local currentChar = LocalPlayer.Character
        if currentChar then
            for _, part in ipairs(currentChar:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end)

    bodyGyro = Instance.new("BodyGyro")
    bodyGyro.P = 9e4
    bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bodyGyro.CFrame = humanoidRootPart.CFrame
    bodyGyro.Parent = humanoidRootPart

    bodyVel = Instance.new("BodyVelocity")
    bodyVel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bodyVel.Velocity = Vector3.zero
    bodyVel.Parent = humanoidRootPart

    flyConnection = RunService.RenderStepped:Connect(function()
        if not flyEnabled then return end

        local moveDir = Vector3.zero
        local cameraCF = Camera.CFrame
        local speed = flySpeed

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDir += cameraCF.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir -= cameraCF.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDir -= cameraCF.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir += cameraCF.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) then
            moveDir += cameraCF.UpVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
            moveDir -= cameraCF.UpVector
        end

        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit * speed
        end

        bodyGyro.CFrame = cameraCF
        bodyVel.Velocity = moveDir
    end)
end

LocalPlayer.CharacterAdded:Connect(function(newChar)
    if flyEnabled then
        task.wait(0.1)
        toggleFly(false)
        toggleFly(true)
    end
end)

SelfTab:AddSlider('FlySpeed', {
    Text = 'Fly Speed',
    Default = 100,
    Min = 0,
    Max = 1400,
    Rounding = 0,
    Compact = false,
    Callback = function(Value)
        flySpeed = Value
    end
})

SelfTab:AddLabel('Fly Key'):AddKeyPicker('FlyKeybind', {
    Default = 'F2',
    SyncToggleState = true,
    Mode = 'Toggle',
    Text = 'Fly',
    NoUI = false,
    Callback = function(Value)
        toggleFly(Value)
    end
})

local player = game:GetService("Players").LocalPlayer
-- reuse top-level RunService

SelfTab:AddDivider()

local uis = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local player = game.Players.LocalPlayer
local hrp

player.CharacterAdded:Connect(function(char)
    hrp = char:WaitForChild("HumanoidRootPart")
end)

if player.Character then
    hrp = player.Character:WaitForChild("HumanoidRootPart")
end

local moving = {
    W = false,
    S = false,
    A = false,
    D = false,
}

uis.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.W then moving.W = true end
    if input.KeyCode == Enum.KeyCode.S then moving.S = true end
    if input.KeyCode == Enum.KeyCode.A then moving.A = true end
    if input.KeyCode == Enum.KeyCode.D then moving.D = true end
end)

uis.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.W then moving.W = false end
    if input.KeyCode == Enum.KeyCode.S then moving.S = false end
    if input.KeyCode == Enum.KeyCode.A then moving.A = false end
    if input.KeyCode == Enum.KeyCode.D then moving.D = false end
end)

SelfTab:AddSlider('WalkTPSpeed', {
    Text = 'WalkSpeed Boost',
    Default = 0,
    Min = 0,
    Max = 240,
    Rounding = 0,
    Suffix = "%",
    Callback = function(Value)
        getgenv().WalkTPSpeed = Value
    end
})

-- Jump Power % (цикличное и без лагов)
local Players = game:GetService("Players")
-- reuse top-level RunService
local player = Players.LocalPlayer
local humanoid

local function attachHumanoid(char)
	humanoid = char:WaitForChild("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end
player.CharacterAdded:Connect(attachHumanoid)
if player.Character then attachHumanoid(player.Character) end

local function percentToJumpPower(p) -- -20..250
	if p >= 0 then
		return math.clamp(50 + 1.8 * p, 0, 500)
	else
		return math.clamp(50 + 2.5 * p, 0, 500)
	end
end

local jpPercent = 0
local lastApplied = nil

SelfTab:AddSlider('JumpPowerPercent', {
	Text = 'Jump Boost',
	Default = 0,
	Min = -20,
	Max = 240,
	Rounding = 0,
	Suffix = '%',
	Callback = function(p)
		jpPercent = p
	end
})

-- Мягкий цикл: проверяем и применяем только при расхождении
RunService.RenderStepped:Connect(function()
	if not humanoid or humanoid.Parent == nil then return end

	local target = percentToJumpPower(jpPercent)
	if lastApplied ~= target or not humanoid.UseJumpPower or humanoid.JumpPower ~= target then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = target
		lastApplied = target
	end
end)

runService.RenderStepped:Connect(function(dt)
    if hrp and getgenv().WalkTPSpeed and getgenv().WalkTPSpeed > 0 then
        local cam = workspace.CurrentCamera
        local moveVec = Vector3.zero

        local forward = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
        local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit

        if moving.W then moveVec = moveVec + forward end
        if moving.S then moveVec = moveVec - forward end
        if moving.A then moveVec = moveVec - right end
        if moving.D then moveVec = moveVec + right end

        if moveVec.Magnitude > 0 then
            local step = moveVec.Unit * getgenv().WalkTPSpeed * dt
            hrp.CFrame = hrp.CFrame + step
        end
    end
end)

local RightTabbox = OtherTab:AddRightTabbox()

local OtherTabb = OtherTab:AddRightTabbox()

local sounds_tab = OtherTabb:AddTab('Sounds')   

local player = game.Players.LocalPlayer

local sounds = {
    ["Gunshot"] = "rbxassetid://0",
    ["headshot"] = "rbxassetid://5764885315",
    ["minecraft bow"] = "rbxassetid://135478009117226",
    ["cs"] = "rbxassetid://7269900245",
    ["nu chto eshche?"] = "rbxassetid://133328523793428",
    ["nikto ne smeet mne prikazyvat"] = "rbxassetid://113736005207071",
    ["vot tak to luchshe"] = "rbxassetid://100302944137122",
    ["xz"] = "rbxassetid://84763750617501",
    ["stun"] = "rbxassetid://105951403871701",
}

local selectedSoundId = sounds["cs"] -- По умолчанию Gunshot

local function applyToCurrentTool()
    local char = player.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            local handle = tool:FindFirstChild("Handle")
            if handle then
                local gunKill = handle:FindFirstChild("GunKill")
                if gunKill and gunKill:IsA("Sound") then
                    gunKill.SoundId = selectedSoundId
                else
                end
                
                local gunShot = handle:FindFirstChild("Gunshot")
                if gunShot and gunShot:IsA("Sound") then
                    gunShot.SoundId = ""  -- Мьют (rbxassetid://0 может не работать, лучше пустая строка)
                else
                end
            end
        end
    end
end

local function setupCharacter(char)
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            spawn(function()
                wait(0.1) -- Немного больше задержки для полной инициализации
                applyToCurrentTool()
            end)
        end
    end)
    
    spawn(function()
        wait(0.1)
        applyToCurrentTool()
    end)
end

if player.Character then
    setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

sounds_tab:AddDropdown("KillSound", {
    Values = {"cs", "headshot", "minecraft bow", "nikto ne smeet mne prikazyvat", "nu chto eshche?", "vot tak to luchshe", "xz", "stun"},
    Default = 3,
    Multi = false,
    Text = "Kill Sound",
    Callback = function(Value)
        selectedSoundId = sounds[Value]
        applyToCurrentTool()
    end
})

sounds_tab:AddButton("Preview Kill Sound", function()
    -- Удаляем старый превью звук, если есть
    if player.Character then
        local prev = player.Character:FindFirstChild("PreviewKillSound")
        if prev and prev:IsA("Sound") then
            prev:Stop()
            prev:Destroy()
        end
        local s = Instance.new("Sound")
        s.Name = "PreviewKillSound"
        s.SoundId = selectedSoundId
        s.Volume = 1
        s.Parent = player.Character
        s.PlayOnRemove = false
        s:Play()
        -- Очистить после проигрывания
        s.Ended:Connect(function()
            s:Destroy()
        end)
    end
end)

local animEnabled = false
local animText = ""
local currentAnimThread = nil  -- ссылка на текущую анимацию, чтобы стопать старую

localplayer_tab:AddToggle('animnick', { 
    Text = 'Animated nick', 
    Default = false,
    Callback = function(Value)
        animEnabled = Value

        if not Value and currentAnimThread then
            task.cancel(currentAnimThread)
            currentAnimThread = nil
        end
    end
})

localplayer_tab:AddInput('MyTextbox', { 
    Default = 'Hello world!',
    Numeric = false,
    Finished = false,
    Text = 'Animated Nickname',
    Tooltip = 'Text for nickname animation',
    Placeholder = 'Enter nickname text',
    Callback = function(Value)
        animText = Value

        if not animEnabled then return end

        if currentAnimThread then
            task.cancel(currentAnimThread)
            currentAnimThread = nil
        end

        currentAnimThread = task.spawn(function()
            -- reuse top-level Players
            local player = Players.LocalPlayer
            if not player then return end

            local function getPlayerNameLabel()
                local char = player.Character or player.CharacterAdded:Wait()
                local hrp = char:WaitForChild("HumanoidRootPart", 5)
                if not hrp then return nil end
                local headTag = hrp:FindFirstChild("HeadTag")
                if not headTag then return nil end
                local streak = headTag:FindFirstChild("Streak")
                if not streak then return nil end
                local label = streak:FindFirstChild("playerName")
                return label
            end

            local nameLabel = getPlayerNameLabel()
            if not nameLabel then
                return
            end

            while animEnabled do
                for i = 1, #animText do
                    if not animEnabled then return end
                    nameLabel.Text = string.sub(animText, 1, i)
                    task.wait(0.08)
                end

                task.wait(1.2)

                for i = #animText, 1, -1 do
                    if not animEnabled then return end
                    nameLabel.Text = string.sub(animText, 1, i)
                    task.wait(0.05)
                end

                task.wait(0.4)
            end
        end)
    end
})

local OtherBox = RightTabbox:AddTab("Other")

OtherBox:AddButton('Remove fog', function()
    game.Lighting.FogEnd = 10000
    game.Lighting.FogStart = 0
end)

OtherBox:AddSlider('ssss', {
    Text = 'Brightness',
    Default = 3,
    Min = 0,
    Max = 10,
    Rounding = 1, -- в Linoria округление задаётся целым числом знаков после запятой
    Suffix = '', -- у Brightness нет процентов, лучше оставить пустым
    Callback = function(Value)
        game:GetService("Lighting").Brightness = Value
    end
})

OtherBox:AddDivider()

local SkyBoxes = {
    ["Night"] = {
        Bk = "http://www.roblox.com/asset/?id=48020371",
        Dn = "http://www.roblox.com/asset/?id=48020144",
        Ft = "http://www.roblox.com/asset/?id=48020234",
        Lf = "http://www.roblox.com/asset/?id=48020211",
        Rt = "http://www.roblox.com/asset/?id=48020254",
        Up = "http://www.roblox.com/asset/?id=48020383",
    },
    ["Green"] = {
        Bk = "rbxassetid://11941775243",
        Dn = "rbxassetid://11941774975",
        Ft = "rbxassetid://11941774655",
        Lf = "rbxassetid://11941774369",
        Rt = "rbxassetid://11941774042",
        Up = "rbxassetid://11941773718",
    },
    ["Pink"] = {
        Bk = "http://www.roblox.com/asset/?id=271042516",
        Dn = "http://www.roblox.com/asset/?id=271077243",
        Ft = "http://www.roblox.com/asset/?id=271042556",
        Lf = "http://www.roblox.com/asset/?id=271042310",
        Rt = "http://www.roblox.com/asset/?id=271042467",
        Up = "http://www.roblox.com/asset/?id=271077958",
    },
    ["Moon"] = {
        Bk = "rbxassetid://159454299",
        Dn = "rbxassetid://159454296",
        Ft = "rbxassetid://159454293",
        Lf = "rbxassetid://159454286",
        Rt = "rbxassetid://159454300",
        Up = "rbxassetid://159454288",
    },
    ["Black"] = {
        Bk = "http://www.roblox.com/asset/?ID=2013298",
        Dn = "http://www.roblox.com/asset/?ID=2013298",
        Ft = "http://www.roblox.com/asset/?ID=2013298",
        Lf = "http://www.roblox.com/asset/?ID=2013298",
        Rt = "http://www.roblox.com/asset/?ID=2013298",
        Up = "http://www.roblox.com/asset/?ID=2013298",
    }
}

local function ApplySky(data)
    if not data then return end -- защита от nil

    for _, v in pairs(game.Lighting:GetChildren()) do
        if v:IsA("Sky") then
            v:Destroy()
        end
    end

    local sky = Instance.new("Sky")
    sky.Name = "ColorfulSky"
    sky.SkyboxBk = data.Bk
    sky.SkyboxDn = data.Dn
    sky.SkyboxFt = data.Ft
    sky.SkyboxLf = data.Lf
    sky.SkyboxRt = data.Rt
    sky.SkyboxUp = data.Up
    sky.SunAngularSize = 21
    sky.SunTextureId = ""
    sky.MoonTextureId = ""
    sky.Parent = game.Lighting
end

OtherBox:AddDropdown("SkySelector", {
    Values = {"Night", "Green", "Pink", "Moon", "Black"},
    Default = 5,
    Multi = false,
    Text = "Skybox",

    Callback = function(Value)
        ApplySky(SkyBoxes[Value])
    end
})

ApplySky(SkyBoxes["Black"])

local L = game:GetService("Lighting")
local Defaults = {
    Ambient = L.Ambient,
    OutdoorAmbient = L.OutdoorAmbient
}

OtherBox:AddToggle('AmbientToggle', { Text = 'Ambient override', Default = false })
    :AddColorPicker('AmbientColor', { Default = Color3.fromRGB(54, 57, 241) })

Toggles.AmbientToggle:OnChanged(function()
    if Toggles.AmbientToggle.Value then
        local c = Options.AmbientColor.Value
        L.Ambient = c
        L.OutdoorAmbient = c
    else
        L.Ambient = Defaults.Ambient
        L.OutdoorAmbient = Defaults.OutdoorAmbient
    end
end)

Options.AmbientColor:OnChanged(function()
    if Toggles.AmbientToggle.Value then
        local c = Options.AmbientColor.Value
        L.Ambient = c
        L.OutdoorAmbient = c
    end
end)

OtherBox:AddDivider()

OtherBox:AddButton('Unlock camera', function()
    -- reuse top-level Players
    local player = Players.LocalPlayer

    player.CameraMaxZoomDistance = 9999

    player.CameraMode = Enum.CameraMode.Classic
end)

local player = game.Players.LocalPlayer
local camera = workspace.CurrentCamera

OtherBox:AddToggle('InvisiCamEnabled', {
    Text = 'Enable InvisiCam',
    Default = false,
    Tooltip = 'Makes walls transparent when blocking view',
    Callback = function(value)
        if value then
            player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
            player.DevComputerCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
            player.DevTouchCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
        else
            player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom
            player.DevComputerCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom
            player.DevTouchCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom
        end
    end
})

local RunService = game:GetService("RunService")
-- reuse top-level Camera

local fovValue = 70 -- начальное значение FOV

OtherBox:AddSlider('FovSlider', {
    Text = 'Fov',
    Default = fovValue,
    Min = 10,
    Max = 120,
    Rounding = 1,
    Callback = function(Value)
        fovValue = Value
    end
})

RunService.RenderStepped:Connect(function()
    if Camera then
        Camera.FieldOfView = fovValue
    end
end)

local Tabs = {
    ['Settings'] = Window:AddTab('Settings'),
}

local MenuGroup = Tabs['Settings']:AddLeftGroupbox('Menu')

        Library.KeybindFrame.Visible = true;

MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddButton('Rejoin', function()
-- reuse top-level Players
local LocalPlayer = Players.LocalPlayer
local MarketplaceService = game:GetService("MarketplaceService")
local TeleportService = game:GetService("TeleportService")

       local ok, err = pcall(function()
           TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
       end)
       if not ok then
       end
end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
ThemeManager:SetFolder('MyScriptHub')
SaveManager:SetFolder('MyScriptHub/specific-game')
SaveManager:BuildConfigSection(Tabs['Settings'])
ThemeManager:ApplyToTab(Tabs['Settings'])
SaveManager:LoadAutoloadConfig()
