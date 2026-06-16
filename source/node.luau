local GetHeuristic = require("./getheuristic");
local NODE_SCALE = 5; -- studs

local Node = {};
Node.__index = Node;

type NodeData = {
    Position: Vector3,
    Scale: Vector3
};

export type Node = typeof(setmetatable({} :: NodeData, Node));

local NodeList: {[Vector3]: Node} = {};


function Node.new(Position: Vector3, Scale: Vector3): Node
    local self = {};

    self.Position = Position;
    self.Scale = Scale;

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
        if neighbor then
            table.insert(neighbors, neighbor);
        end
    end

    return neighbors;
end

return Node;