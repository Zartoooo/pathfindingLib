local GetHeuristic = require("./getheuristic");
local Raycaster = require("@lib/raycaster");

local NODE_SCALE = 5; -- studs

local Node = {};
Node.__index = Node;

type NodeData = {
    Position: Vector3,
    Scale: Vector3
};

export type Node = typeof(setmetatable({} :: NodeData, Node));

local NodeList: {[Vector3]: Node} = {};


function Node.new(Position: Vector3): Node
    local self = {};

    self.Position = Position;
    self.Scale = Vector3.new(NODE_SCALE,NODE_SCALE,NODE_SCALE);
    self.G = 0;
    self.H = 000;
    
    setmetatable(self, Node);
    NodeList[Position] = self;
    return self;
end

function Node.At(Position: Vector3): Node
    return NodeList[Position];
end

function Node:GetNeighbors(): {[number]: Node}
    local neighbors: {[number]: Node} = {};

    local offsets = {
        Vector3.new(NODE_SCALE, 0, 0),
        Vector3.new(-NODE_SCALE, 0, 0),
        Vector3.new(0, NODE_SCALE, 0),
        Vector3.new(0, -NODE_SCALE, 0),
        Vector3.new(0, 0, NODE_SCALE),
        Vector3.new(0, 0, -NODE_SCALE),
    };

    for _, offset in offsets do
        local neighbor = Node.At(self.Position + offset);
        if neighbor and self:CanGoTo(neighbor) then
            table.insert(neighbors, neighbor);
        end
    end

    return neighbors;
end

function Node:GetFCost(): number
    return self.G + self.H;
end 

-- raycasts a ray from center of self to center of node
function Node:CanGoTo(node: Node): boolean
    local d = math.sqrt(GetHeuristic(self.Position, node.Position));

    local raycastresult = Raycaster:RaycastTo(self.Position, node.Position, d);

    if raycastresult.Position == d then
        return true;
    else
        return false;
    end 
end

return Node;