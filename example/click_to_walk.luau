local Pathfinder = loadstring(game:HttpGet("https://raw.githubusercontent.com/Zartoooo/pathfindingLib/refs/heads/main/build/output.luau"))()

local player = game:GetService("Players").LocalPlayer
local character = player.Character
local hrp = character:FindFirstChild("HumanoidRootPart")
local mouse = player:GetMouse();

local path = Pathfinder:Pathfind(hrp.Position, Vector3.new(0,0,0));

if not path then    
    error("Pathfinder:Pathfind returned nil");
end

local lines = {} -- [{ from, to, obj }]

for _, node in next, path do
    local l = Drawing.new("Line");
    l.Thickness = 2;
    l.Color = Color3.fromRGB(255,40,40);
    l.Transparency = 0.5;
    l.Visible = true;

    local from;
    if node.Parent then from = node.Parent.Position
    else from = node.Position end

    table.insert(lines, {
        from = from,
        to = node.Position,
        obj = l
    });
end

while true do
    for _, line in next, lines do
        local from2d, onscreen0 = WorldToScreen(line.from);
        local to2d, onscreen1 = WorldToScreen(line.to);

        if onscreen0 and onscreen1 then
            line.obj.From = from2d;
            line.obj.To = to2d;

            line.obj.Visible = true;
        else
            line.obj.Visible = false;
        end
    end


    wait(.1);
end