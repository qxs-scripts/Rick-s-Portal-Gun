--[[
	RICK'S PORTAL GUN  -  EXECUTOR VERSION  (v3)
	Paste into your executor and run it in-game. Nothing needs to be placed in Studio.

	Hotkeys (gun must be equipped):
		Z  close all portals        X  link two portals (aim + click)
		C  portal menu              V  portal to the nearest player

	Creates the tool itself, auto-equips it, builds the UI, and cleans up after itself
	if you execute it again. Everything is client-side (only you see it).
	Waypoints are saved to your executor's workspace folder (RicksPortalGun/).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
while not player do
	task.wait()
	player = Players.LocalPlayer
end
local playerGui = player:WaitForChild("PlayerGui")

-- Re-execution safety: tear down the previous copy first.
local env = _G
pcall(function()
	if getgenv then
		env = getgenv()
	end
end)
if env.RicksPortalGunCleanup then
	pcall(env.RicksPortalGunCleanup)
end

local conns = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

-- Where to put GUIs (hidden UI container if the executor has one).
local guiParent = playerGui
pcall(function()
	if gethui then
		local h = gethui()
		if h then
			guiParent = h
		end
	end
end)

-- Make sure the hotbar is available so the tool can be equipped by hand.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
end)

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local CONFIG = {
	TOOL_NAME = "Rick's Portal Gun",
	TOOLTIP = "Just a 20 minute adventure, Morty.",

	SOUND_SHOOT = "rbxassetid://1013378689",
	SOUND_ENTER = "rbxassetid://84183563421633",
	SOUND_CLOSE = "rbxassetid://79092478163364",
	SOUND_VOLUME = 1,

	GUN_SCALE = 0.6, -- size of the gun model (1 = default, 1.5 = bigger, 0.7 = smaller)
	GUN_TILT = 0, -- degrees the muzzle points up in your hand (0 = level)

	PORTAL_WIDTH = 8,
	PORTAL_HEIGHT = 12,
	PORTAL_LIFETIME = 10, -- seconds before portals fade
	SHOOT_RANGE = 500,
	B_DISTANCE = 20, -- studs (in front of you / behind the target)
	ENTER_COOLDOWN = 0.9,

	DECAL_LINK = "89137727536782", -- X button
	DECAL_MENU = "15627209448", -- C button
	DECAL_NEAREST = "6877509154", -- V button

	SAVE_FOLDER = "RicksPortalGun", -- inside the executor's workspace folder
}

local W = CONFIG.PORTAL_WIDTH
local H = CONFIG.PORTAL_HEIGHT

-- UI colours
local LIME = Color3.fromRGB(150, 235, 60)
local GREEN = Color3.fromRGB(80, 210, 90)
local BLUE = Color3.fromRGB(70, 160, 255)
local PANEL = Color3.fromRGB(18, 24, 20)
local PANEL2 = Color3.fromRGB(30, 38, 32)
local TEXT = Color3.fromRGB(235, 245, 235)
local SUBTEXT = Color3.fromRGB(150, 170, 150)
local DARK_TEXT = Color3.fromRGB(10, 24, 12)
local DANGER = Color3.fromRGB(205, 70, 70)

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return nil
	end
	return f.Unit
end

-- Portal CFrame: local X = surface normal, local Y = "up" of the oval, local Z = right.
local function portalCFrame(pos, normal, upHint)
	local up = upHint
	if math.abs(normal.Y) < 0.9 then
		up = Vector3.yAxis
	end
	up = up - normal * up:Dot(normal)
	if up.Magnitude < 1e-3 then
		up = Vector3.xAxis - normal * normal.X
	end
	up = up.Unit
	return CFrame.fromMatrix(pos, normal, up, normal:Cross(up))
end

local function easeOutBack(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function easeInBack(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	return c3 * x ^ 3 - c1 * x ^ 2
end

local portalFolder = make("Folder", { Name = "RicksPortals_Local" }, Workspace)

--------------------------------------------------------------------------------
-- MOON AREA (client-side)
--------------------------------------------------------------------------------
local moonFolder = make("Folder", { Name = "RicksPortalGun_Moon" }, Workspace)
local MOON_CENTER = Vector3.new(0, 5000, 0)
local MOON_SURFACE_Y = 5012
local MOON_RADIUS = 600

make("Part", {
	Name = "MoonSurface",
	Anchored = true,
	CanCollide = true,
	CanTouch = false,
	CanQuery = true,
	Shape = Enum.PartType.Cylinder,
	Material = Enum.Material.Slate,
	Color = Color3.fromRGB(115, 115, 112),
	Size = Vector3.new(24, 1200, 1200),
	CFrame = CFrame.new(MOON_CENTER) * CFrame.Angles(0, 0, math.rad(90)),
}, moonFolder)

-- Subtle surface craters.
for i, crater in ipairs({
	{ -230, -150, 115 }, { 190, -260, 78 }, { 310, 170, 130 },
	{ -350, 230, 90 }, { 35, 330, 65 }, { -40, -390, 75 },
}) do
	make("Part", {
		Name = "MoonCrater" .. i,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(88, 88, 86),
		Size = Vector3.new(1, crater[3], crater[3]),
		CFrame = CFrame.new(crater[1], MOON_SURFACE_Y + 0.45, crater[2]) * CFrame.Angles(0, 0, math.rad(90)),
	}, moonFolder)
end

-- Preserve the game's lighting and sky so cleanup can restore them exactly.
local originalLighting = {
	ClockTime = Lighting.ClockTime,
	Brightness = Lighting.Brightness,
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	ExposureCompensation = Lighting.ExposureCompensation,
}
local moonSky = Lighting:FindFirstChildOfClass("Sky")
local madeMoonSky = moonSky == nil
if not moonSky then
	moonSky = make("Sky", {}, Lighting)
end
local originalSky = {
	StarCount = moonSky.StarCount,
	CelestialBodiesShown = moonSky.CelestialBodiesShown,
}
local onMoon = false
local function updateMoonEnvironment(hrp)
	local p = hrp and hrp.Position
	local inside = p ~= nil
		and math.abs(p.Y - 5018) < 650
		and Vector2.new(p.X, p.Z).Magnitude < MOON_RADIUS
	if inside == onMoon then
		return
	end
	onMoon = inside
	if onMoon then
		Lighting.ClockTime = 0
		Lighting.Brightness = 1.2
		Lighting.Ambient = Color3.fromRGB(75, 82, 110)
		Lighting.OutdoorAmbient = Color3.fromRGB(45, 52, 78)
		Lighting.ExposureCompensation = 0
		moonSky.StarCount = 3000
		moonSky.CelestialBodiesShown = true
	else
		Lighting.ClockTime = originalLighting.ClockTime
		Lighting.Brightness = originalLighting.Brightness
		Lighting.Ambient = originalLighting.Ambient
		Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
		Lighting.ExposureCompensation = originalLighting.ExposureCompensation
		moonSky.StarCount = originalSky.StarCount
		moonSky.CelestialBodiesShown = originalSky.CelestialBodiesShown
	end
end

local function raycastParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { portalFolder }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

local function playSoundAt(soundId, position, volume)
	local anchor = make("Part", {
		Name = "PortalSFX",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position,
	}, portalFolder)
	local s = make("Sound", {
		SoundId = soundId,
		Volume = (volume or 1) * CONFIG.SOUND_VOLUME,
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMinDistance = 25,
		RollOffMaxDistance = 300,
	}, anchor)
	s:Play()
	local endConn
	endConn = s.Ended:Connect(function()
		endConn:Disconnect()
		anchor:Destroy()
	end)
	Debris:AddItem(anchor, 12)
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local state = {
	equipped = false,
	modeA = false,
	menuOpen = false,
	tab = "players",
	pendingFirst = nil,
	busy = false,
	gen = 0,
}

local portals = {}
local lastTeleport = 0
local gun = nil -- gun animation data
local currentTool = nil

-- forward declarations (assigned further down)
local toast, clearToast, updateButtons, openMenu, closeMenu, flash
local fireB, fireWaypoint, fireServer

--------------------------------------------------------------------------------
-- PLAYER NOCLIP
-- While you are over a portal opening your own character stops colliding, so you
-- can walk / fall straight into it. On a floor portal the humanoid is also put in
-- the Physics state so it stops standing on the ground and drops through.
--------------------------------------------------------------------------------
local charSaved = {}
local charNoclipActive = false
local charFalling = false

local function restoreChar()
	for part, orig in pairs(charSaved) do
		if part.Parent then
			pcall(function()
				part.CanCollide = orig
			end)
		end
	end
	charSaved = {}
	charNoclipActive = false
	if charFalling then
		charFalling = false
		local c = player.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			pcall(function()
				h:ChangeState(Enum.HumanoidStateType.Freefall)
			end)
		end
	end
end

-- Runs every physics step (the humanoid resets CanCollide, so it has to be reapplied).
local function stepCharNoclip()
	local want, fall = false, false
	for _, p in ipairs(portals) do
		if p.noclipOn then
			want = true
			if p.fall then
				fall = true
			end
		end
	end

	local char = player.Character
	if not want or not char then
		if charNoclipActive then
			restoreChar()
		end
		return
	end

	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			if charSaved[d] == nil then
				charSaved[d] = d.CanCollide
			end
			d.CanCollide = false
		end
	end
	charNoclipActive = true

	if fall then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 then
			if not charFalling then
				charFalling = true
				if hrp then
					local v = hrp.AssemblyLinearVelocity
					hrp.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, -20), v.Z)
				end
			end
			if hum:GetState() ~= Enum.HumanoidStateType.Physics then
				hum:ChangeState(Enum.HumanoidStateType.Physics)
			end
		end
	end
end

bind(RunService.Stepped, stepCharNoclip)

--------------------------------------------------------------------------------
-- PORTAL VISUALS
-- Layered neon ovals (rotated slightly so the rim is lumpy) + a SurfaceGui with
-- swirling spiral strokes and white specks, like the show's portal.
--------------------------------------------------------------------------------
local CW = 330
local CH = math.floor(CW * H / W + 0.5)

-- Ordered outside -> inside. Thicker layers sit in front, so every layer stays visible.
local LAYERS = {
	{ thick = 0.08, h = 1.20, w = 1.24, color = Color3.fromRGB(110, 255, 70), transp = 0.75 }, -- halo
	{ thick = 0.16, h = 1.02, w = 1.00, color = Color3.fromRGB(150, 232, 52), rim = true },
	{ thick = 0.18, h = 1.00, w = 0.97, color = Color3.fromRGB(188, 244, 70), rot = math.rad(14), oy = 0.012, oz = -0.015 },
	{ thick = 0.20, h = 0.98, w = 1.02, color = Color3.fromRGB(126, 222, 54), rot = math.rad(-11), oy = -0.015, oz = 0.012 },
	{ thick = 0.22, h = 0.93, w = 0.92, color = Color3.fromRGB(104, 205, 48) },
	{ thick = 0.26, h = 0.86, w = 0.85, color = Color3.fromRGB(38, 150, 44) },
	{ thick = 0.30, h = 0.78, w = 0.76, color = Color3.fromRGB(14, 104, 28) },
}

local function addCapsule(root, z, color, w, h)
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	return f
end

local SPIRAL_K = 4.6 -- how many radians the arms twist from edge to centre

local function buildDots(root)
	local dots = {}
	local base = (CW * 0.5 * 0.80 + CH * 0.5 * 0.82) * 0.5

	local function arm(count, arms, armIndex, z, colA, colB, r0, r1, th0, th1, lenMul, phaseOff, speed)
		for i = 1, count do
			local u = (i - 0.5) / count
			local r = r0 + (r1 - r0) * u
			local thick = th0 + (th1 - th0) * u
			local ds = base * ((r1 - r0) / count) * math.sqrt(1 + (r * SPIRAL_K) ^ 2)
			local len = math.max(thick * 1.4, ds * lenMul)
			table.insert(dots, {
				kind = "spiral",
				gui = addCapsule(root, z, colA:Lerp(colB, math.random()), len, thick),
				r = r,
				theta = armIndex * (2 * math.pi / arms) + phaseOff + SPIRAL_K * (1 - r) + (math.random() - 0.5) * 0.12,
				speed = speed,
				seed = math.random() * 10,
			})
		end
	end

	for a = 0, 2 do -- broad dark swirl arms
		arm(16, 3, a, 1, Color3.fromRGB(8, 84, 22), Color3.fromRGB(18, 108, 32), 0.10, 0.93, 14, 30, 1.7, 0, 1.0)
	end
	for a = 0, 2 do -- mid green arms between them
		arm(14, 3, a, 2, Color3.fromRGB(30, 140, 40), Color3.fromRGB(62, 172, 52), 0.12, 0.93, 8, 15, 1.6, math.pi / 3, 1.2)
	end
	for a = 0, 2 do -- thin lime streaks
		arm(10, 3, a, 3, Color3.fromRGB(150, 238, 64), Color3.fromRGB(205, 255, 110), 0.35, 0.95, 3, 7, 1.5, 0.5, 1.5)
	end
	for a = 0, 1 do -- little swirl in the middle
		arm(5, 2, a, 3, Color3.fromRGB(110, 215, 70), Color3.fromRGB(160, 245, 100), 0.04, 0.24, 4, 8, 1.6, 0.2, 1.8)
	end

	for _ = 1, 14 do -- white specks
		local size = math.random(3, 10)
		table.insert(dots, {
			kind = "speck",
			gui = addCapsule(root, 4, Color3.new(1, 1, 1), size, size),
			r = 0.35 + math.random() * 0.65,
			ang = math.random() * math.pi * 2,
			spd = (math.random() - 0.5) * 0.5,
			seed = math.random() * 10,
		})
	end
	for _ = 1, 8 do -- bigger white blobs hugging the rim
		table.insert(dots, {
			kind = "blob",
			gui = addCapsule(root, 4, Color3.new(1, 1, 1), math.random(9, 18), math.random(4, 8)),
			r = 0.88 + math.random() * 0.14,
			ang = math.random() * math.pi * 2,
			spd = (math.random() - 0.5) * 0.25,
			seed = math.random() * 10,
		})
	end
	return dots
end

local function buildFace(canvasPart, face)
	local gui = make("SurfaceGui", {
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(CW, CH),
		LightInfluence = 0,
		Brightness = 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, canvasPart)
	local root = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	return { gui = gui, dots = buildDots(root) }
end

local function updateDots(face, t)
	local cx, cy = CW * 0.5, CH * 0.5
	local rx, ry = CW * 0.5 * 0.80, CH * 0.5 * 0.82
	local rx2, ry2 = CW * 0.5 * 0.90, CH * 0.5 * 0.91
	for _, d in ipairs(face.dots) do
		local gui = d.gui
		if d.kind == "spiral" then
			local r = d.r * (1 + 0.02 * math.sin(t * 2 + d.seed))
			local a = d.theta - t * d.speed
			local ca, sa = math.cos(a), math.sin(a)
			gui.Position = UDim2.fromScale((cx + ca * r * rx) / CW, (cy + sa * r * ry) / CH)
			-- tangent of the spiral so every stroke follows the swirl
			local dx = rx * (ca + r * SPIRAL_K * sa)
			local dy = ry * (sa - r * SPIRAL_K * ca)
			gui.Rotation = math.deg(math.atan2(dy, dx))
		else
			local a = d.ang + t * d.spd
			local ca, sa = math.cos(a), math.sin(a)
			gui.Position = UDim2.fromScale((cx + ca * d.r * rx2) / CW, (cy + sa * d.r * ry2) / CH)
			if d.kind == "blob" then
				gui.Rotation = math.deg(math.atan2(ry2 * ca, -rx2 * sa))
				gui.BackgroundTransparency = 0.05 + 0.3 * (0.5 + 0.5 * math.sin(t * 2 + d.seed))
			else
				gui.BackgroundTransparency = 0.1 + 0.65 * (0.5 + 0.5 * math.sin(t * 3 + d.seed))
			end
		end
	end
end

local function applyScale(p, s)
	p.scale = s
	local sc = math.max(s, 0.001)
	for _, l in ipairs(p.layers) do
		local d = l.def
		l.part.Size = Vector3.new(d.thick, math.max(0.05, H * d.h * sc), math.max(0.05, W * d.w * sc))
		l.part.CFrame = p.cf
			* CFrame.new(0, (d.oy or 0) * H * sc, (d.oz or 0) * W * sc)
			* CFrame.Angles(d.rot or 0, 0, 0)
	end
	p.canvas.Size = Vector3.new(0.5, math.max(0.05, H * sc), math.max(0.05, W * sc))
	p.canvas.CFrame = p.cf
	p.light.Brightness = 2.6 * math.clamp(s, 0, 1)
end

local function animate(p, to, dur)
	p.anim = { from = p.scale, to = to, start = os.clock(), dur = dur }
end

local function createPortal(cf, options)
	options = options or {}
	local model = make("Model", { Name = "RicksPortal" }, portalFolder)
	local p = {
		cf = cf,
		pos = cf.Position,
		normal = cf.XVector,
		fall = cf.XVector.Y > 0.7, -- floor portal: you drop into it
		model = model,
		layers = {},
		scale = 0,
		onEnter = options.onEnter,
		armed = options.armed or false,
		closing = false,
		suppress = false,
		noclipOn = false,
	}

	for _, def in ipairs(LAYERS) do
		local part = make("Part", {
			Name = "Layer",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(def.thick, 0.1, 0.1),
			CFrame = cf,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = def.color,
			Transparency = def.transp or 0,
		}, model)
		table.insert(p.layers, { part = part, def = def })
		if def.rim then
			p.rim = part
		end
	end

	p.canvas = make("Part", {
		Name = "Canvas",
		Size = Vector3.new(0.5, 0.1, 0.1),
		CFrame = cf,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
	}, model)
	p.faces = {
		right = buildFace(p.canvas, Enum.NormalId.Right),
		left = buildFace(p.canvas, Enum.NormalId.Left),
	}

	p.light = make("PointLight", {
		Color = Color3.fromRGB(110, 255, 80),
		Range = 24,
		Brightness = 0,
		Shadows = false,
	}, p.canvas)

	-- sparks flying off the rim
	make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 40,
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(200, 255, 120), Color3.fromRGB(80, 230, 70)),
		LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Sphere,
	}, p.rim)

	applyScale(p, 0.001)
	table.insert(portals, p)
	return p
end

local function openPortal(p)
	p.expiry = os.clock() + CONFIG.PORTAL_LIFETIME
	animate(p, 1, 0.45)
end

local function closePortal(p, silent)
	if p.closing then
		return
	end
	p.closing = true
	p.armed = false
	p.noclipOn = false
	local tiny = p.scale < 0.1
	if not silent and not tiny then
		playSoundAt(CONFIG.SOUND_CLOSE, p.pos, 1)
	end
	for _, d in ipairs(p.model:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
	animate(p, 0, (silent or tiny) and 0.15 or 0.4)
	if p.onClosed then
		task.defer(p.onClosed, p)
	end
end

local function destroyPortal(p)
	local idx = table.find(portals, p)
	if idx then
		table.remove(portals, idx)
	end
	p.noclipOn = false
	p.model:Destroy()
end

local function closeAllPortals(silent)
	for _, p in ipairs(portals) do
		closePortal(p, silent)
	end
end

local function hasOpenPortals()
	for _, p in ipairs(portals) do
		if not p.closing then
			return true
		end
	end
	return false
end

local function relocatePortal(p, cf)
	p.cf = cf
	p.pos = cf.Position
	p.normal = cf.XVector
	p.fall = cf.XVector.Y > 0.7
	p.suppress = false
	applyScale(p, 0.001)
	animate(p, 1, 0.4)
	p.expiry = os.clock() + CONFIG.PORTAL_LIFETIME
	playSoundAt(CONFIG.SOUND_SHOOT, p.pos, 1)
end

--------------------------------------------------------------------------------
-- TELEPORTING
--------------------------------------------------------------------------------
local function teleportThrough(entry, dest)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum) or hum.Health <= 0 or not dest or dest.closing then
		return
	end
	lastTeleport = os.clock()

	-- give the character its collision / humanoid control back before moving it
	for _, q in ipairs(portals) do
		q.noclipOn = false
	end
	restoreChar()

	local speed = hrp.AssemblyLinearVelocity.Magnitude
	local n = dest.normal
	local feet = hum.HipHeight + hrp.Size.Y * 0.5
	local pos
	if n.Y > 0.7 then
		pos = dest.pos + n * (feet + 1.0)
	elseif n.Y < -0.7 then
		pos = dest.pos + n * 3.5
	else
		pos = dest.pos + n * 3
		pos = Vector3.new(pos.X, dest.pos.Y - H * 0.5 + feet + 0.6, pos.Z)
		local r = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), raycastParams())
		if r then
			pos = Vector3.new(pos.X, math.max(pos.Y, r.Position.Y + feet + 0.1), pos.Z)
		end
	end

	local look = (math.abs(n.Y) > 0.7) and flat(hrp.CFrame.LookVector) or n
	look = flat(look) or Vector3.zAxis

	playSoundAt(CONFIG.SOUND_ENTER, entry.pos, 1)
	char:PivotTo(CFrame.lookAt(pos, pos + look))
	hrp.AssemblyLinearVelocity = n * math.clamp(speed, 14, 40)
	hrp.AssemblyAngularVelocity = Vector3.zero
	dest.suppress = true
	playSoundAt(CONFIG.SOUND_ENTER, dest.pos, 1)
	flash()
end

local function linkPair(a, b)
	a.link, b.link = b, a
	a.armed, b.armed = true, true
	local expiry = os.clock() + CONFIG.PORTAL_LIFETIME
	a.expiry, b.expiry = expiry, expiry
	a.onEnter = function()
		teleportThrough(a, b)
	end
	b.onEnter = function()
		teleportThrough(b, a)
	end
end

--------------------------------------------------------------------------------
-- PROJECTILE
--------------------------------------------------------------------------------
local function fireProjectile(from, to, onDone)
	local dist = (to - from).Magnitude
	local dur = math.clamp(dist / 260, 0.07, 0.4)
	local green = Color3.fromRGB(120, 255, 70)
	local ball = make("Part", {
		Name = "PortalShot",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.8, 0.8),
		Material = Enum.Material.Neon,
		Color = green,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Position = from,
	}, portalFolder)
	make("PointLight", { Color = green, Brightness = 3, Range = 12 }, ball)
	local a0 = make("Attachment", { Position = Vector3.new(0, 0.4, 0) }, ball)
	local a1 = make("Attachment", { Position = Vector3.new(0, -0.4, 0) }, ball)
	make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Lifetime = 0.25,
		LightEmission = 1,
		Color = ColorSequence.new(green, Color3.fromRGB(30, 150, 40)),
		Transparency = NumberSequence.new(0, 1),
		FaceCamera = true,
	}, ball)
	TweenService:Create(ball, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Position = to }):Play()
	task.delay(dur, function()
		ball:Destroy()
		onDone()
	end)
end

--------------------------------------------------------------------------------
-- THE GUN
-- Rebuilt from the reference screenshots (side, front and top views).
--
--   * long, flat, box-shaped body with a thin lip along the top edge
--   * tall bullet-shaped GLASS canister standing on a ring in the middle of the
--     top face, filled with glowing portal fluid
--   * front face: a framed panel holding three round lens bumps
--   * rear corners of the body are chamfered (seen from above) and flow into a
--     rounded grip that slopes down and back, getting fatter toward its tip
--   * round button sitting on the neck where the grip leaves the body
--   * a thin L-shaped groove cut into the top face behind the canister
--
-- Every size below is written in "D" units, where D = the canister's diameter.
-- Gun space: origin = centre of the body, +X right, +Y up, -Z = muzzle.
--------------------------------------------------------------------------------
local function buildGun()
	local D = 0.55 * (CONFIG.GUN_SCALE or 1) -- studs per D

	-- colours ---------------------------------------------------------------------
	local WHITE = Color3.fromRGB(238, 240, 242) -- body + grip
	local LIP = Color3.fromRGB(212, 216, 221) -- thin top lip
	local GROOVE = Color3.fromRGB(110, 116, 124)
	local FACE_DARK = Color3.fromRGB(34, 36, 40) -- recessed front panel
	local FRAME = Color3.fromRGB(205, 209, 214)
	local STEEL = Color3.fromRGB(158, 164, 172)
	local STEEL_DARK = Color3.fromRGB(70, 74, 80)
	local BEZEL = Color3.fromRGB(40, 41, 45)
	local RED = Color3.fromRGB(225, 35, 35)
	local GLASS = Color3.fromRGB(195, 240, 228)
	local FLUID = Color3.fromRGB(110, 255, 90)
	local FLUID_HI = Color3.fromRGB(215, 255, 170)

	local tool = make("Tool", {
		Name = CONFIG.TOOL_NAME,
		ToolTip = CONFIG.TOOLTIP,
		RequiresHandle = true,
		CanBeDropped = false,
	})

	local function newPart(name, size, color, opts)
		opts = opts or {}
		return make("Part", {
			Name = name,
			Size = size,
			Color = color,
			Shape = opts.shape or Enum.PartType.Block,
			Material = opts.material or Enum.Material.SmoothPlastic,
			Transparency = opts.transparency or 0,
			Reflectance = opts.reflectance or 0,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			CastShadow = opts.castShadow ~= false,
			Massless = true,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
		}, tool)
	end

	-- Invisible handle at the centre of the body; every visible part is welded to it.
	local handle = newPart("Handle", Vector3.new(0.3, 0.3, 0.3) * D, WHITE, { transparency = 1, castShadow = false })

	-- scales a gun-space CFrame (written in D units) into studs
	local function sc(cf)
		return cf.Rotation + cf.Position * D
	end

	local function add(name, size, cf, color, opts)
		opts = opts or {}
		local p = newPart(name, size * D, color, opts)
		if opts.ellipsoid then -- block + sphere mesh = ellipsoid that follows the part's size
			make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, p)
		end
		local weld = make("Weld", { Part0 = handle, Part1 = p, C0 = sc(cf) }, p)
		return p, weld
	end

	local UP = CFrame.Angles(0, 0, math.rad(90)) -- stands an X-axis cylinder upright
	local CYL = Enum.PartType.Cylinder
	local BALL = Enum.PartType.Ball
	local METAL = Enum.Material.Metal
	local NEON = Enum.Material.Neon

	----------------------------------------------------------------------------
	-- BODY
	----------------------------------------------------------------------------
	local BODY_W = 2.1 -- body width
	local BODY_H = 0.94 -- body height (including the lip)
	local TOP = BODY_H / 2 -- y of the top face
	local Z_FRONT = -2.2
	local Z_BODY_END = 1.65 -- where the chamfered rear begins
	local Z_REAR = 2.25 -- flat rear face of the chamfered part
	local NECK_HALF = 0.47 -- half-width of the body at its rear face

	add("Body", Vector3.new(BODY_W, 0.87, 3.85), CFrame.new(0, -0.035, -0.275), WHITE)
	add("TopLip", Vector3.new(BODY_W + 0.05, 0.07, 3.875), CFrame.new(0, 0.435, -0.2875), LIP)

	-- Rear of the body: seen from above it narrows from the full width down to the
	-- neck. One block under the neck plus a rotated block on each side makes the chamfer.
	add("RearNeck", Vector3.new(NECK_HALF * 2, 0.866, Z_REAR - Z_BODY_END), CFrame.new(0, -0.035, (Z_BODY_END + Z_REAR) / 2), WHITE)
	for _, sx in ipairs({ 1, -1 }) do
		local ax, az = sx * BODY_W / 2, Z_BODY_END
		local bx, bz = sx * NECK_HALF, Z_REAR
		local ex, ez = bx - ax, bz - az
		local len = math.sqrt(ex * ex + ez * ez)
		ex, ez = ex / len, ez / len
		local nx, nz = sx * -ez, sx * ex -- points into the body
		local thick = 0.45
		local cx = (ax + bx) / 2 + nx * thick / 2
		local cz = (az + bz) / 2 + nz * thick / 2
		add(
			sx > 0 and "RearWingR" or "RearWingL",
			Vector3.new(len, 0.866, thick),
			CFrame.fromMatrix(Vector3.new(cx, -0.035, cz), Vector3.new(ex, 0, ez), Vector3.yAxis),
			WHITE
		)
	end

	----------------------------------------------------------------------------
	-- FRONT FACE: framed panel with three round lens bumps
	----------------------------------------------------------------------------
	local PW, PH, PY = 1.92, 0.70, 0.015
	add("FrontPanel", Vector3.new(PW, PH, 0.03), CFrame.new(0, PY, Z_FRONT - 0.005), FACE_DARK)
	local f = 0.04
	local fz = Z_FRONT - 0.01
	add("FrameTop", Vector3.new(PW + 2 * f, f, 0.04), CFrame.new(0, PY + PH / 2 + f / 2, fz), FRAME)
	add("FrameBottom", Vector3.new(PW + 2 * f, f, 0.04), CFrame.new(0, PY - PH / 2 - f / 2, fz), FRAME)
	add("FrameLeft", Vector3.new(f, PH, 0.04), CFrame.new(-(PW / 2 + f / 2), PY, fz), FRAME)
	add("FrameRight", Vector3.new(f, PH, 0.04), CFrame.new(PW / 2 + f / 2, PY, fz), FRAME)

	for i, x in ipairs({ -0.67, 0, 0.67 }) do
		add("Lens" .. i, Vector3.new(0.46, 0.46, 0.46), CFrame.new(x, 0.02, Z_FRONT + 0.08), FLUID, {
			shape = BALL,
			material = METAL,
			reflectance = 0.15,
		})
	end

	-- invisible spot the portal shot leaves from
	local muzzle = add("Muzzle", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 0.02, Z_FRONT - 0.35), WHITE, {
		transparency = 1,
		castShadow = false,
	})

	----------------------------------------------------------------------------
	-- TOP FACE: L-shaped groove
	----------------------------------------------------------------------------
	add("GrooveH", Vector3.new(1.35, 0.012, 0.028), CFrame.new(-0.015, TOP + 0.003, 1.44), GROOVE)
	add("GrooveV", Vector3.new(0.028, 0.012, 0.55), CFrame.new(0.66, TOP + 0.003, 1.165), GROOVE)

	----------------------------------------------------------------------------
	-- GLASS CANISTER (centred on the body)
	----------------------------------------------------------------------------
	add("BaseRing", Vector3.new(0.075, 1.16, 1.16), CFrame.new(0, TOP + 0.0375, 0) * UP, STEEL_DARK, {
		shape = CYL,
		material = METAL,
	})
	add("Collar", Vector3.new(0.065, 1.04, 1.04), CFrame.new(0, TOP + 0.1075, 0) * UP, STEEL, {
		shape = CYL,
		material = METAL,
	})

	local GLASS_BOTTOM = TOP + 0.14 -- 0.61
	local DOME_Y = 1.845 -- height of the dome's equator
	local glassH = DOME_Y - GLASS_BOTTOM

	-- portal fluid (drawn inside the glass)
	add("FluidColumn", Vector3.new(glassH - 0.01, 0.82, 0.82), CFrame.new(0, GLASS_BOTTOM + 0.005 + (glassH - 0.01) / 2, 0) * UP, FLUID, {
		shape = CYL,
		material = NEON,
		transparency = 0.08,
		castShadow = false,
	})
	add("FluidDome", Vector3.new(0.82, 0.82, 0.82), CFrame.new(0, DOME_Y, 0), FLUID, {
		shape = BALL,
		material = NEON,
		transparency = 0.08,
		castShadow = false,
	})

	-- the glass itself: see-through shell around the fluid
	add("GlassTube", Vector3.new(glassH, 1.0, 1.0), CFrame.new(0, GLASS_BOTTOM + glassH / 2, 0) * UP, GLASS, {
		shape = CYL,
		material = Enum.Material.Glass,
		transparency = 0.62,
		reflectance = 0.06,
		castShadow = false,
	})
	add("GlassDome", Vector3.new(1.0, 1.0, 1.0), CFrame.new(0, DOME_Y, 0), GLASS, {
		shape = BALL,
		material = Enum.Material.Glass,
		transparency = 0.62,
		reflectance = 0.06,
		castShadow = false,
	})

	-- glowing core, bubbles and the spinning swirls inside the fluid
	local core = add("Core", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 1.15, 0), FLUID_HI, {
		shape = BALL,
		material = NEON,
		transparency = 0.1,
		castShadow = false,
	})
	local bubbles = {
		{ 0.22, 1.55, 0.18, 0.11 },
		{ -0.20, 1.35, -0.16, 0.08 },
		{ 0.12, 0.85, -0.22, 0.09 },
		{ -0.17, 1.00, 0.20, 0.07 },
		{ 0.05, 1.98, 0.05, 0.10 },
		{ -0.12, 1.72, -0.10, 0.06 },
	}
	for i, b in ipairs(bubbles) do
		add("Bubble" .. i, Vector3.new(b[4], b[4], b[4]), CFrame.new(b[1], b[2], b[3]), FLUID_HI, {
			shape = BALL,
			material = NEON,
			transparency = 0.35,
			castShadow = false,
		})
	end

	local swirlOpts = { shape = CYL, material = NEON, transparency = 0.3, castShadow = false }
	local baseA = sc(CFrame.new(0, 1.50, 0))
	local baseB = sc(CFrame.new(0, 0.95, 0))
	local baseC = sc(CFrame.new(0, 1.78, 0))
	local _, weldA = add("SwirlA", Vector3.new(0.025, 0.5, 0.3), CFrame.new(0, 1.50, 0), Color3.fromRGB(180, 255, 140), swirlOpts)
	local _, weldB = add("SwirlB", Vector3.new(0.025, 0.45, 0.28), CFrame.new(0, 0.95, 0), Color3.fromRGB(120, 255, 90), swirlOpts)
	local _, weldC = add("SwirlC", Vector3.new(0.025, 0.4, 0.24), CFrame.new(0, 1.78, 0), Color3.fromRGB(200, 255, 170), swirlOpts)

	local light = make("PointLight", {
		Color = Color3.fromRGB(110, 255, 90),
		Brightness = 1.6,
		Range = 10,
		Shadows = false,
	}, core)
	make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 8,
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(200, 255, 150)),
		LightEmission = 1,
	}, core)

	----------------------------------------------------------------------------
	-- GRIP: rounded handle that slopes down and back, fatter toward the tip.
	-- Built as a chain of overlapping ellipsoids so the taper stays smooth.
	----------------------------------------------------------------------------
	local ANGLE = math.rad(26) -- how far the grip slopes below horizontal
	local PIVOT = Vector3.new(0, 0, 2.2) -- where the grip's centre line leaves the body
	local dir = Vector3.new(0, -math.sin(ANGLE), math.cos(ANGLE)) -- along the grip (down + back)
	local upv = Vector3.new(0, math.cos(ANGLE), math.sin(ANGLE)) -- perpendicular, "top" of the grip

	local THICK = { { -0.1, 0.90 }, { 0.3, 0.62 }, { 0.8, 0.52 }, { 1.4, 0.50 }, { 1.9, 0.55 }, { 3.0, 0.68 } }
	local WIDTH = { { -0.1, 0.90 }, { 0.6, 0.90 }, { 1.6, 0.96 }, { 3.0, 1.10 } }

	local function profile(pts, t)
		if t <= pts[1][1] then
			return pts[1][2]
		end
		for i = 2, #pts do
			local a, b = pts[i - 1], pts[i]
			if t <= b[1] then
				return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1])
			end
		end
		return pts[#pts][2]
	end

	local function bead(name, t, len)
		local t0 = profile(THICK, t)
		local w0 = profile(WIDTH, t)
		add(name, Vector3.new(len or 0.8, t0, w0), CFrame.fromMatrix(PIVOT + dir * t, dir, upv), WHITE, { ellipsoid = true })
	end

	local n = 0
	local t = -0.1
	while t < 2.95 do
		n += 1
		bead("Grip" .. n, t, 0.8)
		t += 0.18
	end
	bead("GripTip", 3.0, profile(THICK, 3.0)) -- rounded end

	----------------------------------------------------------------------------
	-- BUTTON on the neck (axis = perpendicular to the grip's top surface)
	----------------------------------------------------------------------------
	local tb = 0.15
	local surface = PIVOT + dir * tb + upv * (profile(THICK, tb) / 2)
	local btnCF = function(offset)
		return CFrame.fromMatrix(surface + upv * offset, upv, dir)
	end
	add("ButtonBezel", Vector3.new(0.22, 0.72, 0.72), btnCF(0.0), BEZEL, { shape = CYL, material = METAL })
	add("RedButton", Vector3.new(0.30, 0.58, 0.58), btnCF(0.04), RED, { shape = CYL })

	----------------------------------------------------------------------------
	-- HOLDING POSE: the hand wraps the grip a little past its middle, with the
	-- muzzle tilted up by CONFIG.GUN_TILT degrees.
	----------------------------------------------------------------------------
	tool.Grip = CFrame.new((PIVOT + dir * 1.5) * D) * CFrame.Angles(-math.rad(CONFIG.GUN_TILT or 0), 0, 0)

	return tool, {
		tip = muzzle,
		light = light,
		swirls = {
			{ weld = weldA, base = baseA, offset = 0 },
			{ weld = weldB, base = baseB, offset = 1.6 },
			{ weld = weldC, base = baseC, offset = 3.1 },
		},
	}
end

--------------------------------------------------------------------------------
-- WAYPOINT STORAGE (executor workspace folder)
--------------------------------------------------------------------------------
local hasFs = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
local hasFolders = type(isfolder) == "function" and type(makefolder) == "function"
local SAVE_FILE = hasFolders and (CONFIG.SAVE_FOLDER .. "/Waypoints_" .. tostring(game.PlaceId) .. ".json")
	or (CONFIG.SAVE_FOLDER .. "_Waypoints_" .. tostring(game.PlaceId) .. ".json")

local waypoints = {}

local function saveWaypoints()
	if not hasFs then
		return false
	end
	local data = {}
	for _, w in ipairs(waypoints) do
		if not w.builtin then
			table.insert(data, { name = w.name, x = w.x, y = w.y, z = w.z, lx = w.lx, lz = w.lz })
		end
	end
	local ok = pcall(function()
		if hasFolders and not isfolder(CONFIG.SAVE_FOLDER) then
			makefolder(CONFIG.SAVE_FOLDER)
		end
		writefile(SAVE_FILE, HttpService:JSONEncode(data))
	end)
	return ok
end

local function loadWaypoints()
	waypoints = {}
	if not hasFs then
		return
	end
	pcall(function()
		if not isfile(SAVE_FILE) then
			return
		end
		local data = HttpService:JSONDecode(readfile(SAVE_FILE))
		for _, w in ipairs(data) do
			if type(w) == "table" and type(w.x) == "number" and type(w.y) == "number" and type(w.z) == "number" then
				table.insert(waypoints, {
					name = tostring(w.name or "Waypoint"),
					x = w.x,
					y = w.y,
					z = w.z,
					lx = tonumber(w.lx) or 0,
					lz = tonumber(w.lz) or -1,
				})
			end
		end
	end)
end
loadWaypoints()
-- Built-in Moon waypoint; it is not written into the user's saved waypoint list.
table.insert(waypoints, 1, {
	name = "Moon",
	x = MOON_CENTER.X,
	y = 5018,
	z = MOON_CENTER.Z,
	lx = 0,
	lz = -1,
	builtin = true,
})

local function newWaypointName()
	local used = {}
	for _, w in ipairs(waypoints) do
		used[w.name] = true
	end
	local i = 1
	while used["Waypoint " .. i] do
		i += 1
	end
	return "Waypoint " .. i
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------
local isTouch = UserInputService.TouchEnabled
local BTN = isTouch and 54 or 48
local UI = {}

local screenGui = make("ScreenGui", {
	Name = "RicksPortalGunUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 20,
}, guiParent)

local flashGui = make("ScreenGui", {
	Name = "RicksPortalFlash",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5,
}, guiParent)
local flashFrame = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(150, 255, 90),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, flashGui)

function flash()
	flashFrame.BackgroundTransparency = 0.55
	TweenService:Create(flashFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

-- Left-side button column --------------------------------------------------
local panel = make("Frame", {
	Name = "Buttons",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.42, 0),
	Size = UDim2.fromOffset(BTN, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Visible = false,
}, screenGui)
make("UIListLayout", {
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, panel)

local function addPressFx(button, scaleObj)
	local function to(s)
		TweenService:Create(scaleObj, TweenInfo.new(0.08), { Scale = s }):Play()
	end
	button.MouseButton1Down:Connect(function()
		to(0.9)
	end)
	button.MouseButton1Up:Connect(function()
		to(1)
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
end

-- A decal id may be a Decal asset rather than an Image; try to resolve the real texture.
local function resolveDecal(id, img)
	img.Image = "rbxassetid://" .. id
	task.spawn(function()
		local ok, res = pcall(function()
			return game:GetObjects("rbxassetid://" .. id)
		end)
		if ok and type(res) == "table" and res[1] then
			local o = res[1]
			local tex
			if o:IsA("Decal") or o:IsA("Texture") then
				tex = o.Texture
			else
				local d = o:FindFirstChildWhichIsA("Decal", true)
				tex = d and d.Texture
			end
			if tex and tex ~= "" and img.Parent then
				img.Image = tex
			end
			pcall(function()
				o:Destroy()
			end)
		end
	end)
end

-- Transparent button with a coloured outline and a decal inside.
local function makeIconButton(order, size, outline, decalId, name)
	local b = make("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = outline,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
	make("UIStroke", { Color = outline, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local scale = make("UIScale", { Scale = 1 }, b)
	local img = make("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.68, 0.68),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
	}, b)
	resolveDecal(decalId, img)
	addPressFx(b, scale)
	return { button = b }
end

-- Z: the red button (closes every portal)
do
	local b = make("TextButton", {
		Name = "Z",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(BTN, BTN),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
	}, panel)
	local s = make("UIScale", { Scale = 1 }, b)
	local bezel = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(36, 36, 40),
		BorderSizePixel = 0,
	}, b)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bezel)
	make("UIStroke", { Color = Color3.fromRGB(110, 115, 120), Thickness = 2 }, bezel)
	local face = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, bezel)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, face)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 104, 90), Color3.fromRGB(170, 12, 16)),
		Rotation = 90,
	}, face)
	make("UIStroke", { Color = Color3.fromRGB(120, 8, 10), Thickness = 1.5 }, face)
	local shine = make("Frame", {
		Position = UDim2.fromScale(0.2, 0.14),
		Size = UDim2.fromScale(0.4, 0.2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Rotation = -28,
	}, face)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, shine)
	addPressFx(b, s)
	UI.Z = b
end

UI.X = makeIconButton(2, BTN, LIME, CONFIG.DECAL_LINK, "X")
UI.V = makeIconButton(3, BTN - 8, BLUE, CONFIG.DECAL_NEAREST, "V") -- a bit smaller, right under X
UI.C = makeIconButton(4, BTN, LIME, CONFIG.DECAL_MENU, "C")

local function setActive(btn, on)
	TweenService:Create(btn.button, TweenInfo.new(0.15), { BackgroundTransparency = on and 0.55 or 1 }):Play()
end

function updateButtons()
	setActive(UI.X, state.modeA)
	setActive(UI.C, state.menuOpen)
end

-- Toast ---------------------------------------------------------------------
local toastFrame = make("Frame", {
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	Visible = false,
}, screenGui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, toastFrame)
make("UIStroke", { Color = LIME, Thickness = 1.5 }, toastFrame)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 14),
	PaddingRight = UDim.new(0, 14),
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
}, toastFrame)
local toastLabel = make("TextLabel", {
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	Font = Enum.Font.GothamMedium,
	TextSize = isTouch and 15 or 16,
	TextColor3 = TEXT,
	TextWrapped = true,
	Text = "",
}, toastFrame)
local toastLimit = make("UISizeConstraint", { MaxSize = Vector2.new(400, math.huge) }, toastLabel)

local toastToken = 0
function toast(text, duration)
	toastToken += 1
	local mine = toastToken
	local cam = Workspace.CurrentCamera
	local vpx = cam and cam.ViewportSize.X or 800
	toastLimit.MaxSize = Vector2.new(math.max(160, math.min(400, vpx - 130)), math.huge)
	toastLabel.Text = text
	toastFrame.Visible = true
	if duration then
		task.delay(duration, function()
			if toastToken == mine then
				toastFrame.Visible = false
			end
		end)
	end
end

function clearToast()
	toastToken += 1
	toastFrame.Visible = false
end

-- Menu (Players / Servers / Waypoints) ----------------------------------------
do
	local menu = make("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.82),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
	}, screenGui)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, menu)
	make("UIStroke", { Color = LIME, Thickness = 2 }, menu)
	make("UISizeConstraint", { MaxSize = Vector2.new(400, 470), MinSize = Vector2.new(260, 300) }, menu)
	local menuScale = make("UIScale", { Scale = 1 }, menu)

	make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 0),
		Size = UDim2.new(1, -64, 0, 48),
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextColor3 = LIME,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Portal Menu",
	}, menu)

	local closeBtn = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, 24),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = PANEL2,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = TEXT,
		Text = "X",
		BorderSizePixel = 0,
	}, menu)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, closeBtn)

	-- tab bar
	local tabBar = make("Frame", {
		Position = UDim2.new(0, 10, 0, 52),
		Size = UDim2.new(1, -20, 0, 34),
		BackgroundTransparency = 1,
	}, menu)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)

	local pages = make("Frame", {
		Name = "Pages",
		Position = UDim2.new(0, 10, 0, 96),
		Size = UDim2.new(1, -20, 1, -106),
		BackgroundTransparency = 1,
	}, menu)

	local function makeList(parent, props)
		local sf = make("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = LIME,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Position = props.Position or UDim2.new(0, 0, 0, 0),
			Size = props.Size or UDim2.fromScale(1, 1),
			Visible = props.Visible ~= false,
		}, parent)
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
		return sf
	end

	local function makeEmptyLabel(parent, text)
		return make("TextLabel", {
			LayoutOrder = 0,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -6, 0, 40),
			Font = Enum.Font.GothamMedium,
			TextSize = 15,
			TextColor3 = SUBTEXT,
			TextWrapped = true,
			Text = text,
			Visible = false,
		}, parent)
	end

	------------------------------------------------------------------ Players tab
	local playersList = makeList(pages, {})
	local emptyPlayers = makeEmptyLabel(playersList, "Nobody else is in this server.")

	local function makePlayerRow(target, order)
		local row = make("Frame", {
			Name = target.Name,
			LayoutOrder = order,
			Size = UDim2.new(1, -6, 0, 54),
			BackgroundColor3 = PANEL2,
			BorderSizePixel = 0,
		}, playersList)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, row)

		local thumb = make("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = PANEL,
			BorderSizePixel = 0,
			Image = "",
		}, row)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, thumb)
		task.spawn(function()
			local ok, img = pcall(function()
				return Players:GetUserThumbnailAsync(
					target.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size48x48
				)
			end)
			if ok and thumb.Parent then
				thumb.Image = img
			end
		end)

		make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 54, 0, 8),
			Size = UDim2.new(1, -(54 + 104), 0, 20),
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = target.DisplayName,
		}, row)
		make("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 54, 0, 28),
			Size = UDim2.new(1, -(54 + 104), 0, 16),
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = SUBTEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "@" .. target.Name,
		}, row)

		local go = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(92, 38),
			BackgroundColor3 = GREEN,
			AutoButtonColor = true,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = DARK_TEXT,
			Text = "Teleport",
			BorderSizePixel = 0,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, go)
		go.Activated:Connect(function()
			if fireB(target) then
				closeMenu()
			end
		end)
	end

	local function refreshPlayers()
		for _, c in ipairs(playersList:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local others = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				table.insert(others, p)
			end
		end
		table.sort(others, function(a, b)
			return a.DisplayName:lower() < b.DisplayName:lower()
		end)
		emptyPlayers.Visible = #others == 0
		for i, p in ipairs(others) do
			makePlayerRow(p, i)
		end
	end

	------------------------------------------------------------------ Servers tab
	local serversPage = make("Frame", {
		Name = "Servers",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, pages)
	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 54),
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = SUBTEXT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "Paste a server ID (Job ID). A portal opens in front of you; step through it to join that server.",
	}, serversPage)
	local serverBox = make("TextBox", {
		Position = UDim2.new(0, 0, 0, 62),
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundColor3 = PANEL2,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = TEXT,
		PlaceholderText = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
		PlaceholderColor3 = SUBTEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, serversPage)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, serverBox)
	make("UIStroke", { Color = LIME, Thickness = 1, Transparency = 0.5 }, serverBox)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, serverBox)
	local serverGo = make("TextButton", {
		Position = UDim2.new(0, 0, 0, 114),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = GREEN,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = DARK_TEXT,
		Text = "Create Portal",
		BorderSizePixel = 0,
	}, serversPage)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, serverGo)
	serverGo.Activated:Connect(function()
		if fireServer(serverBox.Text) then
			closeMenu()
		end
	end)

	------------------------------------------------------------------ Waypoints tab
	local wpPage = make("Frame", {
		Name = "Waypoints",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, pages)
	local wpAdd = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = GREEN,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = DARK_TEXT,
		Text = "+  Save current spot",
		BorderSizePixel = 0,
	}, wpPage)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, wpAdd)
	local wpList = makeList(wpPage, { Position = UDim2.new(0, 0, 0, 48), Size = UDim2.new(1, 0, 1, -48) })
	local emptyWp = makeEmptyLabel(wpList, "No waypoints yet. Stand somewhere and press Save.")

	local refreshWaypoints

	local function makeWaypointRow(wp, order)
		local row = make("Frame", {
			Name = "WP",
			LayoutOrder = order,
			Size = UDim2.new(1, -6, 0, 52),
			BackgroundColor3 = PANEL2,
			BorderSizePixel = 0,
		}, wpList)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, row)

		local box = make("TextBox", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.new(1, -136, 0, 34),
			BackgroundColor3 = PANEL,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = TEXT,
			PlaceholderText = "Name",
			PlaceholderColor3 = SUBTEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = wp.name,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
		box.FocusLost:Connect(function()
			local t = box.Text:match("^%s*(.-)%s*$")
			if t == "" then
				box.Text = wp.name
				return
			end
			t = t:sub(1, 24)
			box.Text = t
			if t ~= wp.name then
				wp.name = t
				saveWaypoints()
			end
		end)

		local go = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -58, 0.5, 0),
			Size = UDim2.fromOffset(64, 34),
			BackgroundColor3 = GREEN,
			AutoButtonColor = true,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = DARK_TEXT,
			Text = wp.builtin and "Teleport" or "Portal",
			BorderSizePixel = 0,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, go)
		go.Activated:Connect(function()
			if wp.builtin then
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.AssemblyLinearVelocity = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
					hrp.CFrame = CFrame.new(wp.x, wp.y, wp.z)
					closeMenu()
					toast("Teleported to the Moon.", 2.5)
				else
					toast("No character to teleport.", 2)
				end
			elseif fireWaypoint(wp) then
				closeMenu()
			end
		end)

		local del = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(44, 34),
			BackgroundColor3 = DANGER,
			AutoButtonColor = true,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = TEXT,
			Text = "Del",
			BorderSizePixel = 0,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, del)
		del.Visible = not wp.builtin
		del.Activated:Connect(function()
			local idx = table.find(waypoints, wp)
			if idx then
				table.remove(waypoints, idx)
				saveWaypoints()
				refreshWaypoints()
			end
		end)
	end

	function refreshWaypoints()
		for _, c in ipairs(wpList:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		emptyWp.Visible = #waypoints == 0
		for i, wp in ipairs(waypoints) do
			makeWaypointRow(wp, i)
		end
	end

	wpAdd.Activated:Connect(function()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			toast("No character to save.", 2)
			return
		end
		local look = flat(hrp.CFrame.LookVector) or Vector3.zAxis
		local pos = hrp.Position
		local wp = { name = newWaypointName(), x = pos.X, y = pos.Y, z = pos.Z, lx = look.X, lz = look.Z }
		table.insert(waypoints, wp)
		local saved = saveWaypoints()
		refreshWaypoints()
		if saved then
			toast('Saved "' .. wp.name .. '".', 2)
		else
			toast("Waypoint added, but your executor can't save files.", 3)
		end
	end)

	------------------------------------------------------------------ tabs
	local pageByTab = { players = playersList, servers = serversPage, waypoints = wpPage }
	local tabBtns = {}

	local function setTab(id)
		state.tab = id
		for tid, page in pairs(pageByTab) do
			page.Visible = (tid == id)
		end
		for tid, b in pairs(tabBtns) do
			local on = tid == id
			b.BackgroundColor3 = on and LIME or PANEL2
			b.TextColor3 = on and DARK_TEXT or TEXT
		end
		if id == "players" then
			refreshPlayers()
		elseif id == "waypoints" then
			refreshWaypoints()
		end
	end

	local TABS = {
		{ id = "players", label = "Players" },
		{ id = "servers", label = "Servers" },
		{ id = "waypoints", label = "Waypoints" },
	}
	for i, t in ipairs(TABS) do
		local b = make("TextButton", {
			Name = t.id,
			LayoutOrder = i,
			Size = UDim2.new(1 / 3, -4, 1, 0),
			BackgroundColor3 = PANEL2,
			AutoButtonColor = true,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = TEXT,
			Text = t.label,
			BorderSizePixel = 0,
		}, tabBar)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
		b.Activated:Connect(function()
			setTab(t.id)
		end)
		tabBtns[t.id] = b
	end
	setTab("players")

	function openMenu(tab)
		state.menuOpen = true
		setTab(tab or state.tab)
		menu.Visible = true
		menuScale.Scale = 0.88
		TweenService:Create(menuScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		updateButtons()
	end

	function closeMenu()
		if serverBox:IsFocused() then
			serverBox:ReleaseFocus()
		end
		if not state.menuOpen and not menu.Visible then
			return
		end
		state.menuOpen = false
		menu.Visible = false
		updateButtons()
	end

	closeBtn.Activated:Connect(closeMenu)

	bind(Players.PlayerAdded, function()
		if state.menuOpen and state.tab == "players" then
			task.defer(refreshPlayers)
		end
	end)
	bind(Players.PlayerRemoving, function()
		if state.menuOpen and state.tab == "players" then
			task.delay(0.1, refreshPlayers)
		end
	end)
end

--------------------------------------------------------------------------------
-- GAME LOGIC
--------------------------------------------------------------------------------
local function cancelModes()
	state.modeA = false
	if state.pendingFirst then
		local p = state.pendingFirst
		state.pendingFirst = nil
		p.onClosed = nil
		closePortal(p)
	end
	closeMenu()
	clearToast()
	updateButtons()
end

local function resetAll()
	state.gen += 1
	state.busy = false
	closeAllPortals(true)
	state.pendingFirst = nil
	state.modeA = false
	state.equipped = false
	closeMenu()
	clearToast()
	panel.Visible = false
	updateButtons()
end

local function tipPosition()
	if gun and gun.tip and gun.tip.Parent then
		return gun.tip.Position
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp.Position + Vector3.new(0, 1, 0)) or Vector3.zero
end

-- True when a new portal can be made right now (otherwise tells the player why).
local function canCreate()
	if state.busy then
		return false
	end
	if hasOpenPortals() then
		toast("Portals are still open. Press Z or wait for them to fade.", 2.5)
		return false
	end
	return true
end

-- Fire the gun at entryCF; onLanded runs when the shot arrives.
local function launchTo(entryCF, onLanded)
	state.busy = true
	local gen = state.gen
	local tip = tipPosition()
	playSoundAt(CONFIG.SOUND_SHOOT, tip, 1)
	fireProjectile(tip, entryCF.Position, function()
		state.busy = false
		if gen ~= state.gen then
			return
		end
		onLanded()
	end)
end

-- Mode A: shoot a portal wherever the player aims ---------------------------
local function onPortalLandedA(cf)
	local portal = createPortal(cf)
	openPortal(portal)

	if not state.pendingFirst then
		state.pendingFirst = portal
		portal.onClosed = function()
			if state.pendingFirst == portal then
				state.pendingFirst = nil
				if state.modeA then
					toast("Portal 1 faded. Place portal 1 of 2.")
				end
			end
		end
		toast("Portal 2 of 2: choose where it comes out.")
	else
		local first = state.pendingFirst
		state.pendingFirst = nil
		first.onClosed = nil
		linkPair(first, portal)
		state.modeA = false
		updateButtons()
		toast("Portals open for " .. CONFIG.PORTAL_LIFETIME .. " seconds.", 2.5)
	end
end

local function shootFromRay(ray)
	if not (state.equipped and state.modeA) or state.busy then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local cam = Workspace.CurrentCamera
	if not (hrp and cam) then
		return
	end

	local result = Workspace:Raycast(ray.Origin, ray.Direction.Unit * CONFIG.SHOOT_RANGE, raycastParams())
	if not result then
		toast("Nothing in range. Aim at a surface.", 2)
		return
	end

	local inst = result.Instance
	local model = inst:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		toast("Pick a solid surface, not a person.", 2)
		return
	end

	local n = result.Normal
	local pos = result.Position + n * 0.12
	local camLook = flat(cam.CFrame.LookVector) or Vector3.zAxis

	-- Upright (wall) portals sit on the floor instead of sinking into it.
	if math.abs(n.Y) < 0.6 then
		local fr = Workspace:Raycast(pos + n * 0.4, Vector3.new(0, -H, 0), raycastParams())
		if fr then
			local minY = fr.Position.Y + H * 0.5
			if pos.Y < minY then
				pos = Vector3.new(pos.X, minY, pos.Z)
			end
		end
	end

	local cf = portalCFrame(pos, n, camLook)
	launchTo(cf, function()
		onPortalLandedA(cf)
	end)
end

-- Portals that stand upright on the ground -------------------------------------
local function groundedPortalCF(nearPos, facing)
	local r = Workspace:Raycast(nearPos + Vector3.new(0, 3, 0), Vector3.new(0, -80, 0), raycastParams())
	local groundY = r and r.Position.Y or (nearPos.Y - 3)
	local pos = Vector3.new(nearPos.X, groundY + H * 0.5 + 0.05, nearPos.Z)
	return portalCFrame(pos, facing, Vector3.yAxis)
end

local function exitCFFor(targetHrp)
	local tlook = flat(targetHrp.CFrame.LookVector) or Vector3.zAxis
	-- 20 studs BEHIND the target, opening toward them
	return groundedPortalCF(targetHrp.Position - tlook * CONFIG.B_DISTANCE, tlook)
end

local function myHrp()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- Players tab / V button: send yourself to another player ------------------------
function fireB(target)
	if not state.equipped or not canCreate() then
		return false
	end
	local hrp = myHrp()
	if not hrp then
		return false
	end
	local tchar = target.Character
	local thrp = tchar and tchar:FindFirstChild("HumanoidRootPart")
	if not thrp then
		toast(target.DisplayName .. " isn't available right now.", 2.5)
		return false
	end

	local look = flat(hrp.CFrame.LookVector) or Vector3.zAxis
	-- 20 studs in FRONT of the user, facing the user
	local entryCF = groundedPortalCF(hrp.Position + look * CONFIG.B_DISTANCE, -look)
	local exitCF = exitCFFor(thrp)

	launchTo(entryCF, function()
		local entry = createPortal(entryCF, { armed = true })
		local exitP = createPortal(exitCF)
		openPortal(entry)
		openPortal(exitP)
		playSoundAt(CONFIG.SOUND_SHOOT, exitP.pos, 1)

		entry.onEnter = function()
			local tc = target.Character
			local th = tc and tc:FindFirstChild("HumanoidRootPart")
			if not th then
				toast(target.DisplayName .. " left. Portal closed.", 2.5)
				closePortal(entry)
				closePortal(exitP)
				return
			end
			-- Re-open the exit fresh behind them, in case they moved.
			relocatePortal(exitP, exitCFFor(th))
			teleportThrough(entry, exitP)
		end
		toast("Portal to " .. target.DisplayName .. " is open.", 2.5)
	end)
	return true
end

-- Waypoints tab: portal to a saved spot -------------------------------------------
function fireWaypoint(wp)
	if not state.equipped or not canCreate() then
		return false
	end
	local hrp = myHrp()
	if not hrp then
		return false
	end

	local look = flat(hrp.CFrame.LookVector) or Vector3.zAxis
	local entryCF = groundedPortalCF(hrp.Position + look * CONFIG.B_DISTANCE, -look)

	local wlook = flat(Vector3.new(wp.lx, 0, wp.lz)) or Vector3.zAxis
	local wpos = Vector3.new(wp.x, wp.y, wp.z)
	-- the exit stands 3 studs behind the saved spot, so you step out right onto it
	local exitCF = groundedPortalCF(wpos - wlook * 3, wlook)

	launchTo(entryCF, function()
		local entry = createPortal(entryCF, { armed = true })
		local exitP = createPortal(exitCF)
		openPortal(entry)
		openPortal(exitP)
		playSoundAt(CONFIG.SOUND_SHOOT, exitP.pos, 1)
		entry.onEnter = function()
			teleportThrough(entry, exitP)
		end
		toast('Portal to "' .. wp.name .. '" is open.', 2.5)
	end)
	return true
end

-- Servers tab: a portal that hops you to another server ---------------------------
function fireServer(rawId)
	if not state.equipped then
		return false
	end
	local jobId = string.gsub(tostring(rawId or ""), "%s", "")
	if #jobId ~= 36 or not jobId:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
		toast("That doesn't look like a server ID.", 2.5)
		return false
	end
	if jobId:lower() == game.JobId:lower() then
		toast("You're already in that server.", 2.5)
		return false
	end
	if not canCreate() then
		return false
	end
	local hrp = myHrp()
	if not hrp then
		return false
	end

	local look = flat(hrp.CFrame.LookVector) or Vector3.zAxis
	local entryCF = groundedPortalCF(hrp.Position + look * CONFIG.B_DISTANCE, -look)

	launchTo(entryCF, function()
		local entry = createPortal(entryCF, { armed = true })
		openPortal(entry)
		entry.onEnter = function()
			entry.armed = false -- one try; re-arms shortly if the teleport doesn't go through
			lastTeleport = os.clock()
			playSoundAt(CONFIG.SOUND_ENTER, entry.pos, 1)
			flash()
			toast("Joining server...", 6)
			local ok, err = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, player)
			end)
			if not ok then
				toast("Teleport failed: " .. tostring(err), 4)
			end
			task.delay(6, function()
				if not entry.closing then
					entry.armed = true
				end
			end)
		end
		toast("Server portal is open.", 2.5)
	end)
	return true
end

bind(TeleportService.TeleportInitFailed, function(plr, result, msg)
	if plr == player then
		toast("Teleport failed: " .. tostring(msg or result), 4)
	end
end)

-- V button: nearest player ---------------------------------------------------------
local function nearestPlayer()
	local hrp = myHrp()
	if not hrp then
		return nil
	end
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local c = p.Character
			local h = c and c:FindFirstChild("HumanoidRootPart")
			local hm = c and c:FindFirstChildOfClass("Humanoid")
			if h and hm and hm.Health > 0 then
				local d = (h.Position - hrp.Position).Magnitude
				if not bestD or d < bestD then
					best, bestD = p, d
				end
			end
		end
	end
	return best
end

-- Actions (buttons + hotkeys) ---------------------------------------------------------
local function actionClose() -- Z
	if not state.equipped then
		return
	end
	local had = hasOpenPortals()
	cancelModes()
	closeAllPortals()
	toast(had and "Portals closed." or "No portals to close.", 1.5)
end

local function actionLink() -- X
	if not state.equipped then
		return
	end
	closeMenu()
	if state.modeA then
		cancelModes()
		toast("Portal mode off.", 1.5)
		return
	end
	if hasOpenPortals() then
		toast("Portals are still open. Press Z or wait for them to fade.", 2.5)
		return
	end
	state.modeA = true
	updateButtons()
	toast("Portal 1 of 2: click or tap where you want it.")
end

local function actionMenu() -- C
	if not state.equipped then
		return
	end
	if state.menuOpen then
		closeMenu()
		return
	end
	if state.modeA then
		cancelModes()
	end
	clearToast()
	openMenu()
end

local function actionNearest() -- V
	if not state.equipped then
		return
	end
	if state.modeA then
		cancelModes()
	end
	closeMenu()
	if not canCreate() then
		return
	end
	local target = nearestPlayer()
	if not target then
		toast("Nobody else is around.", 2)
		return
	end
	fireB(target)
end

UI.Z.Activated:Connect(actionClose)
UI.X.button.Activated:Connect(actionLink)
UI.C.button.Activated:Connect(actionMenu)
UI.V.button.Activated:Connect(actionNearest)

-- World input -----------------------------------------------------------------
bind(UserInputService.InputBegan, function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local cam = Workspace.CurrentCamera
		if cam then
			local loc = UserInputService:GetMouseLocation()
			shootFromRay(cam:ViewportPointToRay(loc.X, loc.Y))
		end
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		if not state.equipped or UserInputService:GetFocusedTextBox() then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Z then
			actionClose()
		elseif k == Enum.KeyCode.X then
			actionLink()
		elseif k == Enum.KeyCode.C then
			actionMenu()
		elseif k == Enum.KeyCode.V then
			actionNearest()
		end
	end
end)

-- Correct event name is TouchTapInWorld. Wrapped so a bad member can never stop the script.
local okTap, tapErr = pcall(function()
	bind(UserInputService.TouchTapInWorld, function(pos, processed)
		if processed then
			return
		end
		local cam = Workspace.CurrentCamera
		if cam then
			shootFromRay(cam:ScreenPointToRay(pos.X, pos.Y))
		end
	end)
end)
if not okTap then
	warn("[Rick's Portal Gun] touch tap hookup failed: " .. tostring(tapErr))
end

--------------------------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------------------------
local lastDotUpdate = 0

bind(RunService.Heartbeat, function()
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local alive = hum ~= nil and hum.Health > 0
	updateMoonEnvironment(hrp)

	local doDots = now - lastDotUpdate >= 1 / 30
	if doDots then
		lastDotUpdate = now
	end

	-- gun idle animation
	if state.equipped and gun then
		for _, s in ipairs(gun.swirls) do
			s.weld.C0 = s.base * CFrame.Angles(0, now * 4 + s.offset, s.offset * 0.5)
		end
		gun.light.Brightness = 1.4 + 0.6 * math.sin(now * 5)
	end

	for i = #portals, 1, -1 do
		local p = portals[i]

		if not p.closing and p.expiry and now >= p.expiry then
			closePortal(p)
		end

		-- open / close animation
		local anim = p.anim
		if anim then
			local a = math.clamp((now - anim.start) / anim.dur, 0, 1)
			local s
			if anim.to >= anim.from then
				s = anim.from + (anim.to - anim.from) * easeOutBack(a)
			else
				s = anim.from + (anim.to - anim.from) * easeInBack(a)
			end
			applyScale(p, s)
			if a >= 1 then
				p.anim = nil
				applyScale(p, anim.to)
				if p.closing then
					destroyPortal(p)
					continue
				end
			end
		end

		-- visuals: only the face the camera sees is animated
		if cam then
			local rel = p.cf:PointToObjectSpace(cam.CFrame.Position)
			local showRight = rel.X >= 0
			if p.showRight ~= showRight then
				p.showRight = showRight
				p.faces.right.gui.Enabled = showRight
				p.faces.left.gui.Enabled = not showRight
			end
			if doDots and rel.Magnitude < 300 then
				updateDots(showRight and p.faces.right or p.faces.left, now)
			end
		end
		p.rim.Color = Color3.fromRGB(150, 232, 52):Lerp(Color3.fromRGB(205, 255, 110), 0.5 + 0.5 * math.sin(now * 4))

		-- player noclip + stepping through
		local active = p.armed and p.onEnter ~= nil and not p.closing and p.scale > 0.7 and hrp ~= nil and alive
		if active then
			local rel = p.cf:PointToObjectSpace(hrp.Position)
			local ax = math.abs(rel.X)
			local v = (rel.Y / (H * 0.5)) ^ 2 + (rel.Z / (W * 0.5)) ^ 2

			if p.suppress and v > 2.4 then
				p.suppress = false
			end

			if not p.noclipOn then
				if not p.suppress and v < 1.1 and ax < 5 then
					p.noclipOn = true
					p.noclipSince = now
				end
			elseif v > 2.6 or ax > 8 then
				p.noclipOn = false
			end

			-- floor portals: you sink in, so the plane is crossed a little higher up
			local trigX = p.fall and 2.3 or 1.8
			-- safety net: if you've been dropping into a floor portal for a while, just go
			local forced = p.noclipOn and p.fall and (now - (p.noclipSince or now)) > 0.8

			if
				not p.suppress
				and now - lastTeleport > CONFIG.ENTER_COOLDOWN
				and ((ax < trigX and v < 1.6) or forced)
			then
				p.onEnter(p)
			end
		elseif p.noclipOn then
			p.noclipOn = false
		end
	end
end)

--------------------------------------------------------------------------------
-- TOOL LIFECYCLE
--------------------------------------------------------------------------------
local function onEquipped()
	state.equipped = true
	panel.Visible = true
	panel.Position = UDim2.new(0, -BTN - 10, 0.42, 0)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 10, 0.42, 0),
	}):Play()
end

local function onUnequipped()
	state.equipped = false
	cancelModes()
	panel.Visible = false
end

local function giveTool()
	resetAll()
	if currentTool then
		pcall(function()
			currentTool:Destroy()
		end)
	end
	local backpack = player:WaitForChild("Backpack")
	local tool, gunData = buildGun()
	currentTool, gun = tool, gunData
	tool.Equipped:Connect(onEquipped)
	tool.Unequipped:Connect(onUnequipped)
	tool.Parent = backpack

	-- Auto-equip so the gun is in hand right away (hotbar still works to unequip/re-equip).
	task.delay(0.4, function()
		local c = player.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 and tool.Parent == backpack then
			pcall(function()
				h:EquipTool(tool)
			end)
		end
	end)
end

local function onCharacter(char)
	giveTool()
	local hum = char:WaitForChild("Humanoid")
	bind(hum.Died, resetAll)
end

bind(player.CharacterAdded, onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

env.RicksPortalGunCleanup = function()
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(resetAll)
	pcall(restoreChar)
	pcall(function()
		currentTool:Destroy()
	end)
	pcall(function()
		screenGui:Destroy()
	end)
	pcall(function()
		flashGui:Destroy()
	end)
	pcall(function()
		portalFolder:Destroy()
	end)
	pcall(function()
		moonFolder:Destroy()
	end)
	pcall(function()
		Lighting.ClockTime = originalLighting.ClockTime
		Lighting.Brightness = originalLighting.Brightness
		Lighting.Ambient = originalLighting.Ambient
		Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
		Lighting.ExposureCompensation = originalLighting.ExposureCompensation
		if madeMoonSky then
			moonSky:Destroy()
		else
			moonSky.StarCount = originalSky.StarCount
			moonSky.CelestialBodiesShown = originalSky.CelestialBodiesShown
		end
	end)
	env.RicksPortalGunCleanup = nil
end

print("[Rick's Portal Gun] loaded. Hotkeys: Z close portals | X link portals | C menu | V nearest player.")
