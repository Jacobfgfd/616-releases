--!nocheck
-- 616 :: Roblox Rivals skinchanger
-- INSERT toggles UI. Right-Shift toggles backdrop lock.
-- Loads via: loadstring(game:HttpGet("<raw-url>"))()

local VERSION    = "1.0.0"
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local TS         = game:GetService("TweenService")
local HTTP       = game:GetService("HttpService")
local CoreGui    = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local LP         = Players.LocalPlayer

-- =====================================================================
-- parent host — tries gethui()/CoreGui/PlayerGui so it survives teleports
-- =====================================================================
local function host()
    local ok, g = pcall(function() return gethui() end)
    if ok and g then return g end
    if CoreGui and CoreGui:FindFirstChild("RobloxGui") then return CoreGui end
    return LP:WaitForChild("PlayerGui")
end

-- strip any previous instance
for _, name in ipairs({"616_UI","616_LOGO","616_BACKDROP"}) do
    local old = host():FindFirstChild(name)
    if old then old:Destroy() end
end

-- =====================================================================
-- Rivals weapon / skin surface (resilient to minor layout changes)
-- Rivals stores weapons under player's Backpack + Character. Skin data
-- is a StringValue / ObjectValue named "Skin" or "SkinId" on the tool,
-- or an Attribute "Skin". We cover all three and also hook the
-- ReplicatedStorage skin-equip remote if present.
-- =====================================================================
local SkinAPI = {}

function SkinAPI:getTools()
    local tools = {}
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then tools[#tools+1] = t end
        end
    end
    local char = LP.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then tools[#tools+1] = t end
        end
    end
    return tools
end

function SkinAPI:findSkinFolder()
    for _, name in ipairs({"Skins","SkinList","Cosmetics","WeaponSkins","Items"}) do
        local f = RS:FindFirstChild(name, true)
        if f then return f end
    end
    return nil
end

function SkinAPI:listSkinsForWeapon(weaponName)
    local out = {}
    local folder = self:findSkinFolder()
    if folder then
        local sub = folder:FindFirstChild(weaponName) or folder:FindFirstChild(weaponName.."Skins")
        local src = sub or folder
        for _, c in ipairs(src:GetChildren()) do
            out[#out+1] = c.Name
        end
    end
    -- always allow "Default"
    table.insert(out, 1, "Default")
    -- dedupe
    local seen, dedup = {}, {}
    for _, n in ipairs(out) do
        if not seen[n] then seen[n] = true; dedup[#dedup+1] = n end
    end
    table.sort(dedup, function(a,b) return a:lower() < b:lower() end)
    return dedup
end

function SkinAPI:applyToTool(tool, skinName)
    if not tool or not tool.Parent then return false end

    -- 1) Attribute route
    pcall(function() tool:SetAttribute("Skin", skinName) end)

    -- 2) StringValue "Skin"
    local sv = tool:FindFirstChild("Skin")
    if sv and sv:IsA("StringValue") then
        pcall(function() sv.Value = skinName end)
    elseif not sv then
        pcall(function()
            local nv = Instance.new("StringValue")
            nv.Name = "Skin"
            nv.Value = skinName
            nv.Parent = tool
        end)
    end

    -- 3) RemoteEvent route — "EquipSkin" / "SetSkin"
    for _, name in ipairs({"EquipSkin","SetSkin","ApplySkin","ChangeSkin","SkinEquip"}) do
        local r = RS:FindFirstChild(name, true)
        if r and r:IsA("RemoteEvent") then
            pcall(function() r:FireServer(tool.Name, skinName) end)
        elseif r and r:IsA("RemoteFunction") then
            pcall(function() r:InvokeServer(tool.Name, skinName) end)
        end
    end

    -- 4) client-side mesh/texture swap from ReplicatedStorage.Skins.<weapon>.<skin>
    local folder = self:findSkinFolder()
    if folder then
        local wf = folder:FindFirstChild(tool.Name) or folder:FindFirstChild(tool.Name.."Skins")
        local skin = wf and wf:FindFirstChild(skinName) or folder:FindFirstChild(skinName)
        if skin then
            for _, part in ipairs(tool:GetDescendants()) do
                if part:IsA("MeshPart") then
                    local src = skin:FindFirstChild(part.Name, true)
                    if src and src:IsA("MeshPart") then
                        pcall(function()
                            part.TextureID = src.TextureID
                            part.MeshId    = src.MeshId
                            part.Color     = src.Color
                        end)
                    end
                elseif part:IsA("SpecialMesh") then
                    local src = skin:FindFirstChild(part.Parent and part.Parent.Name or "", true)
                    if src and src:FindFirstChildOfClass("SpecialMesh") then
                        local m = src:FindFirstChildOfClass("SpecialMesh")
                        pcall(function()
                            part.MeshId    = m.MeshId
                            part.TextureId = m.TextureId
                        end)
                    end
                end
            end
        end
    end

    return true
end

function SkinAPI:applyAll(weaponName, skinName)
    for _, t in ipairs(self:getTools()) do
        if t.Name == weaponName then
            self:applyToTool(t, skinName)
        end
    end
end

-- auto-reapply when character respawns / tools re-added
local Equipped = {} -- [weaponName] = skinName
local function hookTool(t)
    if Equipped[t.Name] then
        task.spawn(function() task.wait(0.2); SkinAPI:applyToTool(t, Equipped[t.Name]) end)
    end
end
local function hookChar(char)
    char.ChildAdded:Connect(function(c) if c:IsA("Tool") then hookTool(c) end end)
    for _, c in ipairs(char:GetChildren()) do if c:IsA("Tool") then hookTool(c) end end
end
LP.CharacterAdded:Connect(hookChar)
if LP.Character then hookChar(LP.Character) end
local bp = LP:WaitForChild("Backpack")
bp.ChildAdded:Connect(hookTool)

-- =====================================================================
-- UI — self-contained Roblox GUI, 616 brand, dark + crimson + glow,
-- spinning 616 center, backdrop modal lock.
-- =====================================================================
local UI = {}
UI.ACCENT   = Color3.fromRGB(230, 25, 40)
UI.BG       = Color3.fromRGB(10, 10, 12)
UI.PANEL    = Color3.fromRGB(18, 18, 22)
UI.PANEL2   = Color3.fromRGB(26, 26, 32)
UI.TEXT     = Color3.fromRGB(240, 240, 245)
UI.MUTED    = Color3.fromRGB(140, 140, 150)

local function corner(inst, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = inst; return c
end
local function stroke(inst, t, col)
    local s = Instance.new("UIStroke"); s.Thickness = t or 1
    s.Color = col or UI.ACCENT; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = inst; return s
end
local function pad(inst, p)
    local u = Instance.new("UIPadding")
    u.PaddingTop = UDim.new(0, p); u.PaddingBottom = UDim.new(0, p)
    u.PaddingLeft = UDim.new(0, p); u.PaddingRight = UDim.new(0, p)
    u.Parent = inst; return u
end

-- ---- backdrop (modal lock) ----
local Backdrop = Instance.new("ScreenGui")
Backdrop.Name = "616_BACKDROP"
Backdrop.IgnoreGuiInset = true
Backdrop.DisplayOrder = 9998
Backdrop.ResetOnSpawn = false
Backdrop.Parent = host()

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1,1)
dim.BackgroundColor3 = Color3.fromRGB(0,0,0)
dim.BackgroundTransparency = 1
dim.BorderSizePixel = 0
dim.ZIndex = 1
dim.Parent = Backdrop

-- vignette gradient
local vig = Instance.new("UIGradient")
vig.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(30,0,5)),
})
vig.Rotation = 90
vig.Parent = dim

-- eat input while menu open (modal lock)
local block = Instance.new("TextButton")
block.Size = UDim2.fromScale(1,1)
block.BackgroundTransparency = 1
block.Text = ""
block.AutoButtonColor = false
block.Modal = true
block.ZIndex = 2
block.Parent = Backdrop

-- ---- spinning 616 logo ----
local LogoGui = Instance.new("ScreenGui")
LogoGui.Name = "616_LOGO"
LogoGui.IgnoreGuiInset = true
LogoGui.DisplayOrder = 9999
LogoGui.ResetOnSpawn = false
LogoGui.Parent = host()

local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.fromOffset(340, 340)
ring.BackgroundTransparency = 1
ring.Parent = LogoGui

-- outer rotating stroke
local ringStroke = Instance.new("Frame")
ringStroke.AnchorPoint = Vector2.new(0.5,0.5)
ringStroke.Position = UDim2.fromScale(0.5,0.5)
ringStroke.Size = UDim2.fromScale(1,1)
ringStroke.BackgroundTransparency = 1
ringStroke.Parent = ring
local c1 = Instance.new("UICorner"); c1.CornerRadius = UDim.new(1,0); c1.Parent = ringStroke
local s1 = Instance.new("UIStroke"); s1.Thickness = 2; s1.Color = UI.ACCENT; s1.Transparency = 0.4
s1.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s1.Parent = ringStroke

local ringGrad = Instance.new("UIGradient")
ringGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
    ColorSequenceKeypoint.new(0.5, UI.ACCENT),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(80,0,10)),
})
ringGrad.Parent = s1

-- inner rotating tick ring
local tickRing = Instance.new("Frame")
tickRing.AnchorPoint = Vector2.new(0.5,0.5)
tickRing.Position = UDim2.fromScale(0.5,0.5)
tickRing.Size = UDim2.fromScale(0.85,0.85)
tickRing.BackgroundTransparency = 1
tickRing.Parent = ring
-- build 24 tick marks around it
for i = 0, 23 do
    local tick = Instance.new("Frame")
    tick.AnchorPoint = Vector2.new(0.5,0.5)
    tick.Size = UDim2.fromOffset(3, 14)
    tick.BackgroundColor3 = UI.ACCENT
    tick.BackgroundTransparency = 0.3
    tick.BorderSizePixel = 0
    tick.Rotation = i * 15
    local angle = math.rad(i * 15 - 90)
    local r = 130
    tick.Position = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(math.cos(angle)*r, math.sin(angle)*r)
    tick.Parent = tickRing
end

-- the big 616 text
local logo = Instance.new("TextLabel")
logo.AnchorPoint = Vector2.new(0.5,0.5)
logo.Position = UDim2.fromScale(0.5,0.5)
logo.Size = UDim2.fromOffset(240, 200)
logo.BackgroundTransparency = 1
logo.Text = "616"
logo.Font = Enum.Font.GothamBlack
logo.TextSize = 140
logo.TextColor3 = UI.ACCENT
logo.TextStrokeTransparency = 0.6
logo.TextStrokeColor3 = Color3.fromRGB(255,0,30)
logo.Parent = ring

-- glow halo
local halo = Instance.new("ImageLabel")
halo.AnchorPoint = Vector2.new(0.5,0.5)
halo.Position = UDim2.fromScale(0.5,0.5)
halo.Size = UDim2.fromScale(1.6,1.6)
halo.BackgroundTransparency = 1
halo.Image = "rbxasset://textures/ui/Glow.png"
halo.ImageColor3 = UI.ACCENT
halo.ImageTransparency = 0.5
halo.ZIndex = 0
halo.Parent = ring

LogoGui.Enabled   = false
Backdrop.Enabled  = false

-- animation loop
local spinConn
local function startSpin()
    if spinConn then return end
    spinConn = RunService.RenderStepped:Connect(function(dt)
        ringStroke.Rotation = (ringStroke.Rotation + dt * 55) % 360
        tickRing.Rotation   = (tickRing.Rotation   - dt * 30) % 360
        local p = math.sin(tick() * 2) * 0.5 + 0.5
        logo.TextTransparency = 0.05 + p * 0.25
        halo.ImageTransparency = 0.35 + p * 0.25
        logo.TextStrokeTransparency = 0.4 + p * 0.3
    end)
end
local function stopSpin() if spinConn then spinConn:Disconnect(); spinConn = nil end end

-- ---- main window ----
local Main = Instance.new("ScreenGui")
Main.Name = "616_UI"
Main.IgnoreGuiInset = true
Main.DisplayOrder = 10000
Main.ResetOnSpawn = false
Main.Parent = host()

local win = Instance.new("Frame")
win.AnchorPoint = Vector2.new(0.5,0.5)
win.Position = UDim2.fromScale(0.5, 0.5)
win.Size = UDim2.fromOffset(820, 520)
win.BackgroundColor3 = UI.BG
win.BackgroundTransparency = 0.05
win.BorderSizePixel = 0
win.Parent = Main
corner(win, 12)
stroke(win, 1, Color3.fromRGB(60, 10, 15))

-- header
local hdr = Instance.new("Frame")
hdr.Size = UDim2.new(1, 0, 0, 56)
hdr.BackgroundColor3 = UI.PANEL
hdr.BorderSizePixel = 0
hdr.Parent = win
corner(hdr, 12)
-- flatten bottom
local hdrFlat = Instance.new("Frame")
hdrFlat.Size = UDim2.new(1, 0, 0, 12); hdrFlat.Position = UDim2.new(0, 0, 1, -12)
hdrFlat.BackgroundColor3 = UI.PANEL; hdrFlat.BorderSizePixel = 0; hdrFlat.Parent = hdr

local brand = Instance.new("TextLabel")
brand.Size = UDim2.new(0, 120, 1, 0)
brand.Position = UDim2.fromOffset(16, 0)
brand.BackgroundTransparency = 1
brand.Font = Enum.Font.GothamBlack
brand.TextSize = 30
brand.Text = "616"
brand.TextColor3 = UI.ACCENT
brand.TextXAlignment = Enum.TextXAlignment.Left
brand.Parent = hdr

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -300, 1, 0)
subtitle.Position = UDim2.fromOffset(120, 0)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 13
subtitle.Text = "  rivals skinchanger  ·  INSERT toggle"
subtitle.TextColor3 = UI.MUTED
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = hdr

local function headerBtn(text, x, w)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, 32)
    b.Position = UDim2.new(1, -x, 0, 12)
    b.BackgroundColor3 = UI.PANEL2
    b.BorderSizePixel = 0
    b.Text = text
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 13
    b.TextColor3 = UI.TEXT
    b.AutoButtonColor = false
    b.Parent = hdr
    corner(b, 6)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = UI.ACCENT end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = UI.PANEL2 end)
    return b
end
local btnRescan = headerBtn("Rescan",    270, 100)
local btnReset  = headerBtn("Reset all", 160, 130)
local btnClose  = headerBtn("×",         42,  32)
btnClose.Font = Enum.Font.GothamBold
btnClose.TextSize = 20

-- body
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -56 - 48)
body.Position = UDim2.fromOffset(0, 56)
body.BackgroundTransparency = 1
body.Parent = win

-- sidebar: weapons
local side = Instance.new("Frame")
side.Size = UDim2.new(0, 220, 1, -20)
side.Position = UDim2.fromOffset(12, 10)
side.BackgroundColor3 = UI.PANEL
side.BorderSizePixel = 0
side.Parent = body
corner(side, 10); pad(side, 10)

local sideTitle = Instance.new("TextLabel")
sideTitle.Size = UDim2.new(1, 0, 0, 20)
sideTitle.BackgroundTransparency = 1
sideTitle.Font = Enum.Font.GothamSemibold; sideTitle.TextSize = 12
sideTitle.Text = "WEAPONS"
sideTitle.TextColor3 = UI.MUTED
sideTitle.TextXAlignment = Enum.TextXAlignment.Left
sideTitle.Parent = side

local weaponList = Instance.new("ScrollingFrame")
weaponList.Size = UDim2.new(1, 0, 1, -26)
weaponList.Position = UDim2.fromOffset(0, 26)
weaponList.BackgroundTransparency = 1
weaponList.BorderSizePixel = 0
weaponList.CanvasSize = UDim2.fromOffset(0,0)
weaponList.AutomaticCanvasSize = Enum.AutomaticSize.Y
weaponList.ScrollBarThickness = 3
weaponList.ScrollBarImageColor3 = UI.ACCENT
weaponList.Parent = side
local wLay = Instance.new("UIListLayout"); wLay.Padding = UDim.new(0,4); wLay.Parent = weaponList

-- right panel: skins
local right = Instance.new("Frame")
right.Size = UDim2.new(1, -244, 1, -20)
right.Position = UDim2.fromOffset(240, 10)
right.BackgroundColor3 = UI.PANEL
right.BorderSizePixel = 0
right.Parent = body
corner(right, 10); pad(right, 12)

local search = Instance.new("TextBox")
search.Size = UDim2.new(1, 0, 0, 32)
search.BackgroundColor3 = UI.PANEL2
search.BorderSizePixel = 0
search.Font = Enum.Font.Gotham
search.TextSize = 13
search.PlaceholderText = "  search skins…"
search.Text = ""
search.ClearTextOnFocus = false
search.TextColor3 = UI.TEXT
search.PlaceholderColor3 = UI.MUTED
search.TextXAlignment = Enum.TextXAlignment.Left
search.Parent = right
corner(search, 6); pad(search, 8)

local skinScroll = Instance.new("ScrollingFrame")
skinScroll.Size = UDim2.new(1, 0, 1, -44)
skinScroll.Position = UDim2.fromOffset(0, 40)
skinScroll.BackgroundTransparency = 1
skinScroll.BorderSizePixel = 0
skinScroll.CanvasSize = UDim2.fromOffset(0,0)
skinScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
skinScroll.ScrollBarThickness = 3
skinScroll.ScrollBarImageColor3 = UI.ACCENT
skinScroll.Parent = right
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(170, 70)
grid.CellPadding = UDim2.fromOffset(8, 8)
grid.SortOrder = Enum.SortOrder.Name
grid.Parent = skinScroll

-- footer status
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 24)
status.Position = UDim2.new(0, 12, 1, -36)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.Text = "v"..VERSION.."  ·  waiting for input"
status.TextColor3 = UI.MUTED
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = win

-- ---- populate weapons + skins ----
local selectedWeapon = nil
local function clearChildren(parent)
    for _, c in ipairs(parent:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
    end
end

local function renderSkins()
    clearChildren(skinScroll)
    if not selectedWeapon then return end
    local items = SkinAPI:listSkinsForWeapon(selectedWeapon)
    local q = search.Text:lower()
    for _, name in ipairs(items) do
        if q == "" or name:lower():find(q, 1, true) then
            local card = Instance.new("TextButton")
            card.BackgroundColor3 = (Equipped[selectedWeapon] == name) and UI.ACCENT or UI.PANEL2
            card.BorderSizePixel = 0
            card.Text = ""
            card.AutoButtonColor = false
            card.Parent = skinScroll
            corner(card, 8)

            local n = Instance.new("TextLabel")
            n.Size = UDim2.new(1, -16, 0, 22)
            n.Position = UDim2.fromOffset(10, 10)
            n.BackgroundTransparency = 1
            n.Font = Enum.Font.GothamSemibold; n.TextSize = 14
            n.Text = name
            n.TextColor3 = UI.TEXT
            n.TextXAlignment = Enum.TextXAlignment.Left
            n.Parent = card

            local st = Instance.new("TextLabel")
            st.Size = UDim2.new(1, -16, 0, 16)
            st.Position = UDim2.fromOffset(10, 36)
            st.BackgroundTransparency = 1
            st.Font = Enum.Font.Gotham; st.TextSize = 11
            st.Text = (Equipped[selectedWeapon] == name) and "EQUIPPED" or "tap to equip"
            st.TextColor3 = (Equipped[selectedWeapon] == name) and Color3.fromRGB(10,10,10) or UI.MUTED
            st.TextXAlignment = Enum.TextXAlignment.Left
            st.Parent = card

            card.MouseButton1Click:Connect(function()
                Equipped[selectedWeapon] = name
                SkinAPI:applyAll(selectedWeapon, name)
                status.Text = "equipped  "..selectedWeapon.."  →  "..name
                renderSkins()
            end)
        end
    end
end

local function renderWeapons()
    clearChildren(weaponList)
    local tools = SkinAPI:getTools()
    local seen = {}
    for _, t in ipairs(tools) do
        if not seen[t.Name] then
            seen[t.Name] = true
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, 0, 0, 30)
            b.BackgroundColor3 = (t.Name == selectedWeapon) and UI.ACCENT or UI.PANEL2
            b.BorderSizePixel = 0
            b.Text = "  "..t.Name
            b.TextColor3 = (t.Name == selectedWeapon) and Color3.fromRGB(10,10,10) or UI.TEXT
            b.Font = Enum.Font.GothamSemibold; b.TextSize = 13
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.AutoButtonColor = false
            b.Parent = weaponList
            corner(b, 6)
            b.MouseButton1Click:Connect(function()
                selectedWeapon = t.Name
                renderWeapons(); renderSkins()
            end)
        end
    end
    if not next(seen) then
        local e = Instance.new("TextLabel")
        e.Size = UDim2.new(1, 0, 0, 40)
        e.BackgroundTransparency = 1
        e.Font = Enum.Font.Gotham; e.TextSize = 12
        e.Text = "no weapons in backpack"
        e.TextColor3 = UI.MUTED
        e.TextWrapped = true
        e.Parent = weaponList
    end
end

btnRescan.MouseButton1Click:Connect(function() renderWeapons(); renderSkins() end)
btnReset .MouseButton1Click:Connect(function()
    for w, _ in pairs(Equipped) do SkinAPI:applyAll(w, "Default") end
    Equipped = {}
    status.Text = "all skins reset to default"
    renderSkins()
end)
search.Changed:Connect(function(prop) if prop == "Text" then renderSkins() end end)

-- ---- open / close with fade + modal lock ----
local open = false
local function setOpen(v)
    open = v
    Backdrop.Enabled = v
    LogoGui.Enabled  = v
    Main.Enabled     = v
    if v then
        startSpin()
        TS:Create(dim, TweenInfo.new(0.25), {BackgroundTransparency = 0.35}):Play()
        win.Size = UDim2.fromOffset(820, 520)
        win.GroupTransparency = nil
        renderWeapons(); renderSkins()
    else
        stopSpin()
        dim.BackgroundTransparency = 1
    end
end
setOpen(false)

btnClose.MouseButton1Click:Connect(function() setOpen(false) end)

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        setOpen(not open)
    elseif input.KeyCode == Enum.KeyCode.End and UIS:IsKeyDown(Enum.KeyCode.LeftShift) then
        -- unload
        Main:Destroy(); Backdrop:Destroy(); LogoGui:Destroy()
        stopSpin()
    end
end)

-- startup notify
pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "616",
        Text  = "skinchanger loaded. press INSERT.",
        Duration = 4,
    })
end)

setOpen(true)
