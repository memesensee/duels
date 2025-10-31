-- init
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

-- variables
getgenv().SilentAimSettings = Settings
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

local mouse_box = Drawing.new("Square")
mouse_box.Visible = true 
mouse_box.ZIndex = 999 
mouse_box.Color = Color3.fromRGB(54, 57, 241)
mouse_box.Thickness = 20 
mouse_box.Size = Vector2.new(20, 20)
mouse_box.Filled = true 

local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1
fov_circle.NumSides = 100
fov_circle.Radius = 180
fov_circle.Filled = false
fov_circle.Visible = false
fov_circle.ZIndex = 999
fov_circle.Transparency = 1
fov_circle.Color = Color3.fromRGB(54, 57, 241)

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
    -- // Floor the percentage
    Percentage = math.floor(Percentage)

    -- // Get the chance
    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100

    -- // Return
    return chance <= Percentage / 100
end


--[[file handling]] do 
    if not isfolder(MainFileName) then 
        makefolder(MainFileName);
    end
    
    if not isfolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) then 
        makefolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))
    end
end

local Files = listfiles(string.format("%s/%s", "UniversalSilentAim", tostring(game.PlaceId)))

-- functions
local function GetFiles() -- credits to the linoria lib for this function, listfiles returns the files full path and its annoying
	local out = {}
	for i = 1, #Files do
		local file = Files[i]
		if file:sub(-4) == '.lua' then
			-- i hate this but it has to be done ...

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
        if Toggles.TeamCheck.Value and Player.Team == LocalPlayer.Team then continue end

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
    
    mouse_box.Visible = SilentAimSettings.Enabled

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
    Main:AddDropdown("Method", {AllowNull = true, Text = "Silent Aim Method", Default = SilentAimSettings.SilentAimMethod, Values = {
        "Raycast","FindPartOnRay",
        "FindPartOnRayWithWhitelist",
        "FindPartOnRayWithIgnoreList",
        "Mouse.Hit/Target"
    }}):OnChanged(function() 
        SilentAimSettings.SilentAimMethod = Options.Method.Value 
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
local FieldOfViewBOX = GeneralTab:AddLeftTabbox("Field Of View") do
    local Main = FieldOfViewBOX:AddTab("")
    
    Main:AddToggle("Visible", {Text = "Show FOV Circle"}):AddColorPicker("Color", {Default = Color3.fromRGB(54, 57, 241)}):OnChanged(function()
        fov_circle.Visible = Toggles.Visible.Value
        SilentAimSettings.FOVVisible = Toggles.Visible.Value
    end)
    Main:AddSlider("Radius", {Text = "FOV Circle Radius", Min = 0, Max = 360, Default = 130, Rounding = 0}):OnChanged(function()
        fov_circle.Radius = Options.Radius.Value
        SilentAimSettings.FOVRadius = Options.Radius.Value
    end)
    Main:AddToggle("MousePosition", {Text = "Show Silent Aim Target"}):AddColorPicker("MouseVisualizeColor", {Default = Color3.fromRGB(54, 57, 241)}):OnChanged(function()
        mouse_box.Visible = Toggles.MousePosition.Value 
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
        if Toggles.MousePosition.Value and Toggles.aim_Enabled.Value then
            if getClosestPlayer() then 
                local Root = getClosestPlayer().Parent.PrimaryPart or getClosestPlayer()
                local RootToViewportPoint, IsOnScreen = WorldToViewportPoint(Camera, Root.Position);
                -- using PrimaryPart instead because if your Target Part is "Random" it will flicker the square between the Target's Head and HumanoidRootPart (its annoying)
                
                mouse_box.Visible = IsOnScreen
                mouse_box.Position = Vector2.new(RootToViewportPoint.X, RootToViewportPoint.Y)
            else 
                mouse_box.Visible = false 
                mouse_box.Position = Vector2.new()
            end
        end
        
        if Toggles.Visible.Value then 
            fov_circle.Visible = Toggles.Visible.Value
            fov_circle.Color = Options.Color.Value
            fov_circle.Position = getMousePosition()
        end
    end)
end))

local autoshotConnection
local lastShot = 0

Toggles.Autoshot:OnChanged(function()
    if Toggles.Autoshot.Value then
        autoshotConnection = RunService.Heartbeat:Connect(function()
            if not Toggles.aim_Enabled.Value then return end
            local Closest = getClosestPlayer()
            if Closest and tick() - lastShot >= (SilentAimSettings.AutoshotDelay / 1000 + 0.01) then
                mouse1press()
                task.wait(0.01)  -- Время "hold" клика, можно увеличить до 0.05 если не работает
                mouse1release()
                lastShot = tick()
            end
        end)
    else
        if autoshotConnection then
            autoshotConnection:Disconnect()
            autoshotConnection = nil
        end
    end
end)

-- hooks
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
    local Method = getnamecallmethod()
    local Arguments = {...}
    local self = Arguments[1]
    local chance = CalculateChance(SilentAimSettings.HitChance)
    if Toggles.aim_Enabled.Value and self == workspace and not checkcaller() and chance == true then
        if Method == "FindPartOnRayWithIgnoreList" and Options.Method.Value == Method then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithIgnoreList) then
                local A_Ray = Arguments[2]

                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)

                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif Method == "FindPartOnRayWithWhitelist" and Options.Method.Value == Method then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithWhitelist) then
                local A_Ray = Arguments[2]

                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)

                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif (Method == "FindPartOnRay" or Method == "findPartOnRay") and Options.Method.Value:lower() == Method:lower() then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRay) then
                local A_Ray = Arguments[2]

                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)

                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif Method == "Raycast" and Options.Method.Value == Method then
            if ValidateArguments(Arguments, ExpectedArguments.Raycast) then
                local A_Origin = Arguments[2]

                local HitPart = getClosestPlayer()
                if HitPart then
                    Arguments[3] = getDirection(A_Origin, HitPart.Position)

                    return oldNamecall(unpack(Arguments))
                end
            end
        end
    end
    return oldNamecall(...)
end))

local oldIndex = nil 
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
    if self == Mouse and not checkcaller() and Toggles.aim_Enabled.Value and Options.Method.Value == "Mouse.Hit/Target" and getClosestPlayer() then
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

-- Левый Tabbox (исправлено на левый, так как используется AddLeftTabbox)
local rage_left = rage:AddLeftTabbox()

local players_tab = rage_left:AddTab("Players")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Radius = 800
local TeleportCooldown = 0.1

local LocalPlayer = Players.LocalPlayer
local activeConnections = {}  -- Для хранения подключений, чтобы отключать при тоггле off
local lastTeleportTimes = {}  -- {Player = lastTime}
local isEnabled = false

-- Функция для запуска эффекта от конкретного Tool
local function startEffect(tool)
    if not isEnabled then return end
    
    local character = tool.Parent
    if not character or not character:IsA("Model") then return end
    if Players:GetPlayerFromCharacter(character) ~= LocalPlayer then return end
    
    local handle = tool:FindFirstChild("Handle")
    if not handle then return end
    
    -- Сбрасываем таймеры при экипировке
    lastTeleportTimes = {}
    
    local effectConnection = RunService.Heartbeat:Connect(function()
        if not isEnabled then return end  -- Проверяем каждый тик
        
        local rightHand = character:FindFirstChild("RightHand")
        if not rightHand then return end
        
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then return end
        
        local gripCFrame = rightHand.CFrame * tool.Grip
        local gripPosition = gripCFrame.Position
        local direction = gripCFrame.LookVector
        
        local currentTime = tick()
        
        for _, otherPlayer in pairs(Players:GetPlayers()) do
            if otherPlayer == LocalPlayer then continue end
            
            local otherCharacter = otherPlayer.Character
            if not otherCharacter then continue end
            
            local otherRoot = otherCharacter:FindFirstChild("HumanoidRootPart")
            if not otherRoot then continue end
            
            local distance = (otherRoot.Position - gripPosition).Magnitude
            
            if distance <= Radius then
                local lastTime = lastTeleportTimes[otherPlayer] or 0
                if currentTime - lastTime >= TeleportCooldown then
                    otherRoot.CFrame = CFrame.lookAt(gripPosition, gripPosition + direction)
                    
                    -- Проверка на застревание (сразу после телепорта)
                    local newDistance = (otherRoot.Position - gripPosition).Magnitude
                    if newDistance > 10 then
                        otherRoot.CFrame = CFrame.lookAt(gripPosition, gripPosition + direction)
                    end
                    
                    lastTeleportTimes[otherPlayer] = currentTime
                end
            end
        end
    end)
    
    activeConnections[tool] = effectConnection
end

-- Функция для остановки эффекта от Tool
local function stopEffect(tool)
    local connection = activeConnections[tool]
    if connection then
        connection:Disconnect()
        activeConnections[tool] = nil
    end
    
    -- Отпускание игроков (если инструмент еще в руках)
    local character = tool.Parent
    if character and character:IsA("Model") and isEnabled then  -- Только если enabled, но на самом деле для отпускания всегда
        local rightHand = character:FindFirstChild("RightHand")
        if rightHand then
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                local gripCFrame = rightHand.CFrame * tool.Grip
                local gripPosition = gripCFrame.Position
                local direction = gripCFrame.LookVector
                
                for _, otherPlayer in pairs(Players:GetPlayers()) do
                    if otherPlayer == LocalPlayer then continue end
                    
                    local otherCharacter = otherPlayer.Character
                    if not otherCharacter then continue end
                    
                    local otherRoot = otherCharacter:FindFirstChild("HumanoidRootPart")
                    if not otherRoot then continue end
                    
                    local distance = (otherRoot.Position - gripPosition).Magnitude
                    if distance <= Radius + 50 then
                        local offset = otherRoot.Position - gripPosition
                        local dist = offset.Magnitude
                        local releasePosition
                        if dist > 1 then
                            releasePosition = otherRoot.Position + offset.Unit * 20
                        else
                            releasePosition = gripPosition + direction * -20
                        end
                        otherRoot.CFrame = CFrame.lookAt(releasePosition, releasePosition + direction)
                    end
                end
            end
        end
    end
end

-- Функция для подключения мониторинга Tools персонажа
local function connectCharacterMonitoring(character)
    -- Отключаем старые, если есть
    for tool, conn in pairs(activeConnections) do
        if tool.Parent == character then
            stopEffect(tool)
        end
    end
    
    -- Новые подключения
    local childAddedConn = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and isEnabled then
            child.Equipped:Connect(function()
                startEffect(child)
            end)
            child.Unequipped:Connect(function()
                stopEffect(child)
            end)
        end
    end)
    
    -- ChildRemoved для очистки
    local childRemovedConn = character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            stopEffect(child)
        end
    end)
    
    -- Уже существующие Tools
    for _, child in pairs(character:GetChildren()) do
        if child:IsA("Tool") and isEnabled then
            child.Equipped:Connect(function()
                startEffect(child)
            end)
            child.Unequipped:Connect(function()
                stopEffect(child)
            end)
            if child.Parent == character then  -- Уже equipped
                startEffect(child)
            end
        end
    end
    
    -- Сохраняем подключения мониторинга
    activeConnections[character] = {childAdded = childAddedConn, childRemoved = childRemovedConn}
end

-- Функция для отключения мониторинга персонажа
local function disconnectCharacterMonitoring(character)
    local monitoring = activeConnections[character]
    if monitoring then
        if monitoring.childAdded then monitoring.childAdded:Disconnect() end
        if monitoring.childRemoved then monitoring.childRemoved:Disconnect() end
        activeConnections[character] = nil
    end
    
    -- Останавливаем все эффекты для Tools в этом персонаже
    for tool, _ in pairs(activeConnections) do
        if tool.Parent == character and tool:IsA("Tool") then
            stopEffect(tool)
        end
    end
end

-- Основная функция для старта/стопа всего
local function toggleTpPlayers(value)
    isEnabled = value
    lastTeleportTimes = {}
    
    if value then
        -- Подключаем мониторинг для текущего персонажа
        if LocalPlayer.Character then
            connectCharacterMonitoring(LocalPlayer.Character)
        end
        -- И для будущих респавнов
        local charAddedConn = LocalPlayer.CharacterAdded:Connect(function(character)
            wait(1)  -- Ждем загрузки
            connectCharacterMonitoring(character)
        end)
        activeConnections["charAdded"] = charAddedConn
    else
        -- Отключаем все
        if LocalPlayer.Character then
            disconnectCharacterMonitoring(LocalPlayer.Character)
        end
        local charAdded = activeConnections["charAdded"]
        if charAdded then
            charAdded:Disconnect()
            activeConnections["charAdded"] = nil
        end
        -- Останавливаем все активные эффекты
        for tool, _ in pairs(activeConnections) do
            if tool:IsA("Tool") then
                stopEffect(tool)
            end
        end
        activeConnections = {}
    end
end

-- Теперь интегрируем в твой GUI
players_tab:AddToggle('tpplayers', {
    Text = 'tp players', 
    Default = false,
    Callback = function(Value)
        toggleTpPlayers(Value)
    end
})

local visuals = Window:AddTab("Visuals")

-- Левый Tabbox (исправлено на левый)
local visuals_right = visuals:AddLeftTabbox()

-- Добавляем Tab в левый Tabbox (исправлена опечатка в имени переменной)
local localplayer_tabb = visuals_right:AddTab("Enemy")

-- Левый Tabbox (исправлено на левый)
local visuals_left = visuals:AddRightTabbox()

-- Добавляем Tab в левый Tabbox (исправлена опечатка в имени переменной)
local localplayer_tab = visuals_left:AddTab("LocalPlayer")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local coneColor = Color3.fromRGB(54, 57, 241) -- Начальный цвет
local conePart = nil -- Хранит текущий конус
local enabled = false -- Флаг для включения/выключения

-- Функция для создания конуса
local function createCone(character)
    if not enabled or not character or not character:FindFirstChild("Head") then return end

    -- Удаляем старый конус, если он есть
    if conePart and conePart.Parent then
        conePart:Destroy()
    end

    local head = character.Head

    -- Создаём конус
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

-- Проверяем наличие конуса и обновляем цвет
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
        -- обновляем цвет
        hatExists.Color = coneColor
    end
end

-- Автоматическое пересоздание при респавне
player.CharacterAdded:Connect(function(character)
    createCone(character)
    
    -- Проверяем конус каждую секунду (на случай удаления)
    while character and character:IsDescendantOf(game) do
        checkCone()
        task.wait(1)
    end
end)

-- Если персонаж уже есть при запуске скрипта
if player.Character then
    createCone(player.Character)
end

-- UI Elements for China Hat
localplayer_tab:AddToggle('ChinahatToggle', { Text = 'Chinahat', Default = false })
    :AddColorPicker('ChinahatColor', { Default = Color3.fromRGB(54, 57, 241) })

-- Реакция на ВКЛ/ВЫКЛ тумблера
Toggles.ChinahatToggle:OnChanged(function()
    enabled = Toggles.ChinahatToggle.Value
    checkCone()
end)

-- Если меняем цвет — применяем его
Options.ChinahatColor:OnChanged(function()
    coneColor = Options.ChinahatColor.Value
    checkCone()
end)

local highlights = {}
local espEnabled = false
local refreshCoroutine = nil
local distanceCoroutine = nil
local currentColor = Color3.fromRGB(54, 57, 241)
local maxDistance = 1000

-- ✅ Получаем атрибут команды игрока (TeamRed/TeamBlue и т.д.)
local function getTeam(player)
    local team = player:GetAttribute("Team")
    if not team then
    else
    end
    return team
end

-- ✅ Проверяем враг / союзник по атрибутам
local function isEnemy(player)
    local localPlayer = game.Players.LocalPlayer
    local localTeam = getTeam(localPlayer)
    local targetTeam = getTeam(player)

    -- если у кого-то нет команды, ESP не работает
    if not localTeam or not targetTeam then
 
        return false
    end

    local isEnemyCheck = localTeam ~= targetTeam
    if isEnemyCheck then

    else

    end
    return isEnemyCheck
end

-- ✅ Проверяем жив ли игрок (Died атрибут + Humanoid)
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

-- ✅ Создание подсветки
local function createHighlight(character)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = currentColor
    highlight.OutlineColor = currentColor
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.Parent = character
    return highlight
end

-- ✅ Расчёт дистанции
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

-- ✅ Добавление ESP
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

-- ✅ Удаление ESP
local function removeHighlight(player)
    if highlights[player] then
        highlights[player]:Destroy()
        highlights[player] = nil
    end
end

-- ✅ Настройка игрока
local function setupPlayer(player)
    local distFunc = getDistance()
    local dist = distFunc(player)
    local character = player.Character
    local alive = isAlive(character)
    if dist <= maxDistance and isEnemy(player) and alive then
        addHighlight(player)
    end

    -- При респауне
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

    -- Обновление при смене атрибута Team
    player:GetAttributeChangedSignal("Team"):Connect(function()
        if espEnabled then
            if isEnemy(player) then
                addHighlight(player)
            else
                removeHighlight(player)
            end
        end
    end)

    -- Обновление при изменении Died
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

    -- Очистка при выходе
    player.AncestryChanged:Connect(function()
        if not player.Parent then
            removeHighlight(player)
        end
    end)
end

-- ✅ Обновление дистанции
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

-- ✅ Полное обновление ESP
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

-- ✅ Циклы
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

-- ✅ UI
localplayer_tabb:AddToggle('EspToggle', { Text = 'Esp', Default = false })
    :AddColorPicker('EspColor', { Default = Color3.fromRGB(54, 57, 241) })

Toggles.EspToggle:OnChanged(function(value)
    espEnabled = value
    currentColor = Options.EspColor.Value

    if value then
        local localTeam = getTeam(game.Players.LocalPlayer)
        if not localTeam then
            espEnabled = false
            return
        end

        for _, player in ipairs(game.Players:GetPlayers()) do
            setupPlayer(player)
        end

        game.Players.PlayerAdded:Connect(setupPlayer)
        startDistanceLoop()
        startRefreshLoop()
    else
        for _, player in ipairs(game.Players:GetPlayers()) do
            removeHighlight(player)
        end
        highlights = {}
        stopLoops()
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
        if espEnabled then
            updateDistances()
        end
    end
})

-- Variables
local playerEnabled = false
local toolEnabled = false
local toolCol = Color3.fromRGB(255, 0, 0)
local playerCol = Color3.fromRGB(255, 255, 255)

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

-- =========================
-- Functions for player (with ForceField material)
-- =========================
function applyPlayer()
    if not Character then return end

    -- Change material and color of all player parts
    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Material = Enum.Material.ForceField
            part.Color = playerCol
            -- Preserve CanCollide
            part.CanCollide = part.CanCollide
        end
    end
end

function resetPlayer()
    if not Character then return end

    -- Reset to default material and color
    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Material = Enum.Material.Plastic
            part.Color = Color3.fromRGB(255, 255, 255)
            -- Preserve CanCollide
            part.CanCollide = part.CanCollide
        end
    end
end

-- =========================
-- Functions for tools
-- =========================
function applyTool(tool)
    if not tool:IsA("Tool") then return end
    for _, part in pairs(tool:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Material = Enum.Material.ForceField
            part.Color = toolCol
            -- Preserve CanCollide
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
            -- Preserve CanCollide
            part.CanCollide = part.CanCollide
        end
    end
end

function applyAllTools()
    -- Apply to tools in Backpack
    for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
        applyTool(tool)
    end
    -- Apply to equipped tool in Character (held item)
    for _, tool in pairs(Character:GetChildren()) do
        if tool:IsA("Tool") then
            applyTool(tool)
        end
    end
end

function resetTools()
    -- Reset tools in Backpack
    for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") then
            resetTool(tool)
        end
    end
    -- Reset equipped tool in Character
    for _, tool in pairs(Character:GetChildren()) do
        if tool:IsA("Tool") then
            resetTool(tool)
        end
    end
end

-- =========================
-- Event Setup
-- =========================
local function setupCharacterEvents()
    Character.ChildAdded:Connect(function(child)
        if toolEnabled and child:IsA("Tool") then
            applyTool(child)
        end
    end)
end

-- Handle new tools added to Backpack
LocalPlayer.Backpack.ChildAdded:Connect(function(child)
    if toolEnabled and child:IsA("Tool") then
        applyTool(child)
    end
end)

-- Initial setup
setupCharacterEvents()

-- Handle character respawn
LocalPlayer.CharacterAdded:Connect(function(newChar)
    Character = newChar
    if playerEnabled then
        applyPlayer()
    end
    if toolEnabled then
        -- Apply to any immediately equipped tool
        for _, tool in pairs(Character:GetChildren()) do
            if tool:IsA("Tool") then
                applyTool(tool)
            end
        end
    end
    setupCharacterEvents()
end)

-- Cyclic update to ensure application sticks without lagging (every 2 seconds)
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

-- =========================
-- UI Elements
-- =========================

-- ForceField on player
localplayer_tab:AddToggle("ForceFieldPlayerToggle", {
    Text = "ForceField on Player",
    Default = false
}) :AddColorPicker('PlayerColor', {
    Default = Color3.fromRGB(255, 255, 255)
})

-- Toggle for tools
localplayer_tab:AddToggle("ToolMaterialToggle", {
    Text = "Tool FF",
    Default = false
}) :AddColorPicker('ToolColor', {
    Default = Color3.fromRGB(255, 0, 0)
})

-- OnChanged for player toggle
Toggles.ForceFieldPlayerToggle:OnChanged(function()
    playerEnabled = Toggles.ForceFieldPlayerToggle.Value
    if playerEnabled then
        applyPlayer()
    else
        resetPlayer()
    end
end)

-- OnChanged for player color
Options.PlayerColor:OnChanged(function()
    playerCol = Options.PlayerColor.Value
    if playerEnabled then
        applyPlayer()
    end
end)

-- OnChanged for tool toggle
Toggles.ToolMaterialToggle:OnChanged(function()
    toolEnabled = Toggles.ToolMaterialToggle.Value
    if toolEnabled then
        applyAllTools()
    else
        resetTools()
    end
end)

-- OnChanged for tool color
Options.ToolColor:OnChanged(function()
    toolCol = Options.ToolColor.Value
    if toolEnabled then
        applyAllTools()
    end
end)

localplayer_tab:AddDivider()

-- Сервисы
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local OtherTab   = Window:AddTab("Other")

-- таббокс слева (обычно без названия при создании)
local LeftTabbox = OtherTab:AddLeftTabbox()

-- сам таб внутри таббокса
local SelfTab = LeftTabbox:AddTab("Self")

--// Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local rootPart, humanoid = nil, nil

--// BunnyHop Vars
local bunnyHopEnabled = false
local jumped = false
local rotationMode = "Forward"
local bhopSpeed = 50 -- дефолт

--// FakeLag Vars
local fakeLagEnabled = false
local lagChance = 0.6
local freezeTime = 0.2
local skipTime = 0.1

--// Character Handler
local function setupChar(char)
    rootPart = char:WaitForChild("HumanoidRootPart")
    humanoid = char:WaitForChild("Humanoid")
    humanoid.AutoRotate = true
end

player.CharacterAdded:Connect(setupChar)
if player.Character then setupChar(player.Character) end

--// Input Handling
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Space then
        jumped = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space then
        jumped = false
    end
end)

--// Camera Directions
local function getCameraDirs()
    local camCF = workspace.CurrentCamera.CFrame
    local forward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z).Unit
    local right = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
    return forward, right
end

--// FakeLag Function
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

--// Main Loop
RunService.RenderStepped:Connect(function(dt)
    if not rootPart or not humanoid then return end

    -- FakeLag check
    if fakeLagEnabled then
        applyFakeLag()
    end

    -- BunnyHop check
    if not bunnyHopEnabled then
        humanoid.AutoRotate = true
        return
    end

    local state = humanoid:GetState()
    local onGround = (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics)

    if onGround then
        humanoid.AutoRotate = true
        return
    end

    if jumped then
        humanoid.AutoRotate = false

        local forward, right = getCameraDirs()
        local move = Vector3.new()

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += forward end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= forward end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
        if move.Magnitude == 0 then move = forward end

        rootPart.AssemblyLinearVelocity = move.Unit * bhopSpeed + Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)

        if rotationMode == "Spin" then
            rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(10), 0)

        elseif rotationMode == "180" then
            local lookAt = rootPart.Position - forward
            rootPart.CFrame = CFrame.new(rootPart.Position, Vector3.new(lookAt.X, rootPart.Position.Y, lookAt.Z))

        elseif rotationMode == "Forward" then
            rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + forward)
        end
    else
        humanoid.AutoRotate = true
    end
end)

-- UI Elements
SelfTab:AddToggle('FakeLagEnabled', {
    Text = 'Fake Lag',
    Default = false,
    Callback = function(Value)
        fakeLagEnabled = Value
    end
})

local RunService = game:GetService("RunService")
local player = game.Players.LocalPlayer

local hrp, humanoid
local connection -- для хранения RenderStepped

-- Функция включения/выключения Fake AA
local function setFakeAA(enabled)
	if enabled then
		if player.Character then
			humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if humanoid and hrp then
				humanoid.AutoRotate = false
				-- Подключаем RenderStepped
				connection = RunService.RenderStepped:Connect(function()
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
		-- Отключаем Fake AA
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if humanoid then
			humanoid.AutoRotate = true
		end
	end
end

-- Linoria Toggle
SelfTab:AddToggle('FakeLagEnabled', {
	Text = 'Fake aa', 
	Default = false,
	Callback = function(Value)
		setFakeAA(Value)
	end
})

SelfTab:AddDivider()

-- Подписка на смену персонажа (чтобы работало при respawn)
player.CharacterAdded:Connect(function(char)
	humanoid = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")
end)


SelfTab:AddToggle('BunnyHopEnabled', {
    Text = 'Bunny Hop',
    Default = false,
    Callback = function(Value)
        bunnyHopEnabled = Value
    end
})

SelfTab:AddSlider('BhopSpeed', {
    Text = 'Bhop Speed',
    Default = 50,
    Min = 10,
    Max = 360,
    Rounding = 0,
    Compact = false,
    Callback = function(Value)
        bhopSpeed = Value
    end
})

SelfTab:AddDropdown('RotationMode', {
    Values = { 'Spin', '180', 'Forward' },
    Default = 3,
    Multi = false,
    Text = 'Rotation Mode',
    Callback = function(Value)
        rotationMode = Value
    end
})

SelfTab:AddDivider()

local flyEnabled = false
local flySpeed = 30 -- базовая скорость
local bodyGyro, bodyVel
local flyConnection
local noclipConnection

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- disable fly and noclip
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

-- toggle fly
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

    -- Initial noclip for all parts
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end

    -- Continuous noclip enforcement for all parts
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

-- Handle respawn
LocalPlayer.CharacterAdded:Connect(function(newChar)
    if flyEnabled then
        task.wait(0.1)
        toggleFly(false)
        toggleFly(true)
    end
end)

-- Fly Speed slider
SelfTab:AddSlider('FlySpeed', {
    Text = 'Fly Speed',
    Default = 100,
    Min = 0,
    Max = 200,
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

SelfTab:AddDivider()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

fcRunning = false
local Camera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	local newCamera = workspace.CurrentCamera
	if newCamera then
		Camera = newCamera
	end
end)

local INPUT_PRIORITY = Enum.ContextActionPriority.High.Value

Spring = {} do
	Spring.__index = Spring

	function Spring.new(freq, pos)
		local self = setmetatable({}, Spring)
		self.f = freq
		self.p = pos
		self.v = pos*0
		return self
	end

	function Spring:Update(dt, goal)
		local f = self.f*2*math.pi
		local p0 = self.p
		local v0 = self.v

		local offset = goal - p0
		local decay = math.exp(-f*dt)

		local p1 = goal + (v0*dt - offset*(f*dt + 1))*decay
		local v1 = (f*dt*(offset*f - v0) + v0)*decay

		self.p = p1
		self.v = v1

		return p1
	end

	function Spring:Reset(pos)
		self.p = pos
		self.v = pos*0
	end
end

local cameraPos = Vector3.new()
local cameraRot = Vector2.new()

local velSpring = Spring.new(5, Vector3.new())
local panSpring = Spring.new(5, Vector2.new())

local cameraFov = 70

Input = {} do

	keyboard = {
		W = 0,
		A = 0,
		S = 0,
		D = 0,
		E = 0,
		Q = 0,
		Up = 0,
		Down = 0,
		LeftShift = 0,
	}

	mouse = {
		Delta = Vector2.new(),
	}

	NAV_KEYBOARD_SPEED = Vector3.new(1, 1, 1)
	PAN_MOUSE_SPEED = Vector2.new(1, 1)*(math.pi/64)
	NAV_ADJ_SPEED = 0.75
	NAV_SHIFT_MUL = 0.25

	navSpeed = 1

	function Input.Vel(dt)
		navSpeed = math.clamp(navSpeed + dt*(keyboard.Up - keyboard.Down)*NAV_ADJ_SPEED, 0.01, 4)

		local kKeyboard = Vector3.new(
			keyboard.D - keyboard.A,
			keyboard.E - keyboard.Q,
			keyboard.S - keyboard.W
		)*NAV_KEYBOARD_SPEED

		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)

		return (kKeyboard)*(navSpeed*(shift and NAV_SHIFT_MUL or 1))
	end

	function Input.Pan(dt)
		local kMouse = mouse.Delta*PAN_MOUSE_SPEED
		mouse.Delta = Vector2.new()
		return kMouse
	end

	do
		function Keypress(action, state, input)
			keyboard[input.KeyCode.Name] = state == Enum.UserInputState.Begin and 1 or 0
			return Enum.ContextActionResult.Sink
		end

		function MousePan(action, state, input)
			local delta = input.Delta
			mouse.Delta = Vector2.new(-delta.y, -delta.x)
			return Enum.ContextActionResult.Sink
		end

		function Zero(t)
			for k, v in pairs(t) do
				t[k] = v*0
			end
		end

		function Input.StartCapture()
			ContextActionService:BindActionAtPriority("FreecamKeyboard",Keypress,false,INPUT_PRIORITY,
				Enum.KeyCode.W,
				Enum.KeyCode.A,
				Enum.KeyCode.S,
				Enum.KeyCode.D,
				Enum.KeyCode.E,
				Enum.KeyCode.Q,
				Enum.KeyCode.Up,
				Enum.KeyCode.Down
			)
			ContextActionService:BindActionAtPriority("FreecamMousePan",MousePan,false,INPUT_PRIORITY,Enum.UserInputType.MouseMovement)
		end

		function Input.StopCapture()
			navSpeed = 1
			Zero(keyboard)
			Zero(mouse)
			ContextActionService:UnbindAction("FreecamKeyboard")
			ContextActionService:UnbindAction("FreecamMousePan")
		end
	end
end

function GetFocusDistance(cameraFrame)
	local znear = 0.1
	local viewport = Camera.ViewportSize
	local projy = 2*math.tan(math.rad(cameraFov/2))
	local projx = viewport.x/viewport.y*projy
	local fx = cameraFrame.RightVector
	local fy = cameraFrame.UpVector
	local fz = cameraFrame.LookVector

	local minVect = Vector3.new()
	local minDist = 512

	for x = 0, 1, 0.5 do
		for y = 0, 1, 0.5 do
			local cx = (x - 0.5)*projx
			local cy = (y - 0.5)*projy
			local offset = fx*cx - fy*cy + fz
			local origin = cameraFrame.Position + offset*znear
			local direction = offset.Unit * minDist
			local result = workspace:Raycast(origin, direction)
			local dist = minDist
			local hit = origin + direction
			if result then
				hit = result.Position
				dist = (hit - origin).Magnitude
			end
			if minDist > dist then
				minDist = dist
				minVect = offset.Unit
			end
		end
	end

	return fz:Dot(minVect)*minDist
end

local function StepFreecam(dt)
	local vel = velSpring:Update(dt, Input.Vel(dt))
	local pan = panSpring:Update(dt, Input.Pan(dt))

	local zoomFactor = math.sqrt(math.tan(math.rad(70/2))/math.tan(math.rad(cameraFov/2)))

	cameraRot = cameraRot + pan*Vector2.new(0.75, 1)*8*(dt/zoomFactor)
	cameraRot = Vector2.new(math.clamp(cameraRot.x, -math.rad(90), math.rad(90)), cameraRot.y%(2*math.pi))

	local cameraCFrame = CFrame.new(cameraPos)*CFrame.fromOrientation(cameraRot.x, cameraRot.y, 0)*CFrame.new(vel*Vector3.new(1, 1, 1)*64*dt)
	cameraPos = cameraCFrame.Position

	Camera.CFrame = cameraCFrame
	Camera.Focus = cameraCFrame*CFrame.new(0, 0, -GetFocusDistance(cameraCFrame))
	Camera.FieldOfView = cameraFov
end

local PlayerState = {} do
	mouseBehavior = ""
	mouseIconEnabled = ""
	cameraType = ""
	cameraFocus = ""
	cameraCFrame = ""
	cameraFieldOfView = ""

	function PlayerState.Push()
		cameraFieldOfView = Camera.FieldOfView
		Camera.FieldOfView = 70

		cameraType = Camera.CameraType
		Camera.CameraType = Enum.CameraType.Custom

		cameraCFrame = Camera.CFrame
		cameraFocus = Camera.Focus

		mouseIconEnabled = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true

		mouseBehavior = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	function PlayerState.Pop()
		Camera.FieldOfView = cameraFieldOfView
		cameraFieldOfView = nil

		Camera.CameraType = cameraType
		cameraType = nil

		Camera.CFrame = cameraCFrame
		cameraCFrame = nil

		Camera.Focus = cameraFocus
		cameraFocus = nil

		UserInputService.MouseIconEnabled = mouseIconEnabled
		mouseIconEnabled = nil

		UserInputService.MouseBehavior = mouseBehavior
		mouseBehavior = nil
	end
end

function StartFreecam(pos)
	if fcRunning then
		StopFreecam()
	end
	local cameraCFrame = Camera.CFrame
	if pos then
		cameraCFrame = pos
	end
	cameraRot = Vector2.new()
	cameraPos = cameraCFrame.Position
	cameraFov = 70

	velSpring:Reset(Vector3.new())
	panSpring:Reset(Vector2.new())

	PlayerState.Push()
	RunService:BindToRenderStep("Freecam", Enum.RenderPriority.Camera.Value, StepFreecam)
	Input.StartCapture()
	fcRunning = true
end

function StopFreecam()
	if not fcRunning then return end
	Input.StopCapture()
	RunService:UnbindFromRenderStep("Freecam")
	PlayerState.Pop()
	fcRunning = false
end

-- GUI Integration
SelfTab:AddLabel('FreeCam'):AddKeyPicker('fckey', {
    Default = 'F1',
    SyncToggleState = true,
    Mode = 'Toggle',
    Text = 'Free cam',
    NoUI = false,
    Callback = function(Value)
        if Value then
            StartFreecam()
        else
            StopFreecam()
        end
    end
})

local player = game:GetService("Players").LocalPlayer
local RunService = game:GetService("RunService")

SelfTab:AddDivider()

-- // WalkSpeed Boost (TP-style movement)
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

-- Состояние кнопок
local moving = {
    W = false,
    S = false,
    A = false,
    D = false,
}

-- Обработка нажатия
uis.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.W then moving.W = true end
    if input.KeyCode == Enum.KeyCode.S then moving.S = true end
    if input.KeyCode == Enum.KeyCode.A then moving.A = true end
    if input.KeyCode == Enum.KeyCode.D then moving.D = true end
end)

-- Обработка отпускания
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

-- Плавное движение
runService.RenderStepped:Connect(function(dt)
    if hrp and getgenv().WalkTPSpeed and getgenv().WalkTPSpeed > 0 then
        local cam = workspace.CurrentCamera
        local moveVec = Vector3.zero

        -- Берём векторы камеры, обнуляем Y (движение только по земле)
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

local player = game.Players.LocalPlayer

local sounds = {
    ["Gunshot"] = "rbxassetid://0",
    ["Headshot"] = "rbxassetid://5764885315",
    ["minecraft bow"] = "rbxassetid://135478009117226",
    ["cs"] = "rbxassetid://7269900245",
}

local selectedSoundId = sounds["cs"] -- По умолчанию Gunshot

local function applyToCurrentTool()
    local char = player.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            local handle = tool:FindFirstChild("Handle")
            if handle then
                -- Для GunKill (kill sound)
                local gunKill = handle:FindFirstChild("GunKill")
                if gunKill and gunKill:IsA("Sound") then
                    gunKill.SoundId = selectedSoundId
                else
                end
                
                -- Для второго звука (Gunshot, mute на id=0 или пустой)
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
                wait(0.2) -- Немного больше задержки для полной инициализации
                applyToCurrentTool()
            end)
        end
    end)
    
    -- Применяем к текущему инструменту, если есть
    spawn(function()
        wait(0.5)
        applyToCurrentTool()
    end)
end

if player.Character then
    setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

-- Дропдаун для выбора звука (только для GunKill, Gunshot мутится всегда)
localplayer_tab:AddDropdown("KillSound", {
    Values = {"Headshot", "minecraft bow", "cs"},
    Default = 3,
    Multi = false,
    Text = "Kill Sound",
    Callback = function(Value)
        selectedSoundId = sounds[Value]
        applyToCurrentTool()
    end
})

localplayer_tab:AddDivider()

local animEnabled = false
local animText = ""
local currentAnimThread = nil  -- ссылка на текущую анимацию, чтобы стопать старую

localplayer_tab:AddToggle('animnick', { 
    Text = 'Animated nick', 
    Default = false,
    Callback = function(Value)
        animEnabled = Value

        -- если выключили toggle — убить текущую анимацию
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

        -- если toggle выключен — не делать ничего
        if not animEnabled then return end

        -- если старая анимация была — убиваем её
        if currentAnimThread then
            task.cancel(currentAnimThread)
            currentAnimThread = nil
        end

        -- запускаем новую анимацию
        currentAnimThread = task.spawn(function()
            local Players = game:GetService("Players")
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
                -- эффект печати
                for i = 1, #animText do
                    if not animEnabled then return end
                    nameLabel.Text = string.sub(animText, 1, i)
                    task.wait(0.08)
                end

                task.wait(1.2)

                -- эффект стирания
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


-- таббокс слева (обычно без названия при создании)
local RightTabbox = OtherTab:AddRightTabbox()

-- сам таб внутри таббокса
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

-- сразу Night ставим
ApplySky(SkyBoxes["Black"])

-- Сохраним дефолтные значения, чтобы было куда возвращать
local L = game:GetService("Lighting")
local Defaults = {
    Ambient = L.Ambient,
    OutdoorAmbient = L.OutdoorAmbient
}

-- Тумблер + цвет
OtherBox:AddToggle('AmbientToggle', { Text = 'Ambient override', Default = false })
    :AddColorPicker('AmbientColor', { Default = Color3.fromRGB(54, 57, 241) })

-- Реакция на ВКЛ/ВЫКЛ тумблера
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

-- Если меняем цвет — применяем его, но только когда тумблер включён
Options.AmbientColor:OnChanged(function()
    if Toggles.AmbientToggle.Value then
        local c = Options.AmbientColor.Value
        L.Ambient = c
        L.OutdoorAmbient = c
    end
end)

OtherBox:AddDivider()

OtherBox:AddButton('Unlock camera', function()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer

    -- Set maximum zoom distance to a large number
    player.CameraMaxZoomDistance = 9999

    -- Set camera mode to Classic
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
local Camera = workspace.CurrentCamera

local fovValue = 70 -- начальное значение FOV

-- Слайдер для изменения FOV
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

-- Loop для обновления FOV каждый кадр
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
    -- Сервисы
local Players = game:GetService("Players")
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